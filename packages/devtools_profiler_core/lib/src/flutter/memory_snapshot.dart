import 'package:vm_service/vm_service.dart';

/// A single class allocation entry from a memory snapshot.
final class MemoryClassEntry {
  /// Creates a memory class entry.
  const MemoryClassEntry({
    required this.className,
    required this.instancesCurrent,
    required this.instancesAccumulated,
    required this.sizeCurrent,
    required this.sizeAccumulated,
  });

  /// Deserializes from an [AllocationProfile] class entry.
  factory MemoryClassEntry.fromClassHeapStats(ClassHeapStats stats) {
    final name = stats.classRef?.name ?? 'unknown';
    final instancesCurrent = stats.instancesCurrent ?? 0;
    final instancesAccum = stats.instancesAccumulated ?? 0;
    final sizeCurrent = stats.bytesCurrent ?? 0;
    final sizeAccum = stats.accumulatedSize ?? 0;

    return MemoryClassEntry(
      className: name,
      instancesCurrent: instancesCurrent,
      instancesAccumulated: instancesAccum,
      sizeCurrent: sizeCurrent,
      sizeAccumulated: sizeAccum,
    );
  }

  /// The class name.
  final String className;

  /// Current number of live instances.
  final int instancesCurrent;

  /// Total instances accumulated (including collected).
  final int instancesAccumulated;

  /// Current heap size in bytes.
  final int sizeCurrent;

  /// Total heap size in bytes accumulated (including collected).
  final int sizeAccumulated;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'className': className,
    'instancesCurrent': instancesCurrent,
    'instancesAccumulated': instancesAccumulated,
    'sizeCurrent': sizeCurrent,
    'sizeAccumulated': sizeAccumulated,
  };
}

/// A memory snapshot captured from a running VM service.
final class MemorySnapshot {
  /// Creates a memory snapshot.
  const MemorySnapshot({
    required this.name,
    required this.timestamp,
    required this.totalHeapUsage,
    required this.capacity,
    required this.externalUsage,
    required this.classEntries,
  });

  /// Name of this snapshot.
  final String name;

  /// Timestamp when the snapshot was captured.
  final DateTime timestamp;

  /// Total heap usage in bytes.
  final int totalHeapUsage;

  /// Total heap capacity in bytes.
  final int capacity;

  /// External memory usage in bytes.
  final int externalUsage;

  /// Class allocation entries.
  final List<MemoryClassEntry> classEntries;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'name': name,
    'timestamp': timestamp.toIso8601String(),
    'totalHeapUsage': totalHeapUsage,
    'capacity': capacity,
    'externalUsage': externalUsage,
    'classEntries': [for (final entry in classEntries.take(50)) entry.toJson()],
  };
}

/// Result of comparing two [MemorySnapshot]s.
final class MemorySnapshotDelta {
  /// Creates a memory snapshot delta.
  const MemorySnapshotDelta({
    required this.beforeName,
    required this.afterName,
    required this.heapUsageDelta,
    required this.classDeltas,
  });

  /// Name of the before snapshot.
  final String beforeName;

  /// Name of the after snapshot.
  final String afterName;

  /// Change in total heap usage (after - before).
  final int heapUsageDelta;

  /// Per-class deltas, sorted by size delta descending.
  final List<ClassMemoryDelta> classDeltas;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'beforeName': beforeName,
    'afterName': afterName,
    'heapUsageDelta': heapUsageDelta,
    'classDeltas': [for (final delta in classDeltas.take(30)) delta.toJson()],
  };
}

/// Per-class difference between two memory snapshots.
final class ClassMemoryDelta {
  /// Creates a class memory delta.
  const ClassMemoryDelta({
    required this.className,
    required this.instancesBefore,
    required this.instancesAfter,
    required this.instancesDelta,
    required this.sizeBefore,
    required this.sizeAfter,
    required this.sizeDelta,
  });

  /// The class name.
  final String className;

  /// Instances before.
  final int instancesBefore;

  /// Instances after.
  final int instancesAfter;

  /// Change in instance count.
  final int instancesDelta;

  /// Heap size before in bytes.
  final int sizeBefore;

  /// Heap size after in bytes.
  final int sizeAfter;

  /// Change in heap size in bytes.
  final int sizeDelta;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'className': className,
    'instancesBefore': instancesBefore,
    'instancesAfter': instancesAfter,
    'instancesDelta': instancesDelta,
    'sizeBefore': sizeBefore,
    'sizeAfter': sizeAfter,
    'sizeDelta': sizeDelta,
  };
}

/// Captures memory allocation snapshots from a running VM service.
class MemorySnapshotCapture {
  /// Creates a memory snapshot capture instance.
  MemorySnapshotCapture({required VmService vmService})
    : _vmService = vmService;

  final VmService _vmService;
  final Map<String, MemorySnapshot> _snapshots = {};
  int _snapshotCounter = 0;

  /// Captures an allocation profile snapshot from [isolateId].
  ///
  /// When [name] is omitted, an auto-incrementing name like
  /// `snapshot-1` is generated.
  Future<MemorySnapshot> captureSnapshot({
    required String isolateId,
    String? name,
    bool forceGc = true,
  }) async {
    _snapshotCounter++;
    final snapshotName = name ?? 'snapshot-$_snapshotCounter';

    if (forceGc) {
      try {
        await _vmService.getAllocationProfile(
          isolateId,
          gc: true,
          reset: false,
        );
      } catch (_) {}
    }

    final profile = await _vmService.getAllocationProfile(
      isolateId,
      gc: false,
      reset: false,
    );

    final members = profile.members ?? [];
    final classEntries =
        members
            .map((stats) => MemoryClassEntry.fromClassHeapStats(stats))
            .toList()
          ..sort((a, b) => b.sizeCurrent.compareTo(a.sizeCurrent));

    final snapshot = MemorySnapshot(
      name: snapshotName,
      timestamp: DateTime.now(),
      totalHeapUsage: profile.memoryUsage?.heapUsage ?? 0,
      capacity: profile.memoryUsage?.heapCapacity ?? 0,
      externalUsage: profile.memoryUsage?.externalUsage ?? 0,
      classEntries: classEntries,
    );

    _snapshots[snapshotName] = snapshot;
    return snapshot;
  }

  /// Retrieves a previously saved snapshot by name.
  MemorySnapshot? getSnapshot(String name) => _snapshots[name];

  /// Lists all saved snapshot names.
  List<String> listSnapshotNames() => _snapshots.keys.toList()..sort();

  /// Compares two saved snapshots and returns the delta.
  ///
  /// Throws [ArgumentError] if either snapshot is not found.
  MemorySnapshotDelta compareSnapshots(String beforeName, String afterName) {
    final before = _snapshots[beforeName];
    final after = _snapshots[afterName];
    if (before == null) {
      throw ArgumentError('Snapshot "$beforeName" not found.');
    }
    if (after == null) {
      throw ArgumentError('Snapshot "$afterName" not found.');
    }

    final beforeMap = {
      for (final entry in before.classEntries) entry.className: entry,
    };
    final afterMap = {
      for (final entry in after.classEntries) entry.className: entry,
    };
    final allClasses = <String>{}
      ..addAll(beforeMap.keys)
      ..addAll(afterMap.keys);

    final deltas = <ClassMemoryDelta>[];
    for (final className in allClasses) {
      final b = beforeMap[className];
      final a = afterMap[className];
      final instancesBefore = b?.instancesCurrent ?? 0;
      final instancesAfter = a?.instancesCurrent ?? 0;
      final sizeBefore = b?.sizeCurrent ?? 0;
      final sizeAfter = a?.sizeCurrent ?? 0;
      deltas.add(
        ClassMemoryDelta(
          className: className,
          instancesBefore: instancesBefore,
          instancesAfter: instancesAfter,
          instancesDelta: instancesAfter - instancesBefore,
          sizeBefore: sizeBefore,
          sizeAfter: sizeAfter,
          sizeDelta: sizeAfter - sizeBefore,
        ),
      );
    }

    deltas.sort((a, b) => b.sizeDelta.abs().compareTo(a.sizeDelta.abs()));

    return MemorySnapshotDelta(
      beforeName: beforeName,
      afterName: afterName,
      heapUsageDelta: after.totalHeapUsage - before.totalHeapUsage,
      classDeltas: deltas,
    );
  }

  /// Removes a saved snapshot.
  void removeSnapshot(String name) => _snapshots.remove(name);

  /// Clears all saved snapshots.
  void clearSnapshots() {
    _snapshots.clear();
    _snapshotCounter = 0;
  }
}
