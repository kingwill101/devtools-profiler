import 'profile_comparison_models.dart';

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
          mediumAbsolute: 1_024,
          highAbsolute: 10 * 1_024,
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
            highAbsolute: 4 * 1_024,
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
