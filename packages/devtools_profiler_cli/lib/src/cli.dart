import 'dart:async';
import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import 'cli/commands/analysis_commands.dart';
import 'cli/commands/artifact_commands.dart';
import 'cli/commands/capture_commands.dart';
import 'cli/constants.dart';

/// Runs the `devtools-profiler` CLI.
Future<int> runCli(
  List<String> arguments, {
  ProfileRunner? runner,
  IOSink? output,
  IOSink? errorOutput,
}) async {
  final profiler = runner ?? ProfileRunner();
  final stdoutSink = output ?? stdout;
  final stderrSink = errorOutput ?? stderr;

  int exitCode = successExitCode;
  final commandRunner =
      CommandRunner<int>(
          'devtools-profiler',
          'Profile Dart and Flutter apps and analyze the results.',
          out: stdoutSink.writeln,
          err: stderrSink.writeln,
          outRaw: stdoutSink.write,
          errRaw: stderrSink.write,
          usageExitCode: usageExitCode,
          setExitCode: (code) => exitCode = code,
          ansi: output != null ? false : null,
        )
        ..addCommand(RunCommand(profiler))
        ..addCommand(AttachCommand(profiler))
        ..addCommand(SummarizeCommand(profiler))
        ..addCommand(ExplainCommand(profiler))
        ..addCommand(CompareCommand(profiler))
        ..addCommand(TrendsCommand(profiler))
        ..addCommand(InspectCommand(profiler))
        ..addCommand(CompareMethodCommand(profiler))
        ..addCommand(SearchMethodsCommand(profiler))
        ..addCommand(InspectClassesCommand(profiler))
        ..addCommand(McpCommand(profiler));

  try {
    final result = await commandRunner.run(arguments);
    return result ?? exitCode;
  } on FormatException catch (error) {
    stderrSink.writeln(error.message);
    return usageExitCode;
  } catch (error) {
    stderrSink.writeln(error);
    return softwareExitCode;
  }
}
