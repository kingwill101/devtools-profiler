import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;

Future<void> main() async {
  final artifactRoot = await Directory.systemTemp.createTemp(
    'devtools_profiler_core_interrupt_helper.',
  );
  final result = await ProfileRunner().run(
    ProfileRunRequest(
      command: const ['dart', 'run', 'bin/interrupt_parent.dart'],
      artifactDirectory: path.join(artifactRoot.path, 'session'),
      environment: {'DEVTOOLS_PROFILER_TEST_PARENT_PID': '$pid'},
      handleInterruptSignals: true,
      workingDirectory: Directory.current.path,
    ),
  );

  stdout.writeln(
    jsonEncode({
      'artifactRoot': artifactRoot.path,
      'artifactDirectory': result.artifactDirectory,
      'terminatedByProfiler': result.terminatedByProfiler,
      'warnings': result.warnings,
      'sampleCount': result.overallProfile?.sampleCount,
      'sessionJson': path.join(result.artifactDirectory, 'session.json'),
    }),
  );
}
