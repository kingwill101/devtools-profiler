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

  test('searches methods by query ordered by total samples', () {
    final result = searchProfileMethods(
      methodTable: buildMethodTable(cpuSamples: cpuSamples),
      query: 'worker',
      sortBy: ProfileMethodSearchSort.total,
    );

    expect(result.status, ProfileMethodSearchStatus.available);
    expect(result.totalMatches, 2);
    expect(result.methods.map((method) => method.name), [
      'Worker.run',
      'Worker.hotLeaf',
    ]);
  });

  test('supports self-ordered searches with truncation', () {
    final result = searchProfileMethods(
      methodTable: buildMethodTable(cpuSamples: cpuSamples),
      sortBy: ProfileMethodSearchSort.self,
      limit: 1,
    );

    expect(result.totalMatches, 3);
    expect(result.truncated, isTrue);
    expect(result.methods.single.name, 'Worker.hotLeaf');
  });

  test('returns unavailable without a method table', () {
    final result = searchProfileMethods(methodTable: null, query: 'run');

    expect(result.status, ProfileMethodSearchStatus.unavailable);
    expect(result.methods, isEmpty);
  });
}
