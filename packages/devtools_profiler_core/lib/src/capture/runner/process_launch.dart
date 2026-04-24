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
    required this.stdoutSubscription,
    required this.stderrSubscription,
  });

  final Process process;
  final Completer<Uri> serviceUri;
  final StreamSubscription<String> stdoutSubscription;
  final StreamSubscription<String> stderrSubscription;
}

/// A resolved executable and argument vector for a profiled launch.
final class CommandLaunchPlan {
  const CommandLaunchPlan({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;
}

/// Launches the target command with profiler session wiring applied.
Future<LaunchedProcess> launchProfiledProcess({
  required ProfileRunRequest request,
  required String sessionId,
  required String dtdUri,
  required String workingDirectory,
}) async {
  final launchPlan = instrumentedCommandLaunchPlan(
    request.command,
    dtdUri: dtdUri,
    sessionId: sessionId,
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
  );

  final serviceUri = Completer<Uri>();
  late final StreamSubscription<String> stdoutSubscription;
  late final StreamSubscription<String> stderrSubscription;

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

  return LaunchedProcess(
    process: process,
    serviceUri: serviceUri,
    stdoutSubscription: stdoutSubscription,
    stderrSubscription: stderrSubscription,
  );
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
      'Only Dart and Flutter VM commands are supported. Expected the first argument to be "dart" or "flutter".',
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
}) {
  return switch (profileCommandKind(command)) {
    ProfileCommandKind.dart => CommandLaunchPlan(
      executable:
          normalizedExecutableName(command.first) == 'dart' &&
              command.first == 'dart'
          ? Platform.resolvedExecutable
          : command.first,
      arguments: [
        '--observe=0',
        '--pause-isolates-on-exit=false',
        ...command.skip(1),
      ],
    ),
    ProfileCommandKind.flutter => flutterLaunchPlan(
      command,
      dtdUri: dtdUri,
      sessionId: sessionId,
    ),
  };
}

/// Builds a Flutter launch plan with profiler arguments inserted safely.
CommandLaunchPlan flutterLaunchPlan(
  List<String> command, {
  required String dtdUri,
  required String sessionId,
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
  );
}

/// Returns profiler arguments for a supported Flutter subcommand.
List<String> flutterProfilerArguments(
  String subcommand,
  List<String> arguments, {
  required String dtdUri,
  required String sessionId,
}) {
  return [
    if (subcommand == 'run' &&
        !hasAnyOption(arguments, const [
          'host-vmservice-port',
          'vm-service-port',
        ]))
      '--host-vmservice-port=0',
    if (subcommand == 'test' &&
        !hasAnyOption(arguments, const ['enable-vmservice', 'start-paused']))
      '--enable-vmservice',
    '--dart-define=$profilerDtdUriEnvVar=$dtdUri',
    '--dart-define=$profilerSessionIdEnvVar=$sessionId',
    '--dart-define=$profilerProtocolVersionEnvVar=1',
  ];
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
