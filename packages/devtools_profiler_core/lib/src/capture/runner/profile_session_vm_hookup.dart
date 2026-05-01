import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'profile_session_context.dart';
import 'profile_session_snapshot_capture.dart';

const _vmServiceExitPauseRequestTimeout = Duration(seconds: 2);

/// Handles VM-service attachment and lifecycle concerns for a session.
final class ProfileSessionVmHookup {
  ProfileSessionVmHookup({
    required this.context,
    required this.snapshotCapture,
  });

  final ProfileSessionContext context;
  final ProfileSessionSnapshotCapture snapshotCapture;
  final _pausedExitIsolateIds = <String>{};
  final _exitPauseSignal = Completer<bool>();

  StreamSubscription<Event>? _debugSubscription;
  bool _haveAllAppIsolatesPausedAtExit = false;

  /// Attaches this session to [serviceUri] and starts whole-session capture.
  Future<void> attachToVmService(
    Uri serviceUri, {
    bool clearCpuSamples = false,
    bool monitorExitPause = false,
  }) async {
    final wsUri = convertToWebSocketUrl(serviceProtocolUrl: serviceUri);
    context.vmService = await vmServiceConnectUri(wsUri.toString());
    context.vmServiceUri = serviceUri.toString();

    if (monitorExitPause) {
      await startExitPauseMonitor();
    }

    try {
      await context.vmService!.setFlag('profiler', 'true');
    } catch (error) {
      context.warnings.add('Failed to enable the CPU profiler: $error');
    }

    if (clearCpuSamples) {
      await snapshotCapture.clearCpuSamplesForAllAppIsolates();
    }
    snapshotCapture.startOverallProfilePolling();
    await snapshotCapture.initializeOverallMemoryCapture();

    if (!context.vmServiceReady.isCompleted) {
      context.vmServiceReady.complete();
    }
  }

  /// Starts tracking Dart isolates that pause immediately before exit.
  Future<void> startExitPauseMonitor() async {
    final vmService = context.vmService;
    if (vmService == null || _debugSubscription != null) {
      return;
    }

    _debugSubscription = vmService.onDebugEvent.listen(handleDebugEvent);
    try {
      await vmService.streamListen(EventStreams.kDebug);
      await recordCurrentlyPausedExitIsolates();
    } catch (error) {
      await _debugSubscription?.cancel();
      _debugSubscription = null;
      context.warnings.add(
        'Failed to monitor Dart isolate exit pauses: $error',
      );
      completeExitPauseSignal(allPaused: false);
    }
  }

  /// A signal that exit-pause monitoring reached a terminal state.
  ///
  /// The future completes with `true` when every visible app isolate is paused
  /// at exit. It completes with `false` when monitoring cannot make progress,
  /// such as when the debug stream or VM isolate list is unavailable.
  Future<bool> get exitPauseSignal => _exitPauseSignal.future;

  /// Whether every visible app isolate has paused at exit.
  bool get haveAllAppIsolatesPausedAtExit => _haveAllAppIsolatesPausedAtExit;

  /// Records a debug stream event relevant to Dart launch finalization.
  void handleDebugEvent(Event event) {
    if (event.kind != EventKind.kPauseExit) {
      return;
    }
    final isolateId = event.isolate?.id;
    if (isolateId == null) {
      return;
    }
    _pausedExitIsolateIds.add(isolateId);
    unawaited(recordCurrentlyPausedExitIsolates());
  }

  /// Checks whether every currently visible app isolate is paused at exit.
  Future<void> recordCurrentlyPausedExitIsolates() async {
    final vmService = context.vmService;
    if (vmService == null) {
      return;
    }

    try {
      final vm = await vmService.getVM().timeout(
        _vmServiceExitPauseRequestTimeout,
      );
      final liveAppIsolateIds = <String>{};
      final pausedExitIsolateIds = <String>{};
      await Future.wait([
        for (final isolateRef in vm.isolates ?? const <IsolateRef>[])
          if (!(isolateRef.isSystemIsolate ?? false) && isolateRef.id != null)
            () async {
              liveAppIsolateIds.add(isolateRef.id!);
              try {
                final isolate = await vmService
                    .getIsolate(isolateRef.id!)
                    .timeout(_vmServiceExitPauseRequestTimeout);
                if (isolate.pauseEvent?.kind == EventKind.kPauseExit) {
                  pausedExitIsolateIds.add(isolateRef.id!);
                }
              } on TimeoutException {
                completeExitPauseSignal(allPaused: false);
              } catch (_) {
                // The isolate can disappear while the VM is shutting down.
                liveAppIsolateIds.remove(isolateRef.id!);
              }
            }(),
      ]);
      _pausedExitIsolateIds
        ..clear()
        ..addAll(pausedExitIsolateIds);
      if (liveAppIsolateIds.isEmpty) {
        completeExitPauseSignal(allPaused: false);
        return;
      }
      if (liveAppIsolateIds.length == pausedExitIsolateIds.length) {
        completeExitPauseSignal(allPaused: true);
      }
    } catch (_) {
      completeExitPauseSignal(allPaused: false);
    }
  }

  /// Records an exit-pause coordination result without losing later polls.
  void completeExitPauseSignal({required bool allPaused}) {
    _haveAllAppIsolatesPausedAtExit |= allPaused;
    if (!_exitPauseSignal.isCompleted) {
      _exitPauseSignal.complete(allPaused);
    }
  }

  /// Resumes isolates paused at exit so the target process can terminate.
  Future<int> resumePausedExitIsolates() async {
    await recordCurrentlyPausedExitIsolates();
    final vmService = context.vmService;
    if (vmService == null || _pausedExitIsolateIds.isEmpty) {
      return 0;
    }

    final isolateIds = _pausedExitIsolateIds.toList(growable: false);
    _pausedExitIsolateIds.clear();
    var resumedCount = 0;
    for (final isolateId in isolateIds) {
      try {
        await vmService.resume(isolateId);
        resumedCount++;
      } catch (error) {
        context.warnings.add(
          'Failed to resume exit-paused isolate "$isolateId": $error',
        );
      }
    }
    return resumedCount;
  }

  /// Waits until this session is attached to a VM service.
  Future<void> waitForVmService() {
    return context.vmServiceReady.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw RpcException.invalidParams(
          'The profiling backend has not attached to the VM service yet.',
        );
      },
    );
  }

  /// Validates that the incoming session identifier matches this session.
  void validateSession(String? providedSessionId) {
    if (providedSessionId != null && providedSessionId != context.sessionId) {
      throw RpcException.invalidParams(
        'Session mismatch. Expected "${context.sessionId}" '
        'but received "$providedSessionId".',
      );
    }
  }

  /// Disposes VM resources associated with this session.
  Future<void> dispose() async {
    context.overallProfilePoller?.cancel();
    await _debugSubscription?.cancel();
    await context.vmService?.dispose();
  }
}
