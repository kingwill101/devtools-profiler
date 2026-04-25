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
  ProfileMethodTable? methodTable,
) {
  return {
    ...region.toJson(),
    if (callTree != null) 'callTree': callTree.toJson(),
    if (bottomUpTree != null) 'bottomUpTree': bottomUpTree.toJson(),
    if (methodTable != null) 'methodTable': methodTable.toJson(),
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

String _presentationScope(ProfileRegionResult region) {
  if (region.regionId == 'overall' || region.attributes['scope'] == 'session') {
    return 'session';
  }
  return 'region';
}
