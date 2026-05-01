import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:devtools_profiler_core/src/capture/runner/process_launch.dart'
    as launch;
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  final fixtureDirectory = _fixtureDirectory();

  setUpAll(() async {
    final result = await Process.run(Platform.resolvedExecutable, const [
      'pub',
      'get',
    ], workingDirectory: fixtureDirectory.path);
    expect(
      result.exitCode,
      0,
      reason:
          'Fixture pub get failed:\nstdout: ${result.stdout}\nstderr: '
          '${result.stderr}',
    );
  });

  test('rejects unsupported flutter subcommands before launch', () async {
    await expectLater(
      ProfileRunner().run(
        const ProfileRunRequest(command: ['flutter', 'build', 'apk']),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.toString(),
          'message',
          contains('Only "flutter run" and "flutter test" are supported'),
        ),
      ),
    );
  });

  test('rejects flutter release mode before launch', () async {
    await expectLater(
      ProfileRunner().run(
        const ProfileRunRequest(command: ['flutter', 'run', '--release']),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.toString(),
          'message',
          contains('Flutter release mode does not expose a Dart VM service'),
        ),
      ),
    );
  });

  test('rejects flutter faster testing before launch', () async {
    await expectLater(
      ProfileRunner().run(
        const ProfileRunRequest(
          command: ['flutter', 'test', '--experimental-faster-testing'],
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.toString(),
          'message',
          contains('experimental faster testing is not compatible'),
        ),
      ),
    );
  });

  test('injects flutter profiler arguments before launch', () async {
    if (Platform.isWindows) {
      markTestSkipped('The fake flutter launcher uses a POSIX shell script.');
      return;
    }

    final testArguments = await _recordedFlutterArguments(const [
      'test',
      'test/widget_test.dart',
    ]);
    expect(testArguments, contains('--enable-vmservice'));
    expect(
      testArguments,
      contains(startsWith('--dart-define=DEVTOOLS_PROFILER_DTD_URI=')),
    );
    expect(
      testArguments,
      contains(startsWith('--dart-define=DEVTOOLS_PROFILER_SESSION_ID=')),
    );
    expect(
      testArguments,
      contains('--dart-define=DEVTOOLS_PROFILER_PROTOCOL_VERSION=1'),
    );

    final runArguments = await _recordedFlutterArguments(const [
      'run',
      '-d',
      'linux',
    ]);
    expect(runArguments, contains('--host-vmservice-port=0'));
  });

  test(
    'builds inherited-stdio Dart launch with a deterministic service URI',
    () {
      final plan = launch.instrumentedCommandLaunchPlan(
        const ['dart', 'run', 'bin/main.dart'],
        dtdUri: 'http://127.0.0.1:1/',
        sessionId: 'session-test',
        processIoMode: ProfileProcessIoMode.inheritStdio,
        vmServicePort: 12345,
      );

      expect(plan.arguments.take(3), [
        '--observe=12345',
        '--disable-service-auth-codes',
        '--pause-isolates-on-exit=false',
      ]);
      expect(plan.expectedVmServiceUri, Uri.parse('http://127.0.0.1:12345/'));
    },
  );

  test(
    'builds inherited-stdio Flutter run with a deterministic service URI',
    () {
      final plan = launch.flutterLaunchPlan(
        const ['flutter', 'run', '-d', 'linux'],
        dtdUri: 'http://127.0.0.1:1/',
        sessionId: 'session-test',
        processIoMode: ProfileProcessIoMode.inheritStdio,
        vmServicePort: 12345,
      );

      expect(plan.arguments, contains('--host-vmservice-port=12345'));
      expect(plan.arguments, contains('--disable-service-auth-codes'));
      expect(plan.expectedVmServiceUri, Uri.parse('http://127.0.0.1:12345/'));
    },
  );

  test('uses configurable VM service timeout', () async {
    if (Platform.isWindows) {
      markTestSkipped('The fake flutter launcher uses a POSIX shell script.');
      return;
    }

    final tempDirectory = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_vm_service_timeout.',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final flutter = File(path.join(tempDirectory.path, 'flutter'));
    await flutter.writeAsString('''
#!/bin/sh
sleep 5
''');
    await Process.run('chmod', ['+x', flutter.path]);

    await expectLater(
      ProfileRunner().run(
        ProfileRunRequest(
          command: [flutter.path, 'run', '-d', 'linux'],
          artifactDirectory: path.join(tempDirectory.path, 'session'),
          vmServiceTimeout: const Duration(milliseconds: 50),
          workingDirectory: tempDirectory.path,
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('Timed out after 50ms waiting for the Dart VM service URI'),
        ),
      ),
    );
  });

  test('profiles a marked region and writes session artifacts', () async {
    final runner = ProfileRunner();
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_run.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final result = await runner.run(
      ProfileRunRequest(
        command: const ['dart', 'run', 'bin/profiled_app.dart'],
        artifactDirectory: path.join(artifactRoot.path, 'session'),
        workingDirectory: fixtureDirectory.path,
      ),
    );

    expect(result.exitCode, 0);
    expect(result.vmServiceUri, isNotNull);
    expect(result.overallProfile, isNotNull);
    expect(result.regions, hasLength(1));

    final overallProfile = result.overallProfile!;
    expect(overallProfile.name, 'whole-session');
    expect(overallProfile.attributes, containsPair('scope', 'session'));
    expect(overallProfile.sampleCount, greaterThan(0));
    expect(overallProfile.memory, isNotNull);
    expect(File(overallProfile.summaryPath).existsSync(), isTrue);
    expect(File(overallProfile.rawProfilePath!).existsSync(), isTrue);
    expect(File(overallProfile.memory!.rawProfilePath!).existsSync(), isTrue);

    final region = result.regions.single;
    expect(region.name, 'cpu-burn');
    expect(region.attributes, containsPair('phase', 'fixture'));
    expect(region.sampleCount, greaterThan(0));
    expect(region.topSelfFrames, isNotEmpty);
    expect(File(region.summaryPath).existsSync(), isTrue);
    expect(File(region.rawProfilePath!).existsSync(), isTrue);

    final session = await ProfileArtifacts.readSession(
      result.artifactDirectory,
    );
    expect(session.sessionId, result.sessionId);
    expect(session.overallProfile, isNotNull);
    expect(session.regions, hasLength(1));
  });

  test('profiles a bare Dart file before a fast process exits', () async {
    final runner = ProfileRunner();
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_quick_exit.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final result = await runner.run(
      ProfileRunRequest(
        command: const ['bin/quick_exit.dart'],
        artifactDirectory: path.join(artifactRoot.path, 'session'),
        workingDirectory: fixtureDirectory.path,
      ),
    );

    expect(result.command, ['dart', 'run', 'bin/quick_exit.dart']);
    expect(result.exitCode, 0);
    expect(result.overallProfile, isNotNull);
    expect(result.overallProfile!.succeeded, isTrue);
    expect(result.overallProfile!.sampleCount, greaterThan(0));
    expect(result.overallProfile!.rawProfilePath, isNotNull);
    expect(
      result.warnings.where(
        (warning) => warning.contains('Service connection disposed'),
      ),
      isEmpty,
    );
  });

  test('profiles an artisanal widget TUI with inherited stdio', () async {
    final runner = ProfileRunner();
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_terminal.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final result = await runner.run(
      ProfileRunRequest(
        command: const ['dart', 'run', 'bin/artisanal_widget_app.dart'],
        artifactDirectory: path.join(artifactRoot.path, 'session'),
        processIoMode: ProfileProcessIoMode.inheritStdio,
        workingDirectory: fixtureDirectory.path,
      ),
    );

    expect(result.command, ['dart', 'run', 'bin/artisanal_widget_app.dart']);
    expect(result.exitCode, 0);
    expect(result.vmServiceUri, startsWith('http://127.0.0.1:'));
    expect(result.overallProfile, isNotNull);
    expect(result.overallProfile!.succeeded, isTrue);
    expect(result.overallProfile!.sampleCount, greaterThan(0));
  });

  test('returns available diagnostics when interrupted', () async {
    if (Platform.isWindows) {
      markTestSkipped('Process signal delivery differs on Windows.');
      return;
    }

    final processResult =
        await Process.run(Platform.resolvedExecutable, const [
          'run',
          'bin/interrupting_profiler.dart',
        ], workingDirectory: fixtureDirectory.path).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw StateError(
            'Timed out waiting for interrupting_profiler.dart.',
          ),
        );

    expect(
      processResult.exitCode,
      0,
      reason:
          'stdout:\n${processResult.stdout}\nstderr:\n${processResult.stderr}',
    );
    final payload =
        jsonDecode(processResult.stdout as String) as Map<String, Object?>;
    addTearDown(
      () =>
          Directory(payload['artifactRoot']! as String).delete(recursive: true),
    );

    expect(payload['terminatedByProfiler'], isTrue);
    expect(payload['warnings'], contains(contains('Received SIGINT')));
    expect(
      payload['sampleCount'],
      isA<int>().having((count) => count, 'count', greaterThan(0)),
    );
    expect(File(payload['sessionJson']! as String).existsSync(), isTrue);
  });

  test('waits for worker isolates before finalizing a Dart run', () async {
    final runner = ProfileRunner();
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_quick_worker.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final result = await runner.run(
      ProfileRunRequest(
        command: const ['dart', 'run', 'bin/quick_worker_isolate.dart'],
        artifactDirectory: path.join(artifactRoot.path, 'session'),
        workingDirectory: fixtureDirectory.path,
      ),
    );

    expect(result.exitCode, 0);
    expect(result.overallProfile, isNotNull);
    expect(result.overallProfile!.succeeded, isTrue);
    expect(result.overallProfile!.durationMicros, greaterThan(300_000));
    expect(result.overallProfile!.sampleCount, greaterThan(0));
    expect(result.overallProfile!.isolateIds.length, greaterThan(1));
  });

  test('attaches to an existing VM service without killing it', () async {
    final runner = ProfileRunner();
    final tempDirectory = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_attach.',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final script = File(path.join(tempDirectory.path, 'attached_target.dart'));
    await script.writeAsString('''
import 'dart:async';

Future<void> main() async {
  final stopwatch = Stopwatch()..start();
  var state = 1;
  while (stopwatch.elapsed < const Duration(seconds: 20)) {
    for (var i = 0; i < 50000; i++) {
      state = ((state * 1664525) + i) & 0x7fffffff;
    }
    await Future<void>.delayed(Duration.zero);
  }
  if (state == -1) {
    throw StateError('unreachable');
  }
}
''');

    final target = await _startObservedDartScript(script);
    addTearDown(target.dispose);

    final result = await runner.attach(
      ProfileAttachRequest(
        artifactDirectory: path.join(tempDirectory.path, 'session'),
        duration: const Duration(milliseconds: 500),
        vmServiceUri: target.serviceUri,
        workingDirectory: tempDirectory.path,
      ),
    );

    expect(result.exitCode, 0);
    expect(result.command, ['attach', target.serviceUri.toString()]);
    expect(result.vmServiceUri, target.serviceUri.toString());
    expect(result.overallProfile, isNotNull);
    expect(result.overallProfile!.sampleCount, greaterThan(0));
    expect(
      result.warnings,
      contains(contains('Attach mode captured an existing VM-service process')),
    );
    expect(File(result.overallProfile!.summaryPath).existsSync(), isTrue);
    expect(File(result.overallProfile!.rawProfilePath!).existsSync(), isTrue);

    final exitedBeforeKill = await target.process.exitCode
        .then((_) => true)
        .timeout(const Duration(milliseconds: 100), onTimeout: () => false);
    expect(exitedBeforeKill, isFalse);
  });

  test('records a failed region when the process exits before stop', () async {
    final runner = ProfileRunner();
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_unclosed.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final result = await runner.run(
      ProfileRunRequest(
        command: const ['dart', 'run', 'bin/unclosed_region.dart'],
        artifactDirectory: path.join(artifactRoot.path, 'session'),
        workingDirectory: fixtureDirectory.path,
      ),
    );

    expect(result.exitCode, 0);
    expect(result.overallProfile, isNotNull);
    expect(result.regions, hasLength(1));

    final region = result.regions.single;
    expect(region.name, 'unfinished-region');
    expect(region.error, contains('exited before the region was stopped'));
    expect(region.sampleCount, 0);
    expect(
      result.warnings.any((warning) => warning.contains('still active')),
      isTrue,
    );
  });

  test('profiles a marked region across multiple app isolates', () async {
    final runner = ProfileRunner();
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_all_isolates.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final result = await runner.run(
      ProfileRunRequest(
        command: const ['dart', 'run', 'bin/all_isolates.dart'],
        artifactDirectory: path.join(artifactRoot.path, 'session'),
        workingDirectory: fixtureDirectory.path,
      ),
    );

    expect(result.exitCode, 0);
    expect(result.overallProfile, isNotNull);
    expect(result.regions, hasLength(1));

    final overallProfile = result.overallProfile!;
    expect(overallProfile.isolateIds.length, greaterThan(1));
    expect(overallProfile.isolateScope, ProfileIsolateScope.all);

    final region = result.regions.single;
    expect(region.name, 'multi-isolate-burn');
    expect(region.captureKinds, [
      ProfileCaptureKind.cpu,
      ProfileCaptureKind.memory,
    ]);
    expect(region.isolateScope, ProfileIsolateScope.all);
    expect(region.isolateIds.length, greaterThan(1));
    expect(region.sampleCount, greaterThan(0));
  });

  test('captures region-scoped memory summaries', () async {
    final runner = ProfileRunner();
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_memory_regions.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final result = await runner.run(
      ProfileRunRequest(
        command: const ['dart', 'run', 'bin/memory_profiled_app.dart'],
        artifactDirectory: path.join(artifactRoot.path, 'session'),
        workingDirectory: fixtureDirectory.path,
      ),
    );

    expect(result.exitCode, 0);
    expect(result.overallProfile?.memory, isNotNull);
    expect(result.regions, hasLength(1));

    final region = result.regions.single;
    expect(region.name, 'memory-burn');
    expect(region.captureKinds, [ProfileCaptureKind.memory]);
    expect(region.rawProfilePath, isNull);
    expect(region.sampleCount, 0);
    expect(region.memory, isNotNull);
    expect(region.memory!.deltaHeapBytes, greaterThan(0));
    expect(region.memory!.topClasses, isNotEmpty);
    expect(File(region.memory!.rawProfilePath!).existsSync(), isTrue);
  });

  test('captures nested regions and preserves parent linkage', () async {
    final runner = ProfileRunner();
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_nested_regions.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final result = await runner.run(
      ProfileRunRequest(
        command: const ['dart', 'run', 'bin/nested_regions.dart'],
        artifactDirectory: path.join(artifactRoot.path, 'session'),
        workingDirectory: fixtureDirectory.path,
      ),
    );

    expect(result.exitCode, 0);
    expect(result.regions, hasLength(2));

    final outerRegion = result.regions.first;
    final innerRegion = result.regions.last;

    expect(outerRegion.name, 'outer-region');
    expect(outerRegion.parentRegionId, isNull);
    expect(innerRegion.name, 'inner-region');
    expect(innerRegion.parentRegionId, outerRegion.regionId);
    expect(
      outerRegion.startTimestampMicros,
      lessThan(innerRegion.startTimestampMicros),
    );
    expect(
      outerRegion.endTimestampMicros,
      greaterThan(innerRegion.endTimestampMicros),
    );
  });

  test('captures overlapping regions in a single isolate', () async {
    final runner = ProfileRunner();
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_overlapping_regions.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final result = await runner.run(
      ProfileRunRequest(
        command: const ['dart', 'run', 'bin/overlapping_regions.dart'],
        artifactDirectory: path.join(artifactRoot.path, 'session'),
        workingDirectory: fixtureDirectory.path,
      ),
    );

    expect(result.exitCode, 0);
    expect(result.regions, hasLength(2));
    expect(result.regions.map((region) => region.name), [
      'first-region',
      'second-region',
    ]);
    expect(result.regions.every((region) => region.sampleCount > 0), isTrue);
  });

  test('summarizes a raw cpu profile artifact', () async {
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_summary.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final rawArtifact = File(path.join(artifactRoot.path, 'cpu_profile.json'));
    await rawArtifact.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'type': 'CpuSamples',
        'samplePeriod': 1000,
        'timeOriginMicros': 0,
        'timeExtentMicros': 2000,
        'functions': [
          {
            'kind': 'Dart',
            'resolvedUrl': 'package:fixture/a.dart',
            'function': {
              'type': '@Function',
              'id': 'functions/a',
              'name': 'hotLeaf',
              'owner': {
                'type': '@Class',
                'id': 'classes/worker',
                'name': 'Worker',
              },
            },
          },
        ],
        'samples': [
          {
            'timestamp': 1,
            'stack': [0],
          },
        ],
      }),
    );

    final summary = await ProfileArtifacts.summarizeArtifact(rawArtifact.path);
    final region = ProfileRegionResult.fromJson(summary);

    expect(region.sampleCount, 1);
    expect(region.topSelfFrames.single.name, 'Worker.hotLeaf');
  });

  test('summarizes a profile artifact directory', () async {
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_core_summary_dir.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final profileDirectory = Directory(path.join(artifactRoot.path, 'overall'));
    await profileDirectory.create(recursive: true);
    final rawArtifact = File(
      path.join(profileDirectory.path, 'cpu_profile.json'),
    );
    await rawArtifact.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'type': 'CpuSamples',
        'samplePeriod': 1000,
        'timeOriginMicros': 0,
        'timeExtentMicros': 2000,
        'functions': [
          {
            'kind': 'Dart',
            'resolvedUrl': 'package:fixture/a.dart',
            'function': {
              'type': '@Function',
              'id': 'functions/a',
              'name': 'hotLeaf',
              'owner': {
                'type': '@Class',
                'id': 'classes/worker',
                'name': 'Worker',
              },
            },
          },
        ],
        'samples': [
          {
            'timestamp': 1,
            'stack': [0],
          },
        ],
      }),
    );

    final summaryFile = File(path.join(profileDirectory.path, 'summary.json'));
    final summary = summarizeCpuSamples(
      regionId: 'overall',
      name: 'whole-session',
      attributes: const {'scope': 'session'},
      isolateId: 'isolates/1',
      isolateIds: const ['isolates/1'],
      captureKinds: const [ProfileCaptureKind.cpu],
      startTimestampMicros: 0,
      endTimestampMicros: 2000,
      cpuSamples: CpuSamples.parse(
        jsonDecode(await rawArtifact.readAsString()) as Map<String, dynamic>,
      )!,
      summaryPath: summaryFile.path,
      rawProfilePath: rawArtifact.path,
    );
    await summaryFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary.toJson()),
    );

    final resolved = await ProfileArtifacts.summarizeArtifact(
      profileDirectory.path,
    );
    final region = ProfileRegionResult.fromJson(resolved);

    expect(region.regionId, 'overall');
    expect(region.rawProfilePath, rawArtifact.path);
    expect(region.topSelfFrames.single.name, 'Worker.hotLeaf');
  });
}

Directory _fixtureDirectory() {
  final candidates = [
    path.join(Directory.current.path, 'test', 'fixtures', 'profiled_app'),
    path.join(
      Directory.current.path,
      'packages',
      'devtools_profiler_core',
      'test',
      'fixtures',
      'profiled_app',
    ),
  ];

  for (final candidate in candidates) {
    final directory = Directory(candidate);
    if (directory.existsSync()) {
      return directory;
    }
  }

  throw StateError('Could not find the profiled_app test fixture.');
}

Future<List<String>> _recordedFlutterArguments(List<String> arguments) async {
  final tempDirectory = await Directory.systemTemp.createTemp(
    'devtools_profiler_core_fake_flutter.',
  );
  try {
    final flutter = File(path.join(tempDirectory.path, 'flutter'));
    final argumentsFile = File(path.join(tempDirectory.path, 'arguments.txt'));
    await flutter.writeAsString('''
#!/bin/sh
printf '%s\\n' "\$@" > "\$PROFILE_TEST_ARGS_FILE"
echo "The Dart VM service is listening on http://127.0.0.1:1/"
''');
    await Process.run('chmod', ['+x', flutter.path]);

    var failed = false;
    try {
      await ProfileRunner().run(
        ProfileRunRequest(
          command: [flutter.path, ...arguments],
          artifactDirectory: path.join(tempDirectory.path, 'session'),
          environment: {'PROFILE_TEST_ARGS_FILE': argumentsFile.path},
          workingDirectory: tempDirectory.path,
        ),
      );
    } catch (_) {
      failed = true;
    }
    expect(failed, isTrue);
    return argumentsFile.readAsLines();
  } finally {
    await tempDirectory.delete(recursive: true);
  }
}

class _ObservedDartProcess {
  const _ObservedDartProcess({
    required this.process,
    required this.serviceUri,
    required this.stderrSubscription,
    required this.stdoutSubscription,
  });

  final Process process;
  final Uri serviceUri;
  final StreamSubscription<String> stderrSubscription;
  final StreamSubscription<String> stdoutSubscription;

  Future<void> dispose() async {
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
    if (process.kill()) {
      await process.exitCode;
    }
  }
}

Future<_ObservedDartProcess> _startObservedDartScript(File script) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    '--observe=0',
    '--pause-isolates-on-exit=false',
    script.path,
  ]);
  final serviceUriCompleter = Completer<Uri>();

  void handleLine(String line) {
    if (serviceUriCompleter.isCompleted) {
      return;
    }
    final match = RegExp(
      r'(?:Observatory|Dart VM service|VM service).*?((?:https?:)?//[a-zA-Z0-9:/=_\-\.\[\]%?&]+)',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) {
      return;
    }
    final uriString = match.group(1)!;
    final uri = Uri.parse(
      uriString.startsWith('//') ? 'http:$uriString' : uriString,
    );
    serviceUriCompleter.complete(
      uri.replace(path: uri.path.endsWith('/') ? uri.path : '${uri.path}/'),
    );
  }

  final stdoutSubscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(handleLine);
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(handleLine);

  try {
    final serviceUri = await serviceUriCompleter.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw StateError('Timed out waiting for the observed VM service URI.');
      },
    );
    return _ObservedDartProcess(
      process: process,
      serviceUri: serviceUri,
      stderrSubscription: stderrSubscription,
      stdoutSubscription: stdoutSubscription,
    );
  } catch (_) {
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
    process.kill();
    await process.exitCode;
    rethrow;
  }
}
