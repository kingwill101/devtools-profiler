import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('summarizeArtifact accepts memory-only artifact directories', () async {
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_memory_artifact.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final rawMemoryFile = File(
      path.join(artifactRoot.path, 'memory_profile.json'),
    );
    await rawMemoryFile.writeAsString(jsonEncode(_rawMemoryArtifact()));

    final summary = await ProfileArtifacts.summarizeArtifact(artifactRoot.path);

    expect(summary['type'], 'ProfileMemoryArtifact');
    expect(summary['start'], isA<Map<Object?, Object?>>());
    expect(summary['end'], isA<Map<Object?, Object?>>());
  });

  test('readMemoryClasses resolves session json file targets', () async {
    final artifactRoot = await Directory.systemTemp.createTemp(
      'devtools_profiler_session_memory.',
    );
    addTearDown(() => artifactRoot.delete(recursive: true));

    final rawMemoryFile = File(
      path.join(artifactRoot.path, 'memory_profile.json'),
    );
    await rawMemoryFile.writeAsString(jsonEncode(_rawMemoryArtifact()));

    final sessionFile = File(path.join(artifactRoot.path, 'session.json'));
    final session = ProfileRunResult(
      sessionId: 'session-1',
      command: const ['dart', 'run', 'bin/main.dart'],
      workingDirectory: artifactRoot.path,
      exitCode: 0,
      artifactDirectory: artifactRoot.path,
      overallProfile: _regionWithMemory(rawMemoryFile.path),
      regions: const [],
      warnings: const [],
    );
    await sessionFile.writeAsString(jsonEncode(session.toJson()));

    final memory = await ProfileArtifacts.readMemoryClasses(sessionFile.path);

    expect(memory.rawProfilePath, rawMemoryFile.path);
    expect(memory.classCount, 0);
  });

  test('rebuildMemoryProfileFromArtifact validates required maps', () {
    expect(
      () => rebuildMemoryProfileFromArtifact(const {
        'type': 'ProfileMemoryArtifact',
      }, rawProfilePath: '/tmp/malformed_memory_profile.json'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('/tmp/malformed_memory_profile.json'),
            contains('start'),
          ),
        ),
      ),
    );
  });
}

ProfileRegionResult _regionWithMemory(String rawMemoryPath) {
  return ProfileRegionResult(
    regionId: 'overall',
    name: 'whole-session',
    attributes: const {'scope': 'session'},
    isolateId: 'isolates/1',
    isolateIds: const ['isolates/1'],
    captureKinds: const [ProfileCaptureKind.memory],
    isolateScope: ProfileIsolateScope.current,
    startTimestampMicros: 1,
    endTimestampMicros: 2,
    durationMicros: 1,
    sampleCount: 0,
    samplePeriodMicros: 0,
    topSelfFrames: const [],
    topTotalFrames: const [],
    memory: _memoryResult(rawMemoryPath),
    summaryPath: path.join(path.dirname(rawMemoryPath), 'summary.json'),
  );
}

ProfileMemoryResult _memoryResult(String rawMemoryPath) {
  return ProfileMemoryResult.fromJson({
    'start': _heapSampleJson(timestamp: 1, used: 1024),
    'end': _heapSampleJson(timestamp: 2, used: 2048),
    'deltaHeapBytes': 1024,
    'deltaExternalBytes': 0,
    'deltaCapacityBytes': 1024,
    'classCount': 0,
    'topClasses': const [],
    'rawProfilePath': rawMemoryPath,
  });
}

Map<String, Object?> _rawMemoryArtifact() {
  return {
    'type': 'ProfileMemoryArtifact',
    'isolateIds': const ['isolates/1'],
    'start': {
      'heapSample': _heapSampleJson(timestamp: 1, used: 1024),
      'profiles': const [],
    },
    'end': {
      'heapSample': _heapSampleJson(timestamp: 2, used: 2048),
      'profiles': const [],
    },
  };
}

Map<String, Object?> _heapSampleJson({
  required int timestamp,
  required int used,
}) {
  return {
    'timestamp': timestamp,
    'rss': 0,
    'capacity': 4096,
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
