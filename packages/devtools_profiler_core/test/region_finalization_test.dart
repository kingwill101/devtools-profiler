import 'dart:async';
import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:devtools_profiler_core/src/capture/runner/capture_state.dart';
import 'package:devtools_profiler_core/src/capture/runner/profile_session_controller.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test(
    'rejects non-object region metadata before waiting for VM readiness',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'region_metadata.',
      );
      addTearDown(() => directory.delete(recursive: true));
      final controller = ProfileSessionController(
        artifactStore: ProfileArtifactStore(directory),
        childProcessId: null,
        dtd: null,
        sessionId: 'session',
      );
      await expectLater(
        controller.handleStartRegion(
          Parameters('startRegion', {
            'extra': ['invalid'],
          }),
        ),
        throwsA(isA<RpcException>()),
      );
      expect(controller.context.activeRegions, isEmpty);
    },
  );

  for (final fail in [false, true]) {
    test(
      'finalization waits for an in-flight region stop (failure=$fail)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'region_finalize.',
        );
        addTearDown(() => directory.delete(recursive: true));
        final service = _DelayedCpuService();
        addTearDown(service.dispose);
        final controller = ProfileSessionController(
          artifactStore: ProfileArtifactStore(directory),
          childProcessId: null,
          dtd: null,
          sessionId: 'session',
        );
        final context = controller.context;
        context.vmService = service;
        context.vmServiceReady.complete();
        context.overallProfileReady.complete();
        context.activeRegions['region'] = const ActiveProfileRegion(
          attributes: {},
          isolateId: 'main',
          memoryStartSnapshot: null,
          name: 'work',
          options: ProfileRegionOptions(captureKinds: [ProfileCaptureKind.cpu]),
          parentRegionId: null,
          regionId: 'region',
          startTimestampMicros: 10,
        );
        final stop = controller.handleStopRegion(
          Parameters('stopRegion', {
            'sessionId': 'session',
            'regionId': 'region',
            'isolateId': 'main',
            'timestampMicros': 20,
          }),
        );
        // Install the error expectation before completing the delayed RPC.
        final stopChecked = fail
            ? expectLater(stop, throwsA(isA<RpcException>()))
            : stop;
        await service.requested.future;
        expect(context.activeRegions, isEmpty);
        var finalized = false;
        final finish = controller.handleProcessExit().then(
          (_) => finalized = true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(finalized, isFalse);
        if (fail) {
          service.samples.completeError(StateError('fixture failure'));
        } else {
          service.samples.complete(
            CpuSamples(
              samplePeriod: 1000,
              functions: [
                ProfileFunction(
                  kind: 'Native',
                  function: NativeFunction(name: 'work'),
                ),
              ],
              samples: [
                CpuSample(tid: 7, timestamp: 15, stack: [0]),
              ],
            ),
          );
        }
        await stopChecked;
        await finish;
        await controller.handleProcessExit();
        expect(context.regions, hasLength(1));
        expect(context.regions.single.succeeded, !fail);
        expect(context.regions.single.sampleCount, fail ? 0 : 1);
        if (!fail) {
          context.latestOverallSnapshot = CpuCaptureSnapshot(
            cpuSamples: CpuSamples(sampleCount: 0, functions: [], samples: []),
            isolateIds: const ['main'],
          );
          await controller.snapshotCapture.captureOverallProfile();
          expect(
            context.overallProfile!.sampleCount,
            1,
            reason: 'Final capture must not use a poll older than the region',
          );
        }
      },
    );
  }
}

class _DelayedCpuService extends VmService {
  _DelayedCpuService() : super(const Stream.empty(), (_) {});

  final requested = Completer<void>();
  final samples = Completer<CpuSamples>();

  @override
  Future<VM> getVM() async => VM(
    isolates: [IsolateRef(id: 'main', name: 'main')],
  );

  @override
  Future<CpuSamples> getCpuSamples(String isolateId, int origin, int extent) {
    if (!requested.isCompleted) requested.complete();
    return samples.future;
  }
}
