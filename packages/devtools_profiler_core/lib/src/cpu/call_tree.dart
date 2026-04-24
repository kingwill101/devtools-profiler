import 'package:vm_service/vm_service.dart';

import 'profile_frames.dart';

const _rootFrameName = 'all';

/// Supported hierarchical CPU profile tree views.
enum ProfileCallTreeView {
  /// A standard top-down inclusive call tree.
  topDown,

  /// A DevTools-style bottom-up tree where roots are leaf methods and
  /// descendants are callers.
  bottomUp;

  /// Parses a wire value.
  static ProfileCallTreeView parse(String value) {
    for (final view in values) {
      if (view.name == value) {
        return view;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unsupported call tree view.');
  }
}

/// A hierarchical CPU profile tree built from VM CPU samples.
class ProfileCallTree {
  /// Creates a call tree rooted at [root].
  const ProfileCallTree({
    required this.sampleCount,
    required this.samplePeriodMicros,
    required this.root,
    this.view = ProfileCallTreeView.topDown,
  });

  /// Deserializes a call tree from JSON.
  factory ProfileCallTree.fromJson(Map<String, Object?> json) {
    return ProfileCallTree(
      sampleCount: json['sampleCount'] as int? ?? 0,
      samplePeriodMicros: json['samplePeriodMicros'] as int? ?? 0,
      view: switch (json['view']) {
        final String value => ProfileCallTreeView.parse(value),
        _ => ProfileCallTreeView.topDown,
      },
      root: ProfileCallTreeNode.fromJson(
        (json['root'] as Map<Object?, Object?>? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      ),
    );
  }

  /// The total number of samples in the captured region.
  final int sampleCount;

  /// The VM-reported sample period in microseconds.
  final int samplePeriodMicros;

  /// The tree view type represented by [root].
  final ProfileCallTreeView view;

  /// The synthetic `all` root of the tree.
  final ProfileCallTreeNode root;

  /// Returns a copy of this tree limited to [maxDepth] and [maxChildren].
  ///
  /// A value of `null` or `<= 0` disables the corresponding limit.
  ProfileCallTree limited({int? maxDepth, int? maxChildren}) {
    return ProfileCallTree(
      sampleCount: sampleCount,
      samplePeriodMicros: samplePeriodMicros,
      view: view,
      root: root.limited(
        currentDepth: 0,
        maxDepth: maxDepth,
        maxChildren: maxChildren,
      ),
    );
  }

  /// Converts this call tree to JSON.
  Map<String, Object?> toJson() => {
    'sampleCount': sampleCount,
    'samplePeriodMicros': samplePeriodMicros,
    'view': view.name,
    'root': root.toJson(),
  };
}

/// A single node in a hierarchical CPU profile tree.
class ProfileCallTreeNode {
  /// Creates a call tree node.
  const ProfileCallTreeNode({
    required this.name,
    required this.kind,
    required this.selfSamples,
    required this.totalSamples,
    required this.selfPercent,
    required this.totalPercent,
    required this.selfMicros,
    required this.totalMicros,
    required this.children,
    this.location,
  });

  /// Deserializes a node from JSON.
  factory ProfileCallTreeNode.fromJson(Map<String, Object?> json) {
    return ProfileCallTreeNode(
      name: json['name'] as String? ?? 'unknown',
      kind: json['kind'] as String? ?? 'unknown',
      location: json['location'] as String?,
      selfSamples: json['selfSamples'] as int? ?? 0,
      totalSamples: json['totalSamples'] as int? ?? 0,
      selfPercent: (json['selfPercent'] as num?)?.toDouble() ?? 0.0,
      totalPercent: (json['totalPercent'] as num?)?.toDouble() ?? 0.0,
      selfMicros: json['selfMicros'] as int? ?? 0,
      totalMicros: json['totalMicros'] as int? ?? 0,
      children: (json['children'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (child) => ProfileCallTreeNode.fromJson(
              child.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(),
    );
  }

  /// The display name for this frame.
  final String name;

  /// The VM-reported frame kind.
  final String kind;

  /// The resolved source location, when available.
  final String? location;

  /// The number of samples that stopped at this frame.
  final int selfSamples;

  /// The number of samples attributed to this frame in the current view.
  final int totalSamples;

  /// The self sample ratio in the range `[0, 1]`.
  final double selfPercent;

  /// The total sample ratio in the range `[0, 1]`.
  final double totalPercent;

  /// Approximate self time for this frame in microseconds.
  final int selfMicros;

  /// Approximate attributed time for this frame in microseconds.
  final int totalMicros;

  /// Child frames ordered by descending attributed cost.
  final List<ProfileCallTreeNode> children;

  /// Returns a copy of this node limited to [maxDepth] and [maxChildren].
  ProfileCallTreeNode limited({
    required int currentDepth,
    int? maxDepth,
    int? maxChildren,
  }) {
    final normalizedMaxDepth = maxDepth == null || maxDepth <= 0
        ? null
        : maxDepth;
    final normalizedMaxChildren = maxChildren == null || maxChildren <= 0
        ? null
        : maxChildren;

    if (normalizedMaxDepth != null && currentDepth >= normalizedMaxDepth) {
      return ProfileCallTreeNode(
        name: name,
        kind: kind,
        location: location,
        selfSamples: selfSamples,
        totalSamples: totalSamples,
        selfPercent: selfPercent,
        totalPercent: totalPercent,
        selfMicros: selfMicros,
        totalMicros: totalMicros,
        children: const [],
      );
    }

    final childLimit = normalizedMaxChildren ?? children.length;
    final limitedChildren = [
      for (final child in children.take(childLimit))
        child.limited(
          currentDepth: currentDepth + 1,
          maxDepth: normalizedMaxDepth,
          maxChildren: normalizedMaxChildren,
        ),
    ];

    return ProfileCallTreeNode(
      name: name,
      kind: kind,
      location: location,
      selfSamples: selfSamples,
      totalSamples: totalSamples,
      selfPercent: selfPercent,
      totalPercent: totalPercent,
      selfMicros: selfMicros,
      totalMicros: totalMicros,
      children: limitedChildren,
    );
  }

  /// Converts this node to JSON.
  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind,
    'location': location,
    'selfSamples': selfSamples,
    'totalSamples': totalSamples,
    'selfPercent': selfPercent,
    'totalPercent': totalPercent,
    'selfMicros': selfMicros,
    'totalMicros': totalMicros,
    'children': children.map((child) => child.toJson()).toList(),
  };
}

/// Builds a top-down call tree from raw VM CPU samples.
ProfileCallTree buildCallTree({
  required CpuSamples cpuSamples,
  ProfileFramePredicate? includeFrame,
}) {
  final buildResult = _buildTopDownTree(
    cpuSamples: cpuSamples,
    includeFrame: includeFrame,
  );
  return ProfileCallTree(
    sampleCount: buildResult.sampleCount,
    samplePeriodMicros: buildResult.samplePeriodMicros,
    view: ProfileCallTreeView.topDown,
    root: buildResult.root.freeze(
      totalSampleCount: buildResult.sampleCount,
      samplePeriodMicros: buildResult.samplePeriodMicros,
    ),
  );
}

/// Builds a DevTools-style bottom-up tree from raw VM CPU samples.
ProfileCallTree buildBottomUpTree({
  required CpuSamples cpuSamples,
  ProfileFramePredicate? includeFrame,
}) {
  final buildResult = _buildTopDownTree(
    cpuSamples: cpuSamples,
    includeFrame: includeFrame,
  );
  final bottomUpRoots = <_MutableBottomUpNode>[];

  for (final rootChild in buildResult.root.children) {
    _generateBottomUpRoots(
      node: rootChild,
      parent: null,
      bottomUpRoots: bottomUpRoots,
    );
  }

  final mergedRoots = _mergeBottomUpNodes(bottomUpRoots);
  final syntheticRoot = _MutableBottomUpNode.root(
    sampleCount: buildResult.sampleCount,
  )..children.addAll(mergedRoots);

  return ProfileCallTree(
    sampleCount: buildResult.sampleCount,
    samplePeriodMicros: buildResult.samplePeriodMicros,
    view: ProfileCallTreeView.bottomUp,
    root: syntheticRoot.freeze(
      totalSampleCount: buildResult.sampleCount,
      samplePeriodMicros: buildResult.samplePeriodMicros,
    ),
  );
}

_TopDownBuildResult _buildTopDownTree({
  required CpuSamples cpuSamples,
  ProfileFramePredicate? includeFrame,
}) {
  final samplePeriodMicros = cpuSamples.samplePeriod ?? 0;
  final functions = cpuSamples.functions ?? const <ProfileFunction>[];
  final root = _MutableCallTreeNode.root();
  var sampleCount = 0;

  for (final sample in cpuSamples.samples ?? const <CpuSample>[]) {
    final frames = filterStackFrames(
      sample.stack ?? const <int>[],
      functions,
      includeFrame: includeFrame,
    );
    if (frames.isEmpty) continue;

    sampleCount++;
    root.totalSamples++;

    var current = root;
    for (final frame in frames.reversed) {
      final child = current.childFor(frame);
      child.totalSamples++;
      current = child;
    }
    current.selfSamples++;
  }

  return _TopDownBuildResult(
    sampleCount: sampleCount,
    samplePeriodMicros: samplePeriodMicros,
    root: root,
  );
}

void _generateBottomUpRoots({
  required _MutableCallTreeNode node,
  required _MutableBottomUpNode? parent,
  required List<_MutableBottomUpNode> bottomUpRoots,
}) {
  final copy = _MutableBottomUpNode.fromTopDownNode(node);
  if (parent != null) {
    copy.children.add(parent);
  }

  if (node.selfSamples > 0) {
    final rootCopy = copy.deepCopy();
    rootCopy.cascadeSampleCounts();
    bottomUpRoots.add(rootCopy);
  }

  for (final child in node.children) {
    _generateBottomUpRoots(
      node: child,
      parent: copy,
      bottomUpRoots: bottomUpRoots,
    );
  }
}

List<_MutableBottomUpNode> _mergeBottomUpNodes(
  List<_MutableBottomUpNode> nodes,
) {
  final mergedByKey = <String, _MutableBottomUpNode>{};

  for (final node in nodes) {
    final existing = mergedByKey[node.frameKey];
    if (existing == null) {
      mergedByKey[node.frameKey] = node.deepCopy();
      continue;
    }
    existing.selfSamples += node.selfSamples;
    existing.totalSamples += node.totalSamples;
    existing.children.addAll(node.children.map((child) => child.deepCopy()));
  }

  final merged = mergedByKey.values.toList()..sort(_compareMutableNodes);
  for (final node in merged) {
    final mergedChildren = _mergeBottomUpNodes(node.children);
    node.children
      ..clear()
      ..addAll(mergedChildren);
  }
  return merged;
}

final class _TopDownBuildResult {
  const _TopDownBuildResult({
    required this.sampleCount,
    required this.samplePeriodMicros,
    required this.root,
  });

  final int sampleCount;
  final int samplePeriodMicros;
  final _MutableCallTreeNode root;
}

final class _MutableCallTreeNode {
  _MutableCallTreeNode({
    required this.name,
    required this.kind,
    required this.location,
  });

  factory _MutableCallTreeNode.root() =>
      _MutableCallTreeNode(name: _rootFrameName, kind: 'root', location: null);

  factory _MutableCallTreeNode.fromFrame(ProfileFrame frame) {
    return _MutableCallTreeNode(
      name: frame.name,
      kind: frame.kind,
      location: frame.location,
    );
  }

  final String name;
  final String kind;
  final String? location;
  final Map<String, _MutableCallTreeNode> _childrenByKey = {};

  int selfSamples = 0;
  int totalSamples = 0;

  Iterable<_MutableCallTreeNode> get children => _childrenByKey.values;

  _MutableCallTreeNode childFor(ProfileFrame frame) {
    return _childrenByKey.putIfAbsent(
      frame.key,
      () => _MutableCallTreeNode.fromFrame(frame),
    );
  }

  ProfileCallTreeNode freeze({
    required int totalSampleCount,
    required int samplePeriodMicros,
  }) {
    final divisor = totalSampleCount == 0 ? 1 : totalSampleCount;
    final children =
        _childrenByKey.values
            .map(
              (child) => child.freeze(
                totalSampleCount: totalSampleCount,
                samplePeriodMicros: samplePeriodMicros,
              ),
            )
            .toList()
          ..sort(_compareCallTreeNodes);

    return ProfileCallTreeNode(
      name: name,
      kind: kind,
      location: location,
      selfSamples: selfSamples,
      totalSamples: totalSamples,
      selfPercent: selfSamples / divisor,
      totalPercent: totalSamples / divisor,
      selfMicros: selfSamples * samplePeriodMicros,
      totalMicros: totalSamples * samplePeriodMicros,
      children: children,
    );
  }
}

final class _MutableBottomUpNode {
  _MutableBottomUpNode({
    required this.name,
    required this.kind,
    required this.location,
    required this.selfSamples,
    required this.totalSamples,
  });

  factory _MutableBottomUpNode.root({required int sampleCount}) {
    return _MutableBottomUpNode(
      name: _rootFrameName,
      kind: 'root',
      location: null,
      selfSamples: 0,
      totalSamples: sampleCount,
    );
  }

  factory _MutableBottomUpNode.fromTopDownNode(_MutableCallTreeNode node) {
    return _MutableBottomUpNode(
      name: node.name,
      kind: node.kind,
      location: node.location,
      selfSamples: node.selfSamples,
      totalSamples: node.totalSamples,
    );
  }

  final String name;
  final String kind;
  final String? location;
  final List<_MutableBottomUpNode> children = [];

  int selfSamples;
  int totalSamples;

  String get frameKey => '$kind::$name::$location';

  _MutableBottomUpNode deepCopy() {
    return _MutableBottomUpNode(
      name: name,
      kind: kind,
      location: location,
      selfSamples: selfSamples,
      totalSamples: totalSamples,
    )..children.addAll(children.map((child) => child.deepCopy()));
  }

  void cascadeSampleCounts() {
    for (final child in children) {
      child
        ..selfSamples = selfSamples
        ..totalSamples = totalSamples;
      child.cascadeSampleCounts();
    }
  }

  ProfileCallTreeNode freeze({
    required int totalSampleCount,
    required int samplePeriodMicros,
  }) {
    final divisor = totalSampleCount == 0 ? 1 : totalSampleCount;
    final frozenChildren =
        children
            .map(
              (child) => child.freeze(
                totalSampleCount: totalSampleCount,
                samplePeriodMicros: samplePeriodMicros,
              ),
            )
            .toList()
          ..sort(_compareCallTreeNodes);

    return ProfileCallTreeNode(
      name: name,
      kind: kind,
      location: location,
      selfSamples: selfSamples,
      totalSamples: totalSamples,
      selfPercent: selfSamples / divisor,
      totalPercent: totalSamples / divisor,
      selfMicros: selfSamples * samplePeriodMicros,
      totalMicros: totalSamples * samplePeriodMicros,
      children: frozenChildren,
    );
  }
}

int _compareMutableNodes(_MutableBottomUpNode a, _MutableBottomUpNode b) {
  final totalCompare = b.totalSamples.compareTo(a.totalSamples);
  if (totalCompare != 0) return totalCompare;

  final selfCompare = b.selfSamples.compareTo(a.selfSamples);
  if (selfCompare != 0) return selfCompare;

  return a.name.compareTo(b.name);
}

int _compareCallTreeNodes(ProfileCallTreeNode a, ProfileCallTreeNode b) {
  final totalCompare = b.totalSamples.compareTo(a.totalSamples);
  if (totalCompare != 0) return totalCompare;

  final selfCompare = b.selfSamples.compareTo(a.selfSamples);
  if (selfCompare != 0) return selfCompare;

  return a.name.compareTo(b.name);
}
