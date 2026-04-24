
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:test/test.dart';

void main() {
  test('explainProfileHotspots highlights dominant cpu and memory signals', () {
    final summary = explainProfileHotspots(
      ProfileRegionResult(
        regionId: 'region-1',
        name: 'cpu-burn',
        attributes: const {'phase': 'fixture'},
        isolateId: 'isolates/1',
        isolateIds: const ['isolates/1'],
        captureKinds: const [ProfileCaptureKind.cpu, ProfileCaptureKind.memory],
        isolateScope: ProfileIsolateScope.current,
        startTimestampMicros: 0,
        endTimestampMicros: 1000,
        durationMicros: 1000,
        sampleCount: 10,
        samplePeriodMicros: 50,
        topSelfFrames: const [
          ProfileFrameSummary(
            name: 'Worker.hotLeaf',
            kind: 'Dart',
            location: 'package:fixture/hot_leaf.dart',
            selfSamples: 7,
            totalSamples: 8,
            selfPercent: 0.7,
            totalPercent: 0.8,
          ),
        ],
        topTotalFrames: const [
          ProfileFrameSummary(
            name: 'Worker.run',
            kind: 'Dart',
            location: 'package:fixture/run.dart',
            selfSamples: 2,
            totalSamples: 9,
            selfPercent: 0.2,
            totalPercent: 0.9,
          ),
        ],
        memory: ProfileMemoryResult(
          start: HeapSample(1, 0, 2048, 1024, 0, false, null, null, null),
          end: HeapSample(2, 0, 4096, 4096, 0, false, null, null, null),
          deltaHeapBytes: 3072,
          deltaExternalBytes: 0,
          deltaCapacityBytes: 2048,
          classCount: 1,
          topClasses: const [
            ProfileMemoryClassSummary(
              className: 'Buffer',
              libraryUri: 'package:fixture/buffer.dart',
              allocationBytesDelta: 2048,
              allocationInstancesDelta: 2,
              liveBytes: 2048,
              liveBytesDelta: 2048,
              liveInstances: 2,
              liveInstancesDelta: 2,
            ),
          ],
        ),
        summaryPath: '/tmp/summary.json',
      ),
      callTree: const ProfileCallTree(
        sampleCount: 10,
        samplePeriodMicros: 50,
        root: ProfileCallTreeNode(
          name: 'all',
          kind: 'root',
          selfSamples: 0,
          totalSamples: 10,
          selfPercent: 0.0,
          totalPercent: 1.0,
          selfMicros: 0,
          totalMicros: 500,
          children: [
            ProfileCallTreeNode(
              name: 'Worker.run',
              kind: 'Dart',
              location: 'package:fixture/run.dart',
              selfSamples: 2,
              totalSamples: 9,
              selfPercent: 0.2,
              totalPercent: 0.9,
              selfMicros: 100,
              totalMicros: 450,
              children: [
                ProfileCallTreeNode(
                  name: 'Worker.hotLeaf',
                  kind: 'Dart',
                  location: 'package:fixture/hot_leaf.dart',
                  selfSamples: 7,
                  totalSamples: 8,
                  selfPercent: 0.7,
                  totalPercent: 0.8,
                  selfMicros: 350,
                  totalMicros: 400,
                  children: [],
                ),
              ],
            ),
          ],
        ),
      ),
      bottomUpTree: const ProfileCallTree(
        sampleCount: 10,
        samplePeriodMicros: 50,
        view: ProfileCallTreeView.bottomUp,
        root: ProfileCallTreeNode(
          name: 'all',
          kind: 'root',
          selfSamples: 0,
          totalSamples: 10,
          selfPercent: 0.0,
          totalPercent: 1.0,
          selfMicros: 0,
          totalMicros: 500,
          children: [
            ProfileCallTreeNode(
              name: 'Worker.hotLeaf',
              kind: 'Dart',
              location: 'package:fixture/hot_leaf.dart',
              selfSamples: 7,
              totalSamples: 8,
              selfPercent: 0.7,
              totalPercent: 0.8,
              selfMicros: 350,
              totalMicros: 400,
              children: [
                ProfileCallTreeNode(
                  name: 'Worker.run',
                  kind: 'Dart',
                  location: 'package:fixture/run.dart',
                  selfSamples: 2,
                  totalSamples: 8,
                  selfPercent: 0.2,
                  totalPercent: 0.8,
                  selfMicros: 100,
                  totalMicros: 400,
                  children: [],
                ),
              ],
            ),
          ],
        ),
      ),
      methodTable: ProfileMethodTable(
        sampleCount: 10,
        samplePeriodMicros: 50,
        methods: [
          ProfileMethodSummary(
            methodId: 'method/run',
            name: 'Worker.run',
            kind: 'Dart',
            location: 'package:fixture/run.dart',
            selfSamples: 2,
            totalSamples: 9,
            selfPercent: 0.2,
            totalPercent: 0.9,
            selfMicros: 100,
            totalMicros: 450,
            callers: const [],
            callees: const [
              ProfileMethodRelation(
                methodId: 'method/hotLeaf',
                name: 'Worker.hotLeaf',
                kind: 'Dart',
                location: 'package:fixture/hot_leaf.dart',
                sampleCount: 7,
                percent: 0.7,
              ),
            ],
          ),
          ProfileMethodSummary(
            methodId: 'method/hotLeaf',
            name: 'Worker.hotLeaf',
            kind: 'Dart',
            location: 'package:fixture/hot_leaf.dart',
            selfSamples: 7,
            totalSamples: 8,
            selfPercent: 0.7,
            totalPercent: 0.8,
            selfMicros: 350,
            totalMicros: 400,
            callers: const [
              ProfileMethodRelation(
                methodId: 'method/run',
                name: 'Worker.run',
                kind: 'Dart',
                location: 'package:fixture/run.dart',
                sampleCount: 7,
                percent: 1.0,
              ),
            ],
            callees: const [],
          ),
        ],
      ),
    );

    expect(summary.status, 'analyzed');
    expect(summary.insights, isNotEmpty);
    final selfInsight = summary.insights.firstWhere(
      (insight) => insight.kind == 'selfFrame',
    );
    expect(selfInsight.path, isNotNull);
    expect(
      selfInsight.path!.frames.map((frame) => frame.name),
      ['all', 'Worker.run', 'Worker.hotLeaf'],
    );
    expect(selfInsight.bottomUpPath, isNotNull);
    expect(
      selfInsight.bottomUpPath!.frames.map((frame) => frame.name),
      ['all', 'Worker.hotLeaf'],
    );
    expect(selfInsight.focusMethod, isNotNull);
    expect(selfInsight.focusMethod!.methodId, 'method/hotLeaf');
    expect(
      selfInsight.focusMethod!.callers.map((caller) => caller.name),
      ['Worker.run'],
    );
    expect(
      summary.insights.any((insight) => insight.kind == 'memory'),
      isTrue,
    );
    expect(
      summary.insights.any((insight) => insight.kind == 'callee'),
      isTrue,
    );
  });

  test('explainProfileHotspots warns when method table is unavailable', () {
    final summary = explainProfileHotspots(
      ProfileRegionResult(
        regionId: 'region-1',
        name: 'cpu-burn',
        attributes: const {},
        isolateId: 'isolates/1',
        isolateIds: const ['isolates/1'],
        captureKinds: const [ProfileCaptureKind.cpu],
        isolateScope: ProfileIsolateScope.current,
        startTimestampMicros: 0,
        endTimestampMicros: 1000,
        durationMicros: 1000,
        sampleCount: 4,
        samplePeriodMicros: 50,
        topSelfFrames: const [
          ProfileFrameSummary(
            name: 'JsonRpcClient.send',
            kind: 'Dart',
            location: 'package:json_rpc_2/json_rpc_2.dart',
            selfSamples: 1,
            totalSamples: 1,
            selfPercent: 0.25,
            totalPercent: 0.25,
          ),
        ],
        topTotalFrames: const [],
        summaryPath: '/tmp/summary.json',
      ),
    );

    expect(summary.warnings, isNotEmpty);
    expect(
      summary.insights.any((insight) => insight.kind == 'runtimeNoise'),
      isTrue,
    );
  });
}
