
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test('mergeCpuSamples preserves stacks from multiple isolates', () {
    final workerClass = ClassRef(id: 'classes/worker', name: 'Worker');
    final left = CpuSamples(
      sampleCount: 1,
      samplePeriod: 1000,
      timeOriginMicros: 10,
      timeExtentMicros: 50,
      functions: [
        ProfileFunction(
          kind: 'Dart',
          function: FuncRef(
            id: 'functions/left',
            name: 'leftLeaf',
            owner: workerClass,
          ),
          resolvedUrl: 'package:fixture/left.dart',
        ),
      ],
      samples: [
        CpuSample(timestamp: 20, stack: const [0]),
      ],
    );
    final right = CpuSamples(
      sampleCount: 1,
      samplePeriod: 1000,
      timeOriginMicros: 15,
      timeExtentMicros: 80,
      functions: [
        ProfileFunction(
          kind: 'Dart',
          function: FuncRef(
            id: 'functions/right',
            name: 'rightLeaf',
            owner: workerClass,
          ),
          resolvedUrl: 'package:fixture/right.dart',
        ),
      ],
      samples: [
        CpuSample(timestamp: 30, stack: const [0]),
      ],
    );

    final merged = mergeCpuSamples([left, right]);
    final summary = summarizeCpuSamples(
      regionId: 'region-1',
      name: 'merged',
      attributes: const {},
      isolateId: 'isolates/main',
      startTimestampMicros: 10,
      endTimestampMicros: 95,
      cpuSamples: merged,
      summaryPath: '/tmp/summary.json',
    );

    expect(merged.sampleCount, 2);
    expect(merged.functions, hasLength(2));
    expect(merged.samples, hasLength(2));
    expect(summary.sampleCount, 2);
    expect(
      summary.topSelfFrames.map((frame) => frame.name),
      containsAll(['Worker.leftLeaf', 'Worker.rightLeaf']),
    );
  });
}
