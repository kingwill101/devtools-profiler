import 'package:devtools_profiler_core/devtools_profiler_core.dart';

/// Resolved comparison target metadata and the prepared region view.
class PreparedComparisonTarget {
  /// Creates a prepared comparison target.
  const PreparedComparisonTarget({
    required this.path,
    required this.inputKind,
    required this.selectedProfileId,
    required this.presentation,
    this.sessionId,
  });

  /// The user-provided target path.
  final String path;

  /// The resolved target kind, either `session` or `artifact`.
  final String inputKind;

  /// The selected session profile id or region id.
  final String selectedProfileId;

  /// The prepared presentation for the selected profile.
  final PreparedRegionPresentation presentation;

  /// The owning session id when the source path was a session directory.
  final String? sessionId;
}

/// Prepared comparison data for CLI or MCP output.
class PreparedProfileComparison {
  /// Creates prepared comparison data.
  const PreparedProfileComparison({
    required this.baseline,
    required this.current,
    required this.comparison,
    required this.regressions,
  });

  /// The baseline comparison target.
  final PreparedComparisonTarget baseline;

  /// The current comparison target.
  final PreparedComparisonTarget current;

  /// The structured delta between the two targets.
  final ProfileRegionComparison comparison;

  /// Prioritized regression insights derived from the comparison.
  final ProfileRegressionSummary regressions;
}

/// Prepared hotspot explanation data for CLI or MCP output.
class PreparedProfileExplanation {
  /// Creates prepared explanation data.
  const PreparedProfileExplanation({
    required this.target,
    required this.hotspots,
  });

  /// The resolved profile target.
  final PreparedComparisonTarget target;

  /// Prioritized hotspot insights for the profile.
  final ProfileHotspotSummary hotspots;
}

/// Prepared method inspection data for CLI or MCP output.
class PreparedProfileMethodInspection {
  /// Creates prepared method inspection data.
  const PreparedProfileMethodInspection({
    required this.target,
    required this.inspection,
  });

  /// The resolved profile target.
  final PreparedComparisonTarget target;

  /// The inspection result for the selected method query.
  final ProfileMethodInspection inspection;
}

/// Prepared method comparison data for CLI or MCP output.
class PreparedProfileMethodComparison {
  /// Creates prepared method comparison data.
  const PreparedProfileMethodComparison({
    required this.baseline,
    required this.current,
    required this.comparison,
  });

  /// The baseline profile target.
  final PreparedComparisonTarget baseline;

  /// The current profile target.
  final PreparedComparisonTarget current;

  /// The method comparison result.
  final ProfileMethodComparison comparison;
}

/// Prepared method search data for CLI or MCP output.
class PreparedProfileMethodSearch {
  /// Creates prepared method search data.
  const PreparedProfileMethodSearch({
    required this.target,
    required this.search,
  });

  /// The resolved profile target.
  final PreparedComparisonTarget target;

  /// The method search result.
  final ProfileMethodSearchResult search;
}

/// Prepared cross-session profile trend data for CLI or MCP output.
class PreparedProfileTrends {
  /// Creates prepared trend data.
  const PreparedProfileTrends({required this.targets, required this.trends});

  /// The resolved profile targets in series order.
  final List<PreparedComparisonTarget> targets;

  /// The aggregated trend summary.
  final ProfileTrendSummary trends;
}

/// Prepared session data for CLI or MCP output.
class PreparedSessionPresentation {
  /// Creates prepared session data.
  const PreparedSessionPresentation({
    required this.session,
    this.overallTree,
    this.overallBottomUpTree,
    this.overallMethodTable,
    required this.regionTrees,
    required this.regionBottomUpTrees,
    required this.regionMethodTables,
  });

  /// The session result with region summaries adjusted for the view options.
  final ProfileRunResult session;

  /// The whole-session call tree, when requested.
  final ProfileCallTree? overallTree;

  /// The whole-session bottom-up tree, when requested.
  final ProfileCallTree? overallBottomUpTree;

  /// The whole-session method table, when requested.
  final ProfileMethodTable? overallMethodTable;

  /// Call trees keyed by region id.
  final Map<String, ProfileCallTree> regionTrees;

  /// Bottom-up trees keyed by region id.
  final Map<String, ProfileCallTree> regionBottomUpTrees;

  /// Method tables keyed by region id.
  final Map<String, ProfileMethodTable> regionMethodTables;
}

/// Prepared region data for CLI or MCP output.
class PreparedRegionPresentation {
  /// Creates prepared region data.
  const PreparedRegionPresentation({
    required this.region,
    this.callTree,
    this.bottomUpTree,
    this.methodTable,
    this.warnings = const [],
  });

  /// The region summary adjusted for the view options.
  final ProfileRegionResult region;

  /// The optional region call tree.
  final ProfileCallTree? callTree;

  /// The optional region bottom-up tree.
  final ProfileCallTree? bottomUpTree;

  /// The optional region method table.
  final ProfileMethodTable? methodTable;

  /// Warnings generated while preparing this region, such as a mismatch
  /// between the stored sample count and the count re-derived from the raw
  /// CPU profile artifact.
  final List<String> warnings;
}
