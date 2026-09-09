import 'dart:io';

/// Resolves the Dart VM executable used to launch helper processes.
///
/// In a JIT invocation [Platform.resolvedExecutable] is the Dart VM. A CLI
/// installed with `dart install`, however, is an AOT executable, so resolving
/// the current executable would recursively launch the profiler itself. Use
/// the Dart executable from PATH for that case, with an explicit override for
/// environments where it is not discoverable there.
String resolveDartExecutable({
  String? resolvedExecutable,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final override = env['DEVTOOLS_PROFILER_DART_EXECUTABLE'];
  if (override != null && override.isNotEmpty) {
    return override;
  }

  final executable = resolvedExecutable ?? Platform.resolvedExecutable;
  final name = executable.replaceAll('\\', '/').split('/').last.toLowerCase();
  if (name == 'dart' || name == 'dart.exe') {
    return executable;
  }
  return 'dart';
}
