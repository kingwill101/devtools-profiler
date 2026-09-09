@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File executable;
  late File target;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('profiler_output.');
    addTearDown(() => directory.delete(recursive: true));
    executable = File('${directory.path}/profiler.exe');
    target = File('${directory.path}/target.dart');
    await target.writeAsString('''
import 'dart:io';

void main() {
  stdout.writeln('target stdout marker');
  stderr.writeln('target stderr marker');
}
''');

    // Resolve the entrypoint from either the workspace or package directory.
    final entrypoint = File('bin/devtools_profiler.dart').existsSync()
        ? 'bin/devtools_profiler.dart'
        : 'packages/devtools_profiler_cli/bin/devtools_profiler.dart';
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      entrypoint,
      '-o',
      executable.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  for (final forwardOutput in [true, false]) {
    test(
      'native JSON capture keeps stdout clean with forwarding=$forwardOutput',
      () async {
        final result = await Process.run(executable.path, [
          'run',
          '--json',
          if (!forwardOutput) '--no-forward-output',
          '--artifact-dir',
          '${directory.path}/session-$forwardOutput',
          '--',
          'dart',
          target.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final json =
            jsonDecode(result.stdout as String) as Map<String, Object?>;
        expect(json['exitCode'], 0);
        expect(json['overallProfile'], isA<Map<String, Object?>>());
        for (final marker in ['target stdout marker', 'target stderr marker']) {
          expect(result.stdout, isNot(contains(marker)));
          expect(
            result.stderr,
            forwardOutput ? contains(marker) : isNot(contains(marker)),
          );
        }
      },
    );
  }
}
