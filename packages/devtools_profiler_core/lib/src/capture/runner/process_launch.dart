import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models.dart';
import 'profile_runner_shared.dart';

/// A launched target process plus the subscriptions needed to monitor it.
final class LaunchedProcess {
  const LaunchedProcess({
    required this.process,
    required this.serviceUri,
    this.stdoutSubscription,
    this.stderrSubscription,
  });

  final Process process;
  final Completer<Uri> serviceUri;
  final StreamSubscription<String>? stdoutSubscription;
  final StreamSubscription<String>? stderrSubscription;
}

/// A resolved executable and argument vector for a profiled launch.
final class CommandLaunchPlan {
  const CommandLaunchPlan({
    required this.executable,
    required this.arguments,
    this.expectedVmServiceUri,
  });

  final String executable;
  final List<String> arguments;

  /// VM-service URI that can be used without scraping process output.
  final Uri? expectedVmServiceUri;
}

/// Launches the target command with profiler session wiring applied.
Future<LaunchedProcess> launchProfiledProcess({
  required ProfileRunRequest request,
  required List<String> command,
  required String sessionId,
  required String dtdUri,
  required Duration vmServiceTimeout,
  required String workingDirectory,
}) async {
  final vmServicePort =
      request.processIoMode == ProfileProcessIoMode.inheritStdio
      ? await _reserveLoopbackPort()
      : null;
  final launchPlan = instrumentedCommandLaunchPlan(
    command,
    dtdUri: dtdUri,
    sessionId: sessionId,
    processIoMode: request.processIoMode,
    vmServicePort: vmServicePort,
  );
  final process = await Process.start(
    launchPlan.executable,
    launchPlan.arguments,
    workingDirectory: workingDirectory,
    environment: {
      ...Platform.environment,
      ...request.environment,
      profilerDtdUriEnvVar: dtdUri,
      profilerSessionIdEnvVar: sessionId,
      profilerProtocolVersionEnvVar: '1',
    },
    mode: switch (request.processIoMode) {
      ProfileProcessIoMode.pipe => ProcessStartMode.normal,
      ProfileProcessIoMode.inheritStdio => ProcessStartMode.inheritStdio,
    },
  );

  final serviceUri = Completer<Uri>();
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;

  void handleLine(String line, IOSink sink) {
    final parsedUri = parseVmServiceUri(line);
    if (parsedUri != null) {
      if (!serviceUri.isCompleted) {
        serviceUri.complete(parsedUri);
      }
      return;
    }

    if (request.forwardOutput) {
      sink.writeln(line);
    }
  }

  final expectedVmServiceUri = launchPlan.expectedVmServiceUri;
  if (expectedVmServiceUri != null) {
    unawaited(
      _completeKnownVmServiceUri(
        serviceUri: serviceUri,
        expectedVmServiceUri: expectedVmServiceUri,
        exitCodeFuture: process.exitCode,
        vmServiceTimeout: vmServiceTimeout,
      ),
    );
  } else {
    stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => handleLine(line, stdout));

    stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => handleLine(line, stderr));

    unawaited(
      process.exitCode.then((_) {
        if (!serviceUri.isCompleted) {
          serviceUri.completeError(
            StateError(
              'The profiled process exited before exposing a VM service URI.',
            ),
          );
        }
      }),
    );
  }

  return LaunchedProcess(
    process: process,
    serviceUri: serviceUri,
    stdoutSubscription: stdoutSubscription,
    stderrSubscription: stderrSubscription,
  );
}

/// Returns the Dart or Flutter command shape used by the profiler.
///
/// A bare Dart file path is treated as shorthand for `dart run <file>`.
List<String> normalizeProfileCommand(List<String> command) {
  if (command.isEmpty) {
    return command;
  }

  if (isBareDartFileCommand(command)) {
    return ['dart', 'run', ...command];
  }

  return command;
}

/// Returns whether [command] starts with a Dart file path.
bool isBareDartFileCommand(List<String> command) {
  if (command.isEmpty) {
    return false;
  }
  return path.extension(command.first).toLowerCase() == '.dart';
}

/// Validates that [command] is a supported Dart or Flutter launch shape.
void validateProfileCommand(List<String> command) {
  if (command.isEmpty) {
    throw ArgumentError('A Dart or Flutter command is required.');
  }

  switch (profileCommandKind(command)) {
    case ProfileCommandKind.dart:
      validateDartCommand(command);
    case ProfileCommandKind.flutter:
      validateFlutterCommand(command);
  }
}

/// Validates Dart-specific profiler launch constraints.
void validateDartCommand(List<String> command) {
  final firstNonOption = command
      .skip(1)
      .firstWhere((argument) => !argument.startsWith('-'), orElse: () => '');
  if (firstNonOption.isEmpty) {
    throw ArgumentError('A Dart subcommand or script path is required.');
  }
  if (firstNonOption == 'compile') {
    throw ArgumentError(
      'Compiled AOT executables are out of scope for this profiler backend.',
    );
  }
}

/// Validates Flutter-specific profiler launch constraints.
void validateFlutterCommand(List<String> command) {
  final subcommandIndex = flutterSubcommandIndex(command);
  if (subcommandIndex == null) {
    throw ArgumentError(
      'A supported Flutter subcommand is required. Use "flutter run" or "flutter test".',
    );
  }

  final subcommand = command[subcommandIndex];
  if (!supportedFlutterSubcommands.contains(subcommand)) {
    throw ArgumentError(
      'Only "flutter run" and "flutter test" are supported for Flutter profiling.',
    );
  }

  final subcommandArguments = command.sublist(subcommandIndex + 1);
  if (hasOption(subcommandArguments, 'release')) {
    throw ArgumentError(
      'Flutter release mode does not expose a Dart VM service. Use debug or profile mode.',
    );
  }

  if (subcommand == 'test' &&
      hasOption(subcommandArguments, 'experimental-faster-testing')) {
    throw ArgumentError(
      'Flutter experimental faster testing is not compatible with VM service profiling.',
    );
  }
}

/// Returns the supported command family for [command].
ProfileCommandKind profileCommandKind(List<String> command) {
  final executableName = normalizedExecutableName(command.first);
  return switch (executableName) {
    'dart' => ProfileCommandKind.dart,
    'flutter' => ProfileCommandKind.flutter,
    _ => throw ArgumentError(
      'Only Dart and Flutter VM commands are supported. Expected the first argument to be "dart", "flutter", or a Dart file path.',
    ),
  };
}

/// Normalizes platform-specific executable suffixes for command detection.
String normalizedExecutableName(String executable) {
  var name = path.basename(executable).toLowerCase();
  for (final extension in const ['.exe', '.bat', '.cmd']) {
    if (name.endsWith(extension)) {
      name = name.substring(0, name.length - extension.length);
      break;
    }
  }
  return name;
}

/// Builds the launch plan with profiler-specific VM and define arguments.
CommandLaunchPlan instrumentedCommandLaunchPlan(
  List<String> command, {
  required String dtdUri,
  required String sessionId,
  ProfileProcessIoMode processIoMode = ProfileProcessIoMode.pipe,
  int? vmServicePort,
}) {
  return switch (profileCommandKind(command)) {
    ProfileCommandKind.dart => _dartLaunchPlan(
      command,
      processIoMode: processIoMode,
      vmServicePort: vmServicePort,
    ),
    ProfileCommandKind.flutter => flutterLaunchPlan(
      command,
      dtdUri: dtdUri,
      sessionId: sessionId,
      processIoMode: processIoMode,
      vmServicePort: vmServicePort,
    ),
  };
}

/// Builds a Dart [CommandLaunchPlan] with profiler VM arguments first.
///
/// Pipe mode enables exit pausing so short Dart scripts keep their VM service
/// alive long enough for final snapshots. Inherited-stdio mode explicitly
/// disables exit pausing because terminal apps own their shutdown behavior and
/// because the profiler uses [CommandLaunchPlan.expectedVmServiceUri] instead
/// of scraping output for service auth codes. The bare `dart` command is
/// replaced with [Platform.resolvedExecutable] only when
/// [normalizedExecutableName] confirms it is exactly the SDK token; explicit
/// paths and suffixed executables are preserved.
CommandLaunchPlan _dartLaunchPlan(
  List<String> command, {
  required ProfileProcessIoMode processIoMode,
  required int? vmServicePort,
}) {
  final usesInheritedStdio = processIoMode == ProfileProcessIoMode.inheritStdio;
  final expectedVmServiceUri = usesInheritedStdio
      ? _expectedLoopbackVmServiceUri(vmServicePort)
      : null;

  return CommandLaunchPlan(
    executable:
        normalizedExecutableName(command.first) == 'dart' &&
            command.first == 'dart'
        ? Platform.resolvedExecutable
        : command.first,
    arguments: [
      usesInheritedStdio ? '--observe=$vmServicePort' : '--observe=0',
      if (usesInheritedStdio) '--disable-service-auth-codes',
      if (usesInheritedStdio)
        '--pause-isolates-on-exit=false'
      else
        '--pause-isolates-on-exit',
      ...command.skip(1),
    ],
    expectedVmServiceUri: expectedVmServiceUri,
  );
}

/// Builds a Flutter launch plan with profiler arguments inserted safely.
CommandLaunchPlan flutterLaunchPlan(
  List<String> command, {
  required String dtdUri,
  required String sessionId,
  ProfileProcessIoMode processIoMode = ProfileProcessIoMode.pipe,
  int? vmServicePort,
}) {
  final subcommandIndex = flutterSubcommandIndex(command)!;
  final subcommand = command[subcommandIndex];
  final prefixArguments = command.sublist(1, subcommandIndex);
  final subcommandArguments = command.sublist(subcommandIndex + 1);
  final passthroughIndex = subcommandArguments.indexOf('--');
  final flutterArguments = passthroughIndex == -1
      ? subcommandArguments
      : subcommandArguments.sublist(0, passthroughIndex);
  final passthroughArguments = passthroughIndex == -1
      ? const <String>[]
      : subcommandArguments.sublist(passthroughIndex);
  final profilerArguments = flutterProfilerArguments(
    subcommand,
    flutterArguments,
    dtdUri: dtdUri,
    sessionId: sessionId,
    processIoMode: processIoMode,
    vmServicePort: vmServicePort,
  );
  final expectedVmServiceUri = _flutterExpectedVmServiceUri(
    subcommand,
    flutterArguments,
    processIoMode: processIoMode,
    vmServicePort: vmServicePort,
  );

  return CommandLaunchPlan(
    executable: command.first,
    arguments: [
      ...prefixArguments,
      subcommand,
      ...flutterArguments,
      ...profilerArguments,
      ...passthroughArguments,
    ],
    expectedVmServiceUri: expectedVmServiceUri,
  );
}

/// Returns profiler arguments for a supported Flutter subcommand.
List<String> flutterProfilerArguments(
  String subcommand,
  List<String> arguments, {
  required String dtdUri,
  required String sessionId,
  ProfileProcessIoMode processIoMode = ProfileProcessIoMode.pipe,
  int? vmServicePort,
}) {
  final usesInheritedStdio = processIoMode == ProfileProcessIoMode.inheritStdio;
  final profilerPort = usesInheritedStdio
      ? _flutterTerminalVmServicePort(
          subcommand,
          arguments,
          vmServicePort: vmServicePort,
        )
      : null;

  return [
    if (subcommand == 'run' &&
        !hasAnyOption(arguments, const [
          'host-vmservice-port',
          'vm-service-port',
        ]))
      '--host-vmservice-port=${profilerPort ?? 0}',
    if (subcommand == 'test' &&
        !hasAnyOption(arguments, const ['enable-vmservice', 'start-paused']))
      '--enable-vmservice',
    if (usesInheritedStdio &&
        subcommand == 'run' &&
        !hasOption(arguments, 'disable-service-auth-codes'))
      '--disable-service-auth-codes',
    '--dart-define=$profilerDtdUriEnvVar=$dtdUri',
    '--dart-define=$profilerSessionIdEnvVar=$sessionId',
    '--dart-define=$profilerProtocolVersionEnvVar=1',
  ];
}

/// Returns the VM-service URI implied by Flutter terminal-mode arguments.
Uri? _flutterExpectedVmServiceUri(
  String subcommand,
  List<String> arguments, {
  required ProfileProcessIoMode processIoMode,
  required int? vmServicePort,
}) {
  if (processIoMode != ProfileProcessIoMode.inheritStdio) {
    return null;
  }
  return _expectedLoopbackVmServiceUri(
    _flutterTerminalVmServicePort(
      subcommand,
      arguments,
      vmServicePort: vmServicePort,
    ),
  );
}

/// Returns the fixed VM-service port used for Flutter terminal mode.
int _flutterTerminalVmServicePort(
  String subcommand,
  List<String> arguments, {
  required int? vmServicePort,
}) {
  if (subcommand != 'run') {
    throw ArgumentError(
      '--terminal is only supported for "flutter run". Flutter test does not '
      'provide a predictable VM-service URI when process output is inherited.',
    );
  }

  final explicitPort =
      _longOptionIntValue(arguments, 'host-vmservice-port') ??
      _longOptionIntValue(arguments, 'vm-service-port');
  final resolvedPort = explicitPort ?? vmServicePort;
  if (resolvedPort == null || resolvedPort <= 0) {
    throw ArgumentError(
      '--terminal requires a fixed Flutter VM-service port. Omit '
      '--host-vmservice-port so the profiler can choose one, or pass a '
      'non-zero port.',
    );
  }
  return resolvedPort;
}

const knownFlutterSubcommands = {
  'analyze',
  'assemble',
  'attach',
  'build',
  'channel',
  'clean',
  'config',
  'create',
  'custom-devices',
  'devices',
  'doctor',
  'downgrade',
  'drive',
  'emulators',
  'gen-l10n',
  'install',
  'logs',
  'precache',
  'pub',
  'run',
  'screenshot',
  'symbolize',
  'test',
  'upgrade',
};

const supportedFlutterSubcommands = {'run', 'test'};

/// Returns the first recognized Flutter subcommand index in [command].
int? flutterSubcommandIndex(List<String> command) {
  for (var i = 1; i < command.length; i++) {
    if (knownFlutterSubcommands.contains(command[i])) {
      return i;
    }
  }
  return null;
}

/// Returns whether [arguments] contains any named long option in [names].
bool hasAnyOption(List<String> arguments, Iterable<String> names) {
  return names.any((name) => hasOption(arguments, name));
}

/// Returns whether [arguments] contains the long option [name].
bool hasOption(List<String> arguments, String name) {
  final option = '--$name';
  return arguments.any(
    (argument) => argument == option || argument.startsWith('$option='),
  );
}

/// Returns an integer value for a long option when it is present.
int? _longOptionIntValue(List<String> arguments, String name) {
  final option = '--$name';
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    String? value;
    if (argument == option) {
      if (i + 1 < arguments.length && !arguments[i + 1].startsWith('-')) {
        value = arguments[i + 1];
      }
    } else if (argument.startsWith('$option=')) {
      value = argument.substring(option.length + 1);
    }
    if (value != null) {
      return int.tryParse(value);
    }
  }
  return null;
}

/// Reserves a currently available loopback port for deterministic attachment.
///
/// This uses a bind-then-close pattern, which leaves a brief race window before
/// the target binds the port. That tradeoff is acceptable for this local
/// profiling path; stronger guarantees would require letting the target pick an
/// ephemeral port and scraping output, or using platform-specific reservation
/// APIs.
Future<int> _reserveLoopbackPort() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return port;
}

/// Returns the profiler's auth-free loopback VM-service URI for [port].
Uri _expectedLoopbackVmServiceUri(int? port) {
  if (port == null || port <= 0) {
    throw ArgumentError(
      'A non-zero VM-service port is required for inherited stdio mode.',
    );
  }
  return Uri.parse('http://127.0.0.1:$port/');
}

/// Completes [serviceUri] once the known VM-service port starts accepting IO.
Future<void> _completeKnownVmServiceUri({
  required Completer<Uri> serviceUri,
  required Uri expectedVmServiceUri,
  required Future<int> exitCodeFuture,
  required Duration vmServiceTimeout,
}) async {
  var processExited = false;
  final stopwatch = Stopwatch()..start();
  unawaited(
    exitCodeFuture.then((_) {
      processExited = true;
      if (!serviceUri.isCompleted) {
        serviceUri.completeError(
          StateError(
            'The profiled process exited before exposing a VM service URI.',
          ),
        );
      }
    }),
  );

  var probeDelay = const Duration(milliseconds: 25);
  while (!serviceUri.isCompleted && !processExited) {
    if (stopwatch.elapsed >= vmServiceTimeout) {
      if (!serviceUri.isCompleted) {
        serviceUri.completeError(
          StateError(
            'Timed out after ${formatProfileDuration(vmServiceTimeout)} '
            'waiting for the Dart VM service URI from the profiled process.',
          ),
        );
      }
      return;
    }
    if (await _canConnectToVmService(expectedVmServiceUri)) {
      if (!serviceUri.isCompleted) {
        serviceUri.complete(expectedVmServiceUri);
      }
      return;
    }
    final remaining = vmServiceTimeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      continue;
    }
    await Future<void>.delayed(remaining < probeDelay ? remaining : probeDelay);
    probeDelay = _nextVmServiceProbeDelay(probeDelay);
  }
}

/// Returns whether the VM-service socket is accepting connections.
Future<bool> _canConnectToVmService(Uri serviceUri) async {
  Socket? socket;
  try {
    socket = await Socket.connect(
      serviceUri.host,
      serviceUri.port,
      timeout: const Duration(milliseconds: 100),
    );
    return true;
  } catch (_) {
    return false;
  } finally {
    socket?.destroy();
  }
}

Duration _nextVmServiceProbeDelay(Duration currentDelay) {
  final nextDelay = currentDelay * 2;
  return nextDelay > const Duration(milliseconds: 250)
      ? const Duration(milliseconds: 250)
      : nextDelay;
}

/// Returns the default VM-service wait timeout for [command].
Duration defaultVmServiceTimeoutForCommand(List<String> command) {
  return switch (profileCommandKind(command)) {
    ProfileCommandKind.dart => defaultDartVmServiceTimeout,
    ProfileCommandKind.flutter => defaultFlutterVmServiceTimeout,
  };
}

/// Parses a VM-service URI from one line of tool output when present.
Uri? parseVmServiceUri(String line) {
  final match = RegExp(
    r'(?:Observatory|Dart VM service|VM service).*?((?:https?:)?//[a-zA-Z0-9:/=_\-\.\[\]%?&]+)',
    caseSensitive: false,
  ).firstMatch(line);
  if (match == null) return null;
  return normalizeVmServiceUri(match.group(1)!);
}

/// Normalizes a VM-service URI to the HTTP form expected by callers.
Uri normalizeVmServiceUri(String uriString) {
  final uri = Uri.parse(
    uriString.startsWith('//') ? 'http:$uriString' : uriString,
  );
  final normalizedPath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri.replace(path: normalizedPath);
}
