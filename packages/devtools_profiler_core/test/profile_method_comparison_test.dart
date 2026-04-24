import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  final workerClass = ClassRef(id: 'classes/worker', name: 'Worker');
  final baselineSamples = CpuSamples(
    sampleCount: 10,
    samplePeriod: 50,
    timeOriginMicros: 0,
    timeExtentMicros: 100,
    functions: [
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
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/complete',
          name: '_completeWithValue',
          owner: ClassRef(id: 'classes/future', name: '_Future'),
        ),
        resolvedUrl: 'org-dartlang-sdk:///sdk/lib/async/future_impl.dart',
      ),
    ],
    samples: [
      for (var i = 0; i < 8; i++) CpuSample(timestamp: i, stack: [0, 2, 1]),
      CpuSample(timestamp: 8, stack: const [1]),
      CpuSample(timestamp: 9, stack: const [1]),
    ],
  );
  final currentSamples = CpuSamples(
    sampleCount: 14,
    samplePeriod: 50,
    timeOriginMicros: 0,
    timeExtentMicros: 140,
    functions: baselineSamples.functions,
    samples: [
      for (var i = 0; i < 9; i++) CpuSample(timestamp: i, stack: [0, 2, 1]),
      for (var i = 0; i < 5; i++) CpuSample(timestamp: 9 + i, stack: [0, 1]),
    ],
  );

  test('compares one resolved method across two profiles', () {
    final baselineInspection = inspectProfileMethod(
      query: 'Worker.hotLeaf',
      queryKind: 'methodName',
      methodTable: buildMethodTable(cpuSamples: baselineSamples),
      callTree: buildCallTree(cpuSamples: baselineSamples),
      bottomUpTree: buildBottomUpTree(cpuSamples: baselineSamples),
    );
    final currentInspection = inspectProfileMethod(
      query: 'Worker.hotLeaf',
      queryKind: 'methodName',
      methodTable: buildMethodTable(cpuSamples: currentSamples),
      callTree: buildCallTree(cpuSamples: currentSamples),
      bottomUpTree: buildBottomUpTree(cpuSamples: currentSamples),
    );

    final comparison = compareProfileMethods(
      baseline: baselineInspection,
      current: currentInspection,
    );

    expect(comparison.status, ProfileMethodComparisonStatus.compared);
    expect(comparison.methodDelta?.name, 'Worker.hotLeaf');
    expect(comparison.methodDelta?.selfSamples.delta, 6);
    expect(comparison.methodDelta?.totalSamples.delta, 6);
    expect(comparison.callerDeltas, isNotEmpty);
    expect(
      comparison.callerDeltas.map((delta) => delta.name),
      containsAll(['_Future._completeWithValue', 'Worker.run']),
    );
  });

  test('returns partial when only one side resolves a method', () {
    final inspection = inspectProfileMethod(
      query: 'Worker.hotLeaf',
      queryKind: 'methodName',
      methodTable: buildMethodTable(cpuSamples: baselineSamples),
    );
    final missing = inspectProfileMethod(
      query: 'Missing.method',
      queryKind: 'methodName',
      methodTable: buildMethodTable(cpuSamples: currentSamples),
    );

    final comparison = compareProfileMethods(
      baseline: inspection,
      current: missing,
    );

    expect(comparison.status, ProfileMethodComparisonStatus.partial);
    expect(comparison.methodDelta, isNull);
  });
}
