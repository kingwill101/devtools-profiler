import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:vm_service/utils.dart';
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

  /// Attaches this session to [serviceUri] and starts whole-session capture.
  Future<void> attachToVmService(
    Uri serviceUri, {
    bool clearCpuSamples = false,
  }) async {
    final wsUri = convertToWebSocketUrl(serviceProtocolUrl: serviceUri);
    context.vmService = await vmServiceConnectUri(wsUri.toString());
    context.vmServiceUri = serviceUri.toString();

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
    await context.vmService?.dispose();
  }
}
