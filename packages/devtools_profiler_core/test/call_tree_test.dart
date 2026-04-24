import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test('buildCallTree mirrors DevTools top-down stack semantics', () {
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
      sampleCount: 3,
      samplePeriod: 50,
      timeOriginMicros: 100,
      timeExtentMicros: 300,
      functions: functions,
      samples: [
        CpuSample(timestamp: 110, stack: const [0, 1]),
        CpuSample(timestamp: 160, stack: const [0, 1]),
        CpuSample(timestamp: 220, stack: const [2, 1]),
      ],
    );

    final tree = buildCallTree(cpuSamples: cpuSamples);

    expect(tree.sampleCount, 3);
    expect(tree.samplePeriodMicros, 50);
    expect(tree.root.name, 'all');
    expect(tree.root.totalSamples, 3);
    expect(tree.root.children, hasLength(1));

    final runNode = tree.root.children.single;
    expect(runNode.name, 'Worker.run');
    expect(runNode.selfSamples, 0);
    expect(runNode.totalSamples, 3);
    expect(runNode.children.map((child) => child.name), [
      'Worker.hotLeaf',
      'Worker.parse',
    ]);

    final hotLeafNode = runNode.children.first;
    expect(hotLeafNode.selfSamples, 2);
    expect(hotLeafNode.totalSamples, 2);
    expect(hotLeafNode.selfPercent, closeTo(2 / 3, 0.0001));
    expect(hotLeafNode.totalMicros, 100);
  });

  test('buildCallTree collapses sdk frames when they are filtered', () {
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
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/complete',
          name: '_completeWithValue',
          owner: ClassRef(id: 'classes/future', name: '_Future'),
        ),
        resolvedUrl: 'org-dartlang-sdk:///sdk/lib/async/future_impl.dart',
      ),
    ];
    final cpuSamples = CpuSamples(
      sampleCount: 1,
      samplePeriod: 50,
      functions: functions,
      samples: [
        CpuSample(timestamp: 100, stack: const [0, 2, 1]),
      ],
    );

    final tree = buildCallTree(
      cpuSamples: cpuSamples,
      includeFrame: (frame) => !frame.isSdk,
    );

    expect(tree.sampleCount, 1);
    expect(tree.root.children.single.name, 'Worker.run');
    expect(tree.root.children.single.children.single.name, 'Worker.hotLeaf');
  });

  test('buildBottomUpTree mirrors DevTools bottom-up semantics', () {
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
      timeOriginMicros: 100,
      timeExtentMicros: 400,
      functions: functions,
      samples: [
        CpuSample(timestamp: 110, stack: const [0, 1]),
        CpuSample(timestamp: 160, stack: const [0, 1]),
        CpuSample(timestamp: 220, stack: const [2, 1]),
        CpuSample(timestamp: 280, stack: const [1]),
      ],
    );

    final tree = buildBottomUpTree(cpuSamples: cpuSamples);

    expect(tree.view, ProfileCallTreeView.bottomUp);
    expect(tree.sampleCount, 4);
    expect(tree.root.name, 'all');
    expect(tree.root.children.map((child) => child.name), [
      'Worker.run',
      'Worker.hotLeaf',
      'Worker.parse',
    ]);

    final runRoot = tree.root.children.first;
    expect(runRoot.selfSamples, 1);
    expect(runRoot.totalSamples, 4);
    expect(runRoot.children, isEmpty);

    final hotLeafRoot = tree.root.children[1];
    expect(hotLeafRoot.selfSamples, 2);
    expect(hotLeafRoot.totalSamples, 2);
    expect(hotLeafRoot.children.single.name, 'Worker.run');
    expect(hotLeafRoot.children.single.selfSamples, 2);
    expect(hotLeafRoot.children.single.totalSamples, 2);

    final parseRoot = tree.root.children[2];
    expect(parseRoot.selfSamples, 1);
    expect(parseRoot.totalSamples, 1);
    expect(parseRoot.children.single.name, 'Worker.run');
  });
}
