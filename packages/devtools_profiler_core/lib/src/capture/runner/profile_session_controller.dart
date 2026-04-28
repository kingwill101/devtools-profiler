import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

import '../artifacts.dart';
import '../models.dart';
import 'profile_runner_shared.dart';
import 'profile_session_context.dart';
import 'profile_session_region_rpc.dart';
import 'profile_session_snapshot_capture.dart';
import 'profile_session_vm_hookup.dart';

/// Owns one profiling session from VM attachment through artifact writes.
final class ProfileSessionController {
  ProfileSessionController({
    required ProfileArtifactStore artifactStore,
    required int? childProcessId,
    required DartToolingDaemon? dtd,
    required String sessionId,
  }) : context = ProfileSessionContext(
         artifactStore: artifactStore,
         childProcessId: childProcessId,
         dtd: dtd,
         sessionId: sessionId,
       ) {
    snapshotCapture = ProfileSessionSnapshotCapture(context);
    vmHookup = ProfileSessionVmHookup(
      context: context,
      snapshotCapture: snapshotCapture,
    );
    regionRpc = ProfileSessionRegionRpcHandler(
      context: context,
      snapshotCapture: snapshotCapture,
      vmHookup: vmHookup,
    );
  }

  /// Mutable session state plus shared dependencies.
  final ProfileSessionContext context;

  late final ProfileSessionSnapshotCapture snapshotCapture;
  late final ProfileSessionVmHookup vmHookup;
  late final ProfileSessionRegionRpcHandler regionRpc;

  /// Child process identifier for the profiled target, when known.
  int? get childProcessId => context.childProcessId;
  set childProcessId(int? value) => context.childProcessId = value;

  /// Registers the profiler DTD services for this session.
  Future<void> registerServices() async {
    if (context.dtd == null) return;
    await context.dtd!.registerService(
      profilerControlService,
      getSessionInfoMethod,
      handleGetSessionInfo,
    );
    await context.dtd!.registerService(
      profilerControlService,
      pingMethod,
      handlePing,
    );
    await context.dtd!.registerService(
      profilerControlService,
      startRegionMethod,
      handleStartRegion,
    );
    await context.dtd!.registerService(
      profilerControlService,
      stopRegionMethod,
      handleStopRegion,
    );
  }

  /// Attaches this session to [serviceUri] and starts whole-session capture.
  Future<void> attachToVmService(
    Uri serviceUri, {
    bool clearCpuSamples = false,
    bool monitorExitPause = false,
  }) {
    return vmHookup.attachToVmService(
      serviceUri,
      clearCpuSamples: clearCpuSamples,
      monitorExitPause: monitorExitPause,
    );
  }

  /// Future that completes when a Dart isolate pauses immediately before exit.
  Future<void> get exitPauseReached => vmHookup.exitPauseReached;

  /// Whether a Dart isolate has paused immediately before exit.
  bool get hasExitPauseReached => vmHookup.hasExitPauseReached;

  /// Checks currently visible isolates for an exit pause.
  Future<void> recordCurrentlyPausedExitIsolates() {
    return vmHookup.recordCurrentlyPausedExitIsolates();
  }

  /// Resumes isolates that were held at exit for final profiling capture.
  Future<int> resumePausedExitIsolates() {
    return vmHookup.resumePausedExitIsolates();
  }

  /// Handles the DTD session-info request.
  Future<Map<String, Object?>> handleGetSessionInfo(Parameters params) {
    return regionRpc.handleGetSessionInfo(params);
  }

  /// Handles the DTD ping request.
  Future<Map<String, Object?>> handlePing(Parameters params) {
    return regionRpc.handlePing(params);
  }

  /// Handles the DTD region-start request.
  Future<Map<String, Object?>> handleStartRegion(Parameters params) {
    return regionRpc.handleStartRegion(params);
  }

  /// Handles the DTD region-stop request.
  Future<Map<String, Object?>> handleStopRegion(Parameters params) {
    return regionRpc.handleStopRegion(params);
  }

  /// Finalizes this session when the profiled process exits.
  Future<void> handleProcessExit() {
    return regionRpc.handleProcessExit();
  }

  /// Finalizes this session when attach-mode profiling ends.
  Future<void> finishAttachedWindow() {
    return regionRpc.finishAttachedWindow();
  }

  /// Adds a warning to the final session result.
  void addWarning(String warning) {
    context.warnings.add(warning);
  }

  /// Builds the final stored session result.
  ProfileRunResult buildResult({
    required String artifactDirectory,
    required List<String> command,
    required int exitCode,
    required bool terminatedByProfiler,
    required String workingDirectory,
  }) {
    final sortedRegions = [...context.regions]
      ..sort((left, right) {
        final startCompare = left.startTimestampMicros.compareTo(
          right.startTimestampMicros,
        );
        if (startCompare != 0) {
          return startCompare;
        }
        final endCompare = left.endTimestampMicros.compareTo(
          right.endTimestampMicros,
        );
        if (endCompare != 0) {
          return endCompare;
        }
        return left.regionId.compareTo(right.regionId);
      });
    return ProfileRunResult(
      sessionId: context.sessionId,
      command: command,
      workingDirectory: workingDirectory,
      exitCode: exitCode,
      terminatedByProfiler: terminatedByProfiler,
      artifactDirectory: artifactDirectory,
      vmServiceUri: context.vmServiceUri,
      supportedCaptureKinds: supportedCaptureKinds,
      supportedIsolateScopes: supportedIsolateScopes,
      overallProfile: context.overallProfile,
      regions: List.unmodifiable(sortedRegions),
      warnings: List.unmodifiable(context.warnings),
    );
  }

  /// Disposes resources associated with this profiling session.
  Future<void> dispose() {
    return vmHookup.dispose();
  }
}
