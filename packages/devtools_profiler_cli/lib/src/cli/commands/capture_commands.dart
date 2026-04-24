import 'package:artisanal/args.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../../mcp_server.dart';
import '../../presentation.dart';
import '../../rendering.dart';
import '../constants.dart';
import '../options.dart';
import 'profiler_command.dart';

/// Command that launches and profiles a Dart or Flutter process.
class RunCommand extends ProfilerCommand {
  /// Creates a run command.
  RunCommand(super.profileRunner) {
    argParser
      ..addOption(
        'cwd',
        help: 'The working directory for the launched process.',
      )
      ..addOption(
        'artifact-dir',
        help: 'The directory where session artifacts should be written.',
      )
      ..addOption(
        'duration',
        help:
            'Stop the launched process after this profiling duration. Supports raw seconds, "10s", "500ms", or "2m".',
      )
      ..addOption(
        'vm-service-timeout',
        help:
            'How long to wait for the launched process to expose a Dart VM service URI. Supports raw seconds, "180s", or "3m".',
      )
      ..addFlag(
        'forward-output',
        defaultsTo: true,
        help: 'Echo stdout and stderr from the launched process.',
      );
  }

  @override
  String get name => 'run';

  @override
  String get description => 'Launch and profile a Dart or Flutter command.';

  @override
  Future<int> run() async {
    final commandArguments = argResults!.rest;
    if (commandArguments.isEmpty) {
      usageException(
        'A profiled Dart or Flutter command is required after "--".',
      );
    }

    final session = await profileRunner.run(
      ProfileRunRequest(
        artifactDirectory: argResults!['artifact-dir'] as String?,
        command: commandArguments,
        forwardOutput: argResults!['forward-output'] as bool,
        runDuration: parseDuration(
          argResults!['duration'] as String?,
          optionName: 'duration',
        ),
        vmServiceTimeout: parseDuration(
          argResults!['vm-service-timeout'] as String?,
          optionName: 'vm-service-timeout',
        ),
        workingDirectory: argResults!['cwd'] as String?,
      ),
    );
    final options = presentationOptions;
    final prepared = await prepareSessionPresentation(
      profileRunner,
      session,
      options: options,
    );

    if (printJson) {
      writeJson(
        sessionPresentationJson(
          prepared.session,
          prepared.overallTree,
          prepared.overallBottomUpTree,
          prepared.overallMethodTable,
          prepared.regionTrees,
          prepared.regionBottomUpTrees,
          prepared.regionMethodTables,
        ),
      );
    } else {
      writeSessionSummary(
        io,
        prepared.session,
        overallTree: prepared.overallTree,
        overallBottomUpTree: prepared.overallBottomUpTree,
        overallMethodTable: prepared.overallMethodTable,
        regionTrees: prepared.regionTrees,
        regionBottomUpTrees: prepared.regionBottomUpTrees,
        regionMethodTables: prepared.regionMethodTables,
        options: options,
      );
    }

    return prepared.session.exitCode == 0 ||
            prepared.session.terminatedByProfiler
        ? successExitCode
        : softwareExitCode;
  }
}

/// Command that profiles an already-running Dart VM service.
class AttachCommand extends ProfilerCommand {
  /// Creates an attach command.
  AttachCommand(super.profileRunner) {
    argParser
      ..addOption(
        'cwd',
        help: 'The working directory associated with the profiled target.',
      )
      ..addOption(
        'artifact-dir',
        help: 'The directory where session artifacts should be written.',
      )
      ..addOption(
        'duration',
        help:
            'Required profiling duration. Supports raw seconds, "10s", "500ms", or "2m".',
      );
  }

  @override
  String get name => 'attach';

  @override
  String get description =>
      'Attach to an existing Dart VM service and profile a fixed window.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      usageException('Attach requires exactly one Dart VM service URI.');
    }

    final duration = parseDuration(
      argResults!['duration'] as String?,
      optionName: 'duration',
    );
    if (duration == null) {
      usageException('Attach requires --duration.');
    }

    final session = await profileRunner.attach(
      ProfileAttachRequest(
        artifactDirectory: argResults!['artifact-dir'] as String?,
        duration: duration,
        vmServiceUri: parseVmServiceUriArgument(argResults!.rest.single),
        workingDirectory: argResults!['cwd'] as String?,
      ),
    );
    final options = presentationOptions;
    final prepared = await prepareSessionPresentation(
      profileRunner,
      session,
      options: options,
    );

    if (printJson) {
      writeJson(
        sessionPresentationJson(
          prepared.session,
          prepared.overallTree,
          prepared.overallBottomUpTree,
          prepared.overallMethodTable,
          prepared.regionTrees,
          prepared.regionBottomUpTrees,
          prepared.regionMethodTables,
        ),
      );
    } else {
      writeSessionSummary(
        io,
        prepared.session,
        overallTree: prepared.overallTree,
        overallBottomUpTree: prepared.overallBottomUpTree,
        overallMethodTable: prepared.overallMethodTable,
        regionTrees: prepared.regionTrees,
        regionBottomUpTrees: prepared.regionBottomUpTrees,
        regionMethodTables: prepared.regionMethodTables,
        options: options,
      );
    }

    return successExitCode;
  }
}

/// Command that starts the stdio MCP server.
class McpCommand extends Command<int> {
  /// Creates an MCP command.
  McpCommand(this.profileRunner);

  /// The profiler backend used by this command.
  final ProfileRunner profileRunner;

  @override
  String get name => 'mcp';

  @override
  String get description => 'Run the local stdio MCP server.';

  @override
  Future<int> run() async {
    await serveMcp(runner: profileRunner);
    return successExitCode;
  }
}
