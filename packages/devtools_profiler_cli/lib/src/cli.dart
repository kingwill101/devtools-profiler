
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:artisanal/artisanal.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;

import 'mcp_server.dart';
import 'presentation.dart';

part 'cli/command_base.dart';
part 'cli/capture_commands.dart';
part 'cli/artifact_commands.dart';
part 'cli/analysis_commands.dart';
part 'cli/rendering.dart';

const _successExitCode = 0;
const _usageExitCode = 64;
const _softwareExitCode = 70;
const _dartSdkUriPrefix = 'org-dartlang-sdk:///sdk/lib/';
const _defaultMethodPathLimit = 3;
const _jsonEncoder = JsonEncoder.withIndent('  ');

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

  int exitCode = _successExitCode;
  final commandRunner = CommandRunner<int>(
    'devtools-profiler',
    'Profile Dart and Flutter apps and analyze the results.',
    out: stdoutSink.writeln,
    err: stderrSink.writeln,
    outRaw: stdoutSink.write,
    errRaw: stderrSink.write,
    usageExitCode: _usageExitCode,
    setExitCode: (code) => exitCode = code,
    ansi: output != null ? false : null,
  )
    ..addCommand(_RunCommand(profiler))
    ..addCommand(_AttachCommand(profiler))
    ..addCommand(_SummarizeCommand(profiler))
    ..addCommand(_ExplainCommand(profiler))
    ..addCommand(_CompareCommand(profiler))
    ..addCommand(_TrendsCommand(profiler))
    ..addCommand(_InspectCommand(profiler))
    ..addCommand(_CompareMethodCommand(profiler))
    ..addCommand(_SearchMethodsCommand(profiler))
    ..addCommand(_McpCommand(profiler));

  try {
    final result = await commandRunner.run(arguments);
    return result ?? exitCode;
  } on FormatException catch (error) {
    stderrSink.writeln(error.message);
    return _usageExitCode;
  } catch (error) {
    stderrSink.writeln(error);
    return _softwareExitCode;
  }
}
