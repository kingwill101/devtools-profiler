import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('MemoryClassEntry', () {
    test('toJson produces valid JSON map', () {
      final entry = MemoryClassEntry(
        className: 'String',
        instancesCurrent: 1000,
        instancesAccumulated: 5000,
        sizeCurrent: 64000,
        sizeAccumulated: 320000,
      );

      final json = entry.toJson();
      expect(json['className'], 'String');
      expect(json['instancesCurrent'], 1000);
      expect(json['instancesAccumulated'], 5000);
      expect(json['sizeCurrent'], 64000);
      expect(json['sizeAccumulated'], 320000);
    });

    test('toJson handles zero values', () {
      final entry = MemoryClassEntry(
        className: 'ZeroClass',
        instancesCurrent: 0,
        instancesAccumulated: 0,
        sizeCurrent: 0,
        sizeAccumulated: 0,
      );

      final json = entry.toJson();
      expect(json['instancesCurrent'], 0);
      expect(json['sizeCurrent'], 0);
    });

    test('parses fixture allocation profile data', () {
      final fixturePath = path.join(
        _fixtureDirectory().path,
        'data',
        'allocation_profile_response.json',
      );
      final json = jsonDecode(
        File(fixturePath).readAsStringSync(),
      ) as Map<String, dynamic>;

      final members = json['members'] as List<dynamic>;
      final firstMember = members.first as Map<String, dynamic>;
      final classData = firstMember['class'] as Map<String, dynamic>;

      expect(classData['name'], 'String');
      expect(firstMember['bytesCurrent'], 64000);
      expect(firstMember['instancesCurrent'], 1000);
      expect(firstMember['instancesAccumulated'], 5000);
      expect(firstMember['accumulatedSize'], 320000);

      final memoryUsage = json['memoryUsage'] as Map<String, dynamic>;
      expect(memoryUsage['heapUsage'], 168000);
      expect(memoryUsage['heapCapacity'], 512000);
      expect(memoryUsage['externalUsage'], 32000);
    });
  });

  group('MemorySnapshot', () {
    test('toJson limits class entries to 50', () {
      final entries = [
        for (var i = 0; i < 100; i++)
          MemoryClassEntry(
            className: 'Class$i',
            instancesCurrent: 10,
            instancesAccumulated: 10,
            sizeCurrent: 100,
            sizeAccumulated: 100,
          ),
      ];

      final snapshot = MemorySnapshot(
        name: 'test-snapshot',
        timestamp: DateTime(2026, 7, 9),
        totalHeapUsage: 100_000,
        capacity: 200_000,
        externalUsage: 5000,
        classEntries: entries,
      );

      final json = snapshot.toJson();
      expect(json['classEntries'], hasLength(50));
      expect(json['name'], 'test-snapshot');
      expect(json['totalHeapUsage'], 100_000);
    });
  });

  group('MemorySnapshotDelta', () {
    test('toJson limits class deltas to 30', () {
      final deltas = [
        for (var i = 0; i < 100; i++)
          ClassMemoryDelta(
            className: 'Class$i',
            instancesBefore: 10,
            instancesAfter: 20,
            instancesDelta: 10,
            sizeBefore: 100,
            sizeAfter: 200,
            sizeDelta: 100,
          ),
      ];

      final delta = MemorySnapshotDelta(
        beforeName: 'before',
        afterName: 'after',
        heapUsageDelta: 5000,
        classDeltas: deltas,
      );

      final json = delta.toJson();
      expect(json['classDeltas'], hasLength(30));
      expect(json['beforeName'], 'before');
      expect(json['afterName'], 'after');
      expect(json['heapUsageDelta'], 5000);
    });
  });
}

Directory _fixtureDirectory() {
  final candidates = [
    path.join(Directory.current.path, 'test', 'fixtures'),
    path.join(
      Directory.current.path,
      'packages',
      'devtools_profiler_core',
      'test',
      'fixtures',
    ),
  ];

  for (final candidate in candidates) {
    final directory = Directory(candidate);
    if (directory.existsSync()) {
      return directory;
    }
  }

  throw StateError(
    'Could not find fixtures directory. Searched: ${candidates.join(", ")}',
  );
}
