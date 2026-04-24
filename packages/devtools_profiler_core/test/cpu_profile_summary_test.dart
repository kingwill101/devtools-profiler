import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test('summarizeCpuSamples ranks self and total frames', () {
    final workerClass = ClassRef(id: 'classes/worker', name: 'Worker');
    final functions = [
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/hot_leaf',
          name: 'hotLeaf',
          owner: workerClass,
        ),
        resolvedUrl: 'package:fixture/hot_leaf.dart',
      ),
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(id: 'functions/run', name: 'run', owner: workerClass),
        resolvedUrl: 'package:fixture/run.dart',
      ),
    ];
    final cpuSamples = CpuSamples(
      samplePeriod: 50,
      timeOriginMicros: 100,
      timeExtentMicros: 300,
      functions: functions,
      samples: [
        CpuSample(timestamp: 110, stack: const [0, 1]),
        CpuSample(timestamp: 160, stack: const [0, 1]),
        CpuSample(timestamp: 220, stack: const [1]),
      ],
    );

    final summary = summarizeCpuSamples(
      regionId: 'region-1',
      name: 'cpu-burn',
      attributes: const {'phase': 'fixture'},
      isolateId: 'isolates/1',
      startTimestampMicros: 100,
      endTimestampMicros: 400,
      cpuSamples: cpuSamples,
      summaryPath: '/tmp/summary.json',
      rawProfilePath: '/tmp/cpu_profile.json',
    );

    expect(summary.sampleCount, 3);
    expect(summary.samplePeriodMicros, 50);
    expect(summary.topSelfFrames.first.name, 'Worker.hotLeaf');
    expect(summary.topSelfFrames.first.selfSamples, 2);
    expect(summary.topSelfFrames.first.totalSamples, 2);
    expect(summary.topTotalFrames.first.name, 'Worker.run');
    expect(summary.topTotalFrames.first.totalSamples, 3);
    expect(summary.topTotalFrames.first.selfSamples, 1);
  });

  test('summarizeCpuSamples counts total frames once per sample', () {
    final workerClass = ClassRef(id: 'classes/worker', name: 'Worker');
    final functions = [
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(id: 'functions/run', name: 'run', owner: workerClass),
        resolvedUrl: 'package:fixture/run.dart',
      ),
    ];
    final cpuSamples = CpuSamples(
      samplePeriod: 50,
      functions: functions,
      samples: [
        CpuSample(timestamp: 100, stack: const [0, 0]),
      ],
    );

    final summary = summarizeCpuSamples(
      regionId: 'region-1',
      name: 'cpu-burn',
      attributes: const {},
      isolateId: 'isolates/1',
      startTimestampMicros: 0,
      endTimestampMicros: 100,
      cpuSamples: cpuSamples,
      summaryPath: '/tmp/summary.json',
    );

    expect(summary.sampleCount, 1);
    expect(summary.topTotalFrames.single.totalSamples, 1);
    expect(summary.topTotalFrames.single.totalPercent, 1.0);
  });
}
