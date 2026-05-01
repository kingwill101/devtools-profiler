import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_cli/devtools_profiler_cli.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test('run help shows the target command separator and examples', () async {
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['run', '--help'],
      runner: _FakeProfileRunner(),
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();
    await stderrCapture.flush();

    expect(exitCode, 0);
    expect(
      stdoutCapture.text,
      contains(
        'devtools-profiler run [options] [--] <dart-file|dart-or-flutter-command>',
      ),
    );
    expect(stdoutCapture.text, contains('Examples:'));
    expect(stdoutCapture.text, contains('devtools-profiler run bin/main.dart'));
    expect(
      stdoutCapture.text,
      contains('devtools-profiler run -- dart run bin/main.dart'),
    );
    expect(
      stdoutCapture.text,
      contains('devtools-profiler run --terminal -- dart run bin/tui.dart'),
    );
    expect(stdoutCapture.text, contains('--terminal'));
    expect(
      stdoutCapture.text,
      contains(
        'devtools-profiler run --duration 15s --cwd path/to/flutter_app -- flutter run -d linux -t lib/main.dart',
      ),
    );
    expect(stderrCapture.text, isEmpty);
  });

  test('attach help shows bounded VM service profiling examples', () async {
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['attach', '--help'],
      runner: _FakeProfileRunner(),
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();
    await stderrCapture.flush();

    expect(exitCode, 0);
    expect(
      stdoutCapture.text,
      contains('devtools-profiler attach [options] <vm-service-uri>'),
    );
    expect(stdoutCapture.text, contains('Examples:'));
    expect(
      stdoutCapture.text,
      contains(
        'devtools-profiler attach --duration 15s http://127.0.0.1:8181/abcd/',
      ),
    );
    expect(stderrCapture.text, isEmpty);
  });

  test('run prints json output for a profiling session', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['run', '--json', '--', 'dart', 'run', 'bin/main.dart'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(runner.lastRunRequest?.command, ['dart', 'run', 'bin/main.dart']);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    expect(json['sessionId'], 'session-1');
    expect(json['overallProfile'], isA<Map<String, Object?>>());
    expect(stderrCapture.text, isEmpty);
  });

  test('run accepts flutter commands', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['run', '--json', '--', 'flutter', 'test', 'test/widget_test.dart'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(runner.lastRunRequest?.command, [
      'flutter',
      'test',
      'test/widget_test.dart',
    ]);
    expect(stderrCapture.text, isEmpty);
  });

  test('run forwards duration to the profiler backend', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'run',
        '--json',
        '--duration',
        '3s',
        '--vm-service-timeout',
        '2m',
        '--',
        'flutter',
        'run',
        '-d',
        'linux',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(runner.lastRunRequest?.runDuration, const Duration(seconds: 3));
    expect(runner.lastRunRequest?.vmServiceTimeout, const Duration(minutes: 2));
  });

  test('run forwards terminal mode to the profiler backend', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['run', '--terminal', '--', 'dart', 'run', 'bin/tui.dart'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(
      runner.lastRunRequest?.processIoMode,
      ProfileProcessIoMode.inheritStdio,
    );
    expect(runner.lastRunRequest?.handleInterruptSignals, isTrue);
    expect(runner.lastRunRequest?.command, ['dart', 'run', 'bin/tui.dart']);
    expect(
      stdoutCapture.text,
      contains('devtools-profiler run --terminal --cwd'),
    );
  });

  test('run rejects terminal mode with json output', () async {
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'run',
        '--json',
        '--terminal',
        '--',
        'dart',
        'run',
        'bin/tui.dart',
      ],
      runner: _FakeProfileRunner(),
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stderrCapture.flush();

    expect(exitCode, isNot(0));
    expect(stderrCapture.text, contains('--terminal cannot be combined'));
  });

  test('attach profiles an existing VM service URI', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'attach',
        '--json',
        '--duration',
        '2s',
        '--cwd',
        '/tmp/app',
        'http://127.0.0.1:8181/abcd/',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(
      runner.lastAttachRequest?.vmServiceUri,
      Uri.parse('http://127.0.0.1:8181/abcd/'),
    );
    expect(runner.lastAttachRequest?.duration, const Duration(seconds: 2));
    expect(runner.lastAttachRequest?.workingDirectory, '/tmp/app');
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    expect(json['sessionId'], 'session-attach');
    expect(json['command'], ['attach', 'http://127.0.0.1:8181/abcd/']);
    expect(stderrCapture.text, contains('Attach mode captures'));
    expect(stderrCapture.text, contains('devtools-profiler run'));
  });

  test('run prints json output with a call tree when expanded', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['run', '--json', '--expand', '--', 'dart', 'run', 'bin/main.dart'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    final regions = json['regions'] as List<Object?>;
    final region = regions.single as Map<String, Object?>;
    final callTree = region['callTree'] as Map<String, Object?>;
    final root = callTree['root'] as Map<String, Object?>;
    expect(root['name'], 'all');
    expect(
      ((root['children'] as List<Object?>).single
          as Map<String, Object?>)['name'],
      'Worker.run',
    );
    expect(stderrCapture.text, isEmpty);
  });

  test('run prints artisanal session output for a profiling session', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['run', '--', 'dart', 'run', 'bin/main.dart'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('Profiler Session'));
    expect(stdoutCapture.text, contains('Session'));
    expect(stdoutCapture.text, contains('session-1'));
    expect(stdoutCapture.text, contains('Whole Session'));
    expect(stdoutCapture.text, contains('Regions'));
    expect(stdoutCapture.text, contains('Region Details'));
    expect(stdoutCapture.text, contains('Top Self Frames'));
    expect(stdoutCapture.text, contains('cpu-burn'));
    expect(stdoutCapture.text, contains('Worker.hotLeaf'));
    expect(stderrCapture.text, isEmpty);
  });

  test('run prints a call tree when expanded', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['run', '--expand', '--', 'dart', 'run', 'bin/main.dart'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('Call Tree (top-down'));
    expect(stdoutCapture.text, contains('all [samples 10]'));
    expect(
      stdoutCapture.text,
      contains('Worker.run - (package:fixture/run.dart) [self 2, total 10'),
    );
    expect(
      stdoutCapture.text,
      contains('Worker.hotLeaf - (package:fixture/hot_leaf.dart)'),
    );
    expect(stderrCapture.text, isEmpty);
  });

  test('run prints json output with a bottom-up tree when requested', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'run',
        '--json',
        '--bottom-up',
        '--hide-sdk',
        '--',
        'dart',
        'run',
        'bin/main.dart',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    final region =
        (json['regions'] as List<Object?>).single as Map<String, Object?>;
    final bottomUpTree = region['bottomUpTree'] as Map<String, Object?>;
    expect(bottomUpTree['view'], 'bottomUp');
    final root = bottomUpTree['root'] as Map<String, Object?>;
    expect(
      ((root['children'] as List<Object?>).first
          as Map<String, Object?>)['name'],
      'Worker.run',
    );
    expect(
      ((root['children'] as List<Object?>)[1] as Map<String, Object?>)['name'],
      'Worker.hotLeaf',
    );
    expect(stderrCapture.text, isEmpty);
  });

  test('run prints a bottom-up tree when requested', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'run',
        '--bottom-up',
        '--hide-sdk',
        '--',
        'dart',
        'run',
        'bin/main.dart',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('Bottom Up Tree (bottom-up'));
    expect(
      stdoutCapture.text,
      contains('Worker.run - (package:fixture/run.dart) [self 2, total 10'),
    );
    expect(
      stdoutCapture.text,
      contains(
        'Worker.hotLeaf - (package:fixture/hot_leaf.dart) [self 8, total 8',
      ),
    );
    expect(stderrCapture.text, isEmpty);
  });

  test('run prints json output with a method table when requested', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'run',
        '--json',
        '--method-table',
        '--hide-sdk',
        '--',
        'dart',
        'run',
        'bin/main.dart',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    final region =
        (json['regions'] as List<Object?>).single as Map<String, Object?>;
    final methodTable = region['methodTable'] as Map<String, Object?>;
    final methods = methodTable['methods'] as List<Object?>;
    expect((methods.first as Map<String, Object?>)['name'], 'Worker.run');
    expect((methods[1] as Map<String, Object?>)['name'], 'Worker.hotLeaf');
    final callees =
        (methods.first as Map<String, Object?>)['callees'] as List<Object?>;
    expect((callees.single as Map<String, Object?>)['name'], 'Worker.hotLeaf');
    expect(stderrCapture.text, isEmpty);
  });

  test('run prints a method table when requested', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'run',
        '--method-table',
        '--hide-sdk',
        '--',
        'dart',
        'run',
        'bin/main.dart',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('Method Table'));
    expect(stdoutCapture.text, contains('Method Graph: Worker.run'));
    expect(stdoutCapture.text, contains('Callers'));
    expect(stdoutCapture.text, contains('Callees'));
    expect(stderrCapture.text, isEmpty);
  });

  test('run hides sdk frames when requested', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'run',
        '--expand',
        '--hide-sdk',
        '--',
        'dart',
        'run',
        'bin/main.dart',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('sdk hidden'));
    expect(stdoutCapture.text, isNot(contains('future_impl.dart')));
    expect(stderrCapture.text, isEmpty);
  });

  test(
    'summarize prints session and region detail output for a session artifact',
    () async {
      final runner = _FakeProfileRunner();
      final stdoutCapture = _OutputCapture();
      final stderrCapture = _OutputCapture();
      addTearDown(() async {
        await stdoutCapture.close();
        await stderrCapture.close();
      });

      final exitCode = await runCli(
        const ['summarize', '/tmp/artifacts/session-1'],
        runner: runner,
        output: stdoutCapture.sink,
        errorOutput: stderrCapture.sink,
      );
      await stdoutCapture.flush();

      expect(exitCode, 0);
      expect(stdoutCapture.text, contains('Profiler Session'));
      expect(stdoutCapture.text, contains('Regions'));
      expect(stdoutCapture.text, contains('Region Details'));
      expect(stdoutCapture.text, contains('Top Self Frames'));
      expect(stdoutCapture.text, contains('cpu-burn'));
      expect(stderrCapture.text, isEmpty);
    },
  );

  test(
    'summarize prints artisanal region output for a region artifact',
    () async {
      final runner = _FakeProfileRunner();
      final stdoutCapture = _OutputCapture();
      final stderrCapture = _OutputCapture();
      addTearDown(() async {
        await stdoutCapture.close();
        await stderrCapture.close();
      });

      final exitCode = await runCli(
        const [
          'summarize',
          '/tmp/artifacts/session-1/regions/region-1/summary.json',
        ],
        runner: runner,
        output: stdoutCapture.sink,
        errorOutput: stderrCapture.sink,
      );
      await stdoutCapture.flush();

      expect(exitCode, 0);
      expect(stdoutCapture.text, contains('Region Summary'));
      expect(stdoutCapture.text, contains('Top Self Frames'));
      expect(stdoutCapture.text, contains('Top Total Frames'));
      expect(stdoutCapture.text, contains('phase'));
      expect(stdoutCapture.text, contains('fixture'));
      expect(stdoutCapture.text, contains('Worker.hotLeaf'));
      expect(stderrCapture.text, isEmpty);
    },
  );

  test('explain prints json output with hotspot insights', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['explain', '--json', '/tmp/profile.json'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    expect(json['kind'], 'hotspotExplanation');
    final hotspots = json['hotspots'] as Map<String, Object?>;
    expect(hotspots['status'], 'analyzed');
    final insights = hotspots['insights'] as List<Object?>;
    final selfInsight = insights.cast<Map<String, Object?>>().firstWhere(
      (insight) => insight['kind'] == 'selfFrame',
    );
    final path = selfInsight['path'] as Map<String, Object?>;
    final frames = path['frames'] as List<Object?>;
    expect((frames.first as Map<String, Object?>)['name'], 'all');
    expect((frames[1] as Map<String, Object?>)['name'], 'Worker.run');
    expect((frames.last as Map<String, Object?>)['name'], 'Worker.hotLeaf');
    final bottomUpPath = selfInsight['bottomUpPath'] as Map<String, Object?>;
    final bottomUpFrames = bottomUpPath['frames'] as List<Object?>;
    expect(
      (bottomUpFrames[1] as Map<String, Object?>)['name'],
      'Worker.hotLeaf',
    );
    final focusMethod = selfInsight['focusMethod'] as Map<String, Object?>;
    expect(focusMethod['name'], 'Worker.hotLeaf');
    expect(focusMethod['methodId'], contains('Worker.hotLeaf'));
    expect(stderrCapture.text, isEmpty);
  });

  test('explain prints artisanal hotspot output', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['explain', '/tmp/profile.json'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('Hotspot Explanation'));
    expect(stdoutCapture.text, contains('Hotspot Insights'));
    expect(stdoutCapture.text, contains('Self time is concentrated'));
    expect(
      stdoutCapture.text,
      contains('Path: all -> Worker.run - (package:fixture/run.dart)'),
    );
    expect(stdoutCapture.text, contains('Bottom up: all -> Worker.hotLeaf'));
    expect(
      stdoutCapture.text,
      contains('Inspect: Worker.hotLeaf - (package:fixture/hot_leaf.dart)'),
    );
    expect(stdoutCapture.text, contains('Profile Summary'));
    expect(stderrCapture.text, isEmpty);
  });

  test('inspect prints json output with method inspection details', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'inspect',
        '--json',
        '--method',
        'Worker.hotLeaf',
        '/tmp/profile.json',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    expect(json['kind'], 'methodInspection');
    final inspection = json['inspection'] as Map<String, Object?>;
    expect(inspection['status'], 'found');
    final method = inspection['method'] as Map<String, Object?>;
    expect(method['name'], 'Worker.hotLeaf');
    final topDownPaths = inspection['topDownPaths'] as List<Object?>;
    final frames =
        (topDownPaths.single as Map<String, Object?>)['frames']
            as List<Object?>;
    expect((frames.first as Map<String, Object?>)['name'], 'all');
    expect((frames.last as Map<String, Object?>)['name'], 'Worker.hotLeaf');
    expect(stderrCapture.text, isEmpty);
  });

  test('inspect prints artisanal method inspection output', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['inspect', '--method', 'Worker.hotLeaf', '/tmp/profile.json'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('Method Inspection'));
    expect(stdoutCapture.text, contains('Method Summary'));
    expect(stdoutCapture.text, contains('Worker.hotLeaf'));
    expect(stdoutCapture.text, contains('Top Down Paths'));
    expect(stdoutCapture.text, contains('Bottom Up Paths'));
    expect(stderrCapture.text, isEmpty);
  });

  test('compare-method prints json output with method deltas', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'compare-method',
        '--json',
        '--method',
        'Worker.hotLeaf',
        '/tmp/artifacts/session-1',
        '/tmp/artifacts/session-2',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    expect(json['kind'], 'methodComparison');
    final comparison = json['comparison'] as Map<String, Object?>;
    expect(comparison['status'], 'compared');
    final methodDelta = comparison['methodDelta'] as Map<String, Object?>;
    expect(methodDelta['name'], 'Worker.hotLeaf');
    expect((methodDelta['selfSamples'] as Map<String, Object?>)['delta'], 6);
    final callerDeltas = comparison['callerDeltas'] as List<Object?>;
    expect(
      callerDeltas
          .cast<Map<String, Object?>>()
          .map((delta) => delta['name'])
          .toList(),
      containsAll(['_Future._completeWithValue', 'Worker.run']),
    );
    expect(stderrCapture.text, isEmpty);
  });

  test('compare-method prints artisanal method comparison output', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'compare-method',
        '--method',
        'Worker.hotLeaf',
        '/tmp/artifacts/session-1',
        '/tmp/artifacts/session-2',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('Method Comparison'));
    expect(stdoutCapture.text, contains('Method Delta'));
    expect(stdoutCapture.text, contains('Caller Deltas'));
    expect(stdoutCapture.text, contains('Worker.hotLeaf'));
    expect(stderrCapture.text, isEmpty);
  });

  test('search-methods prints json output with ranked matches', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'search-methods',
        '--json',
        '--query',
        'Worker',
        '/tmp/profile.json',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    expect(json['kind'], 'methodSearch');
    final search = json['search'] as Map<String, Object?>;
    expect(search['status'], 'available');
    expect(search['totalMatches'], 2);
    final methods = search['methods'] as List<Object?>;
    expect(
      methods
          .cast<Map<String, Object?>>()
          .map((method) => method['name'])
          .toList(),
      ['Worker.run', 'Worker.hotLeaf'],
    );
    expect(stderrCapture.text, isEmpty);
  });

  test('search-methods prints artisanal method search output', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['search-methods', '--query', 'Worker', '/tmp/profile.json'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('Method Search'));
    expect(stdoutCapture.text, contains('Matches'));
    expect(stdoutCapture.text, contains('Worker.run'));
    expect(stdoutCapture.text, contains('Worker.hotLeaf'));
    expect(stderrCapture.text, isEmpty);
  });

  test('compare prints json output for two session artifacts', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'compare',
        '--json',
        '--method-table',
        '/tmp/artifacts/session-1',
        '/tmp/artifacts/session-2',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    expect(json['kind'], 'profileComparison');
    final baseline = json['baseline'] as Map<String, Object?>;
    final current = json['current'] as Map<String, Object?>;
    expect(baseline['selectedProfileId'], 'overall');
    expect(current['selectedProfileId'], 'overall');
    final comparison = json['comparison'] as Map<String, Object?>;
    final durationMicros = comparison['durationMicros'] as Map<String, Object?>;
    expect(durationMicros['delta'], 900);
    final regressions = json['regressions'] as Map<String, Object?>;
    expect(regressions['status'], 'regressed');
    final insights = regressions['insights'] as List<Object?>;
    expect((insights.first as Map<String, Object?>)['kind'], 'duration');
    final methods = comparison['methods'] as List<Object?>;
    expect((methods.first as Map<String, Object?>)['name'], 'Worker.hotLeaf');
    expect(stderrCapture.text, isEmpty);
  });

  test(
    'json cli commands omit profile selectors for artifact targets',
    () async {
      const baselinePath =
          '/tmp/artifacts/session-1/regions/region-1/summary.json';
      const currentPath =
          '/tmp/artifacts/session-2/regions/region-2/summary.json';

      final explain = await _runJsonCommand(['explain', '--json', currentPath]);
      expect(explain['cliCommand'], 'devtools-profiler explain $currentPath');

      final inspect = await _runJsonCommand([
        'inspect',
        '--json',
        '--method',
        'Worker.hotLeaf',
        currentPath,
      ]);
      expect(
        inspect['cliCommand'],
        'devtools-profiler inspect --method Worker.hotLeaf $currentPath',
      );

      final search = await _runJsonCommand([
        'search-methods',
        '--json',
        '--query',
        'Worker',
        currentPath,
      ]);
      expect(
        search['cliCommand'],
        'devtools-profiler search-methods --query Worker --sort total '
        '$currentPath',
      );

      final compare = await _runJsonCommand([
        'compare',
        '--json',
        baselinePath,
        currentPath,
      ]);
      expect(
        compare['cliCommand'],
        'devtools-profiler compare $baselinePath $currentPath',
      );

      final compareMethod = await _runJsonCommand([
        'compare-method',
        '--json',
        '--method',
        'Worker.hotLeaf',
        baselinePath,
        currentPath,
      ]);
      expect(
        compareMethod['cliCommand'],
        'devtools-profiler compare-method --method Worker.hotLeaf '
        '$baselinePath $currentPath',
      );
    },
  );

  test('compare treats memory-class-limit 0 as unlimited', () async {
    final runner = _FakeMemoryProfileRunner();
    final json = await _runJsonCommand(const [
      'compare',
      '--json',
      '--min-live-bytes',
      '512',
      '--memory-class-limit',
      '0',
      '/tmp/memory/session-1',
      '/tmp/memory/session-2',
    ], runner: runner);

    expect(runner.readMemoryTopClassCounts, [0, 0]);
    expect(
      json['cliCommand'],
      'devtools-profiler compare --min-live-bytes 512 '
      '--memory-class-limit 0 /tmp/memory/session-1 /tmp/memory/session-2',
    );
    final comparison = json['comparison'] as Map<String, Object?>;
    final memory = comparison['memory'] as Map<String, Object?>;
    final topClasses = memory['topClasses'] as List<Object?>;
    expect(topClasses, hasLength(2));
  });

  test('compare warns when memory class re-read fails', () async {
    final runner = _FakeMemoryProfileRunner(failMemoryReads: true);
    final json = await _runJsonCommand(const [
      'compare',
      '--json',
      '--min-live-bytes',
      '512',
      '/tmp/memory/session-1',
      '/tmp/memory/session-2',
    ], runner: runner);

    final warnings = json['preparationWarnings'] as List<Object?>;
    expect(
      warnings,
      contains(
        allOf(
          contains('readMemoryClasses could not build baselineMemoryOverride'),
          contains('minLiveBytes=512'),
          contains('memoryClassLimit=default'),
        ),
      ),
    );
    expect(
      warnings,
      contains(
        allOf(
          contains('readMemoryClasses could not build currentMemoryOverride'),
          contains('minLiveBytes=512'),
          contains('memoryClassLimit=default'),
        ),
      ),
    );
  });

  test('compare rejects negative memory options', () async {
    final limitResult = await _runCliCommand(const [
      'compare',
      '--memory-class-limit',
      '-1',
      '/tmp/artifacts/session-1',
      '/tmp/artifacts/session-2',
    ]);

    expect(limitResult.exitCode, 64);
    expect(
      limitResult.stderr,
      contains('"memory-class-limit" option must be a non-negative integer'),
    );

    final minLiveBytesResult = await _runCliCommand(const [
      'compare',
      '--min-live-bytes',
      '-1',
      '/tmp/artifacts/session-1',
      '/tmp/artifacts/session-2',
    ]);

    expect(minLiveBytesResult.exitCode, 64);
    expect(
      minLiveBytesResult.stderr,
      contains('"min-live-bytes" option must be a non-negative integer'),
    );
  });

  test('compare prints artisanal delta output', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const ['compare', '/tmp/artifacts/session-1', '/tmp/artifacts/session-2'],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('Profile Comparison'));
    expect(stdoutCapture.text, contains('Delta Summary'));
    expect(stdoutCapture.text, contains('Regression Insights'));
    expect(stdoutCapture.text, contains('Overall duration increased'));
    expect(stdoutCapture.text, contains('Top Self Frame Deltas'));
    expect(stdoutCapture.text, contains('Worker.hotLeaf'));
    expect(stderrCapture.text, isEmpty);
  });

  test('trends prints json output for a multi-session series', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'trends',
        '--json',
        '/tmp/artifacts/session-1',
        '/tmp/artifacts/session-2',
        '/tmp/artifacts/session-3',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    expect(json['kind'], 'profileTrends');
    final trends = json['trends'] as Map<String, Object?>;
    expect(trends['status'], 'regressing');
    final points = trends['points'] as List<Object?>;
    expect(points, hasLength(3));
    final recurring = trends['recurringRegressions'] as List<Object?>;
    expect(
      recurring.cast<Map<String, Object?>>().any(
        (item) => item['subject'] == 'Worker.hotLeaf',
      ),
      isTrue,
    );
    expect(stderrCapture.text, isEmpty);
  });

  test('trends json cli command preserves session profile selection', () async {
    final json = await _runJsonCommand(const [
      'trends',
      '--json',
      '--profile-id',
      'startup',
      '/tmp/artifacts/session-1',
      '/tmp/artifacts/session-2',
      '/tmp/artifacts/session-3',
    ], runner: _FakeProfileRunnerWithSharedTrendRegion());

    expect(
      json['cliCommand'],
      'devtools-profiler trends --profile-id startup '
      '/tmp/artifacts/session-1 /tmp/artifacts/session-2 '
      '/tmp/artifacts/session-3',
    );
    final targets = json['targets'] as List<Object?>;
    expect(
      targets.cast<Map<String, Object?>>().map(
        (target) => target['selectedProfileId'],
      ),
      everyElement('startup'),
    );
  });

  test('trends prints artisanal trend output', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'trends',
        '/tmp/artifacts/session-1',
        '/tmp/artifacts/session-2',
        '/tmp/artifacts/session-3',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('Profile Trends'));
    expect(stdoutCapture.text, contains('Series'));
    expect(stdoutCapture.text, contains('Recurring Regressions'));
    expect(stdoutCapture.text, contains('Step Changes'));
    expect(stdoutCapture.text, contains('Worker.hotLeaf'));
    expect(stderrCapture.text, isEmpty);
  });

  test('inspect-classes prints json memory class output', () async {
    final runner = _FakeMemoryProfileRunner();
    final json = await _runJsonCommand(const [
      'inspect-classes',
      '--json',
      '--class',
      'Love',
      '--min-live-bytes',
      '512',
      '--limit',
      '1',
      '/tmp/memory/session-1',
    ], runner: runner);

    expect(json['kind'], 'memoryClassInspection');
    expect(json['classQuery'], 'Love');
    expect(json['minLiveBytes'], 512);
    expect(json['topClassCount'], 1);
    expect(
      json['cliCommand'],
      'devtools-profiler inspect-classes --class Love --min-live-bytes 512 '
      '--limit 1 /tmp/memory/session-1',
    );
    expect(runner.lastReadMemoryPath, '/tmp/memory/session-1');
    expect(runner.lastMemoryClassQuery, 'Love');
    expect(runner.lastMinLiveBytes, 512);
    expect(runner.readMemoryTopClassCounts, [1]);
    final classes = json['classes'] as List<Object?>;
    expect(classes, hasLength(1));
    expect((classes.single as Map<String, Object?>)['className'], 'LoveImage');
  });

  test('inspect-classes prints artisanal memory class output', () async {
    final result = await _runCliCommand(const [
      'inspect-classes',
      '--class',
      'Love',
      '/tmp/memory/session-1',
    ], runner: _FakeMemoryProfileRunner());

    expect(result.exitCode, 0);
    expect(result.stdout, contains('Memory Class Inspection'));
    expect(result.stdout, contains('Classes'));
    expect(result.stdout, contains('LoveImage'));
    expect(result.stderr, isEmpty);
  });

  test('inspect-classes rejects negative min-live-bytes', () async {
    final result = await _runCliCommand(const [
      'inspect-classes',
      '--min-live-bytes',
      '-1',
      '/tmp/memory/session-1',
    ]);

    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains('"min-live-bytes" option must be a non-negative integer'),
    );
  });

  test('summarize hides runtime helper packages when requested', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'summarize',
        '--json',
        '--hide-runtime-helpers',
        '/tmp/helper_profile.json',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    final json = jsonDecode(stdoutCapture.text) as Map<String, Object?>;
    final topTotalFrames = json['topTotalFrames'] as List<Object?>;
    expect(
      topTotalFrames.any(
        (frame) =>
            (frame as Map<String, Object?>)['name'] == 'JsonRpcClient.send',
      ),
      isFalse,
    );
    expect(stderrCapture.text, isEmpty);
  });

  test('summarize warns when active filters remove every CPU frame', () async {
    final runner = _FakeProfileRunner();
    final stdoutCapture = _OutputCapture();
    final stderrCapture = _OutputCapture();
    addTearDown(() async {
      await stdoutCapture.close();
      await stderrCapture.close();
    });

    final exitCode = await runCli(
      const [
        'summarize',
        '--include-package',
        'missing_package',
        '/tmp/profile.json',
      ],
      runner: runner,
      output: stdoutCapture.sink,
      errorOutput: stderrCapture.sink,
    );
    await stdoutCapture.flush();

    expect(exitCode, 0);
    expect(stdoutCapture.text, contains('available before filtering'));
    expect(stdoutCapture.text, contains('--include-package missing_package'));
    expect(stdoutCapture.text, contains('Retry without those filters'));
    expect(stderrCapture.text, isEmpty);
  });

  group('prepareRegionPresentation sample-count fallback', () {
    test(
      'emits warning and preserves stored count when raw profile produces 0 samples',
      () async {
        final stdoutCapture = _OutputCapture();
        final stderrCapture = _OutputCapture();
        addTearDown(() async {
          await stdoutCapture.close();
          await stderrCapture.close();
        });

        final exitCode = await runCli(
          const ['run', '--', 'dart', 'run', 'bin/main.dart'],
          runner: _FakeRunnerWithZeroSamples(),
          output: stdoutCapture.sink,
          errorOutput: stderrCapture.sink,
        );
        await stdoutCapture.flush();
        await stderrCapture.flush();

        expect(exitCode, 0);
        expect(
          stdoutCapture.text,
          contains('0 samples when re-read'),
          reason: 'warning about zero re-read samples should appear',
        );
        expect(
          stdoutCapture.text,
          contains('50 samples'),
          reason: 'warning should mention the stored sample count',
        );
        expect(stderrCapture.text, isEmpty);
      },
    );

    test(
      'no warning emitted when raw CPU profile produces non-zero samples',
      () async {
        final stdoutCapture = _OutputCapture();
        final stderrCapture = _OutputCapture();
        addTearDown(() async {
          await stdoutCapture.close();
          await stderrCapture.close();
        });

        final exitCode = await runCli(
          const ['run', '--', 'dart', 'run', 'bin/main.dart'],
          runner: _FakeProfileRunner(),
          output: stdoutCapture.sink,
          errorOutput: stderrCapture.sink,
        );
        await stdoutCapture.flush();
        await stderrCapture.flush();

        expect(exitCode, 0);
        expect(
          stdoutCapture.text,
          isNot(contains('produced 0 samples when re-read')),
          reason: 'no fallback warning when samples are healthy',
        );
        expect(stderrCapture.text, isEmpty);
      },
    );
  });
}

Future<Map<String, Object?>> _runJsonCommand(
  List<String> arguments, {
  ProfileRunner? runner,
}) async {
  final result = await _runCliCommand(
    arguments,
    runner: runner ?? _FakeProfileRunner(),
  );

  expect(result.exitCode, 0, reason: result.stderr);
  expect(result.stderr, isEmpty);
  return jsonDecode(result.stdout) as Map<String, Object?>;
}

Future<({int exitCode, String stdout, String stderr})> _runCliCommand(
  List<String> arguments, {
  ProfileRunner? runner,
}) async {
  final stdoutCapture = _OutputCapture();
  final stderrCapture = _OutputCapture();
  addTearDown(() async {
    await stdoutCapture.close();
    await stderrCapture.close();
  });

  final exitCode = await runCli(
    arguments,
    runner: runner ?? _FakeProfileRunner(),
    output: stdoutCapture.sink,
    errorOutput: stderrCapture.sink,
  );
  await stdoutCapture.flush();
  await stderrCapture.flush();

  return (
    exitCode: exitCode,
    stdout: stdoutCapture.text,
    stderr: stderrCapture.text,
  );
}

class _FakeProfileRunner extends ProfileRunner {
  ProfileRunRequest? lastRunRequest;
  ProfileAttachRequest? lastAttachRequest;

  static final _workerClass = ClassRef(id: 'classes/worker', name: 'Worker');

  static final _cpuSamples = CpuSamples(
    sampleCount: 10,
    samplePeriod: 50,
    timeOriginMicros: 100,
    timeExtentMicros: 2_000,
    functions: [
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/hot_leaf',
          name: 'hotLeaf',
          owner: _workerClass,
        ),
        resolvedUrl: 'package:fixture/hot_leaf.dart',
      ),
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/run',
          name: 'run',
          owner: _workerClass,
        ),
        resolvedUrl: 'package:fixture/run.dart',
      ),
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/complete',
          name: '_completeWithValue',
          owner: ClassRef(id: 'classes/future', name: '_Future'),
        ),
        resolvedUrl: 'org-dartlang-sdk:///sdk/lib/async/future_impl.dart',
      ),
    ],
    samples: [
      for (var i = 0; i < 8; i++)
        CpuSample(timestamp: 100 + i, stack: [0, 2, 1]),
      CpuSample(timestamp: 109, stack: const [1]),
      CpuSample(timestamp: 110, stack: const [1]),
    ],
  );

  static final _cpuSamplesCurrent = CpuSamples(
    sampleCount: 14,
    samplePeriod: 50,
    timeOriginMicros: 100,
    timeExtentMicros: 2_900,
    functions: _cpuSamples.functions,
    samples: [
      for (var i = 0; i < 9; i++)
        CpuSample(timestamp: 100 + i, stack: [0, 2, 1]),
      for (var i = 0; i < 5; i++) CpuSample(timestamp: 109 + i, stack: [0, 1]),
    ],
  );

  static final _cpuSamplesTrend = CpuSamples(
    sampleCount: 18,
    samplePeriod: 50,
    timeOriginMicros: 100,
    timeExtentMicros: 3_600,
    functions: _cpuSamples.functions,
    samples: [
      for (var i = 0; i < 11; i++)
        CpuSample(timestamp: 100 + i, stack: [0, 2, 1]),
      for (var i = 0; i < 7; i++) CpuSample(timestamp: 112 + i, stack: [0, 1]),
    ],
  );

  static final _cpuSamplesWithHelper = CpuSamples(
    sampleCount: 11,
    samplePeriod: 50,
    timeOriginMicros: 100,
    timeExtentMicros: 2_100,
    functions: [
      ..._cpuSamples.functions!,
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/json_rpc',
          name: 'send',
          owner: ClassRef(id: 'classes/json_rpc', name: 'JsonRpcClient'),
        ),
        resolvedUrl: 'package:json_rpc_2/json_rpc_2.dart',
      ),
    ],
    samples: [
      for (var i = 0; i < 8; i++)
        CpuSample(timestamp: 100 + i, stack: [0, 2, 1]),
      CpuSample(timestamp: 109, stack: const [1]),
      CpuSample(timestamp: 110, stack: const [1]),
      CpuSample(timestamp: 111, stack: const [3, 1]),
    ],
  );

  static final _cpuSamplesEmpty = CpuSamples(
    sampleCount: 0,
    samplePeriod: 0,
    timeOriginMicros: 0,
    timeExtentMicros: 0,
    functions: const [],
    samples: const [],
  );

  static final _region = ProfileRegionResult(
    regionId: 'region-1',
    name: 'cpu-burn',
    attributes: const {'phase': 'fixture'},
    isolateId: 'isolates/123',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 100,
    endTimestampMicros: 2_100,
    durationMicros: 2_000,
    sampleCount: 10,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/artifacts/session-1/regions/region-1/summary.json',
    rawProfilePath:
        '/tmp/artifacts/session-1/regions/region-1/cpu_profile.json',
  );

  static final _overallProfile = ProfileRegionResult(
    regionId: 'overall',
    name: 'whole-session',
    attributes: const {'scope': 'session'},
    isolateId: 'isolates/123',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 0,
    endTimestampMicros: 2_100,
    durationMicros: 2_100,
    sampleCount: 10,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/artifacts/session-1/overall/summary.json',
    rawProfilePath: '/tmp/artifacts/session-1/overall/cpu_profile.json',
  );

  static final _session = ProfileRunResult(
    sessionId: 'session-1',
    command: ['dart', 'run', 'bin/main.dart'],
    workingDirectory: '/workspace',
    exitCode: 0,
    artifactDirectory: '/tmp/artifacts/session-1',
    vmServiceUri: 'http://127.0.0.1:8181/abcd/',
    overallProfile: _overallProfile,
    regions: [_region],
    warnings: const [],
  );

  static final _regionCurrent = ProfileRegionResult(
    regionId: 'region-2',
    name: 'cpu-burn',
    attributes: const {'phase': 'fixture'},
    isolateId: 'isolates/123',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 100,
    endTimestampMicros: 3_000,
    durationMicros: 2_900,
    sampleCount: 14,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/artifacts/session-2/regions/region-2/summary.json',
    rawProfilePath:
        '/tmp/artifacts/session-2/regions/region-2/cpu_profile.json',
  );

  static final _overallProfileCurrent = ProfileRegionResult(
    regionId: 'overall',
    name: 'whole-session',
    attributes: const {'scope': 'session'},
    isolateId: 'isolates/123',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 0,
    endTimestampMicros: 3_000,
    durationMicros: 3_000,
    sampleCount: 14,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/artifacts/session-2/overall/summary.json',
    rawProfilePath: '/tmp/artifacts/session-2/overall/cpu_profile.json',
  );

  static final _sessionCurrent = ProfileRunResult(
    sessionId: 'session-2',
    command: ['dart', 'run', 'bin/main.dart'],
    workingDirectory: '/workspace',
    exitCode: 0,
    artifactDirectory: '/tmp/artifacts/session-2',
    vmServiceUri: 'http://127.0.0.1:8181/efgh/',
    overallProfile: _overallProfileCurrent,
    regions: [_regionCurrent],
    warnings: const [],
  );

  static final _regionTrend = ProfileRegionResult(
    regionId: 'region-3',
    name: 'cpu-burn',
    attributes: const {'phase': 'fixture'},
    isolateId: 'isolates/123',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 100,
    endTimestampMicros: 3_600,
    durationMicros: 3_500,
    sampleCount: 18,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/artifacts/session-3/regions/region-3/summary.json',
    rawProfilePath:
        '/tmp/artifacts/session-3/regions/region-3/cpu_profile.json',
  );

  static final _overallProfileTrend = ProfileRegionResult(
    regionId: 'overall',
    name: 'whole-session',
    attributes: const {'scope': 'session'},
    isolateId: 'isolates/123',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 0,
    endTimestampMicros: 3_600,
    durationMicros: 3_600,
    sampleCount: 18,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/artifacts/session-3/overall/summary.json',
    rawProfilePath: '/tmp/artifacts/session-3/overall/cpu_profile.json',
  );

  static final _sessionTrend = ProfileRunResult(
    sessionId: 'session-3',
    command: ['dart', 'run', 'bin/main.dart'],
    workingDirectory: '/workspace',
    exitCode: 0,
    artifactDirectory: '/tmp/artifacts/session-3',
    vmServiceUri: 'http://127.0.0.1:8181/ijkl/',
    overallProfile: _overallProfileTrend,
    regions: [_regionTrend],
    warnings: const [],
  );

  static final _helperRegion = ProfileRegionResult(
    regionId: 'region-helper',
    name: 'cpu-burn',
    attributes: const {'phase': 'fixture'},
    isolateId: 'isolates/123',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 100,
    endTimestampMicros: 2_200,
    durationMicros: 2_100,
    sampleCount: 11,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/helper_profile.json',
    rawProfilePath: '/tmp/helper_profile.cpu.json',
  );

  @override
  Future<ProfileRunResult> run(ProfileRunRequest request) async {
    lastRunRequest = request;
    return ProfileRunResult(
      sessionId: _session.sessionId,
      command: request.command,
      workingDirectory: request.workingDirectory ?? '/workspace',
      exitCode: _session.exitCode,
      artifactDirectory: _session.artifactDirectory,
      vmServiceUri: _session.vmServiceUri,
      overallProfile: _session.overallProfile,
      processIoMode: request.processIoMode,
      regions: _session.regions,
      warnings: _session.warnings,
    );
  }

  @override
  Future<ProfileRunResult> attach(ProfileAttachRequest request) async {
    lastAttachRequest = request;
    return ProfileRunResult(
      sessionId: 'session-attach',
      command: ['attach', request.vmServiceUri.toString()],
      workingDirectory: request.workingDirectory ?? '/workspace',
      exitCode: 0,
      artifactDirectory: '/tmp/artifacts/session-attach',
      vmServiceUri: request.vmServiceUri.toString(),
      overallProfile: _overallProfile,
      regions: const [],
      warnings: const [],
    );
  }

  @override
  Future<Map<String, Object?>> summarizeArtifact(String path) async {
    if (path == '/tmp/artifacts/session-1') {
      return _session.toJson();
    }
    if (path == '/tmp/artifacts/session-2') {
      return _sessionCurrent.toJson();
    }
    if (path == '/tmp/artifacts/session-3') {
      return _sessionTrend.toJson();
    }
    if (path == '/tmp/artifacts/session-2/regions/region-2/summary.json') {
      return _regionCurrent.toJson();
    }
    if (path == '/tmp/helper_profile.json') {
      return _helperRegion.toJson();
    }
    return _region.toJson();
  }

  @override
  Future<CpuSamples> readCpuSamples(String targetPath) async {
    if (targetPath.contains('zero-samples')) {
      return _cpuSamplesEmpty;
    }
    if (targetPath == '/tmp/helper_profile.cpu.json') {
      return _cpuSamplesWithHelper;
    }
    if (targetPath.contains('session-3')) {
      return _cpuSamplesTrend;
    }
    if (targetPath.contains('session-2')) {
      return _cpuSamplesCurrent;
    }
    return _cpuSamples;
  }
}

class _FakeMemoryProfileRunner extends _FakeProfileRunner {
  _FakeMemoryProfileRunner({this.failMemoryReads = false});

  final bool failMemoryReads;
  String? lastReadMemoryPath;
  String? lastMemoryClassQuery;
  int? lastMinLiveBytes;
  final List<int> readMemoryTopClassCounts = [];

  static const _baselineRawMemoryPath =
      '/tmp/memory/session-1/overall/memory_profile.json';
  static const _currentRawMemoryPath =
      '/tmp/memory/session-2/overall/memory_profile.json';

  static final _memoryClasses = [
    const ProfileMemoryClassSummary(
      className: 'LoveImage',
      libraryUri: 'package:love2d/image.dart',
      liveBytes: 2048,
      liveBytesDelta: 512,
      liveInstances: 2,
      liveInstancesDelta: 1,
      allocationBytesDelta: 4096,
      allocationInstancesDelta: 4,
    ),
    const ProfileMemoryClassSummary(
      className: 'LoveCanvas',
      libraryUri: 'package:love2d/canvas.dart',
      liveBytes: 1024,
      liveBytesDelta: 256,
      liveInstances: 1,
      liveInstancesDelta: 1,
      allocationBytesDelta: 2048,
      allocationInstancesDelta: 2,
    ),
    const ProfileMemoryClassSummary(
      className: 'WorkerBuffer',
      libraryUri: 'package:fixture/buffer.dart',
      liveBytes: 256,
      liveBytesDelta: 128,
      liveInstances: 1,
      liveInstancesDelta: 0,
      allocationBytesDelta: 512,
      allocationInstancesDelta: 1,
    ),
  ];

  @override
  Future<Map<String, Object?>> summarizeArtifact(String path) async {
    return switch (path) {
      '/tmp/memory/session-1' => _sessionWithMemory(
        _FakeProfileRunner._session,
        _baselineRawMemoryPath,
      ).toJson(),
      '/tmp/memory/session-2' => _sessionWithMemory(
        _FakeProfileRunner._sessionCurrent,
        _currentRawMemoryPath,
      ).toJson(),
      _ => super.summarizeArtifact(path),
    };
  }

  @override
  Future<ProfileMemoryResult> readMemoryClasses(
    String targetPath, {
    String? classQuery,
    int? minLiveBytes,
    int topClassCount = 50,
  }) async {
    lastReadMemoryPath = targetPath;
    lastMemoryClassQuery = classQuery;
    lastMinLiveBytes = minLiveBytes;
    readMemoryTopClassCounts.add(topClassCount);
    if (failMemoryReads) {
      throw StateError('raw memory artifact unavailable');
    }

    var classes = _memoryClasses
        .where((item) {
          if (classQuery != null &&
              !item.className.toLowerCase().contains(
                classQuery.toLowerCase(),
              )) {
            return false;
          }
          if (minLiveBytes != null && item.liveBytes < minLiveBytes) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    if (topClassCount > 0 && classes.length > topClassCount) {
      classes = classes.take(topClassCount).toList(growable: false);
    }
    return _memoryResult(rawProfilePath: targetPath, classes: classes);
  }

  static ProfileRunResult _sessionWithMemory(
    ProfileRunResult session,
    String rawMemoryPath,
  ) {
    return ProfileRunResult(
      sessionId: session.sessionId,
      command: session.command,
      workingDirectory: session.workingDirectory,
      exitCode: session.exitCode,
      artifactDirectory: session.artifactDirectory,
      vmServiceUri: session.vmServiceUri,
      overallProfile: _regionWithMemory(session.overallProfile!, rawMemoryPath),
      regions: session.regions,
      warnings: session.warnings,
    );
  }

  static ProfileRegionResult _regionWithMemory(
    ProfileRegionResult region,
    String rawMemoryPath,
  ) {
    return ProfileRegionResult(
      regionId: region.regionId,
      name: region.name,
      attributes: region.attributes,
      isolateId: region.isolateId,
      isolateIds: region.isolateIds,
      captureKinds: region.captureKinds,
      isolateScope: region.isolateScope,
      parentRegionId: region.parentRegionId,
      memory: _memoryResult(rawProfilePath: rawMemoryPath),
      startTimestampMicros: region.startTimestampMicros,
      endTimestampMicros: region.endTimestampMicros,
      durationMicros: region.durationMicros,
      sampleCount: region.sampleCount,
      samplePeriodMicros: region.samplePeriodMicros,
      topSelfFrames: region.topSelfFrames,
      topTotalFrames: region.topTotalFrames,
      summaryPath: region.summaryPath,
      rawProfilePath: region.rawProfilePath,
      error: region.error,
    );
  }

  static ProfileMemoryResult _memoryResult({
    required String rawProfilePath,
    List<ProfileMemoryClassSummary>? classes,
  }) {
    final topClasses = classes ?? _memoryClasses;
    return ProfileMemoryResult.fromJson({
      'start': _heapSampleJson(timestamp: 1, used: 1024),
      'end': _heapSampleJson(timestamp: 2, used: 4096),
      'deltaHeapBytes': 3072,
      'deltaExternalBytes': 128,
      'deltaCapacityBytes': 4096,
      'classCount': _memoryClasses.length,
      'topClasses': [for (final item in topClasses) item.toJson()],
      'rawProfilePath': rawProfilePath,
    });
  }

  static Map<String, Object?> _heapSampleJson({
    required int timestamp,
    required int used,
  }) {
    return {
      'timestamp': timestamp,
      'rss': 0,
      'capacity': 8192,
      'used': used,
      'external': 0,
      'gc': false,
      'adb_memoryInfo': {
        'Realtime': 0,
        'Java Heap': 0,
        'Native Heap': 0,
        'Code': 0,
        'Stack': 0,
        'Graphics': 0,
        'Private Other': 0,
        'System': 0,
        'Total': 0,
      },
      'memory_eventInfo': {
        'timestamp': -1,
        'gcEvent': false,
        'snapshotEvent': false,
        'snapshotAutoEvent': false,
        'allocationAccumulatorEvent': {
          'start': false,
          'continues': false,
          'reset': false,
        },
        'extensionEvents': null,
      },
      'rasterCache': {'layerBytes': 0, 'pictureBytes': 0},
    };
  }
}

class _FakeProfileRunnerWithSharedTrendRegion extends _FakeProfileRunner {
  static const _profileId = 'startup';

  static final _session1Region = _sharedRegion(
    sessionId: 'session-1',
    durationMicros: 1_400,
    sampleCount: 7,
  );

  static final _session2Region = _sharedRegion(
    sessionId: 'session-2',
    durationMicros: 2_100,
    sampleCount: 11,
  );

  static final _session3Region = _sharedRegion(
    sessionId: 'session-3',
    durationMicros: 2_700,
    sampleCount: 14,
  );

  @override
  Future<Map<String, Object?>> summarizeArtifact(String path) async {
    return switch (path) {
      '/tmp/artifacts/session-1' => _withRegion(
        _FakeProfileRunner._session,
        _session1Region,
      ).toJson(),
      '/tmp/artifacts/session-2' => _withRegion(
        _FakeProfileRunner._sessionCurrent,
        _session2Region,
      ).toJson(),
      '/tmp/artifacts/session-3' => _withRegion(
        _FakeProfileRunner._sessionTrend,
        _session3Region,
      ).toJson(),
      _ => super.summarizeArtifact(path),
    };
  }

  static ProfileRunResult _withRegion(
    ProfileRunResult session,
    ProfileRegionResult region,
  ) {
    return ProfileRunResult(
      sessionId: session.sessionId,
      command: session.command,
      workingDirectory: session.workingDirectory,
      exitCode: session.exitCode,
      artifactDirectory: session.artifactDirectory,
      vmServiceUri: session.vmServiceUri,
      overallProfile: session.overallProfile,
      regions: [...session.regions, region],
      warnings: session.warnings,
    );
  }

  static ProfileRegionResult _sharedRegion({
    required String sessionId,
    required int durationMicros,
    required int sampleCount,
  }) {
    return ProfileRegionResult(
      regionId: _profileId,
      name: 'startup',
      attributes: const {'phase': 'startup'},
      isolateId: 'isolates/123',
      captureKinds: const [ProfileCaptureKind.cpu],
      startTimestampMicros: 100,
      endTimestampMicros: 100 + durationMicros,
      durationMicros: durationMicros,
      sampleCount: sampleCount,
      samplePeriodMicros: 50,
      topSelfFrames: const [],
      topTotalFrames: const [],
      summaryPath: '/tmp/artifacts/$sessionId/regions/$_profileId/summary.json',
      rawProfilePath:
          '/tmp/artifacts/$sessionId/regions/$_profileId/cpu_profile.json',
    );
  }
}

class _FakeRunnerWithZeroSamples extends _FakeProfileRunner {
  static const _zeroRawPath =
      '/tmp/zero-samples/regions/zero-region/cpu_profile.json';

  static final _zeroRegion = ProfileRegionResult(
    regionId: 'zero-region',
    name: 'zero-render',
    attributes: const {},
    isolateId: 'isolates/1',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 0,
    endTimestampMicros: 1_000_000,
    durationMicros: 1_000_000,
    sampleCount: 50,
    samplePeriodMicros: 1_000,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/zero-samples/regions/zero-region/summary.json',
    rawProfilePath: _zeroRawPath,
  );

  static final _zeroOverall = ProfileRegionResult(
    regionId: 'overall',
    name: 'whole-session',
    attributes: const {'scope': 'session'},
    isolateId: 'isolates/1',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 0,
    endTimestampMicros: 1_000_000,
    durationMicros: 1_000_000,
    sampleCount: 50,
    samplePeriodMicros: 1_000,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/zero-samples/overall/summary.json',
    rawProfilePath: '/tmp/zero-samples/overall/cpu_profile.json',
  );

  @override
  Future<ProfileRunResult> run(ProfileRunRequest request) async {
    return ProfileRunResult(
      sessionId: 'session-zero',
      command: request.command,
      workingDirectory: request.workingDirectory ?? '/workspace',
      exitCode: 0,
      artifactDirectory: '/tmp/zero-samples',
      vmServiceUri: 'http://127.0.0.1:8181/zero/',
      overallProfile: _zeroOverall,
      regions: [_zeroRegion],
      warnings: const [],
    );
  }
}

class _OutputCapture {
  _OutputCapture() {
    sink = IOSink(_controller.sink);
    _subscription = _controller.stream
        .transform(utf8.decoder)
        .listen(_buffer.write);
  }

  final _controller = StreamController<List<int>>();
  final _buffer = StringBuffer();
  late final IOSink sink;
  late final StreamSubscription<String> _subscription;

  String get text => _buffer.toString();

  Future<void> flush() async {
    await sink.flush();
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    await sink.close();
    await _subscription.cancel();
    await _controller.close();
  }
}
