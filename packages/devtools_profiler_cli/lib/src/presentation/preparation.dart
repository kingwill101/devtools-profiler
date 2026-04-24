import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import 'models.dart';
import 'options.dart';

/// Rebuilds session summaries and trees to match [options].
Future<PreparedSessionPresentation> prepareSessionPresentation(
  ProfileRunner runner,
  ProfileRunResult session, {
  required ProfilePresentationOptions options,
}) async {
  ProfileRegionResult? overallProfile;
  ProfileCallTree? overallTree;
  ProfileCallTree? overallBottomUpTree;
  ProfileMethodTable? overallMethodTable;
  final storedOverall = session.overallProfile;
  if (storedOverall != null) {
    final prepared = await prepareRegionPresentation(
      runner,
      storedOverall,
      options: options,
    );
    overallProfile = prepared.region;
    overallTree = prepared.callTree;
    overallBottomUpTree = prepared.bottomUpTree;
    overallMethodTable = prepared.methodTable;
  }

  final preparedRegions = <ProfileRegionResult>[];
  final regionTrees = <String, ProfileCallTree>{};
  final regionBottomUpTrees = <String, ProfileCallTree>{};
  final regionMethodTables = <String, ProfileMethodTable>{};

  for (final region in session.regions) {
    final prepared = await prepareRegionPresentation(
      runner,
      region,
      options: options,
    );
    preparedRegions.add(prepared.region);
    if (prepared.callTree != null) {
      regionTrees[prepared.region.regionId] = prepared.callTree!;
    }
    if (prepared.bottomUpTree != null) {
      regionBottomUpTrees[prepared.region.regionId] = prepared.bottomUpTree!;
    }
    if (prepared.methodTable != null) {
      regionMethodTables[prepared.region.regionId] = prepared.methodTable!;
    }
  }

  return PreparedSessionPresentation(
    session: ProfileRunResult(
      sessionId: session.sessionId,
      command: session.command,
      workingDirectory: session.workingDirectory,
      exitCode: session.exitCode,
      artifactDirectory: session.artifactDirectory,
      supportedCaptureKinds: session.supportedCaptureKinds,
      supportedIsolateScopes: session.supportedIsolateScopes,
      overallProfile: overallProfile,
      regions: preparedRegions,
      warnings: session.warnings,
      vmServiceUri: session.vmServiceUri,
    ),
    overallTree: overallTree,
    overallBottomUpTree: overallBottomUpTree,
    overallMethodTable: overallMethodTable,
    regionTrees: regionTrees,
    regionBottomUpTrees: regionBottomUpTrees,
    regionMethodTables: regionMethodTables,
  );
}

/// Resolves and prepares two profile targets for comparison.
Future<PreparedProfileComparison> prepareProfileComparison(
  ProfileRunner runner, {
  required String baselinePath,
  required String currentPath,
  String? baselineProfileId,
  String? currentProfileId,
  required ProfilePresentationOptions options,
}) async {
  final baseline = await _resolveComparisonTarget(
    runner,
    baselinePath,
    requestedProfileId: baselineProfileId,
    options: options,
  );
  final current = await _resolveComparisonTarget(
    runner,
    currentPath,
    requestedProfileId: currentProfileId,
    options: options,
  );
  final comparison = compareProfileRegions(
    baseline: baseline.presentation.region,
    current: current.presentation.region,
    baselineMethodTable: baseline.presentation.methodTable,
    currentMethodTable: current.presentation.methodTable,
    frameLimit: options.frameLimit,
    methodLimit: options.methodLimit,
    memoryClassLimit: options.frameLimit,
  );
  return PreparedProfileComparison(
    baseline: baseline,
    current: current,
    comparison: comparison,
    regressions: summarizeProfileRegressions(comparison),
  );
}

/// Resolves and prepares a profile target for hotspot explanation.
Future<PreparedProfileExplanation> prepareProfileExplanation(
  ProfileRunner runner, {
  required String targetPath,
  String? profileId,
  required ProfilePresentationOptions options,
}) async {
  final target = await _resolveComparisonTarget(
    runner,
    targetPath,
    requestedProfileId: profileId,
    options: options,
  );
  final needsAnalysisTarget =
      target.presentation.methodTable == null ||
      target.presentation.callTree == null ||
      target.presentation.bottomUpTree == null;
  final analysisTarget = needsAnalysisTarget
      ? await _resolveComparisonTarget(
          runner,
          targetPath,
          requestedProfileId: profileId,
          options: options.copyWith(
            includeMethodTable: true,
            includeCallTree: true,
            includeBottomUpTree: true,
          ),
        )
      : target;
  return PreparedProfileExplanation(
    target: target,
    hotspots: explainProfileHotspots(
      analysisTarget.presentation.region,
      methodTable: analysisTarget.presentation.methodTable,
      callTree: analysisTarget.presentation.callTree,
      bottomUpTree: analysisTarget.presentation.bottomUpTree,
    ),
  );
}

/// Resolves and prepares a profile target for method inspection.
Future<PreparedProfileMethodInspection> prepareProfileMethodInspection(
  ProfileRunner runner, {
  required String targetPath,
  String? profileId,
  String? methodId,
  String? methodName,
  int? pathLimit,
  required ProfilePresentationOptions options,
}) async {
  if ((methodId == null || methodId.trim().isEmpty) ==
      (methodName == null || methodName.trim().isEmpty)) {
    throw ArgumentError(
      'Exactly one of "methodId" or "methodName" must be provided.',
    );
  }

  final target = await _resolveComparisonTarget(
    runner,
    targetPath,
    requestedProfileId: profileId,
    options: options,
  );
  final needsAnalysisTarget =
      target.presentation.methodTable == null ||
      target.presentation.callTree == null ||
      target.presentation.bottomUpTree == null;
  final analysisTarget = needsAnalysisTarget
      ? await _resolveComparisonTarget(
          runner,
          targetPath,
          requestedProfileId: profileId,
          options: options.copyWith(
            includeMethodTable: true,
            includeCallTree: true,
            includeBottomUpTree: true,
          ),
        )
      : target;

  return PreparedProfileMethodInspection(
    target: target,
    inspection: inspectProfileMethod(
      query: methodId?.trim().isNotEmpty == true
          ? methodId!.trim()
          : methodName!.trim(),
      queryKind: methodId?.trim().isNotEmpty == true
          ? 'methodId'
          : 'methodName',
      methodTable: analysisTarget.presentation.methodTable,
      callTree: analysisTarget.presentation.callTree,
      bottomUpTree: analysisTarget.presentation.bottomUpTree,
      pathLimit: pathLimit,
    ),
  );
}

/// Resolves and prepares two profile targets for method comparison.
Future<PreparedProfileMethodComparison> prepareProfileMethodComparison(
  ProfileRunner runner, {
  required String baselinePath,
  required String currentPath,
  String? baselineProfileId,
  String? currentProfileId,
  String? methodId,
  String? methodName,
  int? pathLimit,
  int? relationLimit,
  required ProfilePresentationOptions options,
}) async {
  if ((methodId == null || methodId.trim().isEmpty) ==
      (methodName == null || methodName.trim().isEmpty)) {
    throw ArgumentError(
      'Exactly one of "methodId" or "methodName" must be provided.',
    );
  }

  final baseline = await _resolveComparisonTarget(
    runner,
    baselinePath,
    requestedProfileId: baselineProfileId,
    options: options,
  );
  final current = await _resolveComparisonTarget(
    runner,
    currentPath,
    requestedProfileId: currentProfileId,
    options: options,
  );

  Future<PreparedComparisonTarget> ensureAnalysisTarget(
    PreparedComparisonTarget target,
    String targetPath,
    String? requestedProfileId,
  ) async {
    final needsAnalysisTarget =
        target.presentation.methodTable == null ||
        target.presentation.callTree == null ||
        target.presentation.bottomUpTree == null;
    if (!needsAnalysisTarget) {
      return target;
    }
    return _resolveComparisonTarget(
      runner,
      targetPath,
      requestedProfileId: requestedProfileId,
      options: options.copyWith(
        includeMethodTable: true,
        includeCallTree: true,
        includeBottomUpTree: true,
      ),
    );
  }

  final baselineAnalysis = await ensureAnalysisTarget(
    baseline,
    baselinePath,
    baselineProfileId,
  );
  final currentAnalysis = await ensureAnalysisTarget(
    current,
    currentPath,
    currentProfileId,
  );

  final query = methodId?.trim().isNotEmpty == true
      ? methodId!.trim()
      : methodName!.trim();
  final queryKind = methodId?.trim().isNotEmpty == true
      ? 'methodId'
      : 'methodName';

  return PreparedProfileMethodComparison(
    baseline: baseline,
    current: current,
    comparison: compareProfileMethods(
      baseline: inspectProfileMethod(
        query: query,
        queryKind: queryKind,
        methodTable: baselineAnalysis.presentation.methodTable,
        callTree: baselineAnalysis.presentation.callTree,
        bottomUpTree: baselineAnalysis.presentation.bottomUpTree,
        pathLimit: pathLimit,
      ),
      current: inspectProfileMethod(
        query: query,
        queryKind: queryKind,
        methodTable: currentAnalysis.presentation.methodTable,
        callTree: currentAnalysis.presentation.callTree,
        bottomUpTree: currentAnalysis.presentation.bottomUpTree,
        pathLimit: pathLimit,
      ),
      relationLimit: relationLimit,
    ),
  );
}

/// Resolves and prepares a profile target for method search.
Future<PreparedProfileMethodSearch> prepareProfileMethodSearch(
  ProfileRunner runner, {
  required String targetPath,
  String? profileId,
  String? query,
  ProfileMethodSearchSort sortBy = ProfileMethodSearchSort.total,
  int? limit,
  required ProfilePresentationOptions options,
}) async {
  final target = await _resolveComparisonTarget(
    runner,
    targetPath,
    requestedProfileId: profileId,
    options: options,
  );
  final analysisTarget = target.presentation.methodTable == null
      ? await _resolveComparisonTarget(
          runner,
          targetPath,
          requestedProfileId: profileId,
          options: options.copyWith(includeMethodTable: true),
        )
      : target;

  return PreparedProfileMethodSearch(
    target: target,
    search: searchProfileMethods(
      methodTable: analysisTarget.presentation.methodTable,
      query: query,
      sortBy: sortBy,
      limit: limit,
    ),
  );
}

/// Resolves and prepares multiple profile targets for trend analysis.
Future<PreparedProfileTrends> prepareProfileTrends(
  ProfileRunner runner, {
  required List<String> targetPaths,
  String? profileId,
  required ProfilePresentationOptions options,
}) async {
  if (targetPaths.length < 2) {
    throw ArgumentError(
      'Trend analysis requires at least two session directories or profile artifacts.',
    );
  }

  Future<PreparedComparisonTarget> ensureMethodAnalysisTarget(
    PreparedComparisonTarget target,
    String targetPath,
  ) async {
    if (target.presentation.methodTable != null) {
      return target;
    }
    return _resolveComparisonTarget(
      runner,
      targetPath,
      requestedProfileId: profileId,
      options: options.copyWith(includeMethodTable: true),
    );
  }

  final targets = <PreparedComparisonTarget>[];
  final analysisTargets = <PreparedComparisonTarget>[];
  for (final targetPath in targetPaths) {
    final target = await _resolveComparisonTarget(
      runner,
      targetPath,
      requestedProfileId: profileId,
      options: options,
    );
    targets.add(target);
    analysisTargets.add(await ensureMethodAnalysisTarget(target, targetPath));
  }

  return PreparedProfileTrends(
    targets: targets,
    trends: analyzeProfileTrends(
      entries: [
        for (var index = 0; index < analysisTargets.length; index++)
          ProfileTrendSeriesEntry(
            id: _trendTargetLabel(analysisTargets[index], index),
            region: analysisTargets[index].presentation.region,
            methodTable: analysisTargets[index].presentation.methodTable,
          ),
      ],
      frameLimit: options.frameLimit,
      methodLimit: options.methodLimit,
      memoryClassLimit: options.frameLimit,
    ),
  );
}

/// Rebuilds a single region summary and tree to match [options].
Future<PreparedRegionPresentation> prepareRegionPresentation(
  ProfileRunner runner,
  ProfileRegionResult region, {
  required ProfilePresentationOptions options,
}) async {
  final rawProfilePath = region.rawProfilePath;
  if (!region.succeeded || rawProfilePath == null || rawProfilePath.isEmpty) {
    return PreparedRegionPresentation(
      region: _filterStoredRegion(region, options),
    );
  }

  final cpuSamples = await runner.readCpuSamples(rawProfilePath);
  final memory = _filterStoredMemory(region.memory, options);
  final rebuiltRegion = summarizeCpuSamples(
    regionId: region.regionId,
    name: region.name,
    attributes: region.attributes,
    isolateId: region.isolateId,
    isolateIds: region.isolateIds,
    captureKinds: region.captureKinds,
    isolateScope: region.isolateScope,
    parentRegionId: region.parentRegionId,
    memory: memory,
    startTimestampMicros: region.startTimestampMicros,
    endTimestampMicros: region.endTimestampMicros,
    cpuSamples: cpuSamples,
    summaryPath: region.summaryPath,
    rawProfilePath: region.rawProfilePath,
    topFrameCount: options.frameLimit ?? 0,
    includeFrame: options.framePredicate,
  );
  final callTree = options.includeCallTree
      ? buildCallTree(
          cpuSamples: cpuSamples,
          includeFrame: options.framePredicate,
        ).limited(maxDepth: options.maxDepth, maxChildren: options.maxChildren)
      : null;
  final bottomUpTree = options.includeBottomUpTree
      ? buildBottomUpTree(
          cpuSamples: cpuSamples,
          includeFrame: options.framePredicate,
        ).limited(maxDepth: options.maxDepth, maxChildren: options.maxChildren)
      : null;
  final methodTable = options.includeMethodTable
      ? _limitMethodTable(
          buildMethodTable(
            cpuSamples: cpuSamples,
            includeFrame: options.framePredicate,
          ),
          options,
        )
      : null;

  return PreparedRegionPresentation(
    region: rebuiltRegion,
    callTree: callTree,
    bottomUpTree: bottomUpTree,
    methodTable: methodTable,
  );
}

ProfileRegionResult _filterStoredRegion(
  ProfileRegionResult region,
  ProfilePresentationOptions options,
) {
  final topSelfFrames = _filterStoredFrames(region.topSelfFrames, options);
  final topTotalFrames = _filterStoredFrames(region.topTotalFrames, options);
  return ProfileRegionResult(
    regionId: region.regionId,
    name: region.name,
    attributes: region.attributes,
    isolateId: region.isolateId,
    isolateIds: region.isolateIds,
    captureKinds: region.captureKinds,
    isolateScope: region.isolateScope,
    parentRegionId: region.parentRegionId,
    memory: _filterStoredMemory(region.memory, options),
    startTimestampMicros: region.startTimestampMicros,
    endTimestampMicros: region.endTimestampMicros,
    durationMicros: region.durationMicros,
    sampleCount: region.sampleCount,
    samplePeriodMicros: region.samplePeriodMicros,
    topSelfFrames: topSelfFrames,
    topTotalFrames: topTotalFrames,
    summaryPath: region.summaryPath,
    rawProfilePath: region.rawProfilePath,
    error: region.error,
  );
}

ProfileMemoryResult? _filterStoredMemory(
  ProfileMemoryResult? memory,
  ProfilePresentationOptions options,
) {
  if (memory == null) {
    return null;
  }

  return memory.copyWith(
    topClasses: [
      for (final item in memory.topClasses)
        if (!_shouldHideStoredMemoryClass(item, options)) item,
    ],
  );
}

List<ProfileFrameSummary> _filterStoredFrames(
  List<ProfileFrameSummary> frames,
  ProfilePresentationOptions options,
) {
  final filtered = [
    for (final frame in frames)
      if (!_shouldHideStoredFrame(frame, options)) frame,
  ];
  final frameLimit = options.frameLimit;
  if (frameLimit == null || frameLimit <= 0 || filtered.length <= frameLimit) {
    return filtered;
  }
  return filtered.take(frameLimit).toList();
}

bool _shouldHideStoredFrame(
  ProfileFrameSummary frame,
  ProfilePresentationOptions options,
) {
  if (!options.hideSdk) {
    return false;
  }
  return ProfileFrame(
    name: frame.name,
    kind: frame.kind,
    location: frame.location,
  ).isSdk;
}

bool _shouldHideStoredMemoryClass(
  ProfileMemoryClassSummary summary,
  ProfilePresentationOptions options,
) {
  final frame = ProfileFrame(
    name: summary.className,
    kind: 'Dart',
    location: summary.libraryUri,
  );
  if (options.hideSdk && frame.isSdk) {
    return true;
  }
  final packageName = frame.packageName;
  if (packageName == null) {
    return options.includePackages.isNotEmpty;
  }
  if (options.includePackages.isNotEmpty &&
      !_matchesPackagePrefixes(packageName, options.includePackages)) {
    return true;
  }
  final excludePrefixes = [
    ...options.excludePackages,
    if (options.hideRuntimeHelpers) ...runtimeHelperPackagePrefixes,
  ];
  return _matchesPackagePrefixes(packageName, excludePrefixes);
}

Future<PreparedComparisonTarget> _resolveComparisonTarget(
  ProfileRunner runner,
  String targetPath, {
  String? requestedProfileId,
  required ProfilePresentationOptions options,
}) async {
  final summary = await runner.summarizeArtifact(targetPath);
  if (summary case {'regions': final Object? _}) {
    final session = ProfileRunResult.fromJson(summary);
    final region = _resolveRequestedComparisonProfile(
      session,
      requestedProfileId,
    );
    return PreparedComparisonTarget(
      path: targetPath,
      inputKind: 'session',
      selectedProfileId: region.regionId,
      sessionId: session.sessionId,
      presentation: await prepareRegionPresentation(
        runner,
        region,
        options: options,
      ),
    );
  }

  if (summary case {'topSelfFrames': final Object? _}) {
    if (requestedProfileId != null && requestedProfileId.isNotEmpty) {
      throw ArgumentError(
        'A profile id was provided for "$targetPath", but the target is already a single profile artifact.',
      );
    }
    final region = ProfileRegionResult.fromJson(summary);
    return PreparedComparisonTarget(
      path: targetPath,
      inputKind: 'artifact',
      selectedProfileId: region.regionId,
      presentation: await prepareRegionPresentation(
        runner,
        region,
        options: options,
      ),
    );
  }

  throw ArgumentError(
    'Unsupported comparison target at "$targetPath". '
    'Use a session directory or a profile summary/raw CPU artifact.',
  );
}

ProfileRegionResult _resolveRequestedComparisonProfile(
  ProfileRunResult session,
  String? requestedProfileId,
) {
  final profileId = requestedProfileId?.trim();
  if (profileId == null || profileId.isEmpty) {
    final overallProfile = session.overallProfile;
    if (overallProfile != null) {
      return overallProfile;
    }
    if (session.regions.length == 1) {
      return session.regions.single;
    }
    throw ArgumentError(
      'Session "${session.sessionId}" has no whole-session profile. '
      'Specify a profile id explicitly to compare one of its regions.',
    );
  }

  if (profileId == 'overall') {
    final overallProfile = session.overallProfile;
    if (overallProfile == null) {
      throw ArgumentError(
        'Session "${session.sessionId}" does not have a whole-session profile.',
      );
    }
    return overallProfile;
  }

  return session.regions.firstWhere(
    (region) => region.regionId == profileId,
    orElse: () => throw ArgumentError(
      'Profile id "$profileId" was not found in session "${session.sessionId}".',
    ),
  );
}

ProfileMethodTable _limitMethodTable(
  ProfileMethodTable table,
  ProfilePresentationOptions options,
) {
  final methodLimit = options.methodLimit;
  if (methodLimit == null ||
      methodLimit <= 0 ||
      table.methods.length <= methodLimit) {
    return table;
  }
  return table.copyWith(methods: table.methods.take(methodLimit).toList());
}

bool _matchesPackagePrefixes(String packageName, List<String> prefixes) {
  for (final prefix in prefixes) {
    if (packageName.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}

String _trendTargetLabel(PreparedComparisonTarget target, int index) {
  final sessionId = target.sessionId;
  if (sessionId != null && sessionId.isNotEmpty) {
    return sessionId;
  }
  if (target.inputKind == 'artifact') {
    return 'artifact-${index + 1}';
  }
  return 'target-${index + 1}';
}
