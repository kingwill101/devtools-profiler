import 'dart:math';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test('shared views preserve per-sample totals, self counts and edges', () {
    final random = Random(42);
    final functions = [
      for (var i = 0; i < 6; i++)
        ProfileFunction(
          kind: 'Dart',
          function: FuncRef(id: 'functions/$i', name: 'method$i'),
        ),
    ];
    final samples = CpuSamples(
      samplePeriod: 50,
      // Deliberately unreliable VM count: filtered nonempty stacks determine it.
      sampleCount: 1000,
      functions: functions,
      samples: [
        for (var i = 0; i < 100; i++)
          CpuSample(
            timestamp: i * 50,
            stack: [
              for (var j = 0, depth = random.nextInt(8); j < depth; j++)
                random.nextInt(8) - 1,
            ],
          ),
      ],
    );

    for (final includeFrame in <ProfileFramePredicate?>[
      null,
      (frame) => frame.name != 'method2',
      (_) => false,
    ]) {
      final tree = buildCallTree(
        cpuSamples: samples,
        includeFrame: includeFrame,
      );
      final before = tree.toJson();
      final table = buildMethodTableFromCallTree(tree);
      final bottomUp = buildBottomUpTreeFromCallTree(tree);
      final totals = <String, int>{};
      final self = <String, int>{};
      final edges = <(String, String), int>{};
      var count = 0;
      for (final sample in samples.samples!) {
        final frames = filterStackFrames(
          sample.stack!,
          functions,
          includeFrame: includeFrame,
        );
        if (frames.isEmpty) continue;
        count++;
        self.update(frames.first.key, (value) => value + 1, ifAbsent: () => 1);
        for (final key in frames.map((frame) => frame.key).toSet()) {
          totals.update(key, (value) => value + 1, ifAbsent: () => 1);
        }
        for (var i = 1; i < frames.length; i++) {
          edges.update(
            (frames[i].key, frames[i - 1].key),
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }
      expect(table.sampleCount, count);
      expect(bottomUp.sampleCount, count);
      expect(table.methods, hasLength(totals.length));
      for (final method in table.methods) {
        expect(method.totalSamples, totals[method.methodId]);
        expect(method.selfSamples, self[method.methodId] ?? 0);
        expect(method.totalMicros, method.totalSamples * 50);
        expect(
          {for (final edge in method.callees) edge.methodId: edge.sampleCount},
          {
            for (final edge in edges.entries)
              if (edge.key.$1 == method.methodId) edge.key.$2: edge.value,
          },
        );
        expect(
          {for (final edge in method.callers) edge.methodId: edge.sampleCount},
          {
            for (final edge in edges.entries)
              if (edge.key.$2 == method.methodId) edge.key.$1: edge.value,
          },
        );
      }
      expect(
        buildMethodTable(
          cpuSamples: samples,
          includeFrame: includeFrame,
        ).toJson(),
        table.toJson(),
      );
      expect(
        buildBottomUpTree(
          cpuSamples: samples,
          includeFrame: includeFrame,
        ).toJson(),
        bottomUp.toJson(),
      );
      expect(
        tree.toJson(),
        before,
        reason: 'Derived views must not mutate input',
      );
    }
  });

  test('derived views handle missing data and reject bottom-up input', () {
    final tree = buildCallTree(cpuSamples: CpuSamples());
    final bottomUp = buildBottomUpTreeFromCallTree(tree);
    expect(bottomUp.root.children, isEmpty);
    expect(buildMethodTableFromCallTree(tree).methods, isEmpty);
    expect(() => buildBottomUpTreeFromCallTree(bottomUp), throwsArgumentError);
    expect(() => buildMethodTableFromCallTree(bottomUp), throwsArgumentError);
  });
}
