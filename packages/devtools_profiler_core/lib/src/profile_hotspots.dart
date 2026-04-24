
import 'call_tree.dart';
import 'method_table.dart';
import 'models.dart';
import 'profile_frames.dart';

const _runtimeHelperPackagePrefixes = [
  'devtools_profiler_',
  'dtd',
  'json_rpc_2',
  'stream_channel',
  'web_socket_channel',
];

/// Severity for a hotspot insight.
enum ProfileHotspotSeverity {
  /// Strong, likely important signal.
  high,

  /// Meaningful signal worth attention.
  medium,

  /// Smaller or lower-confidence signal.
  low;

  int get weight => switch (this) {
        high => 3,
        medium => 2,
        low => 1,
      };
}

/// A single hotspot insight derived from a prepared profile.
class ProfileHotspotInsight {
  /// Creates a hotspot insight.
  const ProfileHotspotInsight({
    required this.kind,
    required this.subject,
    required this.title,
    required this.summary,
    required this.severity,
    this.location,
    this.path,
    this.bottomUpPath,
    this.focusMethod,
  });

  /// Insight category such as `selfFrame`, `memory`, or `distribution`.
  final String kind;

  /// The frame, method, or memory subject this insight refers to.
  final String subject;

  /// Short title for the insight.
  final String title;

  /// Human-readable explanation.
  final String summary;

  /// Relative importance of the insight.
  final ProfileHotspotSeverity severity;

  /// Source location for the subject when available.
  final String? location;

  /// Representative top-down path to the hotspot, when available.
  final ProfileHotspotPath? path;

  /// Representative bottom-up path to the hotspot, when available.
  final ProfileHotspotPath? bottomUpPath;

  /// Compact method context for follow-up inspection, when available.
  final ProfileHotspotMethodContext? focusMethod;

  /// Converts this insight to JSON.
  Map<String, Object?> toJson() => {
        'kind': kind,
        'subject': subject,
        'title': title,
        'summary': summary,
        'severity': severity.name,
        'location': location,
        if (path != null) 'path': path!.toJson(),
        if (bottomUpPath != null) 'bottomUpPath': bottomUpPath!.toJson(),
        if (focusMethod != null) 'focusMethod': focusMethod!.toJson(),
      };
}

/// Compact method context attached to a hotspot insight.
class ProfileHotspotMethodContext {
  /// Creates a hotspot method context.
  ProfileHotspotMethodContext({
    required this.methodId,
    required this.name,
    required this.kind,
    required this.selfSamples,
    required this.totalSamples,
    required this.selfPercent,
    required this.totalPercent,
    required List<ProfileMethodRelation> callers,
    required List<ProfileMethodRelation> callees,
    this.location,
  })  : callers = List.unmodifiable(callers),
        callees = List.unmodifiable(callees);

  /// Builds compact context from a method summary.
  factory ProfileHotspotMethodContext.fromMethodSummary(
    ProfileMethodSummary summary, {
    int relationLimit = 3,
  }) {
    List<ProfileMethodRelation> limitRelations(
        List<ProfileMethodRelation> list) {
      if (relationLimit <= 0 || list.length <= relationLimit) {
        return list;
      }
      return list.take(relationLimit).toList(growable: false);
    }

    return ProfileHotspotMethodContext(
      methodId: summary.methodId,
      name: summary.name,
      kind: summary.kind,
      location: summary.location,
      selfSamples: summary.selfSamples,
      totalSamples: summary.totalSamples,
      selfPercent: summary.selfPercent,
      totalPercent: summary.totalPercent,
      callers: limitRelations(summary.callers),
      callees: limitRelations(summary.callees),
    );
  }

  /// Stable identifier for the focus method.
  final String methodId;

  /// Display name of the focus method.
  final String name;

  /// VM-reported frame kind.
  final String kind;

  /// Source location for the focus method, when available.
  final String? location;

  /// Top-of-stack samples for the focus method.
  final int selfSamples;

  /// Inclusive samples for the focus method.
  final int totalSamples;

  /// Top-of-stack percent for the focus method.
  final double selfPercent;

  /// Inclusive percent for the focus method.
  final double totalPercent;

  /// Highest-signal callers for the focus method.
  final List<ProfileMethodRelation> callers;

  /// Highest-signal callees for the focus method.
  final List<ProfileMethodRelation> callees;

  /// Converts this context to JSON.
  Map<String, Object?> toJson() => {
        'methodId': methodId,
        'name': name,
        'kind': kind,
        'location': location,
        'selfSamples': selfSamples,
        'totalSamples': totalSamples,
        'selfPercent': selfPercent,
        'totalPercent': totalPercent,
        'callers': [for (final caller in callers) caller.toJson()],
        'callees': [for (final callee in callees) callee.toJson()],
      };
}

/// A frame in a representative hotspot call path.
class ProfileHotspotPathFrame {
  /// Creates a hotspot path frame.
  const ProfileHotspotPathFrame({
    required this.name,
    required this.kind,
    required this.selfSamples,
    required this.totalSamples,
    this.location,
  });

  /// Display name for the frame.
  final String name;

  /// The VM-reported frame kind.
  final String kind;

  /// Self samples attributed to this frame in the selected path.
  final int selfSamples;

  /// Inclusive samples attributed to this frame in the selected path.
  final int totalSamples;

  /// The resolved location for the frame, when available.
  final String? location;

  /// Converts this path frame to JSON.
  Map<String, Object?> toJson() => {
        'name': name,
        'kind': kind,
        'selfSamples': selfSamples,
        'totalSamples': totalSamples,
        'location': location,
      };
}

/// A representative call path for a hotspot insight.
class ProfileHotspotPath {
  /// Creates a hotspot path.
  ProfileHotspotPath({
    required this.view,
    required List<ProfileHotspotPathFrame> frames,
  }) : frames = List.unmodifiable(frames);

  /// The call tree view used for the path.
  final ProfileCallTreeView view;

  /// Ordered frames from root to hotspot.
  final List<ProfileHotspotPathFrame> frames;

  /// Converts this path to JSON.
  Map<String, Object?> toJson() => {
        'view': view.name,
        'frames': [for (final frame in frames) frame.toJson()],
      };
}

/// A structured explanation of a prepared profile's hotspots.
class ProfileHotspotSummary {
  /// Creates a hotspot summary.
  ProfileHotspotSummary({
    required this.status,
    required List<ProfileHotspotInsight> insights,
    required List<String> warnings,
  })  : insights = List.unmodifiable(insights),
        warnings = List.unmodifiable(warnings);

  /// Overall analysis status.
  final String status;

  /// Prioritized hotspot insights.
  final List<ProfileHotspotInsight> insights;

  /// Extra notes about confidence or missing data.
  final List<String> warnings;

  /// Converts this summary to JSON.
  Map<String, Object?> toJson() => {
        'status': status,
        'insights': [for (final insight in insights) insight.toJson()],
        'warnings': warnings,
      };
}

/// Builds prioritized hotspot insights from a prepared profile summary.
ProfileHotspotSummary explainProfileHotspots(
  ProfileRegionResult region, {
  ProfileMethodTable? methodTable,
  ProfileCallTree? callTree,
  ProfileCallTree? bottomUpTree,
  int maxInsights = 6,
  int relationLimit = 3,
}) {
  if (region.error != null) {
    return ProfileHotspotSummary(
      status: 'error',
      insights: [
        ProfileHotspotInsight(
          kind: 'error',
          subject: region.name,
          title: 'Profile capture failed',
          summary: region.error!,
          severity: ProfileHotspotSeverity.high,
        ),
      ],
      warnings: const [],
    );
  }

  final warnings = <String>[];
  final insights = <ProfileHotspotInsight>[];

  if (region.sampleCount == 0 && region.memory == null) {
    return ProfileHotspotSummary(
      status: 'noData',
      insights: const [],
      warnings: const [
        'The selected profile did not contain CPU or memory data.'
      ],
    );
  }

  if (region.sampleCount > 0 && region.sampleCount < 10) {
    warnings.add(
      'Only ${region.sampleCount} CPU samples were captured. Treat hotspot rankings as low confidence.',
    );
  }

  final topSelf =
      region.topSelfFrames.isEmpty ? null : region.topSelfFrames.first;
  final topTotal =
      region.topTotalFrames.isEmpty ? null : region.topTotalFrames.first;

  if (topSelf != null) {
    final focusMethod = _findFocusMethod(
      methodTable,
      name: topSelf.name,
      kind: topSelf.kind,
      location: topSelf.location,
      relationLimit: relationLimit,
    );
    final path = _representativePath(
      callTree,
      name: topSelf.name,
      kind: topSelf.kind,
      location: topSelf.location,
      score: (node) => node.selfSamples * 10 + node.totalSamples,
    );
    final bottomPath = _representativePath(
      bottomUpTree,
      name: topSelf.name,
      kind: topSelf.kind,
      location: topSelf.location,
      score: (node) => node.selfSamples * 10 + node.totalSamples,
    );
    insights.add(
      ProfileHotspotInsight(
        kind: 'selfFrame',
        subject: topSelf.name,
        title: 'Self time is concentrated in ${topSelf.name}',
        summary:
            '${_formatPercent(topSelf.selfPercent)} of samples stop in ${topSelf.name} '
            '(${topSelf.selfSamples}/${region.sampleCount}).',
        severity: _severityForPercent(
          topSelf.selfPercent,
          mediumThreshold: 0.25,
          highThreshold: 0.50,
        ),
        location: topSelf.location,
        path: path,
        bottomUpPath: bottomPath,
        focusMethod: focusMethod,
      ),
    );
  }

  if (topTotal != null) {
    final focusMethod = _findFocusMethod(
      methodTable,
      name: topTotal.name,
      kind: topTotal.kind,
      location: topTotal.location,
      relationLimit: relationLimit,
    );
    final path = _representativePath(
      callTree,
      name: topTotal.name,
      kind: topTotal.kind,
      location: topTotal.location,
      score: (node) => node.totalSamples * 10 + node.selfSamples,
    );
    final bottomPath = _representativePath(
      bottomUpTree,
      name: topTotal.name,
      kind: topTotal.kind,
      location: topTotal.location,
      score: (node) => node.totalSamples * 10 + node.selfSamples,
    );
    insights.add(
      ProfileHotspotInsight(
        kind: 'totalFrame',
        subject: topTotal.name,
        title: 'Inclusive cost accumulates under ${topTotal.name}',
        summary:
            '${_formatPercent(topTotal.totalPercent)} of samples include ${topTotal.name} '
            '(${topTotal.totalSamples}/${region.sampleCount}).',
        severity: _severityForPercent(
          topTotal.totalPercent,
          mediumThreshold: 0.50,
          highThreshold: 0.80,
        ),
        location: topTotal.location,
        path: path,
        bottomUpPath: bottomPath,
        focusMethod: focusMethod,
      ),
    );
  }

  if (topSelf != null) {
    final topFrame = ProfileFrame(
      name: topSelf.name,
      kind: topSelf.kind,
      location: topSelf.location,
    );
    if (topFrame.isSdk || _isRuntimeHelperFrame(topFrame)) {
      insights.add(
        ProfileHotspotInsight(
          kind: 'runtimeNoise',
          subject: topSelf.name,
          title: 'Top frame is runtime or helper code',
          summary:
              'The hottest self frame is ${topSelf.name}, which appears to come from '
              'SDK/runtime helper code. Consider hiding SDK or helper packages to expose user frames.',
          severity: ProfileHotspotSeverity.low,
          location: topSelf.location,
        ),
      );
    }
  }

  if (topSelf != null && topSelf.selfPercent < 0.20) {
    insights.add(
      ProfileHotspotInsight(
        kind: 'distribution',
        subject: region.name,
        title: 'Work is spread across multiple frames',
        summary:
            'No single self frame exceeds 20% of samples, so the bottleneck is likely distributed across a wider call path.',
        severity: ProfileHotspotSeverity.low,
      ),
    );
  }

  final topMethod =
      methodTable?.methods.isEmpty ?? true ? null : methodTable!.methods.first;
  if (topMethod != null) {
    final dominantCallee =
        topMethod.callees.isEmpty ? null : topMethod.callees.first;
    if (dominantCallee != null && dominantCallee.percent >= 0.5) {
      final focusMethod = _findFocusMethod(
        methodTable,
        name: dominantCallee.name,
        kind: dominantCallee.kind,
        location: dominantCallee.location,
        relationLimit: relationLimit,
      );
      final path = _representativePath(
        callTree,
        name: dominantCallee.name,
        kind: dominantCallee.kind,
        location: dominantCallee.location,
        score: (node) => node.totalSamples * 10 + node.selfSamples,
      );
      final bottomPath = _representativePath(
        bottomUpTree,
        name: dominantCallee.name,
        kind: dominantCallee.kind,
        location: dominantCallee.location,
        score: (node) => node.totalSamples * 10 + node.selfSamples,
      );
      insights.add(
        ProfileHotspotInsight(
          kind: 'callee',
          subject: dominantCallee.name,
          title:
              'Most work under ${topMethod.name} flows into ${dominantCallee.name}',
          summary:
              '${_formatPercent(dominantCallee.percent)} of ${topMethod.name}\'s callee edges point to ${dominantCallee.name}.',
          severity: _severityForPercent(
            dominantCallee.percent,
            mediumThreshold: 0.5,
            highThreshold: 0.75,
          ),
          location: dominantCallee.location,
          path: path,
          bottomUpPath: bottomPath,
          focusMethod: focusMethod,
        ),
      );
    }

    final dominantCaller =
        topMethod.callers.isEmpty ? null : topMethod.callers.first;
    if (dominantCaller != null && dominantCaller.percent >= 0.5) {
      final focusMethod = ProfileHotspotMethodContext.fromMethodSummary(
        topMethod,
        relationLimit: relationLimit,
      );
      final path = _representativePath(
        callTree,
        name: topMethod.name,
        kind: topMethod.kind,
        location: topMethod.location,
        score: (node) => node.totalSamples * 10 + node.selfSamples,
      );
      final bottomPath = _representativePath(
        bottomUpTree,
        name: topMethod.name,
        kind: topMethod.kind,
        location: topMethod.location,
        score: (node) => node.totalSamples * 10 + node.selfSamples,
      );
      insights.add(
        ProfileHotspotInsight(
          kind: 'caller',
          subject: dominantCaller.name,
          title:
              '${topMethod.name} is usually reached from ${dominantCaller.name}',
          summary:
              '${_formatPercent(dominantCaller.percent)} of ${topMethod.name}\'s caller edges come from ${dominantCaller.name}.',
          severity: _severityForPercent(
            dominantCaller.percent,
            mediumThreshold: 0.5,
            highThreshold: 0.75,
          ),
          location: dominantCaller.location,
          path: path,
          bottomUpPath: bottomPath,
          focusMethod: focusMethod,
        ),
      );
    }
  } else if (region.sampleCount > 0) {
    warnings.add(
      'Method-table insights were unavailable because no method table was prepared for this profile.',
    );
  }

  final memory = region.memory;
  if (memory != null) {
    if (memory.deltaHeapBytes > 0) {
      insights.add(
        ProfileHotspotInsight(
          kind: 'memory',
          subject: region.name,
          title: 'Heap grew during the profiled window',
          summary:
              'Heap usage increased by ${_formatBytes(memory.deltaHeapBytes)} '
              '(${_formatBytes(memory.start.used)} -> ${_formatBytes(memory.end.used)}).',
          severity: _severityForBytes(memory.deltaHeapBytes),
        ),
      );
    }
    final topClass = memory.topClasses.isEmpty ? null : memory.topClasses.first;
    if (topClass != null && topClass.allocationBytesDelta > 0) {
      insights.add(
        ProfileHotspotInsight(
          kind: 'memoryClass',
          subject: topClass.className,
          title: '${topClass.className} is the top allocator',
          summary:
              '${topClass.className} added ${_formatBytes(topClass.allocationBytesDelta)} '
              'of allocations and ${_formatBytes(topClass.liveBytesDelta)} of live data.',
          severity: _severityForBytes(topClass.allocationBytesDelta),
          location: topClass.libraryUri,
        ),
      );
    }
  }

  insights.sort(_compareHotspotInsights);
  final limited = maxInsights <= 0
      ? insights
      : insights.take(maxInsights).toList(growable: false);
  return ProfileHotspotSummary(
    status: limited.isEmpty ? 'stable' : 'analyzed',
    insights: limited,
    warnings: warnings,
  );
}

int _compareHotspotInsights(
  ProfileHotspotInsight left,
  ProfileHotspotInsight right,
) {
  final severityCompare = right.severity.weight.compareTo(left.severity.weight);
  if (severityCompare != 0) {
    return severityCompare;
  }
  return left.title.compareTo(right.title);
}

ProfileHotspotSeverity _severityForPercent(
  double percent, {
  required double mediumThreshold,
  required double highThreshold,
}) {
  if (percent >= highThreshold) {
    return ProfileHotspotSeverity.high;
  }
  if (percent >= mediumThreshold) {
    return ProfileHotspotSeverity.medium;
  }
  return ProfileHotspotSeverity.low;
}

ProfileHotspotSeverity _severityForBytes(int bytes) {
  if (bytes >= 10 * 1024) {
    return ProfileHotspotSeverity.high;
  }
  if (bytes >= 1024) {
    return ProfileHotspotSeverity.medium;
  }
  return ProfileHotspotSeverity.low;
}

bool _isRuntimeHelperFrame(ProfileFrame frame) {
  final packageName = frame.packageName;
  if (packageName == null) {
    return false;
  }
  for (final prefix in _runtimeHelperPackagePrefixes) {
    if (packageName.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}

ProfileHotspotMethodContext? _findFocusMethod(
  ProfileMethodTable? methodTable, {
  required String name,
  required String kind,
  required String? location,
  required int relationLimit,
}) {
  if (methodTable == null) {
    return null;
  }
  final matches = [
    for (final method in methodTable.methods)
      if (_matchesMethodSummary(
        method,
        name: name,
        kind: kind,
        location: location,
      ))
        method,
  ];
  if (matches.isEmpty) {
    return null;
  }
  matches.sort((left, right) {
    final totalCompare = right.totalSamples.compareTo(left.totalSamples);
    if (totalCompare != 0) {
      return totalCompare;
    }
    return right.selfSamples.compareTo(left.selfSamples);
  });
  return ProfileHotspotMethodContext.fromMethodSummary(
    matches.first,
    relationLimit: relationLimit,
  );
}

bool _matchesMethodSummary(
  ProfileMethodSummary method, {
  required String name,
  required String kind,
  required String? location,
}) {
  return method.name == name &&
      method.kind == kind &&
      (location == null || method.location == location);
}

ProfileHotspotPath? _representativePath(
  ProfileCallTree? callTree, {
  required String name,
  required String kind,
  required String? location,
  required int Function(ProfileCallTreeNode node) score,
}) {
  if (callTree == null) {
    return null;
  }
  List<ProfileCallTreeNode>? bestPath;
  var bestScore = -1;

  void visit(
    ProfileCallTreeNode node,
    List<ProfileCallTreeNode> currentPath,
  ) {
    final nextPath = [...currentPath, node];
    if (_matchesPathNode(
      node,
      name: name,
      kind: kind,
      location: location,
    )) {
      final nodeScore = score(node);
      if (nodeScore > bestScore) {
        bestScore = nodeScore;
        bestPath = nextPath;
      }
    }
    for (final child in node.children) {
      visit(child, nextPath);
    }
  }

  visit(callTree.root, const []);
  final selectedPath = bestPath;
  if (selectedPath == null) {
    return null;
  }
  return ProfileHotspotPath(
    view: callTree.view,
    frames: [
      for (final frame in selectedPath)
        ProfileHotspotPathFrame(
          name: frame.name,
          kind: frame.kind,
          selfSamples: frame.selfSamples,
          totalSamples: frame.totalSamples,
          location: frame.location,
        ),
    ],
  );
}

bool _matchesPathNode(
  ProfileCallTreeNode node, {
  required String name,
  required String kind,
  required String? location,
}) {
  return node.name == name &&
      node.kind == kind &&
      (location == null || node.location == location);
}

String _formatPercent(double percent) =>
    '${(percent * 100).toStringAsFixed(1)}%';

String _formatBytes(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value.abs() >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final precision = unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}
