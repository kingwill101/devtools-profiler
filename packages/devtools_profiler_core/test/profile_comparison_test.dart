import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:test/test.dart';

void main() {
  test('compareProfileRegions computes cpu, method, and memory deltas', () {
    final baseline = _region(
      regionId: 'region-baseline',
      durationMicros: 1000,
      sampleCount: 10,
      topSelfFrames: const [
        ProfileFrameSummary(
          name: 'Worker.run',
          kind: 'Dart',
          location: 'package:fixture/run.dart',
          selfSamples: 6,
          totalSamples: 8,
          selfPercent: 0.6,
          totalPercent: 0.8,
        ),
        ProfileFrameSummary(
          name: 'Worker.parse',
          kind: 'Dart',
          location: 'package:fixture/parse.dart',
          selfSamples: 4,
          totalSamples: 6,
          selfPercent: 0.4,
          totalPercent: 0.6,
        ),
      ],
      topTotalFrames: const [
        ProfileFrameSummary(
          name: 'Worker.run',
          kind: 'Dart',
          location: 'package:fixture/run.dart',
          selfSamples: 6,
          totalSamples: 8,
          selfPercent: 0.6,
          totalPercent: 0.8,
        ),
        ProfileFrameSummary(
          name: 'Worker.parse',
          kind: 'Dart',
          location: 'package:fixture/parse.dart',
          selfSamples: 4,
          totalSamples: 6,
          selfPercent: 0.4,
          totalPercent: 0.6,
        ),
      ],
      memory: ProfileMemoryResult(
        start: HeapSample(1, 0, 2048, 1024, 32, false, null, null, null),
        end: HeapSample(2, 0, 3072, 1124, 64, false, null, null, null),
        deltaHeapBytes: 100,
        deltaExternalBytes: 32,
        deltaCapacityBytes: 1024,
        classCount: 1,
        topClasses: const [
          ProfileMemoryClassSummary(
            className: 'Buffer',
            libraryUri: 'package:fixture/buffer.dart',
            allocationBytesDelta: 100,
            allocationInstancesDelta: 2,
            liveBytes: 100,
            liveBytesDelta: 100,
            liveInstances: 2,
            liveInstancesDelta: 2,
          ),
        ],
      ),
    );
    final current = _region(
      regionId: 'region-current',
      durationMicros: 1700,
      sampleCount: 14,
      topSelfFrames: const [
        ProfileFrameSummary(
          name: 'Worker.hotLeaf',
          kind: 'Dart',
          location: 'package:fixture/hot_leaf.dart',
          selfSamples: 9,
          totalSamples: 11,
          selfPercent: 0.64,
          totalPercent: 0.79,
        ),
        ProfileFrameSummary(
          name: 'Worker.run',
          kind: 'Dart',
          location: 'package:fixture/run.dart',
          selfSamples: 5,
          totalSamples: 10,
          selfPercent: 0.36,
          totalPercent: 0.71,
        ),
      ],
      topTotalFrames: const [
        ProfileFrameSummary(
          name: 'Worker.hotLeaf',
          kind: 'Dart',
          location: 'package:fixture/hot_leaf.dart',
          selfSamples: 9,
          totalSamples: 11,
          selfPercent: 0.64,
          totalPercent: 0.79,
        ),
        ProfileFrameSummary(
          name: 'Worker.run',
          kind: 'Dart',
          location: 'package:fixture/run.dart',
          selfSamples: 5,
          totalSamples: 10,
          selfPercent: 0.36,
          totalPercent: 0.71,
        ),
      ],
      memory: ProfileMemoryResult(
        start: HeapSample(3, 0, 4096, 1124, 64, false, null, null, null),
        end: HeapSample(4, 0, 6144, 1624, 128, false, null, null, null),
        deltaHeapBytes: 500,
        deltaExternalBytes: 64,
        deltaCapacityBytes: 2048,
        classCount: 2,
        topClasses: const [
          ProfileMemoryClassSummary(
            className: 'Buffer',
            libraryUri: 'package:fixture/buffer.dart',
            allocationBytesDelta: 260,
            allocationInstancesDelta: 4,
            liveBytes: 240,
            liveBytesDelta: 240,
            liveInstances: 4,
            liveInstancesDelta: 4,
          ),
          ProfileMemoryClassSummary(
            className: 'Cache',
            libraryUri: 'package:fixture/cache.dart',
            allocationBytesDelta: 140,
            allocationInstancesDelta: 1,
            liveBytes: 140,
            liveBytesDelta: 140,
            liveInstances: 1,
            liveInstancesDelta: 1,
          ),
        ],
      ),
    );

    final comparison = compareProfileRegions(
      baseline: baseline,
      current: current,
      baselineMethodTable: ProfileMethodTable(
        sampleCount: 10,
        samplePeriodMicros: 50,
        methods: [
          ProfileMethodSummary(
            methodId: 'method/run',
            name: 'Worker.run',
            kind: 'Dart',
            location: 'package:fixture/run.dart',
            selfSamples: 6,
            totalSamples: 8,
            selfPercent: 0.6,
            totalPercent: 0.8,
            selfMicros: 300,
            totalMicros: 400,
            callers: const [],
            callees: const [],
          ),
          ProfileMethodSummary(
            methodId: 'method/parse',
            name: 'Worker.parse',
            kind: 'Dart',
            location: 'package:fixture/parse.dart',
            selfSamples: 4,
            totalSamples: 6,
            selfPercent: 0.4,
            totalPercent: 0.6,
            selfMicros: 200,
            totalMicros: 300,
            callers: const [],
            callees: const [],
          ),
        ],
      ),
      currentMethodTable: ProfileMethodTable(
        sampleCount: 14,
        samplePeriodMicros: 50,
        methods: [
          ProfileMethodSummary(
            methodId: 'method/hot_leaf',
            name: 'Worker.hotLeaf',
            kind: 'Dart',
            location: 'package:fixture/hot_leaf.dart',
            selfSamples: 9,
            totalSamples: 11,
            selfPercent: 0.64,
            totalPercent: 0.79,
            selfMicros: 450,
            totalMicros: 550,
            callers: const [],
            callees: const [],
          ),
          ProfileMethodSummary(
            methodId: 'method/run',
            name: 'Worker.run',
            kind: 'Dart',
            location: 'package:fixture/run.dart',
            selfSamples: 5,
            totalSamples: 10,
            selfPercent: 0.36,
            totalPercent: 0.71,
            selfMicros: 250,
            totalMicros: 500,
            callers: const [],
            callees: const [],
          ),
        ],
      ),
      frameLimit: 3,
      methodLimit: 3,
      memoryClassLimit: 3,
    );

    expect(comparison.durationMicros.delta, 700);
    expect(comparison.sampleCount.delta, 4);
    expect(comparison.topSelfFrames.first.name, 'Worker.hotLeaf');
    expect(comparison.topSelfFrames.first.selfSamples.delta, 9);
    expect(comparison.topTotalFrames.first.name, 'Worker.hotLeaf');
    expect(comparison.methods.first.name, 'Worker.hotLeaf');
    expect(comparison.methods.first.totalSamples.delta, 11);
    expect(comparison.memory, isNotNull);
    expect(comparison.memory!.heapBytes.delta, 400);
    expect(comparison.memory!.topClasses.first.className, 'Buffer');
    expect(comparison.memory!.topClasses[1].className, 'Cache');
    expect(comparison.warnings, isEmpty);

    final regressions = summarizeProfileRegressions(comparison, maxInsights: 8);
    expect(regressions.status, 'regressed');
    expect(regressions.insights, isNotEmpty);
    expect(regressions.insights.first.kind, 'duration');
    expect(regressions.insights.first.severity, ProfileRegressionSeverity.high);
    expect(
      regressions.insights.any(
        (insight) => insight.subject == 'Worker.hotLeaf',
      ),
      isTrue,
    );
    expect(
      regressions.insights.any((insight) => insight.kind == 'memory'),
      isTrue,
    );
  });

  test('compareProfileRegions emits warnings for mismatched metadata', () {
    final comparison = compareProfileRegions(
      baseline: _region(
        regionId: 'baseline',
        name: 'baseline-region',
        attributes: const {'phase': 'one'},
        isolateScope: ProfileIsolateScope.current,
        captureKinds: const [ProfileCaptureKind.cpu, ProfileCaptureKind.memory],
      ),
      current: _region(
        regionId: 'current',
        name: 'current-region',
        attributes: const {'phase': 'two'},
        isolateScope: ProfileIsolateScope.all,
        captureKinds: const [ProfileCaptureKind.cpu],
      ),
      baselineMethodTable: ProfileMethodTable(
        sampleCount: 1,
        samplePeriodMicros: 50,
        methods: const [],
      ),
    );

    expect(
      comparison.warnings,
      contains(
        'The compared profile names differ: '
        '"baseline-region" vs "current-region".',
      ),
    );
    expect(
      comparison.warnings,
      contains('The compared profile attributes differ.'),
    );
    expect(comparison.warnings, contains('The compared capture kinds differ.'));
    expect(
      comparison.warnings,
      contains('The compared isolate scopes differ: current vs all.'),
    );
    expect(
      comparison.warnings,
      contains(
        'Method table data was only available for one compared profile.',
      ),
    );

    final regressions = summarizeProfileRegressions(comparison);
    expect(regressions.warnings, comparison.warnings);
  });

  test(
    'compareProfileRegions uses memory overrides for availability warnings',
    () {
      final comparison = compareProfileRegions(
        baseline: _region(regionId: 'baseline'),
        current: _region(regionId: 'current'),
        baselineMemoryOverride: _memoryBaseline(),
        currentMemoryOverride: _memoryCurrent(),
      );

      expect(comparison.memory, isNotNull);
      expect(
        comparison.warnings,
        isNot(
          contains('Memory data was only available for one compared profile.'),
        ),
      );
    },
  );
}

ProfileRegionResult _region({
  required String regionId,
  String name = 'cpu-burn',
  Map<String, String> attributes = const {'phase': 'fixture'},
  ProfileIsolateScope isolateScope = ProfileIsolateScope.current,
  List<ProfileCaptureKind> captureKinds = const [ProfileCaptureKind.cpu],
  int durationMicros = 1000,
  int sampleCount = 10,
  List<ProfileFrameSummary> topSelfFrames = const [],
  List<ProfileFrameSummary> topTotalFrames = const [],
  ProfileMemoryResult? memory,
}) {
  return ProfileRegionResult(
    regionId: regionId,
    name: name,
    attributes: attributes,
    isolateId: 'isolates/1',
    isolateIds: const ['isolates/1'],
    captureKinds: captureKinds,
    isolateScope: isolateScope,
    startTimestampMicros: 100,
    endTimestampMicros: 100 + durationMicros,
    durationMicros: durationMicros,
    sampleCount: sampleCount,
    samplePeriodMicros: 50,
    topSelfFrames: topSelfFrames,
    topTotalFrames: topTotalFrames,
    memory: memory,
    summaryPath: '/tmp/$regionId/summary.json',
  );
}

ProfileMemoryResult _memoryBaseline() {
  return ProfileMemoryResult(
    start: HeapSample(1, 0, 2048, 1024, 0, false, null, null, null),
    end: HeapSample(2, 0, 3072, 1536, 0, false, null, null, null),
    deltaHeapBytes: 512,
    deltaExternalBytes: 0,
    deltaCapacityBytes: 1024,
    classCount: 1,
    topClasses: const [
      ProfileMemoryClassSummary(
        className: 'Buffer',
        libraryUri: 'package:fixture/buffer.dart',
        allocationBytesDelta: 512,
        allocationInstancesDelta: 1,
        liveBytes: 512,
        liveBytesDelta: 512,
        liveInstances: 1,
        liveInstancesDelta: 1,
      ),
    ],
  );
}

ProfileMemoryResult _memoryCurrent() {
  return ProfileMemoryResult(
    start: HeapSample(3, 0, 3072, 1536, 0, false, null, null, null),
    end: HeapSample(4, 0, 4096, 2560, 0, false, null, null, null),
    deltaHeapBytes: 1024,
    deltaExternalBytes: 0,
    deltaCapacityBytes: 1024,
    classCount: 1,
    topClasses: const [
      ProfileMemoryClassSummary(
        className: 'Buffer',
        libraryUri: 'package:fixture/buffer.dart',
        allocationBytesDelta: 1024,
        allocationInstancesDelta: 2,
        liveBytes: 1024,
        liveBytesDelta: 1024,
        liveInstances: 2,
        liveInstancesDelta: 2,
      ),
    ],
  );
}
