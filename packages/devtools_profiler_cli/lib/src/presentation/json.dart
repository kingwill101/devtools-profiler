import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import 'models.dart';

/// Converts a prepared session to structured JSON.
Map<String, Object?> sessionPresentationJson(
  ProfileRunResult session,
  ProfileCallTree? overallTree,
  ProfileCallTree? overallBottomUpTree,
  ProfileMethodTable? overallMethodTable,
  Map<String, ProfileCallTree> regionTrees,
  Map<String, ProfileCallTree> regionBottomUpTrees,
  Map<String, ProfileMethodTable> regionMethodTables,
) {
  return {
    ...session.toJson(),
    'cliCommand': _sessionCliCommand(session),
    if (session.overallProfile != null)
      'overallProfile': regionPresentationJson(
        session.overallProfile!,
        overallTree,
        overallBottomUpTree,
        overallMethodTable,
      ),
    'regions': [
      for (final region in session.regions)
        regionPresentationJson(
          region,
          regionTrees[region.regionId],
          regionBottomUpTrees[region.regionId],
          regionMethodTables[region.regionId],
        ),
    ],
  };
}

/// Converts a prepared region to structured JSON.
Map<String, Object?> regionPresentationJson(
  ProfileRegionResult region,
  ProfileCallTree? callTree,
  ProfileCallTree? bottomUpTree,
  ProfileMethodTable? methodTable, {
  List<String> warnings = const [],
}) {
  return {
    ...region.toJson(),
    if (region.summaryPath.isNotEmpty)
      'cliCommand': _summarizeCliCommand(region.summaryPath),
    if (callTree != null) 'callTree': callTree.toJson(),
    if (bottomUpTree != null) 'bottomUpTree': bottomUpTree.toJson(),
    if (methodTable != null) 'methodTable': methodTable.toJson(),
    if (warnings.isNotEmpty) 'preparationWarnings': warnings,
  };
}

/// Converts prepared comparison data to structured JSON.
Map<String, Object?> comparisonPresentationJson(
  PreparedProfileComparison comparison,
) {
  final preparationWarnings = [
    ...comparison.baseline.presentation.warnings,
    ...comparison.current.presentation.warnings,
  ];
  return {
    'kind': 'profileComparison',
    'cliCommand': _compareCliCommand(comparison),
    'baseline': _comparisonTargetJson(comparison.baseline),
    'current': _comparisonTargetJson(comparison.current),
    'comparison': comparison.comparison.toJson(),
    'regressions': comparison.regressions.toJson(),
    if (preparationWarnings.isNotEmpty)
      'preparationWarnings': preparationWarnings,
  };
}

/// Converts prepared hotspot explanation data to structured JSON.
Map<String, Object?> hotspotExplanationJson(
  PreparedProfileExplanation explanation,
) {
  final preparationWarnings = explanation.target.presentation.warnings;
  return {
    'kind': 'hotspotExplanation',
    'cliCommand': _explainCliCommand(explanation),
    'target': _comparisonTargetJson(explanation.target),
    'hotspots': explanation.hotspots.toJson(),
    if (preparationWarnings.isNotEmpty)
      'preparationWarnings': preparationWarnings,
  };
}

/// Converts prepared method inspection data to structured JSON.
Map<String, Object?> methodInspectionJson(
  PreparedProfileMethodInspection inspection,
) {
  final preparationWarnings = inspection.target.presentation.warnings;
  return {
    'kind': 'methodInspection',
    'cliCommand': _inspectCliCommand(inspection),
    'target': _comparisonTargetJson(inspection.target),
    'inspection': inspection.inspection.toJson(),
    if (preparationWarnings.isNotEmpty)
      'preparationWarnings': preparationWarnings,
  };
}

/// Converts prepared method comparison data to structured JSON.
Map<String, Object?> methodComparisonJson(
  PreparedProfileMethodComparison comparison,
) {
  final preparationWarnings = [
    ...comparison.baseline.presentation.warnings,
    ...comparison.current.presentation.warnings,
  ];
  return {
    'kind': 'methodComparison',
    'cliCommand': _compareMethodCliCommand(comparison),
    'baseline': _comparisonTargetJson(comparison.baseline),
    'current': _comparisonTargetJson(comparison.current),
    'comparison': comparison.comparison.toJson(),
    if (preparationWarnings.isNotEmpty)
      'preparationWarnings': preparationWarnings,
  };
}

/// Converts prepared method search data to structured JSON.
Map<String, Object?> methodSearchJson(PreparedProfileMethodSearch search) {
  final preparationWarnings = search.target.presentation.warnings;
  return {
    'kind': 'methodSearch',
    'cliCommand': _searchMethodsCliCommand(search),
    'target': _comparisonTargetJson(search.target),
    'search': search.search.toJson(),
    if (preparationWarnings.isNotEmpty)
      'preparationWarnings': preparationWarnings,
  };
}

/// Converts prepared trend data to structured JSON.
Map<String, Object?> trendPresentationJson(PreparedProfileTrends trends) {
  return {
    'kind': 'profileTrends',
    'cliCommand': _trendsCliCommand(trends),
    'targets': [for (final target in trends.targets) _trendTargetJson(target)],
    'trends': trends.trends.toJson(),
  };
}

Map<String, Object?> _comparisonTargetJson(PreparedComparisonTarget target) {
  return {
    'path': target.path,
    'inputKind': target.inputKind,
    if (target.sessionId != null) 'sessionId': target.sessionId,
    'selectedProfileId': target.selectedProfileId,
    'scope': _presentationScope(target.presentation.region),
    'profile': regionPresentationJson(
      target.presentation.region,
      target.presentation.callTree,
      target.presentation.bottomUpTree,
      target.presentation.methodTable,
      warnings: target.presentation.warnings,
    ),
  };
}

Map<String, Object?> _trendTargetJson(PreparedComparisonTarget target) {
  final region = target.presentation.region;
  return {
    'path': target.path,
    'inputKind': target.inputKind,
    if (target.sessionId != null) 'sessionId': target.sessionId,
    'selectedProfileId': target.selectedProfileId,
    'scope': _presentationScope(region),
    'regionId': region.regionId,
    'name': region.name,
    'durationMicros': region.durationMicros,
    'sampleCount': region.sampleCount,
  };
}

/// Converts prepared memory class inspection data to structured JSON.
Map<String, Object?> memoryClassInspectionJson(
  PreparedMemoryClassInspection inspection,
) {
  final memory = inspection.memory;
  return {
    'kind': 'memoryClassInspection',
    'cliCommand': _inspectClassesCliCommand(inspection),
    'targetPath': inspection.targetPath,
    'classQuery': inspection.classQuery,
    'minLiveBytes': inspection.minLiveBytes,
    'totalClassCount': memory.classCount,
    'matchedClassCount': memory.topClasses.length,
    'deltaHeapBytes': memory.deltaHeapBytes,
    'deltaExternalBytes': memory.deltaExternalBytes,
    'deltaCapacityBytes': memory.deltaCapacityBytes,
    'classes': [
      for (final item in memory.topClasses)
        {
          'className': item.className,
          'libraryUri': item.libraryUri,
          'liveBytes': item.liveBytes,
          'liveBytesDelta': item.liveBytesDelta,
          'liveInstances': item.liveInstances,
          'liveInstancesDelta': item.liveInstancesDelta,
          'allocationBytesDelta': item.allocationBytesDelta,
          'allocationInstancesDelta': item.allocationInstancesDelta,
        },
    ],
  };
}

String _presentationScope(ProfileRegionResult region) {
  if (region.regionId == 'overall' || region.attributes['scope'] == 'session') {
    return 'session';
  }
  return 'region';
}

String _sessionCliCommand(ProfileRunResult session) {
  if (session.command.isNotEmpty && session.command.first == 'attach') {
    final duration = _durationOptionForSession(session);
    return _shellJoin([
      'devtools-profiler',
      'attach',
      if (duration != null) ...['--duration', duration],
      '--cwd',
      session.workingDirectory,
      '--artifact-dir',
      session.artifactDirectory,
      session.vmServiceUri ?? session.command.skip(1).join(' '),
    ]);
  }
  return _shellJoin([
    'devtools-profiler',
    'run',
    '--cwd',
    session.workingDirectory,
    '--artifact-dir',
    session.artifactDirectory,
    '--',
    ...session.command,
  ]);
}

String _summarizeCliCommand(String targetPath) {
  return _shellJoin(['devtools-profiler', 'summarize', targetPath]);
}

String _compareCliCommand(PreparedProfileComparison comparison) {
  return _shellJoin([
    'devtools-profiler',
    'compare',
    if (comparison.baseline.selectedProfileId != 'overall') ...[
      '--baseline-profile-id',
      comparison.baseline.selectedProfileId,
    ],
    if (comparison.current.selectedProfileId != 'overall') ...[
      '--current-profile-id',
      comparison.current.selectedProfileId,
    ],
    comparison.baseline.path,
    comparison.current.path,
  ]);
}

String _explainCliCommand(PreparedProfileExplanation explanation) {
  return _shellJoin([
    'devtools-profiler',
    'explain',
    if (explanation.target.selectedProfileId != 'overall') ...[
      '--profile-id',
      explanation.target.selectedProfileId,
    ],
    explanation.target.path,
  ]);
}

String _inspectCliCommand(PreparedProfileMethodInspection inspection) {
  final queryOption = inspection.inspection.queryKind == 'methodId'
      ? '--method-id'
      : '--method';
  return _shellJoin([
    'devtools-profiler',
    'inspect',
    if (inspection.target.selectedProfileId != 'overall') ...[
      '--profile-id',
      inspection.target.selectedProfileId,
    ],
    queryOption,
    inspection.inspection.query,
    inspection.target.path,
  ]);
}

String _compareMethodCliCommand(PreparedProfileMethodComparison comparison) {
  final queryOption = comparison.comparison.queryKind == 'methodId'
      ? '--method-id'
      : '--method';
  return _shellJoin([
    'devtools-profiler',
    'compare-method',
    if (comparison.baseline.selectedProfileId != 'overall') ...[
      '--baseline-profile-id',
      comparison.baseline.selectedProfileId,
    ],
    if (comparison.current.selectedProfileId != 'overall') ...[
      '--current-profile-id',
      comparison.current.selectedProfileId,
    ],
    queryOption,
    comparison.comparison.query,
    comparison.baseline.path,
    comparison.current.path,
  ]);
}

String _searchMethodsCliCommand(PreparedProfileMethodSearch search) {
  return _shellJoin([
    'devtools-profiler',
    'search-methods',
    if (search.target.selectedProfileId != 'overall') ...[
      '--profile-id',
      search.target.selectedProfileId,
    ],
    if (search.search.query?.isNotEmpty == true) ...[
      '--query',
      search.search.query!,
    ],
    '--sort',
    search.search.sortBy.name,
    search.target.path,
  ]);
}

String _trendsCliCommand(PreparedProfileTrends trends) {
  return _shellJoin([
    'devtools-profiler',
    'trends',
    ...trends.targets.map((target) => target.path),
  ]);
}

String _inspectClassesCliCommand(PreparedMemoryClassInspection inspection) {
  return _shellJoin([
    'devtools-profiler',
    'inspect-classes',
    if (inspection.classQuery?.isNotEmpty == true) ...[
      '--class',
      inspection.classQuery!,
    ],
    if (inspection.minLiveBytes != null) ...[
      '--min-live-bytes',
      '${inspection.minLiveBytes}',
    ],
    inspection.targetPath,
  ]);
}

String _shellJoin(Iterable<String> arguments) {
  return arguments.map(_shellQuote).join(' ');
}

String _shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  const specialCharacters = "'\"\\\$`!|&;<>(){}[]*?";
  final needsQuoting = value.runes.any((rune) {
    final character = String.fromCharCode(rune);
    return character.trim().isEmpty || specialCharacters.contains(character);
  });
  if (!needsQuoting) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}

String? _durationOptionForSession(ProfileRunResult session) {
  final micros = session.overallProfile?.durationMicros;
  if (micros == null || micros <= 0) {
    return null;
  }
  if (micros % Duration.microsecondsPerSecond == 0) {
    return '${micros ~/ Duration.microsecondsPerSecond}s';
  }
  final milliseconds = (micros / Duration.microsecondsPerMillisecond).ceil();
  return '${milliseconds}ms';
}
