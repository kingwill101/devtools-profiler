import '../capture/models.dart';
import '../cpu/method_table.dart';
import 'profile_comparison.dart';

/// One prepared profile entry in a multi-session trend series.
class ProfileTrendSeriesEntry {
  /// Creates a trend series entry.
  const ProfileTrendSeriesEntry({
    required this.id,
    required this.region,
    this.methodTable,
  });

  /// Stable label for this entry, such as a session id.
  final String id;

  /// The prepared region or whole-session profile.
  final ProfileRegionResult region;

  /// Optional method table for this entry.
  final ProfileMethodTable? methodTable;
}

/// A compact point in a profile trend series.
class ProfileTrendPoint {
  /// Creates a trend point.
  const ProfileTrendPoint({
    required this.id,
    required this.regionId,
    required this.name,
    required this.durationMicros,
    required this.sampleCount,
    required this.samplePeriodMicros,
    this.deltaHeapBytes,
    this.topSelfFrame,
    this.topMethod,
  });

  /// Entry label for this point.
  final String id;

  /// Selected profile id.
  final String regionId;

  /// Profile display name.
  final String name;

  /// Duration of the profile window.
  final int durationMicros;

  /// Captured CPU sample count.
  final int sampleCount;

  /// VM-reported sample period.
  final int samplePeriodMicros;

  /// Heap growth within the window, when memory data was available.
  final int? deltaHeapBytes;

  /// Hottest self frame name, when available.
  final String? topSelfFrame;

  /// Hottest method-table method, when available.
  final String? topMethod;

  /// Converts this point to JSON.
  Map<String, Object?> toJson() => {
        'id': id,
        'regionId': regionId,
        'name': name,
        'durationMicros': durationMicros,
        'sampleCount': sampleCount,
        'samplePeriodMicros': samplePeriodMicros,
        'deltaHeapBytes': deltaHeapBytes,
        'topSelfFrame': topSelfFrame,
        'topMethod': topMethod,
      };
}

/// A consecutive step in a multi-session trend series.
class ProfileTrendStep {
  /// Creates a trend step.
  const ProfileTrendStep({
    required this.baselineId,
    required this.currentId,
    required this.comparison,
    required this.regressions,
  });

  /// Baseline entry label.
  final String baselineId;

  /// Current entry label.
  final String currentId;

  /// Structured profile comparison for this step.
  final ProfileRegionComparison comparison;

  /// Regression summary for this step.
  final ProfileRegressionSummary regressions;

  /// Converts this step to JSON.
  Map<String, Object?> toJson() => {
        'baselineId': baselineId,
        'currentId': currentId,
        'comparison': comparison.toJson(),
        'regressions': regressions.toJson(),
      };
}

/// A recurring regression subject observed across multiple trend steps.
class ProfileRecurringRegression {
  /// Creates a recurring regression summary.
  const ProfileRecurringRegression({
    required this.kind,
    required this.subject,
    required this.metric,
    required this.occurrences,
    required this.totalDelta,
    required this.latestDelta,
    required this.severity,
    this.location,
  });

  /// Regression kind, such as `duration`, `method`, or `memoryClass`.
  final String kind;

  /// Subject for the recurring regression.
  final String subject;

  /// Metric for the recurring regression.
  final String metric;

  /// Number of consecutive steps where this regression appeared.
  final int occurrences;

  /// Sum of positive deltas across all occurrences.
  final num totalDelta;

  /// Most recent positive delta for this subject.
  final num latestDelta;

  /// Highest severity seen for this subject.
  final ProfileRegressionSeverity severity;

  /// Source location for the subject, when available.
  final String? location;

  /// Converts this recurring regression to JSON.
  Map<String, Object?> toJson() => {
        'kind': kind,
        'subject': subject,
        'metric': metric,
        'occurrences': occurrences,
        'totalDelta': totalDelta,
        'latestDelta': latestDelta,
        'severity': severity.name,
        'location': location,
      };
}

/// A structured cross-session trend summary for one selected profile.
class ProfileTrendSummary {
  /// Creates a profile trend summary.
  ProfileTrendSummary({
    required this.status,
    required List<ProfileTrendPoint> points,
    required List<ProfileTrendStep> steps,
    required List<ProfileRecurringRegression> recurringRegressions,
    required List<String> warnings,
    this.overallComparison,
    this.overallRegressions,
  })  : points = List.unmodifiable(points),
        steps = List.unmodifiable(steps),
        recurringRegressions = List.unmodifiable(recurringRegressions),
        warnings = List.unmodifiable(warnings);

  /// Overall trend status.
  final String status;

  /// Compact profile points in chronological series order.
  final List<ProfileTrendPoint> points;

  /// Consecutive comparisons between points.
  final List<ProfileTrendStep> steps;

  /// First-to-last comparison when at least two points were available.
  final ProfileRegionComparison? overallComparison;

  /// First-to-last regression summary when at least two points were available.
  final ProfileRegressionSummary? overallRegressions;

  /// Regression subjects that repeat across multiple steps.
  final List<ProfileRecurringRegression> recurringRegressions;

  /// Trend-analysis warnings.
  final List<String> warnings;

  /// Converts this summary to JSON.
  Map<String, Object?> toJson() => {
        'status': status,
        'points': [for (final point in points) point.toJson()],
        'steps': [for (final step in steps) step.toJson()],
        if (overallComparison != null)
          'overallComparison': overallComparison!.toJson(),
        if (overallRegressions != null)
          'overallRegressions': overallRegressions!.toJson(),
        'recurringRegressions': [
          for (final item in recurringRegressions) item.toJson(),
        ],
        'warnings': warnings,
      };
}

/// Builds a cross-session trend summary from a series of prepared profiles.
ProfileTrendSummary analyzeProfileTrends({
  required List<ProfileTrendSeriesEntry> entries,
  int? frameLimit,
  int? methodLimit,
  int? memoryClassLimit,
  int maxInsights = 5,
  int recurringLimit = 5,
}) {
  final points = [
    for (final entry in entries)
      ProfileTrendPoint(
        id: entry.id,
        regionId: entry.region.regionId,
        name: entry.region.name,
        durationMicros: entry.region.durationMicros,
        sampleCount: entry.region.sampleCount,
        samplePeriodMicros: entry.region.samplePeriodMicros,
        deltaHeapBytes: entry.region.memory?.deltaHeapBytes,
        topSelfFrame: entry.region.topSelfFrames.isEmpty
            ? null
            : entry.region.topSelfFrames.first.name,
        topMethod: entry.methodTable?.methods.isEmpty ?? true
            ? null
            : entry.methodTable!.methods.first.name,
      ),
  ];

  if (entries.length < 2) {
    return ProfileTrendSummary(
      status: 'insufficientData',
      points: points,
      steps: const [],
      recurringRegressions: const [],
      warnings: const [
        'At least two profile points are required for trend analysis.',
      ],
    );
  }

  final warnings = <String>[];
  final steps = <ProfileTrendStep>[];
  final recurring = <String, _MutableRecurringRegression>{};

  for (var index = 1; index < entries.length; index++) {
    final baseline = entries[index - 1];
    final current = entries[index];
    final comparison = compareProfileRegions(
      baseline: baseline.region,
      current: current.region,
      baselineMethodTable: baseline.methodTable,
      currentMethodTable: current.methodTable,
      frameLimit: frameLimit,
      methodLimit: methodLimit,
      memoryClassLimit: memoryClassLimit,
    );
    final regressions = summarizeProfileRegressions(
      comparison,
      maxInsights: maxInsights,
    );
    steps.add(
      ProfileTrendStep(
        baselineId: baseline.id,
        currentId: current.id,
        comparison: comparison,
        regressions: regressions,
      ),
    );
    warnings.addAll(comparison.warnings);
    warnings.addAll(regressions.warnings);

    for (final insight in regressions.insights) {
      final key = '${insight.kind}|${insight.metric}|${insight.subject}';
      final aggregate = recurring.putIfAbsent(
        key,
        () => _MutableRecurringRegression(
          kind: insight.kind,
          subject: insight.subject,
          metric: insight.metric,
          severity: insight.severity,
          location: insight.location,
        ),
      );
      aggregate.occurrences++;
      aggregate.totalDelta += insight.delta.delta;
      aggregate.latestDelta = insight.delta.delta;
      if (insight.severity.weight > aggregate.severity.weight) {
        aggregate.severity = insight.severity;
      }
      aggregate.location ??= insight.location;
    }
  }

  final overallComparison = compareProfileRegions(
    baseline: entries.first.region,
    current: entries.last.region,
    baselineMethodTable: entries.first.methodTable,
    currentMethodTable: entries.last.methodTable,
    frameLimit: frameLimit,
    methodLimit: methodLimit,
    memoryClassLimit: memoryClassLimit,
  );
  final overallRegressions = summarizeProfileRegressions(
    overallComparison,
    maxInsights: maxInsights,
  );
  warnings.addAll(overallComparison.warnings);
  warnings.addAll(overallRegressions.warnings);

  final recurringRegressions = recurring.values
      .map((item) => item.freeze())
      .toList(growable: false)
    ..sort(_compareRecurringRegressions);
  final limitedRecurring =
      recurringLimit <= 0 || recurringRegressions.length <= recurringLimit
          ? recurringRegressions
          : recurringRegressions.take(recurringLimit).toList(growable: false);

  return ProfileTrendSummary(
    status: _trendStatus(
      steps: steps,
      overallComparison: overallComparison,
      overallRegressions: overallRegressions,
      recurringRegressions: limitedRecurring,
    ),
    points: points,
    steps: steps,
    overallComparison: overallComparison,
    overallRegressions: overallRegressions,
    recurringRegressions: limitedRecurring,
    warnings: _dedupeWarnings(warnings),
  );
}

String _trendStatus({
  required List<ProfileTrendStep> steps,
  required ProfileRegionComparison overallComparison,
  required ProfileRegressionSummary overallRegressions,
  required List<ProfileRecurringRegression> recurringRegressions,
}) {
  final positiveDurationSteps =
      steps.where((step) => step.comparison.durationMicros.delta > 0).length;
  final negativeDurationSteps =
      steps.where((step) => step.comparison.durationMicros.delta < 0).length;
  final hasRegressionSignal = overallRegressions.status == 'regressed' ||
      recurringRegressions.isNotEmpty;
  final overallHeapDelta = overallComparison.memory?.heapBytes.delta ?? 0;
  final hasImprovementSignal = overallComparison.durationMicros.delta < 0 ||
      overallHeapDelta < 0 ||
      (negativeDurationSteps > 0 && positiveDurationSteps == 0);

  if (hasRegressionSignal && hasImprovementSignal) {
    return 'mixed';
  }
  if (hasRegressionSignal) {
    return 'regressing';
  }
  if (hasImprovementSignal) {
    return 'improving';
  }
  return 'stable';
}

int _compareRecurringRegressions(
  ProfileRecurringRegression left,
  ProfileRecurringRegression right,
) {
  final occurrenceCompare = right.occurrences.compareTo(left.occurrences);
  if (occurrenceCompare != 0) {
    return occurrenceCompare;
  }
  final severityCompare = right.severity.weight.compareTo(left.severity.weight);
  if (severityCompare != 0) {
    return severityCompare;
  }
  final totalCompare = right.totalDelta.abs().compareTo(left.totalDelta.abs());
  if (totalCompare != 0) {
    return totalCompare;
  }
  return left.subject.compareTo(right.subject);
}

List<String> _dedupeWarnings(List<String> warnings) {
  final seen = <String>{};
  final deduped = <String>[];
  for (final warning in warnings) {
    if (seen.add(warning)) {
      deduped.add(warning);
    }
  }
  return deduped;
}

final class _MutableRecurringRegression {
  _MutableRecurringRegression({
    required this.kind,
    required this.subject,
    required this.metric,
    required this.severity,
    required this.location,
  });

  final String kind;
  final String subject;
  final String metric;
  String? location;
  int occurrences = 0;
  num totalDelta = 0;
  num latestDelta = 0;
  ProfileRegressionSeverity severity;

  ProfileRecurringRegression freeze() {
    return ProfileRecurringRegression(
      kind: kind,
      subject: subject,
      metric: metric,
      occurrences: occurrences,
      totalDelta: totalDelta,
      latestDelta: latestDelta,
      severity: severity,
      location: location,
    );
  }
}
