import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:vm_service/vm_service.dart';

import 'models.dart';
import 'options.dart';

/// Prepares complete available frame lists for cross-run alignment.
///
/// Rebuilds from raw samples when available and honors the shared frame filters.
/// Stored-summary fallbacks remain explicitly incomplete. Output row limits
/// should be applied after alignment, not independently to each source.
Future<({List<ProfileFrameColumn> columns, List<String> warnings})>
prepareProfileFrameColumns(
  ProfileRunner runner, {
  required List<String> paths,
  required ProfilePresentationOptions options,
}) async {
  final columns = <ProfileFrameColumn>[];
  final warnings = <String>[];
  for (final path in paths) {
    final target = await _resolveComparisonTarget(
      runner,
      path,
      includeAllocationCorrelation: false,
      options: options.copyWith(
        frameLimit: 0,
        includeCallTree: false,
        includeBottomUpTree: false,
        includeMethodTable: false,
      ),
    );
    final region = target.presentation.region;
    columns.add(
      ProfileFrameColumn(
        label: target.sessionId ?? path,
        frames: region.topSelfFrames,
      ),
    );
    warnings.addAll(target.presentation.warnings);
    if (!region.succeeded ||
        region.rawProfilePath == null ||
        region.rawProfilePath!.isEmpty) {
      warnings.add('$path: Only the stored top-frame list is available.');
    }
  }
  return (columns: columns, warnings: warnings);
}

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
  List<AllocationAttribution> overallAllocAttribution = const [];
  final preparationWarnings = <String>[];
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
    overallAllocAttribution = prepared.allocAttribution;
    preparationWarnings.addAll(prepared.warnings);
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
    preparationWarnings.addAll(prepared.warnings);
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
      terminatedByProfiler: session.terminatedByProfiler,
      processIoMode: session.processIoMode,
      supportedCaptureKinds: session.supportedCaptureKinds,
      supportedIsolateScopes: session.supportedIsolateScopes,
      overallProfile: overallProfile,
      regions: preparedRegions,
      warnings: [...session.warnings, ...preparationWarnings],
      vmServiceUri: session.vmServiceUri,
    ),
    overallTree: overallTree,
    overallBottomUpTree: overallBottomUpTree,
    overallMethodTable: overallMethodTable,
    regionTrees: regionTrees,
    regionBottomUpTrees: regionBottomUpTrees,
    regionMethodTables: regionMethodTables,
    overallAllocAttribution: overallAllocAttribution,
  );
}

/// Resolves and prepares two profile targets for comparison.
Future<PreparedProfileComparison> prepareProfileComparison(
  ProfileRunner runner, {
  required String baselinePath,
  required String currentPath,
  String? baselineProfileId,
  String? currentProfileId,
  int? minLiveBytes,
  int? memoryClassLimit,
  bool memoryClassLimitSpecified = false,
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

  ProfileMemoryResult? baselineMemoryOverride;
  ProfileMemoryResult? currentMemoryOverride;
  final memoryWarnings = <String>[];

  if (minLiveBytes != null || memoryClassLimitSpecified) {
    final baselineRawPath = baseline.presentation.region.memory?.rawProfilePath;
    final currentRawPath = current.presentation.region.memory?.rawProfilePath;
    final memoryLimitDescription = memoryClassLimitSpecified
        ? '${memoryClassLimit ?? 0}'
        : 'default';

    if (baselineRawPath != null && baselineRawPath.isNotEmpty) {
      try {
        baselineMemoryOverride = await runner.readMemoryClasses(
          baselineRawPath,
          minLiveBytes: minLiveBytes,
          topClassCount: memoryClassLimit ?? 0,
        );
      } catch (error) {
        memoryWarnings.add(
          'readMemoryClasses could not build baselineMemoryOverride from '
          '"$baselineRawPath" (minLiveBytes=${minLiveBytes ?? 'none'}, '
          'memoryClassLimit=$memoryLimitDescription): $error. Falling back '
          'to stored memory summary classes.',
        );
      }
    } else {
      memoryWarnings.add(
        'readMemoryClasses could not build baselineMemoryOverride because no '
        'raw memory artifact path was stored (minLiveBytes='
        '${minLiveBytes ?? 'none'}, memoryClassLimit='
        '$memoryLimitDescription). Falling back to stored memory summary '
        'classes.',
      );
    }
    if (currentRawPath != null && currentRawPath.isNotEmpty) {
      try {
        currentMemoryOverride = await runner.readMemoryClasses(
          currentRawPath,
          minLiveBytes: minLiveBytes,
          topClassCount: memoryClassLimit ?? 0,
        );
      } catch (error) {
        memoryWarnings.add(
          'readMemoryClasses could not build currentMemoryOverride from '
          '"$currentRawPath" (minLiveBytes=${minLiveBytes ?? 'none'}, '
          'memoryClassLimit=$memoryLimitDescription): $error. Falling back '
          'to stored memory summary classes.',
        );
      }
    } else {
      memoryWarnings.add(
        'readMemoryClasses could not build currentMemoryOverride because no '
        'raw memory artifact path was stored (minLiveBytes='
        '${minLiveBytes ?? 'none'}, memoryClassLimit='
        '$memoryLimitDescription). Falling back to stored memory summary '
        'classes.',
      );
    }
  }

  final comparison = compareProfileRegions(
    baseline: baseline.presentation.region,
    current: current.presentation.region,
    baselineMethodTable: baseline.presentation.methodTable,
    currentMethodTable: current.presentation.methodTable,
    frameLimit: options.frameLimit,
    methodLimit: options.methodLimit,
    memoryClassLimit: memoryClassLimitSpecified
        ? memoryClassLimit
        : options.frameLimit,
    baselineMemoryOverride: baselineMemoryOverride,
    currentMemoryOverride: currentMemoryOverride,
  );
  return PreparedProfileComparison(
    baseline: baseline,
    current: current,
    comparison: comparison,
    regressions: summarizeProfileRegressions(comparison),
    minLiveBytes: minLiveBytes,
    memoryClassLimit: memoryClassLimit,
    memoryClassLimitSpecified: memoryClassLimitSpecified,
    warnings: memoryWarnings,
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

/// Prepares memory class inspection data for CLI or MCP output.
///
/// Reads the raw memory artifact at [targetPath], rebuilds the full class
/// list with optional [classQuery] and [minLiveBytes] filtering, and returns
/// a [PreparedMemoryClassInspection].
Future<PreparedMemoryClassInspection> prepareMemoryClassInspection(
  ProfileRunner runner,
  String targetPath, {
  String? classQuery,
  int? minLiveBytes,
  int topClassCount = 50,
}) async {
  final memory = await runner.readMemoryClasses(
    targetPath,
    classQuery: classQuery,
    minLiveBytes: minLiveBytes,
    topClassCount: topClassCount,
  );
  return PreparedMemoryClassInspection(
    targetPath: targetPath,
    memory: memory,
    classQuery: classQuery,
    minLiveBytes: minLiveBytes,
    topClassCount: topClassCount,
  );
}

/// Rebuilds a single region summary and tree to match [options].
///
/// Frame-only consumers can disable [includeAllocationCorrelation] to avoid
/// scanning CPU samples for memory correlation data they do not render.
Future<PreparedRegionPresentation> prepareRegionPresentation(
  ProfileRunner runner,
  ProfileRegionResult region, {
  required ProfilePresentationOptions options,
  bool includeAllocationCorrelation = true,
}) async {
  final rawProfilePath = region.rawProfilePath;
  if (!region.succeeded || rawProfilePath == null || rawProfilePath.isEmpty) {
    final storedRegion = _filterStoredRegion(region, options);
    if (options.collapseAsync) {
      final preCollapseSelfFrames = storedRegion.topSelfFrames;
      final collapsed = _collapseAsyncFramesInRegion(storedRegion);
      final breakWarnings = _buildAsyncBreakdownWarnings(
        preCollapseSelfFrames,
        null,
        collapsed.sampleCount,
      );
      return PreparedRegionPresentation(
        region: collapsed,
        warnings: breakWarnings,
      );
    }
    return PreparedRegionPresentation(region: storedRegion);
  }

  final cpuSamples = await runner.readCpuSamples(rawProfilePath);
  final memory = _filterStoredMemory(region.memory, options);
  final preFilterSampleCount = _countCpuSamplesBeforeFilters(cpuSamples);
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

  // When no frame filter is active but the re-derived sample count is zero
  // while the stored summary reports a positive count, the raw CPU profile
  // round-trip produced an empty sample list (a known serialization edge case
  // with certain VM builds). Fall back to the stored region summary so that
  // the terminal and JSON output matches what was written to session.json.
  // Call trees and the method table are still derived from the re-read data;
  // they will be empty in this case, which is transparent to the caller.
  final warnings = <String>[];
  if (options.hasActiveFrameFilters &&
      preFilterSampleCount > 0 &&
      rebuiltRegion.sampleCount == 0) {
    warnings.add(
      'Profile "${region.name}": $preFilterSampleCount CPU sample(s) were '
      'available before filtering, but no frames remained after applying '
      '${options.activeFrameFilterLabel}. Retry without those filters or use '
      'a broader --include-package value.',
    );
  } else if (_capturesCpu(region) &&
      preFilterSampleCount == 0 &&
      rebuiltRegion.sampleCount == 0 &&
      region.sampleCount == 0) {
    warnings.add(
      'Profile "${region.name}": no CPU samples were captured. Use a longer '
      'capture duration, and for Flutter startup runs make sure compilation '
      'has finished or increase --vm-service-timeout.',
    );
  }
  var regionForSummary = rebuiltRegion;
  if (regionForSummary.sampleCount == 0 &&
      region.sampleCount > 0 &&
      !options.hasActiveFrameFilters) {
    warnings.add(
      'Region "${region.name}": the raw CPU profile artifact at '
      '"$rawProfilePath" produced 0 samples when re-read, but the stored '
      'summary reported ${region.sampleCount} samples. The stored summary '
      'data is used for this output. Re-run with --call-tree or '
      '--method-table to inspect whether the artifact can be parsed.',
    );
    regionForSummary = _filterStoredRegion(region, options);
  }

  // Collapse dart:async frames and add structured breakdown warnings.
  if (options.collapseAsync) {
    // Save pre-collapse self frames for the category breakdown — they
    // contain individual dart:async entries that _buildAsyncBreakdownWarnings
    // uses to compute normal vs error completions.
    final preCollapseSelfFrames = regionForSummary.topSelfFrames;

    regionForSummary = _collapseAsyncFramesInRegion(
      regionForSummary,
      cpuSamples: cpuSamples,
    );

    warnings.addAll(
      _buildAsyncBreakdownWarnings(
        preCollapseSelfFrames,
        cpuSamples,
        regionForSummary.sampleCount,
      ),
    );
  }

  // Allocation call-site attribution: cross-reference memory classes with
  // CPU samples to show which functions were allocating.
  final allocAttribution =
      includeAllocationCorrelation &&
          memory != null &&
          cpuSamples.samples != null
      ? attributeAllocationsToCallers(memory, cpuSamples)
      : const <AllocationAttribution>[];

  // Derive every view from the same complete filtered paths. Limit only the
  // output trees; limiting first would lose method totals and caller edges.
  final completeCallTree =
      options.includeCallTree ||
          options.includeBottomUpTree ||
          options.includeMethodTable
      ? buildCallTree(
          cpuSamples: cpuSamples,
          includeFrame: options.framePredicate,
        )
      : null;
  final callTree = options.includeCallTree
      ? completeCallTree!.limited(
          maxDepth: options.maxDepth,
          maxChildren: options.maxChildren,
        )
      : null;
  final bottomUpTree = options.includeBottomUpTree
      ? buildBottomUpTreeFromCallTree(
          completeCallTree!,
        ).limited(maxDepth: options.maxDepth, maxChildren: options.maxChildren)
      : null;
  final methodTable = options.includeMethodTable
      ? _limitMethodTable(
          buildMethodTableFromCallTree(completeCallTree!),
          options,
        )
      : null;

  return PreparedRegionPresentation(
    region: regionForSummary,
    callTree: callTree,
    bottomUpTree: bottomUpTree,
    methodTable: methodTable,
    warnings: warnings,
    allocAttribution: allocAttribution,
  );
}

bool _capturesCpu(ProfileRegionResult region) {
  return region.captureKinds.contains(ProfileCaptureKind.cpu);
}

int _countCpuSamplesBeforeFilters(CpuSamples cpuSamples) {
  final sampleCount = cpuSamples.sampleCount;
  if (sampleCount != null) {
    return sampleCount;
  }
  return cpuSamples.samples?.length ?? 0;
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
    extra: region.extra,
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
  bool includeAllocationCorrelation = true,
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
        includeAllocationCorrelation: includeAllocationCorrelation,
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
        includeAllocationCorrelation: includeAllocationCorrelation,
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

/// Names of `dart:async` functions that complete futures normally (no error).
const _asyncNormalCompletionNames = {
  '_Future._completeWithValue',
  '_Future._setPendingComplete',
  '_Future._complete',
  '_setPendingComplete',
  '_completeWithValue',
};

/// Names of `dart:async` functions that complete futures with an error.
const _asyncErrorCompletionNames = {
  '_Future._completeError',
  '_Future._completeErrorObject',
  '_completeError',
  '_completeErrorObject',
  '_asyncErrorWrapper',
};

/// Names of `dart:async` functions that dispatch to listeners.
const _asyncListenerDispatchNames = {
  '_Future._propagateToListeners',
  '_FutureListener.handleValue',
  '_FutureListener.handleError',
  'handleValueCallback',
  'handleError',
  '_propagateToListeners',
};

/// Names of `dart:async` functions for microtask scheduling.
const _asyncMicrotaskNames = {
  '_microtaskLoop',
  '_startMicrotaskLoop',
  '_runPendingImmediateCallback',
};

/// Names of `dart:async` zone overhead functions.
const _asyncZoneNames = {
  '_RootZone.run',
  '_RootZone.runUnary',
  '_RootZone.runBinary',
};

/// Returns a display label for a recognized async function name.
///
/// Uses substring matching because VM function names may include the owner
/// class prefix multiple times (e.g. `_Future._Future._completeErrorObject`).
String? _asyncCategoryLabel(ProfileFrameSummary frame) {
  return switch (_asyncCategoryFromName(frame.name)) {
    'normal' => 'async (normal completions)',
    'error' => 'async (error completions)',
    'listener' => 'async (listener dispatch)',
    'microtask' => 'async (microtask scheduling)',
    'zone' => 'async (zone overhead)',
    _ => null,
  };
}

/// Classifies async names using substring matching for VM owner prefixes.
String _asyncCategoryFromName(String name) {
  for (final entry in _asyncNormalCompletionNames) {
    if (name.contains(entry)) return 'normal';
  }
  for (final entry in _asyncErrorCompletionNames) {
    if (name.contains(entry)) return 'error';
  }
  for (final entry in _asyncListenerDispatchNames) {
    if (name.contains(entry)) return 'listener';
  }
  for (final entry in _asyncMicrotaskNames) {
    if (name.contains(entry)) return 'microtask';
  }
  for (final entry in _asyncZoneNames) {
    if (name.contains(entry)) return 'zone';
  }
  return 'other';
}

/// Categorizes async frames into explicit groups and replaces the individual
/// dart:async frame summaries in [region] with categorized entries.
///
/// When [cpuSamples] is provided, async samples are also attributed to the
/// first non-async caller in the stack, producing entries like
/// "async (await _runFrame)" that show which instruction triggered the async
/// cost.
ProfileRegionResult _collapseAsyncFramesInRegion(
  ProfileRegionResult region, {
  CpuSamples? cpuSamples,
}) {
  return ProfileRegionResult(
    regionId: region.regionId,
    name: region.name,
    attributes: region.attributes,
    isolateId: region.isolateId,
    isolateIds: region.isolateIds,
    captureKinds: region.captureKinds,
    isolateScope: region.isolateScope,
    parentRegionId: region.parentRegionId,
    startTimestampMicros: region.startTimestampMicros,
    endTimestampMicros: region.endTimestampMicros,
    durationMicros: region.durationMicros,
    sampleCount: region.sampleCount,
    samplePeriodMicros: region.samplePeriodMicros,
    topSelfFrames: _collapseAsyncFrameList(
      region.topSelfFrames,
      region.sampleCount,
      cpuSamples: cpuSamples,
    ),
    topTotalFrames: _collapseAsyncFrameList(
      region.topTotalFrames,
      region.sampleCount,
    ),
    memory: region.memory,
    rawProfilePath: region.rawProfilePath,
    summaryPath: region.summaryPath,
    error: region.error,
    extra: region.extra,
  );
}

/// Replaces individual `dart:async` frames in [frames] with a single
/// "async overhead" entry and returns the filtered list.
///
/// Detailed category breakdown (normal vs error completions) and call-site
/// attribution are added to warnings by [_buildAsyncBreakdownWarnings] instead
/// of cluttering the main table.
List<ProfileFrameSummary> _collapseAsyncFrameList(
  List<ProfileFrameSummary> frames,
  int totalSampleCount, {
  CpuSamples? cpuSamples,
}) {
  final divisor = totalSampleCount == 0 ? 1 : totalSampleCount;
  var asyncSelfSamples = 0;
  var asyncTotalSamples = 0;
  final filtered = <ProfileFrameSummary>[];

  for (final frame in frames) {
    final profileFrame = ProfileFrame(
      name: frame.name,
      kind: frame.kind,
      location: frame.location,
    );
    if (profileFrame.isAsyncOverhead) {
      asyncSelfSamples += frame.selfSamples;
      asyncTotalSamples += frame.totalSamples;
    } else {
      filtered.add(frame);
    }
  }

  if (asyncSelfSamples == 0 && asyncTotalSamples == 0) {
    return frames;
  }

  filtered.add(
    ProfileFrameSummary(
      name: 'async overhead',
      kind: 'Dart',
      location: 'dart:async',
      selfSamples: asyncSelfSamples,
      totalSamples: asyncTotalSamples,
      selfPercent: asyncSelfSamples / divisor,
      totalPercent: asyncTotalSamples / divisor,
    ),
  );

  filtered.sort(_compareSelfDescending);
  return filtered;
}

/// Builds structured warnings describing the async overhead breakdown by
/// category (normal vs error completions, listener dispatch, etc.) and, when
/// raw [cpuSamples] are available, the top caller sites for error completions.
List<String> _buildAsyncBreakdownWarnings(
  List<ProfileFrameSummary> frames,
  CpuSamples? cpuSamples,
  int totalSampleCount,
) {
  if (frames.isEmpty) return const [];

  // Aggregate stored frames by category.
  final categories = <String, _AsyncCategoryAccumulator>{};
  for (final frame in frames) {
    final profileFrame = ProfileFrame(
      name: frame.name,
      kind: frame.kind,
      location: frame.location,
    );
    if (profileFrame.isAsyncOverhead) {
      final label = _asyncCategoryLabel(frame) ?? 'other';
      categories.putIfAbsent(label, () => _AsyncCategoryAccumulator())
        ..add(frame);
    }
  }

  if (categories.isEmpty) return const [];

  final divisor = totalSampleCount == 0 ? 1 : totalSampleCount;
  final totalAsyncSamples = categories.values.fold<int>(
    0,
    (s, c) => s + c.selfSamples,
  );
  final totalPct = (totalAsyncSamples / divisor) * 100;
  final parts = <String>[
    'Async overhead breakdown: ${totalPct.toStringAsFixed(1)}% of samples '
        'represented by the available top-frame subset',
  ];

  // Add category lines.
  for (final entry in categories.entries) {
    final pct = (entry.value.selfSamples / divisor) * 100;
    final label = switch (entry.key) {
      'async (normal completions)' => 'normal completions',
      'async (error completions)' => 'error completions',
      'async (listener dispatch)' => 'listener dispatch',
      'async (microtask scheduling)' => 'microtask scheduling',
      'async (zone overhead)' => 'zone overhead',
      _ => entry.key,
    };
    parts.add('  $label: ${pct.toStringAsFixed(1)}%');
  }

  // When raw CPU samples are available, add caller attribution for error
  // completions (the most actionable category).
  if (cpuSamples?.samples != null) {
    final attributed = _attributeAsyncByCaller(cpuSamples!);
    if (attributed.isNotEmpty && totalSampleCount > 0) {
      // Find entries with error completions.
      final errorCallers =
          attributed.where((e) => e.errorSelfSamples > 0).toList()
            ..sort((a, b) => b.errorSelfSamples.compareTo(a.errorSelfSamples));

      if (errorCallers.isNotEmpty) {
        final callerDesc = errorCallers
            .take(3)
            .map((e) {
              final callerPct = (e.errorSelfSamples / divisor) * 100;
              return '${e.callerName} (${callerPct.toStringAsFixed(1)}%)';
            })
            .join(', ');
        parts.add('  error completions from: $callerDesc');
      }

      // Also show normal completion callers.
      final normalCallers =
          attributed.where((e) => e.normalSelfSamples > 0).toList()..sort(
            (a, b) => b.normalSelfSamples.compareTo(a.normalSelfSamples),
          );

      if (normalCallers.isNotEmpty) {
        final callerDesc = normalCallers
            .take(3)
            .map((e) {
              final callerPct = (e.normalSelfSamples / divisor) * 100;
              return '${e.callerName} (${callerPct.toStringAsFixed(1)}%)';
            })
            .join(', ');
        parts.add('  normal completions from: $callerDesc');
      }
    }
  }

  return [parts.join('\n')];
}

/// Accumulates sample counts for one async category.
class _AsyncCategoryAccumulator {
  int selfSamples = 0;
  int totalSamples = 0;

  void add(ProfileFrameSummary frame) {
    selfSamples += frame.selfSamples;
    totalSamples += frame.totalSamples;
  }
}

/// A single caller-attributed async cost entry with category breakdown.
final class _AsyncCallerEntry {
  const _AsyncCallerEntry({
    required this.callerName,
    required this.selfSamples,
    required this.totalSamples,
    this.normalSelfSamples = 0,
    this.errorSelfSamples = 0,
    this.listenerSelfSamples = 0,
    this.otherSelfSamples = 0,
  });

  final String callerName;
  final int selfSamples;
  final int totalSamples;

  /// Self samples from normal completions (e.g. _completeWithValue).
  /// These are the best candidates for sync conversion — the future completed
  /// synchronously without yielding.
  final int normalSelfSamples;

  /// Self samples from error completions (e.g. _completeErrorObject).
  /// Harder to eliminate because errors inherently need stack traces.
  final int errorSelfSamples;

  /// Self samples from listener dispatch (e.g. _propagateToListeners).
  final int listenerSelfSamples;

  /// Self samples from other async categories (microtask, zone, etc.).
  final int otherSelfSamples;
}

/// Walks raw [cpuSamples] and attributes each async self-sample to the first
/// non-async caller in the stack trace.
///
/// For each sample where the top (self) frame is a `dart:async` function, this
/// finds the first frame below it that is NOT `dart:async` and accumulates the
/// sample there. The result answers "which calling function triggered this
/// async cost?"
List<_AsyncCallerEntry> _attributeAsyncByCaller(CpuSamples cpuSamples) {
  final functions = cpuSamples.functions ?? const <ProfileFunction>[];
  final samples = cpuSamples.samples ?? const <CpuSample>[];
  if (functions.isEmpty || samples.isEmpty) return const [];

  final callerCounts = <String, int>{};
  final callerCategories = <String, Map<String, int>>{};
  var totalZeroCallerSamples = 0;

  for (final sample in samples) {
    final stack = sample.stack ?? const <int>[];
    if (stack.isEmpty) continue;

    // Check if the top (self) frame is async.
    final selfFrame = profileFrameFromFunction(functions, stack.first);
    if (!selfFrame.isAsyncOverhead) continue;

    // Find the first non-async frame below the self frame.
    String? callerName;
    for (var i = 1; i < stack.length; i++) {
      final frame = profileFrameFromFunction(functions, stack[i]);
      if (!frame.isAsyncOverhead) {
        callerName = frame.name;
        break;
      }
    }

    // Determine async category for what-if analysis.
    final category = _asyncCategoryFromName(selfFrame.name);

    if (callerName != null) {
      callerCounts[callerName] = (callerCounts[callerName] ?? 0) + 1;
      callerCategories.putIfAbsent(callerName, () => {})
        ..update(category, (v) => v + 1, ifAbsent: () => 1);
    } else {
      totalZeroCallerSamples++;
    }
  }

  if (callerCounts.isEmpty && totalZeroCallerSamples == 0) {
    return const [];
  }

  final sorted = callerCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final result = <_AsyncCallerEntry>[
    for (final entry in sorted)
      _AsyncCallerEntry(
        callerName: entry.key,
        selfSamples: entry.value,
        totalSamples: entry.value,
        normalSelfSamples: callerCategories[entry.key]?['normal'] ?? 0,
        errorSelfSamples: callerCategories[entry.key]?['error'] ?? 0,
        listenerSelfSamples: callerCategories[entry.key]?['listener'] ?? 0,
        otherSelfSamples:
            (entry.value) -
            (callerCategories[entry.key]?['normal'] ?? 0) -
            (callerCategories[entry.key]?['error'] ?? 0) -
            (callerCategories[entry.key]?['listener'] ?? 0),
      ),
  ];

  if (totalZeroCallerSamples > 0) {
    result.add(
      _AsyncCallerEntry(
        callerName: 'no-caller',
        selfSamples: totalZeroCallerSamples,
        totalSamples: totalZeroCallerSamples,
      ),
    );
  }

  return result;
}

/// Orders frames by descending self samples, then descending total samples.
int _compareSelfDescending(ProfileFrameSummary a, ProfileFrameSummary b) {
  final c = b.selfSamples.compareTo(a.selfSamples);
  if (c != 0) return c;
  return b.totalSamples.compareTo(a.totalSamples);
}
