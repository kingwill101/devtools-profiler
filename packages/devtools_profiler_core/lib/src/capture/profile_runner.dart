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

    LaunchedProcess? launchedProcess;
    _ProfileRunSignalWatcher? interruptWatcher;
    Process? process;
    Timer? runDurationTimer;
    var processExited = false;
    var terminatedByProfiler = false;

    try {
      final vmServiceTimeout =
          request.vmServiceTimeout ??
          defaultVmServiceTimeoutForCommand(command);
      await sessionController.registerServices();

      launchedProcess = await launchProfiledProcess(
        request: request,
        command: command,
        sessionId: sessionId,
        dtdUri: dtdSession.info.localUri.toString(),
        vmServiceTimeout: vmServiceTimeout,
        workingDirectory: workingDirectory,
      );
      process = launchedProcess.process;
      sessionController.childProcessId = process.pid;
      interruptWatcher = request.handleInterruptSignals
          ? _ProfileRunSignalWatcher.start()
          : null;

      final serviceWait = await _waitForVmServiceUri(
        launchedProcess.serviceUri.future,
        vmServiceTimeout: vmServiceTimeout,
        interruptSignal: interruptWatcher?.signal,
      );
      final serviceInterruptSignal = serviceWait.signal;
      if (serviceInterruptSignal != null) {
        terminatedByProfiler = true;
        sessionController.addWarning(
          'Received ${_profileSignalName(serviceInterruptSignal)} before the '
          'VM service was available; no profile data could be captured.',
        );
        final stoppedProcess = await _stopInterruptedProcess(
          exitCodeFuture: process.exitCode,
          process: process,
          signal: serviceInterruptSignal,
          sessionController: sessionController,
        );
        processExited = stoppedProcess.processExited;
        final result = sessionController.buildResult(
          artifactDirectory: artifactDirectory.path,
          command: command,
          exitCode: stoppedProcess.exitCode,
          processIoMode: request.processIoMode,
          terminatedByProfiler: terminatedByProfiler,
          workingDirectory: workingDirectory,
        );
        await artifactStore.writeSession(result);
        return result;
      }

      final serviceUri = serviceWait.serviceUri!;
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
              interruptSignal: interruptWatcher?.signal,
            )
          : await _waitForProcessCompletion(
              exitCodeFuture,
              interruptSignal: interruptWatcher?.signal,
            );
      runDurationTimer?.cancel();
      int exitCode;
      if (completion.kind == _ProfiledProcessCompletionKind.interrupted) {
        terminatedByProfiler = true;
        final signal = completion.signal!;
        sessionController.addWarning(
          'Received ${_profileSignalName(signal)}; finalizing available '
          'profile data before stopping the target process.',
        );
        try {
          await sessionController.handleProcessExit().timeout(
            _interruptFinalizationWait,
          );
        } on TimeoutException {
          sessionController.addWarning(
            'Timed out finalizing all profile data after interruption; '
            'returning the diagnostics captured so far.',
          );
        } catch (error) {
          sessionController.addWarning(
            'Failed to finalize all profile data after interruption: $error',
          );
        }
        final stoppedProcess = await _stopInterruptedProcess(
          exitCodeFuture: exitCodeFuture,
          process: process,
          signal: signal,
          sessionController: sessionController,
        );
        exitCode = stoppedProcess.exitCode;
        processExited = stoppedProcess.processExited;
      } else if (completion.kind ==
          _ProfiledProcessCompletionKind.pausedAtExit) {
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
        processIoMode: request.processIoMode,
        terminatedByProfiler: terminatedByProfiler,
        workingDirectory: workingDirectory,
      );
      await artifactStore.writeSession(result);
      return result;
    } finally {
      await launchedProcess?.stdoutSubscription?.cancel();
      await launchedProcess?.stderrSubscription?.cancel();
      await interruptWatcher?.dispose();
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
        processIoMode: ProfileProcessIoMode.pipe,
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
  interrupted,
  pausedAtExit,
}

const _initialExitPausePollDelay = Duration(milliseconds: 50);
const _exitPauseProbeTimeout = Duration(milliseconds: 500);
const _maxExitPausePollDelay = Duration(seconds: 3);
const _interruptExitWait = Duration(milliseconds: 750);
const _interruptFinalizationWait = Duration(seconds: 5);
const _interruptTerminationWait = Duration(seconds: 2);

typedef _ProcessCompletion = ({
  int? exitCode,
  _ProfiledProcessCompletionKind kind,
  ProcessSignal? signal,
});

typedef _MaybeProcessCompletion = ({
  int? exitCode,
  _ProfiledProcessCompletionKind? kind,
  ProcessSignal? signal,
});

/// Waits for the VM-service URI or a user interrupt during startup.
Future<({Uri? serviceUri, ProcessSignal? signal})> _waitForVmServiceUri(
  Future<Uri> serviceUriFuture, {
  required Duration vmServiceTimeout,
  required Future<ProcessSignal>? interruptSignal,
}) {
  final serviceUri = serviceUriFuture
      .timeout(
        vmServiceTimeout,
        onTimeout: () {
          throw StateError(
            'Timed out after ${formatProfileDuration(vmServiceTimeout)} '
            'waiting for the Dart VM service URI from the profiled process. '
            'If the target is still building or starting, increase '
            '--vm-service-timeout.',
          );
        },
      )
      .then<({Uri? serviceUri, ProcessSignal? signal})>(
        (uri) => (serviceUri: uri, signal: null),
      );
  final interrupt = interruptSignal?.then(
    (signal) => (serviceUri: null, signal: signal),
  );
  return Future.any([serviceUri, ?interrupt]);
}

/// Waits for a non-Dart process to exit or for the user to interrupt it.
Future<_ProcessCompletion> _waitForProcessCompletion(
  Future<int> exitCodeFuture, {
  required Future<ProcessSignal>? interruptSignal,
}) {
  final exitCompletion = exitCodeFuture.then(
    (exitCode) => (
      kind: _ProfiledProcessCompletionKind.exited,
      exitCode: exitCode,
      signal: null,
    ),
  );
  final interruptCompletion = interruptSignal?.then(
    (signal) => (
      kind: _ProfiledProcessCompletionKind.interrupted,
      exitCode: null,
      signal: signal,
    ),
  );
  return Future.any([exitCompletion, ?interruptCompletion]);
}

/// Waits for a Dart process to exit or pause every app isolate at exit.
///
/// Dart launches use `--pause-isolates-on-exit` so a short script can be
/// captured before the VM service disappears. This helper races the process
/// [exitCodeFuture] with [ProfileSessionController.exitPauseSignal]. It also
/// polls [ProfileSessionController.recordCurrentlyPausedExitIsolates] with
/// backoff because debug stream events can be missed during shutdown. A
/// returned [_ProfiledProcessCompletionKind.exited] means the process produced
/// an exit code normally; [_ProfiledProcessCompletionKind.pausedAtExit] means
/// [ProfileSessionController.haveAllAppIsolatesPausedAtExit] is true and the
/// caller should capture final artifacts before resuming isolates.
Future<_ProcessCompletion> _waitForDartProcessCompletion(
  Future<int> exitCodeFuture,
  ProfileSessionController sessionController, {
  required Future<ProcessSignal>? interruptSignal,
}) async {
  final exitCompletion = exitCodeFuture.then(
    (exitCode) => (
      kind: _ProfiledProcessCompletionKind.exited,
      exitCode: exitCode,
      signal: null,
    ),
  );
  final exitPause = sessionController.exitPauseSignal.then(
    (allPaused) => (
      kind: allPaused
          ? _ProfiledProcessCompletionKind.pausedAtExit
          : _ProfiledProcessCompletionKind.exitPauseUnavailable,
      exitCode: null,
      signal: null,
    ),
  );
  final interruptCompletion = interruptSignal?.then(
    (signal) => (
      kind: _ProfiledProcessCompletionKind.interrupted,
      exitCode: null,
      signal: signal,
    ),
  );
  var listenForExitPauseSignal = true;
  var pollDelay = _initialExitPausePollDelay;

  while (true) {
    final completion = await Future.any<_MaybeProcessCompletion>([
      exitCompletion,
      if (listenForExitPauseSignal) exitPause,
      ?interruptCompletion,
      Future.delayed(
        pollDelay,
        () => (kind: null, exitCode: null, signal: null),
      ),
    ]);

    final kind = completion.kind;
    if (kind != null) {
      if (kind == _ProfiledProcessCompletionKind.exitPauseUnavailable) {
        listenForExitPauseSignal = false;
        pollDelay = _maxExitPausePollDelay;
        continue;
      }
      return (
        kind: kind,
        exitCode: completion.exitCode,
        signal: completion.signal,
      );
    }

    await sessionController.recordCurrentlyPausedExitIsolates().timeout(
      _exitPauseProbeTimeout,
      onTimeout: () {},
    );
    if (sessionController.haveAllAppIsolatesPausedAtExit) {
      return (
        kind: _ProfiledProcessCompletionKind.pausedAtExit,
        exitCode: null,
        signal: null,
      );
    }
    pollDelay = _nextExitPausePollDelay(pollDelay);
  }
}

Duration _nextExitPausePollDelay(Duration currentDelay) {
  final nextDelay = currentDelay * 2;
  return nextDelay > _maxExitPausePollDelay
      ? _maxExitPausePollDelay
      : nextDelay;
}

/// Stops an interrupted target after giving it a short graceful-exit window.
Future<({int exitCode, bool processExited})> _stopInterruptedProcess({
  required Future<int> exitCodeFuture,
  required Process process,
  required ProcessSignal signal,
  required ProfileSessionController sessionController,
}) async {
  try {
    final exitCode = await exitCodeFuture.timeout(_interruptExitWait);
    return (exitCode: exitCode, processExited: true);
  } on TimeoutException {
    // The target did not handle the terminal interrupt itself.
  }

  if (!_killProcess(process, signal)) {
    sessionController.addWarning(
      'Failed to forward ${_profileSignalName(signal)} to the target process.',
    );
  }
  await _resumeAnyInterruptedExitPauses(sessionController);
  try {
    final exitCode = await exitCodeFuture.timeout(_interruptTerminationWait);
    return (exitCode: exitCode, processExited: true);
  } on TimeoutException {
    // Fall through to a stronger termination signal below.
  }

  if (signal != ProcessSignal.sigterm &&
      !_killProcess(process, ProcessSignal.sigterm)) {
    sessionController.addWarning(
      'Failed to terminate the target process after interruption.',
    );
  }
  try {
    final exitCode = await exitCodeFuture.timeout(_interruptTerminationWait);
    return (exitCode: exitCode, processExited: true);
  } on TimeoutException {
    sessionController.addWarning(
      'Timed out waiting for the target process to exit after interruption; '
      'returning a synthetic interrupt exit code.',
    );
    return (exitCode: _profileSignalExitCode(signal), processExited: false);
  }
}

Future<void> _resumeAnyInterruptedExitPauses(
  ProfileSessionController sessionController,
) async {
  try {
    await sessionController.recordCurrentlyPausedExitIsolates().timeout(
      _exitPauseProbeTimeout,
      onTimeout: () {},
    );
    await sessionController.resumePausedExitIsolates();
  } catch (_) {
    // This is best-effort during shutdown; the final result keeps the
    // interruption warning that explains why shutdown was forced.
  }
}

bool _killProcess(Process process, ProcessSignal signal) {
  try {
    return process.kill(signal);
  } catch (_) {
    return false;
  }
}

String _profileSignalName(ProcessSignal signal) {
  if (signal == ProcessSignal.sigint) {
    return 'SIGINT';
  }
  if (signal == ProcessSignal.sigterm) {
    return 'SIGTERM';
  }
  return signal.toString();
}

int _profileSignalExitCode(ProcessSignal signal) {
  if (signal == ProcessSignal.sigint) {
    return 130;
  }
  if (signal == ProcessSignal.sigterm) {
    return 143;
  }
  return 1;
}

/// Watches process-level interrupt signals while one run is active.
final class _ProfileRunSignalWatcher {
  _ProfileRunSignalWatcher({
    required this.signal,
    required List<StreamSubscription<ProcessSignal>> subscriptions,
  }) : _subscriptions = subscriptions;

  final Future<ProcessSignal> signal;
  final List<StreamSubscription<ProcessSignal>> _subscriptions;

  static _ProfileRunSignalWatcher? start() {
    final signal = Completer<ProcessSignal>();
    final subscriptions = <StreamSubscription<ProcessSignal>>[];

    void watch(ProcessSignal processSignal) {
      try {
        subscriptions.add(
          processSignal.watch().listen((receivedSignal) {
            if (!signal.isCompleted) {
              signal.complete(receivedSignal);
            }
          }),
        );
      } on UnsupportedError {
        // Some platforms do not expose all process signals to Dart.
      }
    }

    watch(ProcessSignal.sigint);
    if (!Platform.isWindows) {
      watch(ProcessSignal.sigterm);
    }

    if (subscriptions.isEmpty) {
      return null;
    }
    return _ProfileRunSignalWatcher(
      signal: signal.future,
      subscriptions: subscriptions,
    );
  }

  Future<void> dispose() async {
    await Future.wait([
      for (final subscription in _subscriptions) subscription.cancel(),
    ]);
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
