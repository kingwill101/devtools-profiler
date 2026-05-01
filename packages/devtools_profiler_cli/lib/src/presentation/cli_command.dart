import 'package:devtools_profiler_core/devtools_profiler_core.dart';

/// Returns the CLI command that can reproduce a captured session.
String sessionCliCommand(ProfileRunResult session) {
  if (isAttachSession(session)) {
    final duration = durationOptionForSession(session);
    return shellJoin([
      'devtools-profiler',
      'attach',
      if (duration != null) ...['--duration', duration],
      '--cwd',
      session.workingDirectory,
      '--artifact-dir',
      session.artifactDirectory,
      session.vmServiceUri ?? session.command.skip(1).join(' '),
    ]);
  }
  return shellJoin([
    'devtools-profiler',
    'run',
    if (session.processIoMode == ProfileProcessIoMode.inheritStdio)
      '--terminal',
    '--cwd',
    session.workingDirectory,
    '--artifact-dir',
    session.artifactDirectory,
    '--',
    ...session.command,
  ]);
}

/// Whether [session] was captured through `devtools-profiler attach`.
bool isAttachSession(ProfileRunResult session) {
  return session.command.isNotEmpty && session.command.first == 'attach';
}

/// Returns the closest CLI duration option for [session].
String? durationOptionForSession(ProfileRunResult session) {
  final micros = session.overallProfile?.durationMicros;
  if (micros == null || micros <= 0) {
    return null;
  }
  if (micros % Duration.microsecondsPerSecond == 0) {
    return '${micros ~/ Duration.microsecondsPerSecond}s';
  }
  final milliseconds = (micros / Duration.microsecondsPerMillisecond).ceil();
  return '${milliseconds}ms';
}

/// Joins shell arguments using POSIX-compatible quoting.
String shellJoin(Iterable<String> arguments) {
  return arguments.map(shellQuote).join(' ');
}

/// Quotes one POSIX shell argument when needed.
String shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  const specialCharacters = "'\"\\\$`!|&;<>(){}[]*?";
  final needsQuoting = value.runes.any(
    (rune) =>
        String.fromCharCode(rune).trim().isEmpty ||
        specialCharacters.contains(String.fromCharCode(rune)),
  );
  if (!needsQuoting) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}
