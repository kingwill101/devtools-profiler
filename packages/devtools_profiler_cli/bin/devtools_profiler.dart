#!/usr/bin/env dart

import 'dart:io';

import 'package:devtools_profiler_cli/devtools_profiler_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments);
}
