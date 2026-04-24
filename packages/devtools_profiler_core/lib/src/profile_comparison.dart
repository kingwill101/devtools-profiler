
import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'memory_models.dart';
import 'method_table.dart';
import 'models.dart';

/// A numeric baseline/current comparison with derived delta values.
class ProfileNumericDelta {
  /// Creates a numeric delta.
  const ProfileNumericDelta({
    required this.baseline,
    required this.current,
  });

  /// The baseline value.
  final num baseline;

  /// The current value.
  final num current;

  /// The signed difference between [current] and [baseline].
  num get delta => current - baseline;

  /// The relative change as a percentage, or `null` when the baseline is `0`.
  double? get percentChange {
    final baselineValue = baseline.toDouble();
    if (baselineValue == 0) {
      return null;
    }
    return ((current.toDouble() - baselineValue) / baselineValue) * 100.0;
  }

  /// Converts this delta to JSON.
  Map<String, Object?> toJson() => {
        'baseline': baseline,
        'current': current,
        'delta': delta,
        'percentChange': percentChange,
      };
}

/// A delta for a merged frame between two prepared profile summaries.
class ProfileFrameDelta {
  /// Creates a frame delta.
  const ProfileFrameDelta({
    required this.frameId,
    required this.name,
    required this.kind,
    required this.selfSamples,
    required this.totalSamples,
    required this.selfPercent,
    required this.totalPercent,
    this.location,
  });

  /// Stable comparison id for the merged frame.
  final String frameId;

  /// Display name of the frame.
  final String name;

  /// The VM-reported frame kind.
  final String kind;

  /// The resolved source location, when available.
  final String? location;

  /// Top-of-stack sample delta.
  final ProfileNumericDelta selfSamples;

  /// Inclusive sample delta.
  final ProfileNumericDelta totalSamples;

  /// Top-of-stack percent delta.
  final ProfileNumericDelta selfPercent;

  /// Inclusive percent delta.
  final ProfileNumericDelta totalPercent;

  /// Converts this delta to JSON.
  Map<String, Object?> toJson() => {
        'frameId': frameId,
        'name': name,
        'kind': kind,
        'location': location,
        'selfSamples': selfSamples.toJson(),
        'totalSamples': totalSamples.toJson(),
        'selfPercent': selfPercent.toJson(),
        'totalPercent': totalPercent.toJson(),
      };
}

/// A delta for a merged method between two method tables.
class ProfileMethodDelta {
  /// Creates a method delta.
  const ProfileMethodDelta({
    required this.methodId,
    required this.name,
    required this.kind,
    required this.selfSamples,
    required this.totalSamples,
    required this.selfPercent,
    required this.totalPercent,
    required this.selfMicros,
    required this.totalMicros,
    this.location,
  });

  /// Stable identifier for the merged method.
  final String methodId;

  /// Display name of the method.
  final String name;

  /// The VM-reported frame kind.
  final String kind;

  /// The resolved source location, when available.
  final String? location;

  /// Top-of-stack sample delta.
  final ProfileNumericDelta selfSamples;

  /// Inclusive sample delta.
  final ProfileNumericDelta totalSamples;

  /// Top-of-stack percent delta.
  final ProfileNumericDelta selfPercent;

  /// Inclusive percent delta.
  final ProfileNumericDelta totalPercent;

  /// Approximate self-time delta in microseconds.
  final ProfileNumericDelta selfMicros;

  /// Approximate inclusive-time delta in microseconds.
  final ProfileNumericDelta totalMicros;

  /// Converts this delta to JSON.
  Map<String, Object?> toJson() => {
        'methodId': methodId,
        'name': name,
        'kind': kind,
        'location': location,
        'selfSamples': selfSamples.toJson(),
        'totalSamples': totalSamples.toJson(),
        'selfPercent': selfPercent.toJson(),
        'totalPercent': totalPercent.toJson(),
        'selfMicros': selfMicros.toJson(),
        'totalMicros': totalMicros.toJson(),
      };
}

/// A per-class memory delta between two profiled windows.
class ProfileMemoryClassDelta {
  /// Creates a memory class delta.
  const ProfileMemoryClassDelta({
    required this.className,
    required this.allocationBytesDelta,
    required this.allocationInstancesDelta,
    required this.liveBytes,
    required this.liveBytesDelta,
    required this.liveInstances,
    required this.liveInstancesDelta,
    this.libraryUri,
  });

  /// The class display name.
  final String className;

  /// The owning library URI when available.
  final String? libraryUri;

  /// Delta for accumulated allocated bytes across the profiled window.
  final ProfileNumericDelta allocationBytesDelta;

  /// Delta for accumulated allocated instances across the profiled window.
  final ProfileNumericDelta allocationInstancesDelta;

  /// Delta for end-of-window live bytes.
  final ProfileNumericDelta liveBytes;

  /// Delta for live-byte growth across the window.
  final ProfileNumericDelta liveBytesDelta;

  /// Delta for end-of-window live instances.
  final ProfileNumericDelta liveInstances;

  /// Delta for live-instance growth across the window.
  final ProfileNumericDelta liveInstancesDelta;

  /// Converts this delta to JSON.
  Map<String, Object?> toJson() => {
        'className': className,
        'libraryUri': libraryUri,
        'allocationBytesDelta': allocationBytesDelta.toJson(),
        'allocationInstancesDelta': allocationInstancesDelta.toJson(),
        'liveBytes': liveBytes.toJson(),
        'liveBytesDelta': liveBytesDelta.toJson(),
        'liveInstances': liveInstances.toJson(),
        'liveInstancesDelta': liveInstancesDelta.toJson(),
      };
}

/// A memory diff between two profiled windows.
class ProfileMemoryComparison {
  /// Creates a memory comparison.
  ProfileMemoryComparison({
    required this.heapBytes,
    required this.externalBytes,
    required this.capacityBytes,
    required this.classCount,
    required List<ProfileMemoryClassDelta> topClasses,
  }) : topClasses = List.unmodifiable(topClasses);

  /// Heap usage delta.
  final ProfileNumericDelta heapBytes;

  /// External memory delta.
  final ProfileNumericDelta externalBytes;

  /// Heap-capacity delta.
  final ProfileNumericDelta capacityBytes;

  /// Class-count delta.
  final ProfileNumericDelta classCount;

  /// Highest-signal per-class deltas.
  final List<ProfileMemoryClassDelta> topClasses;

  /// Converts this comparison to JSON.
  Map<String, Object?> toJson() => {
        'heapBytes': heapBytes.toJson(),
        'externalBytes': externalBytes.toJson(),
        'capacityBytes': capacityBytes.toJson(),
        'classCount': classCount.toJson(),
        'topClasses': [for (final item in topClasses) item.toJson()],
      };
}

/// A structured comparison between two profiled regions or session profiles.
class ProfileRegionComparison {
  /// Creates a region comparison.
  ProfileRegionComparison({
    required this.baselineRegionId,
    required this.currentRegionId,
    required this.baselineName,
    required this.currentName,
    required Map<String, String> baselineAttributes,
    required Map<String, String> currentAttributes,
    required this.durationMicros,
    required this.sampleCount,
    required this.samplePeriodMicros,
    required List<ProfileFrameDelta> topSelfFrames,
    required List<ProfileFrameDelta> topTotalFrames,
    required List<String> warnings,
    this.memory,
    List<ProfileMethodDelta> methods = const [],
  })  : baselineAttributes = Map.unmodifiable(baselineAttributes),
        currentAttributes = Map.unmodifiable(currentAttributes),
        topSelfFrames = List.unmodifiable(topSelfFrames),
        topTotalFrames = List.unmodifiable(topTotalFrames),
        methods = List.unmodifiable(methods),
        warnings = List.unmodifiable(warnings);

  /// The baseline region identifier.
  final String baselineRegionId;

  /// The current region identifier.
  final String currentRegionId;

  /// The baseline region name.
  final String baselineName;

  /// The current region name.
  final String currentName;

  /// The baseline region attributes.
  final Map<String, String> baselineAttributes;

  /// The current region attributes.
  final Map<String, String> currentAttributes;

  /// Duration delta.
  final ProfileNumericDelta durationMicros;

  /// Sample-count delta.
  final ProfileNumericDelta sampleCount;

  /// Sample-period delta.
  final ProfileNumericDelta samplePeriodMicros;

  /// Top self-frame deltas.
  final List<ProfileFrameDelta> topSelfFrames;

  /// Top inclusive-frame deltas.
  final List<ProfileFrameDelta> topTotalFrames;

  /// Method deltas when method tables were available.
  final List<ProfileMethodDelta> methods;

  /// Memory deltas when memory summaries were available.
  final ProfileMemoryComparison? memory;

  /// Comparison warnings.
  final List<String> warnings;

  /// Converts this comparison to JSON.
  Map<String, Object?> toJson() => {
        'baselineRegionId': baselineRegionId,
        'currentRegionId': currentRegionId,
        'baselineName': baselineName,
        'currentName': currentName,
        'baselineAttributes': baselineAttributes,
        'currentAttributes': currentAttributes,
        'durationMicros': durationMicros.toJson(),
        'sampleCount': sampleCount.toJson(),
        'samplePeriodMicros': samplePeriodMicros.toJson(),
        'topSelfFrames': [for (final item in topSelfFrames) item.toJson()],
        'topTotalFrames': [for (final item in topTotalFrames) item.toJson()],
        'methods': [for (final item in methods) item.toJson()],
        if (memory != null) 'memory': memory!.toJson(),
        'warnings': warnings,
      };
}

/// Severity for a regression insight.
enum ProfileRegressionSeverity {
  /// Large or strongly suggestive regression.
  high,

  /// Moderate regression worth attention.
  medium,

  /// Smaller regression signal.
  low;

  int get weight => switch (this) {
        high => 3,
        medium => 2,
        low => 1,
      };
}

/// A structured regression insight derived from a profile comparison.
class ProfileRegressionInsight {
  /// Creates a regression insight.
  const ProfileRegressionInsight({
    required this.kind,
    required this.subject,
    required this.metric,
    required this.title,
    required this.summary,
    required this.severity,
    required this.delta,
    this.location,
  });

  /// The insight kind, such as `duration`, `selfFrame`, or `memory`.
  final String kind;

  /// The frame, method, or memory subject this insight refers to.
  final String subject;

  /// The metric that regressed.
  final String metric;

  /// Short title for the insight.
  final String title;

  /// Human-readable regression summary.
  final String summary;

  /// Importance of this insight.
  final ProfileRegressionSeverity severity;

  /// Metric delta for this insight.
  final ProfileNumericDelta delta;

  /// Source location for the subject when available.
  final String? location;

  /// Converts this insight to JSON.
  Map<String, Object?> toJson() => {
        'kind': kind,
        'subject': subject,
        'metric': metric,
        'title': title,
        'summary': summary,
        'severity': severity.name,
        'delta': delta.toJson(),
        'location': location,
      };
}

/// A prioritized regression summary for a profile comparison.
class ProfileRegressionSummary {
  /// Creates a regression summary.
  ProfileRegressionSummary({
    required this.status,
    required List<ProfileRegressionInsight> insights,
    required List<String> warnings,
  })  : insights = List.unmodifiable(insights),
        warnings = List.unmodifiable(warnings);

  /// Overall comparison status.
  final String status;

  /// Prioritized regression insights.
  final List<ProfileRegressionInsight> insights;

  /// Carry-forward warnings from the comparison inputs.
  final List<String> warnings;

  /// Converts this summary to JSON.
  Map<String, Object?> toJson() => {
        'status': status,
        'insights': [for (final insight in insights) insight.toJson()],
        'warnings': warnings,
      };
}

/// Builds a structured comparison between two prepared profile summaries.
ProfileRegionComparison compareProfileRegions({
  required ProfileRegionResult baseline,
  required ProfileRegionResult current,
  ProfileMethodTable? baselineMethodTable,
  ProfileMethodTable? currentMethodTable,
  int? frameLimit,
  int? methodLimit,
  int? memoryClassLimit,
}) {
  final warnings = <String>[];
  if (baseline.name != current.name) {
    warnings.add(
      'The compared profile names differ: '
      '"${baseline.name}" vs "${current.name}".',
    );
  }
  if (!_sameStringMap(baseline.attributes, current.attributes)) {
    warnings.add('The compared profile attributes differ.');
  }
  if (!_sameCaptureKinds(baseline.captureKinds, current.captureKinds)) {
    warnings.add('The compared capture kinds differ.');
  }
  if (baseline.isolateScope != current.isolateScope) {
    warnings.add(
      'The compared isolate scopes differ: '
      '${baseline.isolateScope.name} vs ${current.isolateScope.name}.',
    );
  }
  if ((baseline.memory == null) != (current.memory == null)) {
    warnings.add('Memory data was only available for one compared profile.');
  }
  if ((baselineMethodTable == null) != (currentMethodTable == null)) {
    warnings
        .add('Method table data was only available for one compared profile.');
  }

  final topSelfFrames = _limitList(
    _buildFrameDeltas(
      baseline.topSelfFrames,
      current.topSelfFrames,
      baseline.topTotalFrames,
      current.topTotalFrames,
      sortBySelf: true,
    ),
    frameLimit,
  );
  final topTotalFrames = _limitList(
    _buildFrameDeltas(
      baseline.topSelfFrames,
      current.topSelfFrames,
      baseline.topTotalFrames,
      current.topTotalFrames,
      sortBySelf: false,
    ),
    frameLimit,
  );
  final methods = (baselineMethodTable == null && currentMethodTable == null)
      ? const <ProfileMethodDelta>[]
      : _limitList(
          _buildMethodDeltas(
            baselineMethodTable?.methods ?? const [],
            currentMethodTable?.methods ?? const [],
          ),
          methodLimit,
        );

  final memory = switch ((baseline.memory, current.memory)) {
    (null, null) => null,
    (final ProfileMemoryResult left, final ProfileMemoryResult right) =>
      _buildMemoryComparison(
        left,
        right,
        memoryClassLimit: memoryClassLimit,
      ),
    (final ProfileMemoryResult left, null) => _buildMemoryComparison(
        left,
        _emptyMemoryResult(left.start.timestamp, left.end.timestamp),
        memoryClassLimit: memoryClassLimit,
      ),
    (null, final ProfileMemoryResult right) => _buildMemoryComparison(
        _emptyMemoryResult(right.start.timestamp, right.end.timestamp),
        right,
        memoryClassLimit: memoryClassLimit,
      ),
  };

  return ProfileRegionComparison(
    baselineRegionId: baseline.regionId,
    currentRegionId: current.regionId,
    baselineName: baseline.name,
    currentName: current.name,
    baselineAttributes: baseline.attributes,
    currentAttributes: current.attributes,
    durationMicros: ProfileNumericDelta(
      baseline: baseline.durationMicros,
      current: current.durationMicros,
    ),
    sampleCount: ProfileNumericDelta(
      baseline: baseline.sampleCount,
      current: current.sampleCount,
    ),
    samplePeriodMicros: ProfileNumericDelta(
      baseline: baseline.samplePeriodMicros,
      current: current.samplePeriodMicros,
    ),
    topSelfFrames: topSelfFrames,
    topTotalFrames: topTotalFrames,
    methods: methods,
    memory: memory,
    warnings: warnings,
  );
}

/// Builds prioritized regression insights from a structured comparison.
ProfileRegressionSummary summarizeProfileRegressions(
  ProfileRegionComparison comparison, {
  int maxInsights = 5,
}) {
  final insights = <ProfileRegressionInsight>[];
  final seenSubjects = <String>{};

  void addInsight(ProfileRegressionInsight insight) {
    insights.add(insight);
    seenSubjects.add('${insight.kind}:${insight.subject}');
  }

  if (comparison.durationMicros.delta > 0) {
    addInsight(
      ProfileRegressionInsight(
        kind: 'duration',
        subject: comparison.currentName,
        metric: 'durationMicros',
        title: 'Overall duration increased',
        summary: _numericDeltaSummary(
          label: 'Duration',
          delta: comparison.durationMicros,
          suffix: 'us',
        ),
        severity: _severityForNumericDelta(
          comparison.durationMicros,
          mediumPercent: 10,
          highPercent: 25,
          mediumAbsolute: 500,
          highAbsolute: 5_000,
        ),
        delta: comparison.durationMicros,
      ),
    );
  }

  for (final frame in comparison.topSelfFrames) {
    if (frame.selfSamples.delta <= 0 ||
        !_markInsightSubject(
          seenSubjects,
          kind: 'selfFrame',
          subject: frame.name,
        )) {
      continue;
    }
    insights.add(
      ProfileRegressionInsight(
        kind: 'selfFrame',
        subject: frame.name,
        metric: 'selfSamples',
        title: 'Hotter self time in ${frame.name}',
        summary: _numericDeltaSummary(
          label: 'Self samples',
          delta: frame.selfSamples,
        ),
        severity: _severityForNumericDelta(
          frame.selfSamples,
          mediumPercent: 10,
          highPercent: 25,
          mediumAbsolute: 2,
          highAbsolute: 5,
        ),
        delta: frame.selfSamples,
        location: frame.location,
      ),
    );
    if (insights.length >= maxInsights) {
      return _finalizeRegressionSummary(comparison, insights, maxInsights);
    }
  }

  for (final frame in comparison.topTotalFrames) {
    if (frame.totalSamples.delta <= 0 ||
        !_markInsightSubject(
          seenSubjects,
          kind: 'totalFrame',
          subject: frame.name,
        )) {
      continue;
    }
    insights.add(
      ProfileRegressionInsight(
        kind: 'totalFrame',
        subject: frame.name,
        metric: 'totalSamples',
        title: 'More inclusive time under ${frame.name}',
        summary: _numericDeltaSummary(
          label: 'Total samples',
          delta: frame.totalSamples,
        ),
        severity: _severityForNumericDelta(
          frame.totalSamples,
          mediumPercent: 10,
          highPercent: 25,
          mediumAbsolute: 2,
          highAbsolute: 5,
        ),
        delta: frame.totalSamples,
        location: frame.location,
      ),
    );
    if (insights.length >= maxInsights) {
      return _finalizeRegressionSummary(comparison, insights, maxInsights);
    }
  }

  for (final method in comparison.methods) {
    if (method.totalSamples.delta <= 0 ||
        !_markInsightSubject(
          seenSubjects,
          kind: 'method',
          subject: method.name,
        )) {
      continue;
    }
    insights.add(
      ProfileRegressionInsight(
        kind: 'method',
        subject: method.name,
        metric: 'totalSamples',
        title: 'Method regression in ${method.name}',
        summary: _numericDeltaSummary(
          label: 'Inclusive samples',
          delta: method.totalSamples,
        ),
        severity: _severityForNumericDelta(
          method.totalSamples,
          mediumPercent: 10,
          highPercent: 25,
          mediumAbsolute: 2,
          highAbsolute: 5,
        ),
        delta: method.totalSamples,
        location: method.location,
      ),
    );
    if (insights.length >= maxInsights) {
      return _finalizeRegressionSummary(comparison, insights, maxInsights);
    }
  }

  final memory = comparison.memory;
  if (memory != null && memory.heapBytes.delta > 0) {
    addInsight(
      ProfileRegressionInsight(
        kind: 'memory',
        subject: comparison.currentName,
        metric: 'heapBytes',
        title: 'Heap growth increased',
        summary: _numericDeltaSummary(
          label: 'Heap delta',
          delta: memory.heapBytes,
          suffix: ' bytes',
        ),
        severity: _severityForNumericDelta(
          memory.heapBytes,
          mediumPercent: 10,
          highPercent: 25,
          mediumAbsolute: 1024,
          highAbsolute: 10 * 1024,
        ),
        delta: memory.heapBytes,
      ),
    );
  }

  if (memory != null) {
    for (final item in memory.topClasses) {
      if (item.allocationBytesDelta.delta <= 0 ||
          !_markInsightSubject(
            seenSubjects,
            kind: 'memoryClass',
            subject: item.className,
          )) {
        continue;
      }
      insights.add(
        ProfileRegressionInsight(
          kind: 'memoryClass',
          subject: item.className,
          metric: 'allocationBytesDelta',
          title: 'Allocation growth in ${item.className}',
          summary: _numericDeltaSummary(
            label: 'Allocated bytes',
            delta: item.allocationBytesDelta,
            suffix: ' bytes',
          ),
          severity: _severityForNumericDelta(
            item.allocationBytesDelta,
            mediumPercent: 10,
            highPercent: 25,
            mediumAbsolute: 512,
            highAbsolute: 4 * 1024,
          ),
          delta: item.allocationBytesDelta,
          location: item.libraryUri,
        ),
      );
      if (insights.length >= maxInsights) {
        break;
      }
    }
  }

  return _finalizeRegressionSummary(comparison, insights, maxInsights);
}

List<ProfileFrameDelta> _buildFrameDeltas(
  List<ProfileFrameSummary> baselineSelfFrames,
  List<ProfileFrameSummary> currentSelfFrames,
  List<ProfileFrameSummary> baselineTotalFrames,
  List<ProfileFrameSummary> currentTotalFrames, {
  required bool sortBySelf,
}) {
  final baselineSelfById = {
    for (final frame in baselineSelfFrames) _frameId(frame): frame,
  };
  final currentSelfById = {
    for (final frame in currentSelfFrames) _frameId(frame): frame,
  };
  final baselineTotalById = {
    for (final frame in baselineTotalFrames) _frameId(frame): frame,
  };
  final currentTotalById = {
    for (final frame in currentTotalFrames) _frameId(frame): frame,
  };
  final frameIds = <String>{
    ...baselineSelfById.keys,
    ...currentSelfById.keys,
    ...baselineTotalById.keys,
    ...currentTotalById.keys,
  };

  final deltas = <ProfileFrameDelta>[
    for (final frameId in frameIds)
      _buildFrameDelta(
        frameId,
        baselineSelfById[frameId],
        currentSelfById[frameId],
        baselineTotalById[frameId],
        currentTotalById[frameId],
      ),
  ];

  deltas.sort(
    sortBySelf ? _compareSelfFrameDeltas : _compareTotalFrameDeltas,
  );
  return deltas;
}

ProfileFrameDelta _buildFrameDelta(
  String frameId,
  ProfileFrameSummary? baselineSelf,
  ProfileFrameSummary? currentSelf,
  ProfileFrameSummary? baselineTotal,
  ProfileFrameSummary? currentTotal,
) {
  final sampleFrame =
      baselineSelf ?? currentSelf ?? baselineTotal ?? currentTotal;
  return ProfileFrameDelta(
    frameId: frameId,
    name: sampleFrame?.name ?? 'unknown',
    kind: sampleFrame?.kind ?? 'unknown',
    location: sampleFrame?.location,
    selfSamples: ProfileNumericDelta(
      baseline: baselineSelf?.selfSamples ?? 0,
      current: currentSelf?.selfSamples ?? 0,
    ),
    totalSamples: ProfileNumericDelta(
      baseline: baselineTotal?.totalSamples ?? 0,
      current: currentTotal?.totalSamples ?? 0,
    ),
    selfPercent: ProfileNumericDelta(
      baseline: baselineSelf?.selfPercent ?? 0.0,
      current: currentSelf?.selfPercent ?? 0.0,
    ),
    totalPercent: ProfileNumericDelta(
      baseline: baselineTotal?.totalPercent ?? 0.0,
      current: currentTotal?.totalPercent ?? 0.0,
    ),
  );
}

List<ProfileMethodDelta> _buildMethodDeltas(
  List<ProfileMethodSummary> baselineMethods,
  List<ProfileMethodSummary> currentMethods,
) {
  final baselineById = {
    for (final method in baselineMethods) _methodId(method): method,
  };
  final currentById = {
    for (final method in currentMethods) _methodId(method): method,
  };
  final methodIds = <String>{...baselineById.keys, ...currentById.keys};

  final deltas = <ProfileMethodDelta>[
    for (final methodId in methodIds)
      _buildMethodDelta(
          methodId, baselineById[methodId], currentById[methodId]),
  ];
  deltas.sort(_compareMethodDeltas);
  return deltas;
}

ProfileMethodDelta _buildMethodDelta(
  String methodId,
  ProfileMethodSummary? baseline,
  ProfileMethodSummary? current,
) {
  final sampleMethod = baseline ?? current;
  return ProfileMethodDelta(
    methodId: methodId,
    name: sampleMethod?.name ?? 'unknown',
    kind: sampleMethod?.kind ?? 'unknown',
    location: sampleMethod?.location,
    selfSamples: ProfileNumericDelta(
      baseline: baseline?.selfSamples ?? 0,
      current: current?.selfSamples ?? 0,
    ),
    totalSamples: ProfileNumericDelta(
      baseline: baseline?.totalSamples ?? 0,
      current: current?.totalSamples ?? 0,
    ),
    selfPercent: ProfileNumericDelta(
      baseline: baseline?.selfPercent ?? 0.0,
      current: current?.selfPercent ?? 0.0,
    ),
    totalPercent: ProfileNumericDelta(
      baseline: baseline?.totalPercent ?? 0.0,
      current: current?.totalPercent ?? 0.0,
    ),
    selfMicros: ProfileNumericDelta(
      baseline: baseline?.selfMicros ?? 0,
      current: current?.selfMicros ?? 0,
    ),
    totalMicros: ProfileNumericDelta(
      baseline: baseline?.totalMicros ?? 0,
      current: current?.totalMicros ?? 0,
    ),
  );
}

ProfileMemoryComparison _buildMemoryComparison(
  ProfileMemoryResult baseline,
  ProfileMemoryResult current, {
  int? memoryClassLimit,
}) {
  final baselineById = {
    for (final item in baseline.topClasses) _memoryClassId(item): item,
  };
  final currentById = {
    for (final item in current.topClasses) _memoryClassId(item): item,
  };
  final classIds = <String>{...baselineById.keys, ...currentById.keys};
  final topClasses = <ProfileMemoryClassDelta>[
    for (final classId in classIds)
      _buildMemoryClassDelta(
          classId, baselineById[classId], currentById[classId]),
  ]..sort(_compareMemoryClassDeltas);

  return ProfileMemoryComparison(
    heapBytes: ProfileNumericDelta(
      baseline: baseline.deltaHeapBytes,
      current: current.deltaHeapBytes,
    ),
    externalBytes: ProfileNumericDelta(
      baseline: baseline.deltaExternalBytes,
      current: current.deltaExternalBytes,
    ),
    capacityBytes: ProfileNumericDelta(
      baseline: baseline.deltaCapacityBytes,
      current: current.deltaCapacityBytes,
    ),
    classCount: ProfileNumericDelta(
      baseline: baseline.classCount,
      current: current.classCount,
    ),
    topClasses: _limitList(topClasses, memoryClassLimit),
  );
}

ProfileMemoryClassDelta _buildMemoryClassDelta(
  String classId,
  ProfileMemoryClassSummary? baseline,
  ProfileMemoryClassSummary? current,
) {
  final sampleClass = baseline ?? current;
  return ProfileMemoryClassDelta(
    className: sampleClass?.className ?? classId,
    libraryUri: sampleClass?.libraryUri,
    allocationBytesDelta: ProfileNumericDelta(
      baseline: baseline?.allocationBytesDelta ?? 0,
      current: current?.allocationBytesDelta ?? 0,
    ),
    allocationInstancesDelta: ProfileNumericDelta(
      baseline: baseline?.allocationInstancesDelta ?? 0,
      current: current?.allocationInstancesDelta ?? 0,
    ),
    liveBytes: ProfileNumericDelta(
      baseline: baseline?.liveBytes ?? 0,
      current: current?.liveBytes ?? 0,
    ),
    liveBytesDelta: ProfileNumericDelta(
      baseline: baseline?.liveBytesDelta ?? 0,
      current: current?.liveBytesDelta ?? 0,
    ),
    liveInstances: ProfileNumericDelta(
      baseline: baseline?.liveInstances ?? 0,
      current: current?.liveInstances ?? 0,
    ),
    liveInstancesDelta: ProfileNumericDelta(
      baseline: baseline?.liveInstancesDelta ?? 0,
      current: current?.liveInstancesDelta ?? 0,
    ),
  );
}

ProfileMemoryResult _emptyMemoryResult(int startTimestamp, int endTimestamp) {
  return ProfileMemoryResult(
    start: HeapSample(startTimestamp, 0, 0, 0, 0, false, null, null, null),
    end: HeapSample(endTimestamp, 0, 0, 0, 0, false, null, null, null),
    deltaHeapBytes: 0,
    deltaExternalBytes: 0,
    deltaCapacityBytes: 0,
    classCount: 0,
    topClasses: const [],
  );
}

String _frameId(ProfileFrameSummary frame) =>
    '${frame.name}|${frame.kind}|${frame.location ?? ''}';

String _methodId(ProfileMethodSummary method) {
  if (method.methodId.isNotEmpty) {
    return method.methodId;
  }
  return '${method.name}|${method.kind}|${method.location ?? ''}';
}

String _memoryClassId(ProfileMemoryClassSummary item) =>
    '${item.className}|${item.libraryUri ?? ''}';

int _compareSelfFrameDeltas(ProfileFrameDelta left, ProfileFrameDelta right) {
  final selfCompare = _compareByAbsoluteDelta(
    left.selfSamples.delta,
    right.selfSamples.delta,
  );
  if (selfCompare != 0) {
    return selfCompare;
  }
  final totalCompare = _compareByAbsoluteDelta(
    left.totalSamples.delta,
    right.totalSamples.delta,
  );
  if (totalCompare != 0) {
    return totalCompare;
  }
  return left.name.compareTo(right.name);
}

int _compareTotalFrameDeltas(ProfileFrameDelta left, ProfileFrameDelta right) {
  final totalCompare = _compareByAbsoluteDelta(
    left.totalSamples.delta,
    right.totalSamples.delta,
  );
  if (totalCompare != 0) {
    return totalCompare;
  }
  final selfCompare = _compareByAbsoluteDelta(
    left.selfSamples.delta,
    right.selfSamples.delta,
  );
  if (selfCompare != 0) {
    return selfCompare;
  }
  return left.name.compareTo(right.name);
}

int _compareMethodDeltas(ProfileMethodDelta left, ProfileMethodDelta right) {
  final totalCompare = _compareByAbsoluteDelta(
    left.totalSamples.delta,
    right.totalSamples.delta,
  );
  if (totalCompare != 0) {
    return totalCompare;
  }
  final selfCompare = _compareByAbsoluteDelta(
    left.selfSamples.delta,
    right.selfSamples.delta,
  );
  if (selfCompare != 0) {
    return selfCompare;
  }
  return left.name.compareTo(right.name);
}

int _compareMemoryClassDeltas(
  ProfileMemoryClassDelta left,
  ProfileMemoryClassDelta right,
) {
  final allocationCompare = _compareByAbsoluteDelta(
    left.allocationBytesDelta.delta,
    right.allocationBytesDelta.delta,
  );
  if (allocationCompare != 0) {
    return allocationCompare;
  }
  final liveCompare = _compareByAbsoluteDelta(
    left.liveBytesDelta.delta,
    right.liveBytesDelta.delta,
  );
  if (liveCompare != 0) {
    return liveCompare;
  }
  return left.className.compareTo(right.className);
}

int _compareByAbsoluteDelta(num left, num right) {
  final absoluteCompare = right.abs().compareTo(left.abs());
  if (absoluteCompare != 0) {
    return absoluteCompare;
  }
  return right.compareTo(left);
}

List<T> _limitList<T>(List<T> items, int? limit) {
  if (limit == null || items.length <= limit) {
    return items;
  }
  return items.take(limit).toList(growable: false);
}

bool _sameCaptureKinds(
  List<ProfileCaptureKind> baseline,
  List<ProfileCaptureKind> current,
) {
  if (baseline.length != current.length) {
    return false;
  }
  for (var index = 0; index < baseline.length; index++) {
    if (baseline[index] != current[index]) {
      return false;
    }
  }
  return true;
}

bool _sameStringMap(
  Map<String, String> baseline,
  Map<String, String> current,
) {
  if (baseline.length != current.length) {
    return false;
  }
  for (final entry in baseline.entries) {
    if (current[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

ProfileRegressionSummary _finalizeRegressionSummary(
  ProfileRegionComparison comparison,
  List<ProfileRegressionInsight> insights,
  int maxInsights,
) {
  insights.sort(_compareRegressionInsights);
  final limited = maxInsights <= 0
      ? insights
      : insights.take(maxInsights).toList(growable: false);
  return ProfileRegressionSummary(
    status: limited.isEmpty ? 'stable' : 'regressed',
    insights: limited,
    warnings: comparison.warnings,
  );
}

bool _markInsightSubject(
  Set<String> seenSubjects, {
  required String kind,
  required String subject,
}) {
  final key = '$kind:$subject';
  if (seenSubjects.contains(key)) {
    return false;
  }
  seenSubjects.add(key);
  return true;
}

ProfileRegressionSeverity _severityForNumericDelta(
  ProfileNumericDelta delta, {
  required double mediumPercent,
  required double highPercent,
  required num mediumAbsolute,
  required num highAbsolute,
}) {
  final percent = delta.percentChange;
  final absolute = delta.delta.abs();
  if ((percent != null && percent >= highPercent) || absolute >= highAbsolute) {
    return ProfileRegressionSeverity.high;
  }
  if ((percent != null && percent >= mediumPercent) ||
      absolute >= mediumAbsolute) {
    return ProfileRegressionSeverity.medium;
  }
  return ProfileRegressionSeverity.low;
}

int _compareRegressionInsights(
  ProfileRegressionInsight left,
  ProfileRegressionInsight right,
) {
  final severityCompare = right.severity.weight.compareTo(left.severity.weight);
  if (severityCompare != 0) {
    return severityCompare;
  }
  final deltaCompare =
      right.delta.delta.abs().compareTo(left.delta.delta.abs());
  if (deltaCompare != 0) {
    return deltaCompare;
  }
  return left.title.compareTo(right.title);
}

String _numericDeltaSummary({
  required String label,
  required ProfileNumericDelta delta,
  String suffix = '',
}) {
  final percent = delta.percentChange;
  final change = percent == null
      ? ''
      : ' (${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(1)}%)';
  return '$label increased by ${delta.delta}$suffix '
      '(${delta.baseline}$suffix -> ${delta.current}$suffix)$change.';
}
