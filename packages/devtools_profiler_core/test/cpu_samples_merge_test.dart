import 'dart:convert';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test(
    'compaction drops only unreferenced functions and preserves frame names',
    () {
      final source = CpuSamples(
        sampleCount: 1,
        samplePeriod: 1000,
        pid: 42,
        maxStackDepth: 128,
        functions: [
          for (final name in ['unused', 'root', 'leaf'])
            ProfileFunction(
              kind: 'Dart',
              function: FuncRef(id: name, name: name),
            ),
        ],
        samples: [
          CpuSample(
            tid: 7,
            timestamp: 10,
            truncated: true,
            stack: [2, 1, 2, 9],
          ),
        ],
      );
      final compact = compactCpuSamples(source);
      expect(compact.functions!.map(displayNameForFunction), ['root', 'leaf']);
      expect(compact.samples!.single.stack, [1, 0, 1, -1]);
      expect(compact.samples!.single.tid, 7);
      expect(compact.samples!.single.truncated, isTrue);
      expect(compact.pid, 42);
      expect(compact.maxStackDepth, 128);
      expect(
        buildCallTree(cpuSamples: compact).toJson(),
        buildCallTree(cpuSamples: source).toJson(),
      );
      expect(source.functions, hasLength(3));
      expect(source.samples!.single.stack, [2, 1, 2, 9]);
    },
  );

  test(
    'artifact round trips preserve native, stub, tag and collected names',
    () {
      final source = CpuSamples(
        functions: [
          for (final (kind, name) in [
            ('Native', 'malloc'),
            ('Stub', '[Stub] Allocate Array'),
            ('Tag', 'VM'),
            ('Collected', '<unknown Dart function>'),
          ])
            ProfileFunction(
              kind: kind,
              function: NativeFunction(name: name),
            ),
          ProfileFunction(kind: 'Dart'),
        ],
        samples: [
          CpuSample(timestamp: 1, stack: [0, 1, 2, 3, 4]),
        ],
      );
      final restored = parseProfileCpuSamples(
        jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>,
      )!;
      expect(restored.functions!.map(displayNameForFunction), [
        'malloc',
        '[Stub] Allocate Array',
        'VM',
        '<unknown Dart function>',
        'unknown',
      ]);
    },
  );

  test('merge preserves metadata and never aliases invalid local indices', () {
    CpuSamples source(int tid, String name, List<int> stack) => CpuSamples(
      pid: 42,
      maxStackDepth: 128,
      samplePeriod: 1000,
      functions: [
        ProfileFunction(
          kind: 'Dart',
          function: FuncRef(id: 'f', name: name),
        ),
      ],
      samples: [
        CpuSample(
          tid: tid,
          timestamp: tid,
          stack: stack,
          vmTag: 'Dart',
          userTag: 'work',
          truncated: true,
          identityHashCode: 123,
          classId: 7,
        ),
      ],
    );
    final left = source(10, 'left', [0, 1, -1]);
    final right = source(20, 'right', [0, -1, 99]);
    final result = mergeCpuSamples(
      [left, right],
      isolateIds: ['main', 'worker'],
    );
    expect(result.pid, 42);
    expect(result.maxStackDepth, 128);
    expect(result.samples![0].stack, [0, -1, -1]);
    expect(result.samples![1].stack, [1, -1, -1]);
    expect(left.samples!.single.stack, [0, 1, -1]);
    final restored = parseProfileCpuSamples(
      jsonDecode(jsonEncode(result.toJson())) as Map<String, dynamic>,
    )!;
    for (var i = 0; i < 2; i++) {
      final sample = restored.samples![i] as ProfileCpuSample;
      expect(sample.isolateId, ['main', 'worker'][i]);
      expect(sample.tid, [10, 20][i]);
      expect(sample.vmTag, 'Dart');
      expect(sample.userTag, 'work');
      expect(sample.truncated, isTrue);
      expect(sample.identityHashCode, 123);
      expect(sample.classId, 7);
    }
    final single = mergeCpuSamples([left], isolateIds: ['main']);
    expect((single.samples!.single as ProfileCpuSample).isolateId, 'main');
    expect(() => mergeCpuSamples([left], isolateIds: []), throwsArgumentError);
    expect(
      () => mergeCpuSamples([left, CpuSamples(pid: 99)]),
      throwsArgumentError,
    );
    expect(
      () => mergeCpuSamples([left, CpuSamples(samplePeriod: 50)]),
      throwsArgumentError,
    );
  });

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
