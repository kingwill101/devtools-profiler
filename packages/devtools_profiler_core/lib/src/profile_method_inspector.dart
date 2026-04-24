
import 'call_tree.dart';
import 'method_table.dart';

/// The lookup state for a method inspection request.
enum ProfileMethodInspectionStatus {
  /// A single matching method was found.
  found,

  /// The requested query matched multiple methods.
  ambiguous,

  /// The requested query did not match any methods.
  notFound,

  /// The underlying profile did not have enough raw data to inspect methods.
  unavailable;

  /// Parses a wire value.
  static ProfileMethodInspectionStatus parse(String value) {
    for (final status in values) {
      if (status.name == value) {
        return status;
      }
    }
    throw ArgumentError.value(
      value,
      'value',
      'Unsupported method inspection status.',
    );
  }
}

/// A compact candidate entry returned for ambiguous or failed method lookups.
class ProfileMethodCandidate {
  /// Creates a method candidate.
  const ProfileMethodCandidate({
    required this.methodId,
    required this.name,
    required this.kind,
    required this.selfSamples,
    required this.totalSamples,
    required this.selfPercent,
    required this.totalPercent,
    this.location,
  });

  /// Creates a candidate from a method summary.
  factory ProfileMethodCandidate.fromSummary(ProfileMethodSummary summary) {
    return ProfileMethodCandidate(
      methodId: summary.methodId,
      name: summary.name,
      kind: summary.kind,
      location: summary.location,
      selfSamples: summary.selfSamples,
      totalSamples: summary.totalSamples,
      selfPercent: summary.selfPercent,
      totalPercent: summary.totalPercent,
    );
  }

  /// Deserializes a candidate from JSON.
  factory ProfileMethodCandidate.fromJson(Map<String, Object?> json) {
    return ProfileMethodCandidate(
      methodId: json['methodId'] as String? ?? '',
      name: json['name'] as String? ?? 'unknown',
      kind: json['kind'] as String? ?? 'unknown',
      location: json['location'] as String?,
      selfSamples: json['selfSamples'] as int? ?? 0,
      totalSamples: json['totalSamples'] as int? ?? 0,
      selfPercent: (json['selfPercent'] as num?)?.toDouble() ?? 0.0,
      totalPercent: (json['totalPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Stable identifier for the method.
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

  /// Inclusive sample ratio in the range `[0, 1]`.
  final double totalPercent;

  /// Converts this candidate to JSON.
  Map<String, Object?> toJson() => {
        'methodId': methodId,
        'name': name,
        'kind': kind,
        'location': location,
        'selfSamples': selfSamples,
        'totalSamples': totalSamples,
        'selfPercent': selfPercent,
        'totalPercent': totalPercent,
      };
}

/// A single frame entry within a representative method path.
class ProfileMethodPathFrame {
  /// Creates a path frame.
  const ProfileMethodPathFrame({
    required this.methodId,
    required this.name,
    required this.kind,
    this.location,
  });

  /// Deserializes a path frame from JSON.
  factory ProfileMethodPathFrame.fromJson(Map<String, Object?> json) {
    return ProfileMethodPathFrame(
      methodId: json['methodId'] as String? ?? '',
      name: json['name'] as String? ?? 'unknown',
      kind: json['kind'] as String? ?? 'unknown',
      location: json['location'] as String?,
    );
  }

  /// Stable identifier for the frame.
  final String methodId;

  /// Display name for the frame.
  final String name;

  /// The VM-reported frame kind.
  final String kind;

  /// Source location, when available.
  final String? location;

  /// Converts this path frame to JSON.
  Map<String, Object?> toJson() => {
        'methodId': methodId,
        'name': name,
        'kind': kind,
        'location': location,
      };
}

/// A representative occurrence path for a selected method.
class ProfileMethodPath {
  /// Creates a method path.
  const ProfileMethodPath({
    required this.frames,
    required this.selfSamples,
    required this.totalSamples,
    required this.selfPercent,
    required this.totalPercent,
    required this.selfMicros,
    required this.totalMicros,
  });

  /// Deserializes a method path from JSON.
  factory ProfileMethodPath.fromJson(Map<String, Object?> json) {
    return ProfileMethodPath(
      frames: (json['frames'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (frame) => ProfileMethodPathFrame.fromJson(
              frame.cast<String, Object?>(),
            ),
          )
          .toList(),
      selfSamples: json['selfSamples'] as int? ?? 0,
      totalSamples: json['totalSamples'] as int? ?? 0,
      selfPercent: (json['selfPercent'] as num?)?.toDouble() ?? 0.0,
      totalPercent: (json['totalPercent'] as num?)?.toDouble() ?? 0.0,
      selfMicros: json['selfMicros'] as int? ?? 0,
      totalMicros: json['totalMicros'] as int? ?? 0,
    );
  }

  /// The root-to-node frames for this occurrence.
  final List<ProfileMethodPathFrame> frames;

  /// Self samples for the selected node in this occurrence.
  final int selfSamples;

  /// Inclusive samples for the selected node in this occurrence.
  final int totalSamples;

  /// Self sample ratio in the range `[0, 1]`.
  final double selfPercent;

  /// Inclusive sample ratio in the range `[0, 1]`.
  final double totalPercent;

  /// Approximate self time in microseconds.
  final int selfMicros;

  /// Approximate inclusive time in microseconds.
  final int totalMicros;

  /// Converts this path to JSON.
  Map<String, Object?> toJson() => {
        'frames': [for (final frame in frames) frame.toJson()],
        'selfSamples': selfSamples,
        'totalSamples': totalSamples,
        'selfPercent': selfPercent,
        'totalPercent': totalPercent,
        'selfMicros': selfMicros,
        'totalMicros': totalMicros,
      };
}

/// A structured inspection result for one selected method.
class ProfileMethodInspection {
  /// Creates a method inspection result.
  const ProfileMethodInspection({
    required this.query,
    required this.queryKind,
    required this.status,
    required this.candidates,
    required this.topDownPaths,
    required this.bottomUpPaths,
    this.message,
    this.method,
  });

  /// Deserializes a method inspection from JSON.
  factory ProfileMethodInspection.fromJson(Map<String, Object?> json) {
    return ProfileMethodInspection(
      query: json['query'] as String? ?? '',
      queryKind: json['queryKind'] as String? ?? 'methodName',
      status: switch (json['status']) {
        final String value => ProfileMethodInspectionStatus.parse(value),
        _ => ProfileMethodInspectionStatus.notFound,
      },
      message: json['message'] as String?,
      method: switch (json['method']) {
        final Map<Object?, Object?> method =>
          ProfileMethodSummary.fromJson(method.cast<String, Object?>()),
        _ => null,
      },
      candidates: (json['candidates'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (candidate) => ProfileMethodCandidate.fromJson(
              candidate.cast<String, Object?>(),
            ),
          )
          .toList(),
      topDownPaths: (json['topDownPaths'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (path) => ProfileMethodPath.fromJson(
              path.cast<String, Object?>(),
            ),
          )
          .toList(),
      bottomUpPaths: (json['bottomUpPaths'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (path) => ProfileMethodPath.fromJson(
              path.cast<String, Object?>(),
            ),
          )
          .toList(),
    );
  }

  /// The original method query.
  final String query;

  /// The query mode, either `methodId` or `methodName`.
  final String queryKind;

  /// The inspection status for this query.
  final ProfileMethodInspectionStatus status;

  /// Optional human-readable detail about the status.
  final String? message;

  /// The selected method when [status] is [ProfileMethodInspectionStatus.found].
  final ProfileMethodSummary? method;

  /// Matching candidates for ambiguous or failed lookups.
  final List<ProfileMethodCandidate> candidates;

  /// Representative top-down occurrences for the selected method.
  final List<ProfileMethodPath> topDownPaths;

  /// Representative bottom-up occurrences for the selected method.
  final List<ProfileMethodPath> bottomUpPaths;

  /// Converts this inspection result to JSON.
  Map<String, Object?> toJson() => {
        'query': query,
        'queryKind': queryKind,
        'status': status.name,
        'message': message,
        'method': method?.toJson(),
        'candidates': [for (final candidate in candidates) candidate.toJson()],
        'topDownPaths': [for (final path in topDownPaths) path.toJson()],
        'bottomUpPaths': [for (final path in bottomUpPaths) path.toJson()],
      };
}

/// Inspects a single method using a DevTools-style method table and optional
/// call trees.
ProfileMethodInspection inspectProfileMethod({
  required String query,
  required String queryKind,
  required ProfileMethodTable? methodTable,
  ProfileCallTree? callTree,
  ProfileCallTree? bottomUpTree,
  int? pathLimit,
}) {
  if (queryKind != 'methodId' && queryKind != 'methodName') {
    throw ArgumentError.value(
      queryKind,
      'queryKind',
      'queryKind must be either "methodId" or "methodName".',
    );
  }

  if (methodTable == null) {
    return ProfileMethodInspection(
      query: query,
      queryKind: queryKind,
      status: ProfileMethodInspectionStatus.unavailable,
      message:
          'Method inspection requires a raw CPU profile artifact, but no method table was available.',
      candidates: const [],
      topDownPaths: const [],
      bottomUpPaths: const [],
    );
  }

  final lookup = queryKind == 'methodId'
      ? _lookupByMethodId(methodTable, query)
      : _lookupByMethodName(methodTable, query);
  if (lookup.selected == null) {
    return ProfileMethodInspection(
      query: query,
      queryKind: queryKind,
      status: lookup.status,
      message: lookup.message,
      candidates: [
        for (final candidate in lookup.candidates)
          ProfileMethodCandidate.fromSummary(candidate),
      ],
      topDownPaths: const [],
      bottomUpPaths: const [],
    );
  }

  final selected = lookup.selected!;
  return ProfileMethodInspection(
    query: query,
    queryKind: queryKind,
    status: ProfileMethodInspectionStatus.found,
    message: lookup.message,
    method: selected,
    candidates: const [],
    topDownPaths: _collectMatchingPaths(
      callTree,
      selected.methodId,
      limit: pathLimit,
    ),
    bottomUpPaths: _collectMatchingPaths(
      bottomUpTree,
      selected.methodId,
      limit: pathLimit,
    ),
  );
}

_MethodLookupResult _lookupByMethodId(
    ProfileMethodTable table, String methodId) {
  final normalized = methodId.trim();
  final matches = table.methods
      .where((method) => method.methodId == normalized)
      .toList(growable: false);
  if (matches.isEmpty) {
    return _MethodLookupResult(
      status: ProfileMethodInspectionStatus.notFound,
      message: 'No method with id "$methodId" was found in this profile.',
      candidates: const [],
    );
  }
  return _MethodLookupResult(
    status: ProfileMethodInspectionStatus.found,
    selected: matches.single,
    candidates: const [],
  );
}

_MethodLookupResult _lookupByMethodName(
  ProfileMethodTable table,
  String methodName,
) {
  final normalized = methodName.trim();
  if (normalized.isEmpty) {
    return _MethodLookupResult(
      status: ProfileMethodInspectionStatus.notFound,
      message: 'A non-empty method name is required for inspection.',
      candidates: const [],
    );
  }

  final exactMatches = table.methods
      .where((method) => method.name == normalized)
      .toList(growable: false);
  if (exactMatches.length == 1) {
    return _MethodLookupResult(
      status: ProfileMethodInspectionStatus.found,
      selected: exactMatches.single,
      candidates: const [],
    );
  }
  if (exactMatches.length > 1) {
    return _MethodLookupResult(
      status: ProfileMethodInspectionStatus.ambiguous,
      message:
          'Method name "$methodName" matched multiple methods. Inspect by method id or refine the query.',
      candidates: exactMatches,
    );
  }

  final lowerName = normalized.toLowerCase();
  final caseInsensitiveMatches = table.methods
      .where((method) => method.name.toLowerCase() == lowerName)
      .toList(growable: false);
  if (caseInsensitiveMatches.length == 1) {
    return _MethodLookupResult(
      status: ProfileMethodInspectionStatus.found,
      selected: caseInsensitiveMatches.single,
      candidates: const [],
    );
  }
  if (caseInsensitiveMatches.length > 1) {
    return _MethodLookupResult(
      status: ProfileMethodInspectionStatus.ambiguous,
      message:
          'Method name "$methodName" matched multiple methods ignoring case. Inspect by method id or refine the query.',
      candidates: caseInsensitiveMatches,
    );
  }

  final substringMatches = table.methods
      .where((method) => method.name.toLowerCase().contains(lowerName))
      .toList(growable: false);
  if (substringMatches.length == 1) {
    return _MethodLookupResult(
      status: ProfileMethodInspectionStatus.found,
      selected: substringMatches.single,
      candidates: const [],
    );
  }
  if (substringMatches.length > 1) {
    return _MethodLookupResult(
      status: ProfileMethodInspectionStatus.ambiguous,
      message:
          'Method name "$methodName" matched multiple methods by substring. Inspect by method id or refine the query.',
      candidates: substringMatches,
    );
  }

  return _MethodLookupResult(
    status: ProfileMethodInspectionStatus.notFound,
    message: 'No method named "$methodName" was found in this profile.',
    candidates: const [],
  );
}

List<ProfileMethodPath> _collectMatchingPaths(
  ProfileCallTree? tree,
  String methodId, {
  int? limit,
}) {
  if (tree == null) {
    return const [];
  }

  final matches = <ProfileMethodPath>[];
  _walkMatchingPaths(
    node: tree.root,
    currentFrames: const [],
    methodId: methodId,
    matches: matches,
  );
  matches.sort(_compareMethodPaths);
  final normalizedLimit = limit == null || limit <= 0 ? null : limit;
  if (normalizedLimit == null || matches.length <= normalizedLimit) {
    return matches;
  }
  return matches.take(normalizedLimit).toList(growable: false);
}

void _walkMatchingPaths({
  required ProfileCallTreeNode node,
  required List<ProfileMethodPathFrame> currentFrames,
  required String methodId,
  required List<ProfileMethodPath> matches,
}) {
  final currentPath = [
    ...currentFrames,
    ProfileMethodPathFrame(
      methodId: _methodIdForNode(node),
      name: node.name,
      kind: node.kind,
      location: node.location,
    ),
  ];

  if (_methodIdForNode(node) == methodId) {
    matches.add(
      ProfileMethodPath(
        frames: currentPath,
        selfSamples: node.selfSamples,
        totalSamples: node.totalSamples,
        selfPercent: node.selfPercent,
        totalPercent: node.totalPercent,
        selfMicros: node.selfMicros,
        totalMicros: node.totalMicros,
      ),
    );
  }

  for (final child in node.children) {
    _walkMatchingPaths(
      node: child,
      currentFrames: currentPath,
      methodId: methodId,
      matches: matches,
    );
  }
}

int _compareMethodPaths(ProfileMethodPath left, ProfileMethodPath right) {
  final totalCompare = right.totalSamples.compareTo(left.totalSamples);
  if (totalCompare != 0) {
    return totalCompare;
  }
  final selfCompare = right.selfSamples.compareTo(left.selfSamples);
  if (selfCompare != 0) {
    return selfCompare;
  }
  return left.frames.length.compareTo(right.frames.length);
}

String _methodIdForNode(ProfileCallTreeNode node) {
  return '${node.name}|${node.kind}|${node.location ?? ''}';
}

class _MethodLookupResult {
  const _MethodLookupResult({
    required this.status,
    required this.candidates,
    this.message,
    this.selected,
  });

  final ProfileMethodInspectionStatus status;
  final String? message;
  final ProfileMethodSummary? selected;
  final List<ProfileMethodSummary> candidates;
}
