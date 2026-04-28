import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'profile_session_context.dart';
import 'profile_session_snapshot_capture.dart';

/// Handles VM-service attachment and lifecycle concerns for a session.
final class ProfileSessionVmHookup {
  ProfileSessionVmHookup({
    required this.context,
    required this.snapshotCapture,
  });

  final ProfileSessionContext context;
  final ProfileSessionSnapshotCapture snapshotCapture;
  final _pausedExitIsolateIds = <String>{};
  final _exitPauseReached = Completer<void>();

  StreamSubscription<Event>? _debugSubscription;

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
    }
  }

  /// Future that completes once any app isolate pauses at exit.
  Future<void> get exitPauseReached => _exitPauseReached.future;

  /// Whether any app isolate has paused at exit.
  bool get hasExitPauseReached => _exitPauseReached.isCompleted;

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
    if (!_exitPauseReached.isCompleted) {
      _exitPauseReached.complete();
    }
  }

  /// Checks whether any currently visible isolate is already paused at exit.
  Future<void> recordCurrentlyPausedExitIsolates() async {
    final vmService = context.vmService;
    if (vmService == null) {
      return;
    }

    try {
      final vm = await vmService.getVM();
      await Future.wait([
        for (final isolateRef in vm.isolates ?? const <IsolateRef>[])
          if (!(isolateRef.isSystemIsolate ?? false) && isolateRef.id != null)
            () async {
              try {
                final isolate = await vmService.getIsolate(isolateRef.id!);
                if (isolate.pauseEvent?.kind == EventKind.kPauseExit) {
                  _pausedExitIsolateIds.add(isolateRef.id!);
                }
              } catch (_) {
                // The isolate can disappear while the VM is shutting down.
              }
            }(),
      ]);
      if (_pausedExitIsolateIds.isNotEmpty && !_exitPauseReached.isCompleted) {
        _exitPauseReached.complete();
      }
    } catch (_) {
      // The normal process-exit path will handle disconnected services.
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
