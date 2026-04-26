import 'package:devtools_profiler_core/devtools_profiler_core.dart';

/// Default tree depth for expanded CLI and MCP responses.
const defaultTreeDepth = 8;

/// Default maximum child count per call tree node.
const defaultTreeChildren = 12;

/// Default number of rows to show in summary tables.
const defaultFrameLimit = 12;

/// Default number of memory classes to show in class-inspection output.
const defaultMemoryClassLimit = 50;

/// Package prefixes that belong to profiler transport/runtime helpers.
const runtimeHelperPackagePrefixes = [
  'devtools_profiler_',
  'dtd',
  'json_rpc_2',
  'stream_channel',
  'web_socket_channel',
];

/// Rendering options shared by the CLI and MCP server.
class ProfilePresentationOptions {
  /// Creates presentation options.
  const ProfilePresentationOptions({
    this.includeCallTree = false,
    this.includeBottomUpTree = false,
    this.includeMethodTable = false,
    this.maxDepth,
    this.maxChildren,
    this.hideSdk = false,
    this.hideRuntimeHelpers = false,
    this.frameLimit = defaultFrameLimit,
    this.methodLimit = defaultFrameLimit,
    this.fullLocations = false,
    this.includePackages = const [],
    this.excludePackages = const [],
  });

  /// Whether a top-down call tree should be attached.
  final bool includeCallTree;

  /// Whether a bottom-up tree should be attached.
  final bool includeBottomUpTree;

  /// Whether a method table should be attached.
  final bool includeMethodTable;

  /// Maximum call tree depth, or `null` for unlimited.
  final int? maxDepth;

  /// Maximum child count per tree node, or `null` for unlimited.
  final int? maxChildren;

  /// Whether SDK frames should be hidden from summaries and trees.
  final bool hideSdk;

  /// Whether common profiler/runtime helper packages should be hidden.
  final bool hideRuntimeHelpers;

  /// Maximum rows in the self / total tables, or `null` for unlimited.
  final int? frameLimit;

  /// Maximum methods in the method table, or `null` for unlimited.
  final int? methodLimit;

  /// Whether human-readable output should use full source locations.
  final bool fullLocations;

  /// Optional package prefixes to keep.
  final List<String> includePackages;

  /// Optional package prefixes to exclude.
  final List<String> excludePackages;

  /// Whether any frame-level filters are active.
  bool get hasActiveFrameFilters =>
      hideSdk ||
      hideRuntimeHelpers ||
      includePackages.isNotEmpty ||
      excludePackages.isNotEmpty;

  /// User-facing descriptions for active frame filters.
  List<String> get activeFrameFilterDescriptions => [
    if (hideSdk) '--hide-sdk',
    if (hideRuntimeHelpers) '--hide-runtime-helpers',
    for (final package in includePackages) '--include-package $package',
    for (final package in excludePackages) '--exclude-package $package',
  ];

  /// A compact user-facing label for active frame filters.
  String get activeFrameFilterLabel {
    final descriptions = activeFrameFilterDescriptions;
    return descriptions.isEmpty ? '(none)' : descriptions.join(', ');
  }

  /// The predicate applied while building summaries and call trees.
  ProfileFramePredicate? get framePredicate {
    final excludePrefixes = [
      ...excludePackages,
      if (hideRuntimeHelpers) ...runtimeHelperPackagePrefixes,
    ];
    final includePrefixes = includePackages;
    if (!hasActiveFrameFilters) {
      return null;
    }
    return (frame) {
      if (hideSdk && frame.isSdk) {
        return false;
      }
      final packageName = frame.packageName;
      if (includePrefixes.isNotEmpty &&
          (packageName == null ||
              !_matchesPackagePrefixes(packageName, includePrefixes))) {
        return false;
      }
      if (packageName != null &&
          _matchesPackagePrefixes(packageName, excludePrefixes)) {
        return false;
      }
      return true;
    };
  }

  /// Returns a copy with selected fields replaced.
  ProfilePresentationOptions copyWith({
    bool? includeCallTree,
    bool? includeBottomUpTree,
    bool? includeMethodTable,
    int? maxDepth,
    int? maxChildren,
    bool? hideSdk,
    bool? hideRuntimeHelpers,
    int? frameLimit,
    int? methodLimit,
    bool? fullLocations,
    List<String>? includePackages,
    List<String>? excludePackages,
  }) {
    return ProfilePresentationOptions(
      includeCallTree: includeCallTree ?? this.includeCallTree,
      includeBottomUpTree: includeBottomUpTree ?? this.includeBottomUpTree,
      includeMethodTable: includeMethodTable ?? this.includeMethodTable,
      maxDepth: maxDepth ?? this.maxDepth,
      maxChildren: maxChildren ?? this.maxChildren,
      hideSdk: hideSdk ?? this.hideSdk,
      hideRuntimeHelpers: hideRuntimeHelpers ?? this.hideRuntimeHelpers,
      frameLimit: frameLimit ?? this.frameLimit,
      methodLimit: methodLimit ?? this.methodLimit,
      fullLocations: fullLocations ?? this.fullLocations,
      includePackages: includePackages ?? this.includePackages,
      excludePackages: excludePackages ?? this.excludePackages,
    );
  }
}

bool _matchesPackagePrefixes(String packageName, List<String> prefixes) {
  for (final prefix in prefixes) {
    if (packageName.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}
