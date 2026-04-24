import '../cpu/method_table.dart';
import 'profile_comparison.dart';
import 'profile_method_inspector.dart';

/// The overall state of a method comparison request.
enum ProfileMethodComparisonStatus {
  /// Both baseline and current resolved a unique method and were compared.
  compared,

  /// One side resolved a unique method but the other did not.
  partial,

  /// Neither side resolved a unique method.
  unresolved,

  /// Comparison was blocked because method-table data was unavailable.
  unavailable;

  /// Parses a wire value.
  static ProfileMethodComparisonStatus parse(String value) {
    for (final status in values) {
      if (status.name == value) {
        return status;
      }
    }
    throw ArgumentError.value(
      value,
      'value',
      'Unsupported method comparison status.',
    );
  }
}

/// A delta for a caller or callee relation on a selected method.
class ProfileMethodRelationDelta {
  /// Creates a relation delta.
  const ProfileMethodRelationDelta({
    required this.methodId,
    required this.name,
    required this.kind,
    required this.sampleCount,
    required this.percent,
    this.location,
  });

  /// Deserializes a relation delta from JSON.
  factory ProfileMethodRelationDelta.fromJson(Map<String, Object?> json) {
    return ProfileMethodRelationDelta(
      methodId: json['methodId'] as String? ?? '',
      name: json['name'] as String? ?? 'unknown',
      kind: json['kind'] as String? ?? 'unknown',
      location: json['location'] as String?,
      sampleCount: ProfileNumericDelta(
        baseline:
            (json['sampleCount'] as Map<Object?, Object?>? ??
                    const {})['baseline']
                as num? ??
            0,
        current:
            (json['sampleCount'] as Map<Object?, Object?>? ??
                    const {})['current']
                as num? ??
            0,
      ),
      percent: ProfileNumericDelta(
        baseline:
            (json['percent'] as Map<Object?, Object?>? ?? const {})['baseline']
                as num? ??
            0.0,
        current:
            (json['percent'] as Map<Object?, Object?>? ?? const {})['current']
                as num? ??
            0.0,
      ),
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

  /// Weighted sample-count delta for this edge.
  final ProfileNumericDelta sampleCount;

  /// Percentage delta for this edge.
  final ProfileNumericDelta percent;

  /// Converts this delta to JSON.
  Map<String, Object?> toJson() => {
    'methodId': methodId,
    'name': name,
    'kind': kind,
    'location': location,
    'sampleCount': sampleCount.toJson(),
    'percent': percent.toJson(),
  };
}

/// A structured comparison for one selected method across two profiles.
class ProfileMethodComparison {
  /// Creates a method comparison result.
  ProfileMethodComparison({
    required this.query,
    required this.queryKind,
    required this.status,
    required this.baseline,
    required this.current,
    required List<String> warnings,
    this.methodDelta,
    List<ProfileMethodRelationDelta> callerDeltas = const [],
    List<ProfileMethodRelationDelta> calleeDeltas = const [],
  }) : warnings = List.unmodifiable(warnings),
       callerDeltas = List.unmodifiable(callerDeltas),
       calleeDeltas = List.unmodifiable(calleeDeltas);

  /// Deserializes a method comparison from JSON.
  factory ProfileMethodComparison.fromJson(Map<String, Object?> json) {
    return ProfileMethodComparison(
      query: json['query'] as String? ?? '',
      queryKind: json['queryKind'] as String? ?? 'methodName',
      status: switch (json['status']) {
        final String value => ProfileMethodComparisonStatus.parse(value),
        _ => ProfileMethodComparisonStatus.unresolved,
      },
      baseline: ProfileMethodInspection.fromJson(
        (json['baseline'] as Map<Object?, Object?>? ?? const {})
            .cast<String, Object?>(),
      ),
      current: ProfileMethodInspection.fromJson(
        (json['current'] as Map<Object?, Object?>? ?? const {})
            .cast<String, Object?>(),
      ),
      methodDelta: switch (json['methodDelta']) {
        final Map<Object?, Object?> value => _methodDeltaFromJson(
          value.cast<String, Object?>(),
        ),
        _ => null,
      },
      callerDeltas: (json['callerDeltas'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (item) => ProfileMethodRelationDelta.fromJson(
              item.cast<String, Object?>(),
            ),
          )
          .toList(),
      calleeDeltas: (json['calleeDeltas'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (item) => ProfileMethodRelationDelta.fromJson(
              item.cast<String, Object?>(),
            ),
          )
          .toList(),
      warnings: (json['warnings'] as List<Object?>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  /// The original method query.
  final String query;

  /// The query mode, either `methodId` or `methodName`.
  final String queryKind;

  /// The overall comparison status.
  final ProfileMethodComparisonStatus status;

  /// The baseline inspection result.
  final ProfileMethodInspection baseline;

  /// The current inspection result.
  final ProfileMethodInspection current;

  /// The merged method delta when both sides resolved uniquely.
  final ProfileMethodDelta? methodDelta;

  /// Caller-edge deltas when both sides resolved uniquely.
  final List<ProfileMethodRelationDelta> callerDeltas;

  /// Callee-edge deltas when both sides resolved uniquely.
  final List<ProfileMethodRelationDelta> calleeDeltas;

  /// Comparison warnings.
  final List<String> warnings;

  /// Converts this comparison to JSON.
  Map<String, Object?> toJson() => {
    'query': query,
    'queryKind': queryKind,
    'status': status.name,
    'baseline': baseline.toJson(),
    'current': current.toJson(),
    'methodDelta': methodDelta?.toJson(),
    'callerDeltas': [for (final delta in callerDeltas) delta.toJson()],
    'calleeDeltas': [for (final delta in calleeDeltas) delta.toJson()],
    'warnings': warnings,
  };
}

ProfileMethodDelta _methodDeltaFromJson(Map<String, Object?> json) {
  return ProfileMethodDelta(
    methodId: json['methodId'] as String? ?? '',
    name: json['name'] as String? ?? 'unknown',
    kind: json['kind'] as String? ?? 'unknown',
    location: json['location'] as String?,
    selfSamples: _numericDeltaFromJson(
      (json['selfSamples'] as Map<Object?, Object?>? ?? const {})
          .cast<String, Object?>(),
    ),
    totalSamples: _numericDeltaFromJson(
      (json['totalSamples'] as Map<Object?, Object?>? ?? const {})
          .cast<String, Object?>(),
    ),
    selfPercent: _numericDeltaFromJson(
      (json['selfPercent'] as Map<Object?, Object?>? ?? const {})
          .cast<String, Object?>(),
    ),
    totalPercent: _numericDeltaFromJson(
      (json['totalPercent'] as Map<Object?, Object?>? ?? const {})
          .cast<String, Object?>(),
    ),
    selfMicros: _numericDeltaFromJson(
      (json['selfMicros'] as Map<Object?, Object?>? ?? const {})
          .cast<String, Object?>(),
    ),
    totalMicros: _numericDeltaFromJson(
      (json['totalMicros'] as Map<Object?, Object?>? ?? const {})
          .cast<String, Object?>(),
    ),
  );
}

ProfileNumericDelta _numericDeltaFromJson(Map<String, Object?> json) {
  return ProfileNumericDelta(
    baseline: json['baseline'] as num? ?? 0,
    current: json['current'] as num? ?? 0,
  );
}

/// Compares one selected method across two inspected profiles.
ProfileMethodComparison compareProfileMethods({
  required ProfileMethodInspection baseline,
  required ProfileMethodInspection current,
  int? relationLimit,
}) {
  final warnings = <String>[];
  final baselineMethod = baseline.method;
  final currentMethod = current.method;

  final status = switch ((baseline.status, current.status)) {
    (
      ProfileMethodInspectionStatus.found,
      ProfileMethodInspectionStatus.found,
    ) =>
      ProfileMethodComparisonStatus.compared,
    (ProfileMethodInspectionStatus.unavailable, _) ||
    (
      _,
      ProfileMethodInspectionStatus.unavailable,
    ) => ProfileMethodComparisonStatus.unavailable,
    (ProfileMethodInspectionStatus.found, _) ||
    (
      _,
      ProfileMethodInspectionStatus.found,
    ) => ProfileMethodComparisonStatus.partial,
    _ => ProfileMethodComparisonStatus.unresolved,
  };

  if (baseline.status != current.status) {
    warnings.add(
      'The compared method lookup statuses differ: '
      '${baseline.status.name} vs ${current.status.name}.',
    );
  }

  if (baselineMethod != null &&
      currentMethod != null &&
      baselineMethod.methodId != currentMethod.methodId) {
    warnings.add(
      'The resolved method ids differ between baseline and current: '
      '"${baselineMethod.methodId}" vs "${currentMethod.methodId}".',
    );
  }

  if (baseline.message != null &&
      current.message != null &&
      baseline.message != current.message) {
    warnings.add('The baseline and current method resolution details differ.');
  }

  final methodDelta = switch ((baselineMethod, currentMethod)) {
    (final ProfileMethodSummary left, final ProfileMethodSummary right) =>
      _buildMethodDelta(left, right),
    _ => null,
  };

  final callerDeltas = switch ((baselineMethod, currentMethod)) {
    (final ProfileMethodSummary left, final ProfileMethodSummary right) =>
      _limitList(
        _buildRelationDeltas(left.callers, right.callers),
        relationLimit,
      ),
    _ => const <ProfileMethodRelationDelta>[],
  };

  final calleeDeltas = switch ((baselineMethod, currentMethod)) {
    (final ProfileMethodSummary left, final ProfileMethodSummary right) =>
      _limitList(
        _buildRelationDeltas(left.callees, right.callees),
        relationLimit,
      ),
    _ => const <ProfileMethodRelationDelta>[],
  };

  return ProfileMethodComparison(
    query: baseline.query,
    queryKind: baseline.queryKind,
    status: status,
    baseline: baseline,
    current: current,
    methodDelta: methodDelta,
    callerDeltas: callerDeltas,
    calleeDeltas: calleeDeltas,
    warnings: warnings,
  );
}

ProfileMethodDelta _buildMethodDelta(
  ProfileMethodSummary baseline,
  ProfileMethodSummary current,
) {
  final sampleMethod = current;
  return ProfileMethodDelta(
    methodId: sampleMethod.methodId,
    name: sampleMethod.name,
    kind: sampleMethod.kind,
    location: sampleMethod.location,
    selfSamples: ProfileNumericDelta(
      baseline: baseline.selfSamples,
      current: current.selfSamples,
    ),
    totalSamples: ProfileNumericDelta(
      baseline: baseline.totalSamples,
      current: current.totalSamples,
    ),
    selfPercent: ProfileNumericDelta(
      baseline: baseline.selfPercent,
      current: current.selfPercent,
    ),
    totalPercent: ProfileNumericDelta(
      baseline: baseline.totalPercent,
      current: current.totalPercent,
    ),
    selfMicros: ProfileNumericDelta(
      baseline: baseline.selfMicros,
      current: current.selfMicros,
    ),
    totalMicros: ProfileNumericDelta(
      baseline: baseline.totalMicros,
      current: current.totalMicros,
    ),
  );
}

List<ProfileMethodRelationDelta> _buildRelationDeltas(
  List<ProfileMethodRelation> baseline,
  List<ProfileMethodRelation> current,
) {
  final baselineById = {
    for (final relation in baseline) relation.methodId: relation,
  };
  final currentById = {
    for (final relation in current) relation.methodId: relation,
  };
  final methodIds = <String>{...baselineById.keys, ...currentById.keys};
  final deltas = <ProfileMethodRelationDelta>[
    for (final methodId in methodIds)
      _buildRelationDelta(baselineById[methodId], currentById[methodId]),
  ];
  deltas.sort(_compareRelationDeltas);
  return deltas;
}

ProfileMethodRelationDelta _buildRelationDelta(
  ProfileMethodRelation? baseline,
  ProfileMethodRelation? current,
) {
  final sample = current ?? baseline;
  return ProfileMethodRelationDelta(
    methodId: sample?.methodId ?? '',
    name: sample?.name ?? 'unknown',
    kind: sample?.kind ?? 'unknown',
    location: sample?.location,
    sampleCount: ProfileNumericDelta(
      baseline: baseline?.sampleCount ?? 0,
      current: current?.sampleCount ?? 0,
    ),
    percent: ProfileNumericDelta(
      baseline: baseline?.percent ?? 0.0,
      current: current?.percent ?? 0.0,
    ),
  );
}

List<T> _limitList<T>(List<T> items, int? limit) {
  if (limit == null || limit <= 0 || items.length <= limit) {
    return items;
  }
  return items.take(limit).toList(growable: false);
}

int _compareRelationDeltas(
  ProfileMethodRelationDelta left,
  ProfileMethodRelationDelta right,
) {
  final sampleCompare = right.sampleCount.delta.compareTo(
    left.sampleCount.delta,
  );
  if (sampleCompare != 0) {
    return sampleCompare;
  }
  return left.name.compareTo(right.name);
}
