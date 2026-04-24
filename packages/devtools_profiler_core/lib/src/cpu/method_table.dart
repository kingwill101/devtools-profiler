import 'package:vm_service/vm_service.dart';

import 'profile_frames.dart';

/// A caller or callee relationship for a method table entry.
class ProfileMethodRelation {
  /// Creates a method relation.
  const ProfileMethodRelation({
    required this.methodId,
    required this.name,
    required this.kind,
    required this.sampleCount,
    required this.percent,
    this.location,
  });

  /// Deserializes a method relation from JSON.
  factory ProfileMethodRelation.fromJson(Map<String, Object?> json) {
    return ProfileMethodRelation(
      methodId: json['methodId'] as String? ?? '',
      name: json['name'] as String? ?? 'unknown',
      kind: json['kind'] as String? ?? 'unknown',
      location: json['location'] as String?,
      sampleCount: json['sampleCount'] as int? ?? 0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Stable identifier for the related method.
  final String methodId;

  /// Display name of the related method.
  final String name;

  /// The VM-reported frame kind.
  final String kind;

  /// Source location for the related method, when available.
  final String? location;

  /// Weighted sample count for this caller/callee edge.
  final int sampleCount;

  /// Percentage for this edge relative to all caller/callee edges for the
  /// selected method.
  final double percent;

  /// Converts this method relation to JSON.
  Map<String, Object?> toJson() => {
        'methodId': methodId,
        'name': name,
        'kind': kind,
        'location': location,
        'sampleCount': sampleCount,
        'percent': percent,
      };
}

/// A method-table entry summarizing a merged method across the CPU profile.
class ProfileMethodSummary {
  /// Creates a method summary.
  ProfileMethodSummary({
    required this.methodId,
    required this.name,
    required this.kind,
    required this.selfSamples,
    required this.totalSamples,
    required this.selfPercent,
    required this.totalPercent,
    required this.selfMicros,
    required this.totalMicros,
    required List<ProfileMethodRelation> callers,
    required List<ProfileMethodRelation> callees,
    this.location,
  })  : callers = List.unmodifiable(callers),
        callees = List.unmodifiable(callees);

  /// Deserializes a method summary from JSON.
  factory ProfileMethodSummary.fromJson(Map<String, Object?> json) {
    return ProfileMethodSummary(
      methodId: json['methodId'] as String? ?? '',
      name: json['name'] as String? ?? 'unknown',
      kind: json['kind'] as String? ?? 'unknown',
      location: json['location'] as String?,
      selfSamples: json['selfSamples'] as int? ?? 0,
      totalSamples: json['totalSamples'] as int? ?? 0,
      selfPercent: (json['selfPercent'] as num?)?.toDouble() ?? 0.0,
      totalPercent: (json['totalPercent'] as num?)?.toDouble() ?? 0.0,
      selfMicros: json['selfMicros'] as int? ?? 0,
      totalMicros: json['totalMicros'] as int? ?? 0,
      callers: (json['callers'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (caller) => ProfileMethodRelation.fromJson(
              caller.cast<String, Object?>(),
            ),
          )
          .toList(),
      callees: (json['callees'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (callee) => ProfileMethodRelation.fromJson(
              callee.cast<String, Object?>(),
            ),
          )
          .toList(),
    );
  }

  /// Stable identifier for the merged method.
  final String methodId;

  /// Display name of the method.
  final String name;

  /// The VM-reported frame kind.
  final String kind;

  /// Source location for the method, when available.
  final String? location;

  /// The number of samples where this method was the top frame.
  final int selfSamples;

  /// The number of samples where this method appeared anywhere in the stack.
  final int totalSamples;

  /// Self sample ratio in the range `[0, 1]`.
  final double selfPercent;

  /// Total sample ratio in the range `[0, 1]`.
  final double totalPercent;

  /// Approximate self time for this method in microseconds.
  final int selfMicros;

  /// Approximate inclusive time for this method in microseconds.
  final int totalMicros;

  /// Caller relationships for this method.
  final List<ProfileMethodRelation> callers;

  /// Callee relationships for this method.
  final List<ProfileMethodRelation> callees;

  /// Returns a copy with selected fields replaced.
  ProfileMethodSummary copyWith({
    List<ProfileMethodRelation>? callers,
    List<ProfileMethodRelation>? callees,
  }) {
    return ProfileMethodSummary(
      methodId: methodId,
      name: name,
      kind: kind,
      location: location,
      selfSamples: selfSamples,
      totalSamples: totalSamples,
      selfPercent: selfPercent,
      totalPercent: totalPercent,
      selfMicros: selfMicros,
      totalMicros: totalMicros,
      callers: callers ?? this.callers,
      callees: callees ?? this.callees,
    );
  }

  /// Converts this method summary to JSON.
  Map<String, Object?> toJson() => {
        'methodId': methodId,
        'name': name,
        'kind': kind,
        'location': location,
        'selfSamples': selfSamples,
        'totalSamples': totalSamples,
        'selfPercent': selfPercent,
        'totalPercent': totalPercent,
        'selfMicros': selfMicros,
        'totalMicros': totalMicros,
        'callers': [for (final caller in callers) caller.toJson()],
        'callees': [for (final callee in callees) callee.toJson()],
      };
}

/// A DevTools-style method table for a CPU profile.
class ProfileMethodTable {
  /// Creates a method table.
  ProfileMethodTable({
    required this.sampleCount,
    required this.samplePeriodMicros,
    required List<ProfileMethodSummary> methods,
  }) : methods = List.unmodifiable(methods);

  /// Deserializes a method table from JSON.
  factory ProfileMethodTable.fromJson(Map<String, Object?> json) {
    return ProfileMethodTable(
      sampleCount: json['sampleCount'] as int? ?? 0,
      samplePeriodMicros: json['samplePeriodMicros'] as int? ?? 0,
      methods: (json['methods'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (method) => ProfileMethodSummary.fromJson(
              method.cast<String, Object?>(),
            ),
          )
          .toList(),
    );
  }

  /// The total number of samples in the captured region.
  final int sampleCount;

  /// The VM-reported sample period in microseconds.
  final int samplePeriodMicros;

  /// Merged method entries ordered by descending total cost.
  final List<ProfileMethodSummary> methods;

  /// Returns a copy with selected fields replaced.
  ProfileMethodTable copyWith({
    List<ProfileMethodSummary>? methods,
  }) {
    return ProfileMethodTable(
      sampleCount: sampleCount,
      samplePeriodMicros: samplePeriodMicros,
      methods: methods ?? this.methods,
    );
  }

  /// Converts this method table to JSON.
  Map<String, Object?> toJson() => {
        'sampleCount': sampleCount,
        'samplePeriodMicros': samplePeriodMicros,
        'methods': [for (final method in methods) method.toJson()],
      };
}

/// Builds a DevTools-style method table from raw VM CPU samples.
ProfileMethodTable buildMethodTable({
  required CpuSamples cpuSamples,
  ProfileFramePredicate? includeFrame,
}) {
  final samplePeriodMicros = cpuSamples.samplePeriod ?? 0;
  final functions = cpuSamples.functions ?? const <ProfileFunction>[];
  final root = _MethodTableOccurrence.root();
  var sampleCount = 0;
  var nextOccurrenceId = 1;

  for (final sample in cpuSamples.samples ?? const <CpuSample>[]) {
    final frames = filterStackFrames(
      sample.stack ?? const <int>[],
      functions,
      includeFrame: includeFrame,
    );
    if (frames.isEmpty) continue;

    sampleCount++;
    var current = root;
    for (final frame in frames.reversed) {
      current = current.childFor(
        frame,
        occurrenceIdFactory: () => nextOccurrenceId++,
      );
      current.totalSamples++;
    }
    current.selfSamples++;
  }

  final methodsById = <String, _MutableMethodEntry>{};
  for (final child in root.children.values) {
    _walkMethodTableOccurrences(
      node: child,
      methodsById: methodsById,
      ancestorOccurrenceIds: const <int>{},
      parentEntry: null,
    );
  }

  final summaries = methodsById.values
      .map(
        (entry) => entry.freeze(
          totalSampleCount: sampleCount,
          samplePeriodMicros: samplePeriodMicros,
        ),
      )
      .toList()
    ..sort(_compareMethodSummaries);

  return ProfileMethodTable(
    sampleCount: sampleCount,
    samplePeriodMicros: samplePeriodMicros,
    methods: summaries,
  );
}

void _walkMethodTableOccurrences({
  required _MethodTableOccurrence node,
  required Map<String, _MutableMethodEntry> methodsById,
  required Set<int> ancestorOccurrenceIds,
  required _MutableMethodEntry? parentEntry,
}) {
  final entry = methodsById.putIfAbsent(
    node.methodId,
    () => _MutableMethodEntry.fromNode(node),
  );

  final shouldMergeTotal =
      !entry.contributingOccurrenceIds.any(ancestorOccurrenceIds.contains);
  entry.merge(node, mergeTotal: shouldMergeTotal);

  if (parentEntry != null) {
    parentEntry.calleeEdgeCounts[entry.methodId] =
        (parentEntry.calleeEdgeCounts[entry.methodId] ?? 0) + node.totalSamples;
    entry.callerEdgeCounts[parentEntry.methodId] =
        (entry.callerEdgeCounts[parentEntry.methodId] ?? 0) + node.totalSamples;
  }

  final childAncestorIds = {...ancestorOccurrenceIds, node.occurrenceId};
  for (final child in node.children.values) {
    _walkMethodTableOccurrences(
      node: child,
      methodsById: methodsById,
      ancestorOccurrenceIds: childAncestorIds,
      parentEntry: entry,
    );
  }
}

final class _MethodTableOccurrence {
  _MethodTableOccurrence({
    required this.occurrenceId,
    required this.frame,
  });

  factory _MethodTableOccurrence.root() => _MethodTableOccurrence(
        occurrenceId: 0,
        frame: const ProfileFrame(name: 'all', kind: 'root', location: null),
      );

  final int occurrenceId;
  final ProfileFrame frame;
  final Map<String, _MethodTableOccurrence> children = {};

  int selfSamples = 0;
  int totalSamples = 0;

  String get methodId => frame.key;

  _MethodTableOccurrence childFor(
    ProfileFrame frame, {
    required int Function() occurrenceIdFactory,
  }) {
    return children.putIfAbsent(
      frame.key,
      () => _MethodTableOccurrence(
        occurrenceId: occurrenceIdFactory(),
        frame: frame,
      ),
    );
  }
}

final class _MutableMethodEntry {
  _MutableMethodEntry({
    required this.methodId,
    required this.name,
    required this.kind,
    required this.location,
  });

  factory _MutableMethodEntry.fromNode(_MethodTableOccurrence node) {
    return _MutableMethodEntry(
      methodId: node.methodId,
      name: node.frame.name,
      kind: node.frame.kind,
      location: node.frame.location,
    );
  }

  final String methodId;
  final String name;
  final String kind;
  final String? location;
  final Set<int> contributingOccurrenceIds = {};
  final Map<String, int> callerEdgeCounts = {};
  final Map<String, int> calleeEdgeCounts = {};

  int selfSamples = 0;
  int totalSamples = 0;

  void merge(_MethodTableOccurrence node, {required bool mergeTotal}) {
    contributingOccurrenceIds.add(node.occurrenceId);
    selfSamples += node.selfSamples;
    if (mergeTotal) {
      totalSamples += node.totalSamples;
    }
  }

  ProfileMethodSummary freeze({
    required int totalSampleCount,
    required int samplePeriodMicros,
  }) {
    final divisor = totalSampleCount == 0 ? 1 : totalSampleCount;
    return ProfileMethodSummary(
      methodId: methodId,
      name: name,
      kind: kind,
      location: location,
      selfSamples: selfSamples,
      totalSamples: totalSamples,
      selfPercent: selfSamples / divisor,
      totalPercent: totalSamples / divisor,
      selfMicros: selfSamples * samplePeriodMicros,
      totalMicros: totalSamples * samplePeriodMicros,
      callers: _freezeRelations(callerEdgeCounts),
      callees: _freezeRelations(calleeEdgeCounts),
    );
  }

  List<ProfileMethodRelation> _freezeRelations(Map<String, int> edgeCounts) {
    final totalEdges =
        edgeCounts.values.fold<int>(0, (sum, count) => sum + count);
    final divisor = totalEdges == 0 ? 1 : totalEdges;
    final relations = <ProfileMethodRelation>[
      for (final entry in edgeCounts.entries)
        ProfileMethodRelation(
          methodId: entry.key,
          name: _nameFromMethodId(entry.key),
          kind: _kindFromMethodId(entry.key),
          location: _locationFromMethodId(entry.key),
          sampleCount: entry.value,
          percent: entry.value / divisor,
        ),
    ];
    relations.sort(_compareMethodRelations);
    return relations;
  }
}

int _compareMethodSummaries(
  ProfileMethodSummary left,
  ProfileMethodSummary right,
) {
  final totalCompare = right.totalSamples.compareTo(left.totalSamples);
  if (totalCompare != 0) {
    return totalCompare;
  }

  final selfCompare = right.selfSamples.compareTo(left.selfSamples);
  if (selfCompare != 0) {
    return selfCompare;
  }

  return left.name.compareTo(right.name);
}

int _compareMethodRelations(
  ProfileMethodRelation left,
  ProfileMethodRelation right,
) {
  final sampleCompare = right.sampleCount.compareTo(left.sampleCount);
  if (sampleCompare != 0) {
    return sampleCompare;
  }

  return left.name.compareTo(right.name);
}

String _nameFromMethodId(String methodId) {
  final parts = methodId.split('|');
  return parts.isEmpty ? 'unknown' : parts.first;
}

String _kindFromMethodId(String methodId) {
  final parts = methodId.split('|');
  return parts.length > 1 ? parts[1] : 'unknown';
}

String? _locationFromMethodId(String methodId) {
  final parts = methodId.split('|');
  if (parts.length <= 2 || parts[2].isEmpty) {
    return null;
  }
  return parts[2];
}
