/// A request to profile an already-running Dart or Flutter VM service.
///
/// Use this with [ProfileRunner.attach] when another tool already owns the
/// process lifecycle and can provide the VM service URI. Attach mode captures a
/// fixed whole-session window and does not stop the target process.
class ProfileAttachRequest {
  /// Creates an attach profiling request.
  const ProfileAttachRequest({
    required this.vmServiceUri,
    required this.duration,
    this.workingDirectory,
    this.artifactDirectory,
  });

  /// The HTTP URI printed by the Dart or Flutter VM service.
  final Uri vmServiceUri;

  /// How long to collect profile data after attaching.
  final Duration duration;

  /// The working directory associated with the profiled target.
  final String? workingDirectory;

  /// The directory where profiling artifacts should be written.
  ///
  /// When omitted, a session directory will be created under `.dart_tool`.
  final String? artifactDirectory;
}
