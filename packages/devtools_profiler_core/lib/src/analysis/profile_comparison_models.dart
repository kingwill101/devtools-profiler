/// Shared models for profile comparisons and regression summaries.

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
