import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';

import '../cpu/call_tree.dart';
import '../memory/memory_models.dart';
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
  /// The command in [request] must start with `dart`, `flutter`, or a Dart
  /// file path. Unsupported launch shapes such as Flutter release mode, browser
  /// targets, or AOT-style runs are rejected before the process starts.
  Future<ProfileRunResult> run(ProfileRunRequest request) async {
    final command = normalizeProfileCommand(request.command);
    validateProfileCommand(command);
    final commandKind = profileCommandKind(command);

    final sessionId = generateProfileSessionId();
    final workingDirectory = _resolveWorkingDirectory(request.workingDirectory);
    final artifactDirectory = Directory(
      _resolveArtifactDirectory(
        requestedDirectory: request.artifactDirectory,
        sessionId: sessionId,
        workingDirectory: workingDirectory,
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
        command: command,
        sessionId: sessionId,
        dtdUri: dtdSession.info.localUri.toString(),
        workingDirectory: workingDirectory,
      );
      process = launchedProcess.process;
      sessionController.childProcessId = process.pid;
      stdoutSubscription = launchedProcess.stdoutSubscription;
      stderrSubscription = launchedProcess.stderrSubscription;

      final vmServiceTimeout =
          request.vmServiceTimeout ??
          defaultVmServiceTimeoutForCommand(command);
      final serviceUri = await launchedProcess.serviceUri.future.timeout(
        vmServiceTimeout,
        onTimeout: () {
          throw StateError(
            'Timed out after ${formatProfileDuration(vmServiceTimeout)} waiting for the Dart VM service URI from the profiled process. '
            'If the target is still building or starting, increase --vm-service-timeout.',
          );
        },
      );
      await sessionController.attachToVmService(
        serviceUri,
        monitorExitPause: commandKind == ProfileCommandKind.dart,
      );

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

      final exitCodeFuture = process.exitCode;
      final completion = commandKind == ProfileCommandKind.dart
          ? await _waitForDartProcessCompletion(
              exitCodeFuture,
              sessionController,
            )
          : (
              kind: _ProfiledProcessCompletionKind.exited,
              exitCode: await exitCodeFuture,
            );
      runDurationTimer?.cancel();
      int exitCode;
      if (completion.kind == _ProfiledProcessCompletionKind.pausedAtExit) {
        await sessionController.handleProcessExit();
        final resumedProcess = await _resumeExitPausedProcess(
          exitCodeFuture: exitCodeFuture,
          process: process,
          sessionController: sessionController,
        );
        exitCode = resumedProcess.exitCode;
        processExited = resumedProcess.processExited;
      } else {
        exitCode = completion.exitCode!;
        processExited = true;
        await sessionController.handleProcessExit();
      }

      final result = sessionController.buildResult(
        artifactDirectory: artifactDirectory.path,
        command: command,
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
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          sessionController.addWarning(
            'Timed out waiting for target process cleanup after profiling.',
          );
        }
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
    final workingDirectory = _resolveWorkingDirectory(request.workingDirectory);
    final artifactDirectory = Directory(
      _resolveArtifactDirectory(
        requestedDirectory: request.artifactDirectory,
        sessionId: sessionId,
        workingDirectory: workingDirectory,
      ),
    );
    final artifactStore = ProfileArtifactStore(artifactDirectory);
    await artifactStore.create();

    final DtdProcessSession? dtdSession = request.enableDtd
        ? await DtdProcessSession.start()
        : null;
    final sessionController = ProfileSessionController(
      artifactStore: artifactStore,
      childProcessId: null,
      dtd: dtdSession?.daemon,
      sessionId: sessionId,
    );

    try {
      await sessionController.registerServices();
      sessionController.addWarning(
        'Attach mode captured an existing VM-service process. Explicit region markers are unavailable unless the target was launched by devtools-profiler run.',
      );
      if (!request.enableDtd) {
        sessionController.addWarning(
          'The Dart Tooling Daemon was disabled for this attach session. Explicit region markers are unavailable.',
        );
      }
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
      await dtdSession?.dispose();
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

  /// Reads and filters memory class data from a stored profiling artifact.
  ///
  /// [targetPath] may be a session directory, a region `summary.json` file,
  /// or a raw `memory_profile.json` file.
  ///
  /// When [classQuery] is provided, only classes whose name contains the query
  /// (case-insensitive) are included. When [minLiveBytes] is provided, only
  /// classes with at least that many live bytes at the end of the window are
  /// included.
  ///
  /// Pass [topClassCount] as 0 for unlimited results.
  Future<ProfileMemoryResult> readMemoryClasses(
    String targetPath, {
    String? classQuery,
    int? minLiveBytes,
    int topClassCount = 50,
  }) {
    return ProfileArtifacts.readMemoryClasses(
      targetPath,
      classQuery: classQuery,
      minLiveBytes: minLiveBytes,
      topClassCount: topClassCount,
    );
  }
}

enum _ProfiledProcessCompletionKind {
  exited,
  exitPauseUnavailable,
  pausedAtExit,
}

/// Waits for a Dart process to exit or pause every app isolate at exit.
///
/// Dart launches use `--pause-isolates-on-exit` so a short script can be
/// captured before the VM service disappears. This helper races the process
/// [exitCodeFuture] with [ProfileSessionController.exitPauseSignal]. It also
/// polls [ProfileSessionController.recordCurrentlyPausedExitIsolates] because
/// debug stream events can be missed during shutdown. A returned
/// [_ProfiledProcessCompletionKind.exited] means the process produced an exit
/// code normally; [_ProfiledProcessCompletionKind.pausedAtExit] means
/// [ProfileSessionController.haveAllAppIsolatesPausedAtExit] is true and the
/// caller should capture final artifacts before resuming isolates.
Future<({int? exitCode, _ProfiledProcessCompletionKind kind})>
_waitForDartProcessCompletion(
  Future<int> exitCodeFuture,
  ProfileSessionController sessionController,
) async {
  final exitCompletion = exitCodeFuture.then(
    (exitCode) =>
        (kind: _ProfiledProcessCompletionKind.exited, exitCode: exitCode),
  );
  final exitPause = sessionController.exitPauseSignal.then(
    (allPaused) => (
      kind: allPaused
          ? _ProfiledProcessCompletionKind.pausedAtExit
          : _ProfiledProcessCompletionKind.exitPauseUnavailable,
      exitCode: null,
    ),
  );
  var listenForExitPauseSignal = true;

  while (true) {
    final completion =
        await Future.any<
          ({int? exitCode, _ProfiledProcessCompletionKind? kind})
        >([
          exitCompletion,
          if (listenForExitPauseSignal) exitPause,
          Future.delayed(
            const Duration(milliseconds: 50),
            () => (kind: null, exitCode: null),
          ),
        ]);

    final kind = completion.kind;
    if (kind != null) {
      if (kind == _ProfiledProcessCompletionKind.exitPauseUnavailable) {
        listenForExitPauseSignal = false;
        continue;
      }
      return (kind: kind, exitCode: completion.exitCode);
    }

    await sessionController.recordCurrentlyPausedExitIsolates();
    if (sessionController.haveAllAppIsolatesPausedAtExit) {
      return (
        kind: _ProfiledProcessCompletionKind.pausedAtExit,
        exitCode: null,
      );
    }
  }
}

/// Resumes exit-paused Dart isolates and waits for process termination.
///
/// The VM can report additional isolates paused at exit after an earlier resume
/// call, so this retries [ProfileSessionController.resumePausedExitIsolates]
/// up to five times. Each attempt gives [exitCodeFuture] two seconds to
/// complete. If the target still does not exit, this records a warning with
/// [ProfileSessionController.addWarning], tries to kill the process, waits with
/// a bounded timeout, and finally returns a forced non-zero exit code instead
/// of awaiting an unbounded process future. The result marks whether the exit
/// code came from an observed process exit or from that synthetic fallback.
Future<({int exitCode, bool processExited})> _resumeExitPausedProcess({
  required Future<int> exitCodeFuture,
  required Process process,
  required ProfileSessionController sessionController,
}) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await sessionController.resumePausedExitIsolates();
    try {
      final exitCode = await exitCodeFuture.timeout(const Duration(seconds: 2));
      return (exitCode: exitCode, processExited: true);
    } on TimeoutException {
      // Another isolate may have reached its exit pause after the previous
      // resume call. Loop and resume any newly observed exit pauses.
    }
  }

  sessionController.addWarning(
    'The target process remained paused after final profile capture; '
    'terminating it.',
  );
  if (!process.kill()) {
    sessionController.addWarning(
      'Failed to terminate the target process after exit-paused capture.',
    );
  }
  try {
    final exitCode = await exitCodeFuture.timeout(const Duration(seconds: 2));
    return (exitCode: exitCode, processExited: true);
  } on TimeoutException {
    sessionController.addWarning(
      'Timed out waiting for the target process to exit after termination; '
      'returning a forced non-zero exit code.',
    );
    return (exitCode: 1, processExited: false);
  }
}

String _resolveWorkingDirectory(String? workingDirectory) {
  return path.normalize(
    path.absolute(workingDirectory ?? Directory.current.path),
  );
}

String _resolveArtifactDirectory({
  required String? requestedDirectory,
  required String sessionId,
  required String workingDirectory,
}) {
  return switch (requestedDirectory) {
    final String dir when path.isAbsolute(dir) => path.normalize(dir),
    final String dir => path.normalize(path.join(workingDirectory, dir)),
    null => path.join(
      workingDirectory,
      '.dart_tool',
      'devtools_profiler',
      'sessions',
      sessionId,
    ),
  };
}
