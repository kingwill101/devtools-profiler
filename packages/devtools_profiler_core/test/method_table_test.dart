import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test('buildMethodTable computes self totals and caller/callee edges', () {
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
          id: 'functions/parse',
          name: 'parse',
          owner: workerClass,
        ),
        resolvedUrl: 'package:fixture/parse.dart',
      ),
    ];
    final cpuSamples = CpuSamples(
      sampleCount: 4,
      samplePeriod: 50,
      functions: functions,
      samples: [
        CpuSample(timestamp: 110, stack: const [0, 1]),
        CpuSample(timestamp: 160, stack: const [0, 1]),
        CpuSample(timestamp: 220, stack: const [2, 1]),
        CpuSample(timestamp: 280, stack: const [1]),
      ],
    );

    final table = buildMethodTable(cpuSamples: cpuSamples);

    expect(table.sampleCount, 4);
    expect(table.methods.map((method) => method.name), [
      'Worker.run',
      'Worker.hotLeaf',
      'Worker.parse',
    ]);

    final run = table.methods.first;
    expect(run.selfSamples, 1);
    expect(run.totalSamples, 4);
    expect(run.callees.map((callee) => callee.name), [
      'Worker.hotLeaf',
      'Worker.parse',
    ]);
    expect(run.callees.map((callee) => callee.sampleCount), [2, 1]);

    final hotLeaf = table.methods[1];
    expect(hotLeaf.selfSamples, 2);
    expect(hotLeaf.totalSamples, 2);
    expect(hotLeaf.callers.single.name, 'Worker.run');
    expect(hotLeaf.callers.single.sampleCount, 2);
    expect(hotLeaf.callers.single.percent, 1.0);
  });

  test('buildMethodTable avoids double-counting recursive totals', () {
    final workerClass = ClassRef(id: 'classes/worker', name: 'Worker');
    final functions = [
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/recurse',
          name: 'recurse',
          owner: workerClass,
        ),
        resolvedUrl: 'package:fixture/recurse.dart',
      ),
    ];
    final cpuSamples = CpuSamples(
      sampleCount: 1,
      samplePeriod: 50,
      functions: functions,
      samples: [
        CpuSample(timestamp: 100, stack: const [0, 0]),
      ],
    );

    final table = buildMethodTable(cpuSamples: cpuSamples);

    expect(table.methods, hasLength(1));
    final recurse = table.methods.single;
    expect(recurse.selfSamples, 1);
    expect(recurse.totalSamples, 1);
    expect(recurse.callers.single.name, 'Worker.recurse');
    expect(recurse.callees.single.name, 'Worker.recurse');
    expect(recurse.callers.single.sampleCount, 1);
    expect(recurse.callees.single.sampleCount, 1);
  });
}
