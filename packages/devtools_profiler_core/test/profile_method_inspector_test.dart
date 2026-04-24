import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  final workerClass = ClassRef(id: 'classes/worker', name: 'Worker');
  final cpuSamples = CpuSamples(
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
        function: FuncRef(
          id: 'functions/run',
          name: 'run',
          owner: workerClass,
        ),
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

  test('inspects a method with representative top-down and bottom-up paths',
      () {
    final methodTable = buildMethodTable(cpuSamples: cpuSamples);
    final callTree = buildCallTree(cpuSamples: cpuSamples);
    final bottomUpTree = buildBottomUpTree(cpuSamples: cpuSamples);

    final inspection = inspectProfileMethod(
      query: 'Worker.hotLeaf',
      queryKind: 'methodName',
      methodTable: methodTable,
      callTree: callTree,
      bottomUpTree: bottomUpTree,
    );

    expect(inspection.status, ProfileMethodInspectionStatus.found);
    expect(inspection.method?.name, 'Worker.hotLeaf');
    expect(
      inspection.topDownPaths.single.frames.map((frame) => frame.name),
      ['all', 'Worker.run', '_Future._completeWithValue', 'Worker.hotLeaf'],
    );
    expect(
      inspection.bottomUpPaths.single.frames.map((frame) => frame.name),
      ['all', 'Worker.hotLeaf'],
    );
  });

  test('returns ambiguous candidates for duplicate method names', () {
    final methodTable = ProfileMethodTable(
      sampleCount: 10,
      samplePeriodMicros: 50,
      methods: [
        ProfileMethodSummary(
          methodId: 'dup|Dart|package:one/a.dart',
          name: 'dup',
          kind: 'Dart',
          location: 'package:one/a.dart',
          selfSamples: 3,
          totalSamples: 4,
          selfPercent: 0.3,
          totalPercent: 0.4,
          selfMicros: 150,
          totalMicros: 200,
          callers: const [],
          callees: const [],
        ),
        ProfileMethodSummary(
          methodId: 'dup|Dart|package:two/b.dart',
          name: 'dup',
          kind: 'Dart',
          location: 'package:two/b.dart',
          selfSamples: 2,
          totalSamples: 3,
          selfPercent: 0.2,
          totalPercent: 0.3,
          selfMicros: 100,
          totalMicros: 150,
          callers: const [],
          callees: const [],
        ),
      ],
    );

    final inspection = inspectProfileMethod(
      query: 'dup',
      queryKind: 'methodName',
      methodTable: methodTable,
    );

    expect(inspection.status, ProfileMethodInspectionStatus.ambiguous);
    expect(inspection.method, isNull);
    expect(inspection.candidates, hasLength(2));
    expect(inspection.candidates.map((candidate) => candidate.location), [
      'package:one/a.dart',
      'package:two/b.dart',
    ]);
  });
}
