/// A request to launch and profile a Dart or Flutter command.
///
/// Use this with [ProfileRunner.run] when the profiler should own the target
/// process lifecycle. The command must start with `dart` or `flutter`.
/// Session artifacts are written under [artifactDirectory] when provided, or
/// under a generated `.dart_tool/devtools_profiler/sessions/...` directory
/// inside [workingDirectory] otherwise.
class ProfileRunRequest {
  /// Creates a profiling request.
  const ProfileRunRequest({
    required this.command,
    this.workingDirectory,
    this.artifactDirectory,
    this.forwardOutput = false,
    this.environment = const {},
    this.runDuration,
    this.vmServiceTimeout,
  });

  /// The command to launch.
  ///
  /// The first argument must be `dart` or `flutter`.
  final List<String> command;

  /// The working directory to use for the launched process.
  final String? workingDirectory;

  /// The directory where profiling artifacts should be written.
  ///
  /// When omitted, a session directory will be created under `.dart_tool`.
  final String? artifactDirectory;

  /// Whether stdout and stderr from the profiled process should be echoed.
  final bool forwardOutput;

  /// Extra environment variables to inject into the launched process.
  final Map<String, String> environment;

  /// Optional duration to profile before terminating the launched process.
  ///
  /// This is useful for long-running apps such as `flutter run`, where the
  /// process would otherwise keep running until a user stops it manually.
  final Duration? runDuration;

  /// Optional timeout for waiting for the launched process to expose a VM
  /// service URI.
  ///
  /// This is separate from [runDuration]. The profiler starts [runDuration]
  /// only after the VM service is available and attached.
  final Duration? vmServiceTimeout;
}
