import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';

import '../cpu/call_tree.dart';
import 'artifacts.dart';
import 'models.dart';
import 'runner/dtd_process_session.dart';
import 'runner/process_launch.dart';
import 'runner/profile_runner_shared.dart';
import 'runner/profile_session_controller.dart';

/// Launches profiled Dart processes and reads stored artifacts.
///
/// [ProfileRunner] is the main orchestration API for this package. It can:
///
/// - launch a Dart or Flutter process with profiler session wiring
/// - attach to an existing VM service for a fixed profiling window
/// - write reusable session artifacts
/// - reload stored artifacts and higher-level CPU summaries later
///
/// The class is intentionally state-light for callers. Each [run] or [attach]
/// invocation owns one temporary profiling session and returns a
/// [ProfileRunResult] describing what was captured.
class ProfileRunner {
  /// Profiles the launched [request] and returns the captured session result.
  ///
  /// This method starts the target process, waits for a VM service URI, enables
  /// profiling, captures whole-session data, listens for explicit region
  /// markers, and writes artifacts before returning the final
  /// [ProfileRunResult].
  ///
  /// The command in [request] must start with `dart` or `flutter`. Unsupported
  /// launch shapes such as Flutter release mode, browser targets, or AOT-style
  /// runs are rejected before the process starts.
  Future<ProfileRunResult> run(ProfileRunRequest request) async {
    validateProfileCommand(request.command);

    final sessionId = generateProfileSessionId();
    final workingDirectory = path.normalize(
      request.workingDirectory ?? Directory.current.path,
    );
    final artifactDirectory = Directory(
      request.artifactDirectory ??
          path.join(
            workingDirectory,
            '.dart_tool',
            'devtools_profiler',
            'sessions',
            sessionId,
          ),
    );
    final artifactStore = ProfileArtifactStore(artifactDirectory);
    await artifactStore.create();

    final dtdSession = await DtdProcessSession.start();
    final sessionController = ProfileSessionController(
      artifactStore: artifactStore,
      childProcessId: null,
      dtd: dtdSession.daemon,
      sessionId: sessionId,
    );

    StreamSubscription<String>? stdoutSubscription;
    StreamSubscription<String>? stderrSubscription;
    Process? process;
    Timer? runDurationTimer;
    var processExited = false;
    var terminatedByProfiler = false;

    try {
      await sessionController.registerServices();

      final launchedProcess = await launchProfiledProcess(
        request: request,
        sessionId: sessionId,
        dtdUri: dtdSession.info.localUri.toString(),
        workingDirectory: workingDirectory,
      );
      process = launchedProcess.process;
      sessionController.childProcessId = process.pid;
      stdoutSubscription = launchedProcess.stdoutSubscription;
      stderrSubscription = launchedProcess.stderrSubscription;

      final vmServiceTimeout = request.vmServiceTimeout ??
          defaultVmServiceTimeoutForCommand(request.command);
      final serviceUri = await launchedProcess.serviceUri.future.timeout(
        vmServiceTimeout,
        onTimeout: () {
          throw StateError(
            'Timed out after ${formatProfileDuration(vmServiceTimeout)} waiting for the Dart VM service URI from the profiled process. '
            'If the target is still building or starting, increase --vm-service-timeout.',
          );
        },
      );
      await sessionController.attachToVmService(serviceUri);

      final runDuration = request.runDuration;
      if (runDuration != null) {
        runDurationTimer = Timer(runDuration, () {
          terminatedByProfiler = true;
          sessionController.addWarning(
            'Profile run duration of ${runDuration.inMilliseconds}ms elapsed; terminating the target process.',
          );
          if (process != null && !process.kill()) {
            sessionController.addWarning(
              'Failed to terminate the target process after the profile run duration elapsed.',
            );
          }
        });
      }

      final exitCode = await process.exitCode;
      processExited = true;
      runDurationTimer?.cancel();
      await sessionController.handleProcessExit();

      final result = sessionController.buildResult(
        artifactDirectory: artifactDirectory.path,
        command: request.command,
        exitCode: exitCode,
        terminatedByProfiler: terminatedByProfiler,
        workingDirectory: workingDirectory,
      );
      await artifactStore.writeSession(result);
      return result;
    } finally {
      await stdoutSubscription?.cancel();
      await stderrSubscription?.cancel();
      runDurationTimer?.cancel();
      if (process != null && !processExited) {
        process.kill();
        await process.exitCode;
      }
      await sessionController.dispose();
      await dtdSession.dispose();
    }
  }

  /// Profiles an already-running Dart or Flutter VM service for a fixed window.
  ///
  /// The target process is not launched or terminated by this method. Region
  /// markers are only available when the target process was already configured
  /// to talk to this profiler session, so attach mode primarily captures the
  /// whole-session VM service profile.
  Future<ProfileRunResult> attach(ProfileAttachRequest request) async {
    if (request.duration <= Duration.zero) {
      throw ArgumentError('The attach profiling duration must be positive.');
    }

    final sessionId = generateProfileSessionId();
    final workingDirectory = path.normalize(
      request.workingDirectory ?? Directory.current.path,
    );
    final artifactDirectory = Directory(
      request.artifactDirectory ??
          path.join(
            workingDirectory,
            '.dart_tool',
            'devtools_profiler',
            'sessions',
            sessionId,
          ),
    );
    final artifactStore = ProfileArtifactStore(artifactDirectory);
    await artifactStore.create();

    final dtdSession = await DtdProcessSession.start();
    final sessionController = ProfileSessionController(
      artifactStore: artifactStore,
      childProcessId: null,
      dtd: dtdSession.daemon,
      sessionId: sessionId,
    );

    try {
      await sessionController.registerServices();
      sessionController.addWarning(
        'Attached to an existing VM service. Explicit region markers are only available if the target process was started with this profiler session configuration.',
      );
      await sessionController.attachToVmService(
        request.vmServiceUri,
        clearCpuSamples: true,
      );
      await Future<void>.delayed(request.duration);
      await sessionController.finishAttachedWindow();

      final result = sessionController.buildResult(
        artifactDirectory: artifactDirectory.path,
        command: ['attach', request.vmServiceUri.toString()],
        exitCode: 0,
        terminatedByProfiler: false,
        workingDirectory: workingDirectory,
      );
      await artifactStore.writeSession(result);
      return result;
    } finally {
      await sessionController.dispose();
      await dtdSession.dispose();
    }
  }

  /// Reads an artifact from disk for direct consumption.
  ///
  /// Directory targets resolve to the stored `session.json` shape. File targets
  /// return the raw text and, when possible, the parsed JSON payload.
  Future<Map<String, Object?>> readArtifact(String targetPath) {
    return ProfileArtifacts.readArtifact(targetPath);
  }

  /// Summarizes an artifact directory or a raw CPU profile artifact.
  ///
  /// This is useful when the caller wants a structured summary without having
  /// to inspect whether [targetPath] points at a session directory, a stored
  /// region summary, or a raw CPU profile file.
  Future<Map<String, Object?>> summarizeArtifact(String targetPath) {
    return ProfileArtifacts.summarizeArtifact(targetPath);
  }

  /// Reads raw CPU samples for a region summary or raw CPU profile.
  ///
  /// Region summary files are resolved through their linked raw CPU artifact.
  Future<CpuSamples> readCpuSamples(String targetPath) {
    return ProfileArtifacts.readCpuSamples(targetPath);
  }

  /// Reads a top-down call tree for a region summary or raw CPU profile.
  ///
  /// Use [buildBottomUpTree] directly when a bottom-up view is required.
  Future<ProfileCallTree> readCallTree(String targetPath) {
    return ProfileArtifacts.readCallTree(targetPath);
  }
}
