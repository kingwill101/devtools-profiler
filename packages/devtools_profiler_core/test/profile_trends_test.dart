
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';

void main() {
  test('analyzeProfileTrends summarizes recurring regressions', () {
    final first = _entry(
      id: 'session-1',
      durationMicros: 100,
      sampleCount: 10,
      hotLeafSelfSamples: 4,
      hotLeafTotalSamples: 5,
      hotLeafTotalPercent: 0.50,
      runTotalSamples: 8,
    );
    final second = _entry(
      id: 'session-2',
      durationMicros: 150,
      sampleCount: 12,
      hotLeafSelfSamples: 6,
      hotLeafTotalSamples: 7,
      hotLeafTotalPercent: 0.58,
      runTotalSamples: 10,
    );
    final third = _entry(
      id: 'session-3',
      durationMicros: 190,
      sampleCount: 14,
      hotLeafSelfSamples: 8,
      hotLeafTotalSamples: 9,
      hotLeafTotalPercent: 0.64,
      runTotalSamples: 12,
    );

    final summary = analyzeProfileTrends(
      entries: [first, second, third],
      methodLimit: 4,
    );

    expect(summary.status, 'regressing');
    expect(summary.points, hasLength(3));
    expect(summary.steps, hasLength(2));
    expect(summary.overallComparison, isNotNull);
    expect(summary.overallComparison!.durationMicros.delta, 90);
    expect(summary.overallRegressions, isNotNull);
    expect(summary.overallRegressions!.status, 'regressed');
    expect(summary.recurringRegressions, isNotEmpty);

    final recurringMethod = summary.recurringRegressions.firstWhere(
      (item) => item.kind == 'method' && item.subject == 'Worker.hotLeaf',
    );
    expect(recurringMethod.occurrences, 2);
    expect(recurringMethod.totalDelta, greaterThan(0));
  });
}

ProfileTrendSeriesEntry _entry({
  required String id,
  required int durationMicros,
  required int sampleCount,
  required int hotLeafSelfSamples,
  required int hotLeafTotalSamples,
  required double hotLeafTotalPercent,
  required int runTotalSamples,
}) {
  return ProfileTrendSeriesEntry(
    id: id,
    region: ProfileRegionResult(
      regionId: 'overall',
      name: 'whole-session',
      attributes: const {'scope': 'session'},
      isolateId: 'isolates/1',
      captureKinds: const [ProfileCaptureKind.cpu],
      startTimestampMicros: 0,
      endTimestampMicros: durationMicros,
      durationMicros: durationMicros,
      sampleCount: sampleCount,
      samplePeriodMicros: 50,
      topSelfFrames: [
        ProfileFrameSummary(
          name: 'Worker.hotLeaf',
          kind: 'Dart',
          location: 'package:fixture/hot_leaf.dart',
          selfSamples: hotLeafSelfSamples,
          totalSamples: hotLeafTotalSamples,
          selfPercent: hotLeafSelfSamples / sampleCount,
          totalPercent: hotLeafTotalPercent,
        ),
      ],
      topTotalFrames: [
        ProfileFrameSummary(
          name: 'Worker.run',
          kind: 'Dart',
          location: 'package:fixture/run.dart',
          selfSamples: 1,
          totalSamples: runTotalSamples,
          selfPercent: 1 / sampleCount,
          totalPercent: runTotalSamples / sampleCount,
        ),
      ],
      summaryPath: '/tmp/$id/overall/summary.json',
      rawProfilePath: '/tmp/$id/overall/cpu_profile.json',
    ),
    methodTable: ProfileMethodTable(
      sampleCount: sampleCount,
      samplePeriodMicros: 50,
      methods: [
        ProfileMethodSummary(
          methodId: 'Worker.hotLeaf|Dart|package:fixture/hot_leaf.dart',
          name: 'Worker.hotLeaf',
          kind: 'Dart',
          location: 'package:fixture/hot_leaf.dart',
          selfSamples: hotLeafSelfSamples,
          totalSamples: hotLeafTotalSamples,
          selfPercent: hotLeafSelfSamples / sampleCount,
          totalPercent: hotLeafTotalPercent,
          selfMicros: hotLeafSelfSamples * 50,
          totalMicros: hotLeafTotalSamples * 50,
          callers: const [
            ProfileMethodRelation(
              methodId: 'Worker.run|Dart|package:fixture/run.dart',
              name: 'Worker.run',
              kind: 'Dart',
              location: 'package:fixture/run.dart',
              sampleCount: 1,
              percent: 1.0,
            ),
          ],
          callees: const [],
        ),
        ProfileMethodSummary(
          methodId: 'Worker.run|Dart|package:fixture/run.dart',
          name: 'Worker.run',
          kind: 'Dart',
          location: 'package:fixture/run.dart',
          selfSamples: 1,
          totalSamples: runTotalSamples,
          selfPercent: 1 / sampleCount,
          totalPercent: runTotalSamples / sampleCount,
          selfMicros: 50,
          totalMicros: runTotalSamples * 50,
          callers: const [],
          callees: const [
            ProfileMethodRelation(
              methodId: 'Worker.hotLeaf|Dart|package:fixture/hot_leaf.dart',
              name: 'Worker.hotLeaf',
              kind: 'Dart',
              location: 'package:fixture/hot_leaf.dart',
              sampleCount: 1,
              percent: 1.0,
            ),
          ],
        ),
      ],
    ),
  );
}
