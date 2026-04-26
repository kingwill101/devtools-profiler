import 'dart:convert';
import 'dart:io';

import 'package:devtools_shared/devtools_shared.dart';
import 'package:vm_service/vm_service.dart';

import 'memory_models.dart';

/// Predicate used to retain or hide memory class summaries.
typedef ProfileMemoryClassPredicate =
    bool Function(ProfileMemoryClassSummary summary);

/// Builds a [ProfileMemoryResult] from start and end allocation snapshots.
ProfileMemoryResult summarizeMemoryProfile({
  required HeapSample start,
  required HeapSample end,
  required Iterable<ClassHeapStats> startClasses,
  required Iterable<ClassHeapStats> endClasses,
  required String rawProfilePath,
  int topClassCount = 10,
  ProfileMemoryClassPredicate? includeClass,
}) {
  final startStats = _aggregateClassStats(startClasses);
  final endStats = _aggregateClassStats(endClasses);
  final summaries = <ProfileMemoryClassSummary>[];

  for (final key in {...startStats.keys, ...endStats.keys}) {
    final startStat = startStats[key];
    final endStat = endStats[key];
    final summary = ProfileMemoryClassSummary(
      className: endStat?.className ?? startStat?.className ?? 'unknown',
      libraryUri: endStat?.libraryUri ?? startStat?.libraryUri,
      allocationBytesDelta:
          (endStat?.accumulatedBytes ?? 0) - (startStat?.accumulatedBytes ?? 0),
      allocationInstancesDelta:
          (endStat?.accumulatedInstances ?? 0) -
          (startStat?.accumulatedInstances ?? 0),
      liveBytes: endStat?.liveBytes ?? 0,
      liveBytesDelta: (endStat?.liveBytes ?? 0) - (startStat?.liveBytes ?? 0),
      liveInstances: endStat?.liveInstances ?? 0,
      liveInstancesDelta:
          (endStat?.liveInstances ?? 0) - (startStat?.liveInstances ?? 0),
    );
    if (includeClass != null && !includeClass(summary)) {
      continue;
    }
    summaries.add(summary);
  }

  summaries.sort(_compareMemoryClassSummary);
  if (topClassCount > 0 && summaries.length > topClassCount) {
    summaries.removeRange(topClassCount, summaries.length);
  }

  return ProfileMemoryResult(
    start: start,
    end: end,
    deltaHeapBytes: end.used - start.used,
    deltaExternalBytes: end.external - start.external,
    deltaCapacityBytes: end.capacity - start.capacity,
    classCount: {...startStats.keys, ...endStats.keys}.length,
    topClasses: summaries,
    rawProfilePath: rawProfilePath,
  );
}

/// Parses a raw `ProfileMemoryArtifact` JSON map and returns a
/// [ProfileMemoryResult] with optional class filtering.
///
/// [rawArtifact] must be the decoded JSON of a `memory_profile.json` file
/// produced by [buildRawMemoryPayload].
///
/// When [includeClass] is supplied, only classes that pass the predicate are
/// included in [ProfileMemoryResult.topClasses].
///
/// Pass [topClassCount] as 0 for unlimited results; otherwise the result is
/// truncated to that many classes after sorting.
///
/// This rebuild path defaults to 50 classes for deep-dive inspection, while
/// [summarizeMemoryProfile] defaults to 10 for brief capture summaries.
ProfileMemoryResult rebuildMemoryProfileFromArtifact(
  Map<String, Object?> rawArtifact, {
  required String rawProfilePath,
  ProfileMemoryClassPredicate? includeClass,
  int topClassCount = 50,
}) {
  final startMap = _requiredArtifactMap(
    rawArtifact['start'],
    label: 'start',
    rawProfilePath: rawProfilePath,
  );
  final endMap = _requiredArtifactMap(
    rawArtifact['end'],
    label: 'end',
    rawProfilePath: rawProfilePath,
  );

  final start = HeapSample.fromJson(
    _requiredArtifactMap(
      startMap['heapSample'],
      label: 'start.heapSample',
      rawProfilePath: rawProfilePath,
    ),
  );
  final end = HeapSample.fromJson(
    _requiredArtifactMap(
      endMap['heapSample'],
      label: 'end.heapSample',
      rawProfilePath: rawProfilePath,
    ),
  );

  final startClasses = _extractClassStats(startMap);
  final endClasses = _extractClassStats(endMap);

  return summarizeMemoryProfile(
    start: start,
    end: end,
    startClasses: startClasses,
    endClasses: endClasses,
    rawProfilePath: rawProfilePath,
    topClassCount: topClassCount,
    includeClass: includeClass,
  );
}

/// Reads a raw `memory_profile.json` artifact from [rawProfilePath] and
/// returns a [ProfileMemoryResult] with optional class filtering.
///
/// When [includeClass] is supplied, only classes that pass the predicate are
/// included in [ProfileMemoryResult.topClasses].
///
/// Pass [topClassCount] as 0 for unlimited results.
///
/// This artifact-reader defaults to 50 classes for inspect-style deep dives;
/// use [summarizeMemoryProfile] for the shorter 10-class summary default.
Future<ProfileMemoryResult> readMemoryClassesFromArtifact(
  String rawProfilePath, {
  ProfileMemoryClassPredicate? includeClass,
  int topClassCount = 50,
}) async {
  final json =
      jsonDecode(await File(rawProfilePath).readAsString())
          as Map<Object?, Object?>;
  return rebuildMemoryProfileFromArtifact(
    json.cast<String, Object?>(),
    rawProfilePath: rawProfilePath,
    includeClass: includeClass,
    topClassCount: topClassCount,
  );
}

Map<String, Object?> _requiredArtifactMap(
  Object? value, {
  required String label,
  required String rawProfilePath,
}) {
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  throw FormatException(
    'Invalid memory profile artifact at "$rawProfilePath": expected "$label" '
    'to be an object.',
  );
}

/// Extracts the flat list of [ClassHeapStats] from one snapshot half of a
/// raw `ProfileMemoryArtifact` (either the `start` or `end` map).
List<ClassHeapStats> _extractClassStats(Map<String, Object?> snapshot) {
  final profiles = (snapshot['profiles'] as List<Object?>? ?? const [])
      .cast<Map<Object?, Object?>>();
  final result = <ClassHeapStats>[];
  for (final profile in profiles) {
    final apJson = (profile['allocationProfile'] as Map<Object?, Object?>?)
        ?.cast<String, dynamic>();
    final ap = AllocationProfile.parse(apJson);
    result.addAll(ap?.members ?? const []);
  }
  return result;
}

HeapSample heapSampleFromMemoryUsage({
  required MemoryUsage? memoryUsage,
  required int timestampMicros,
}) {
  return HeapSample(
    timestampMicros,
    0,
    _sanitizeMemoryValue(memoryUsage?.heapCapacity),
    _sanitizeMemoryValue(memoryUsage?.heapUsage),
    _sanitizeMemoryValue(memoryUsage?.externalUsage),
    false,
    null,
    EventSample.empty(),
    null,
  );
}

Map<String, _MutableMemoryClassStats> _aggregateClassStats(
  Iterable<ClassHeapStats> classes,
) {
  final aggregated = <String, _MutableMemoryClassStats>{};
  for (final stats in classes) {
    final className = stats.classRef?.name;
    if (className == null || className.isEmpty) {
      continue;
    }
    final libraryUri = stats.classRef?.library?.uri;
    final key = '$libraryUri::$className';
    final entry = aggregated.putIfAbsent(
      key,
      () => _MutableMemoryClassStats(
        className: className,
        libraryUri: libraryUri,
      ),
    );
    entry.accumulatedBytes += _sanitizeMemoryValue(stats.accumulatedSize);
    entry.accumulatedInstances += _sanitizeMemoryValue(
      stats.instancesAccumulated,
    );
    entry.liveBytes += _sanitizeMemoryValue(stats.bytesCurrent);
    entry.liveInstances += _sanitizeMemoryValue(stats.instancesCurrent);
  }
  return aggregated;
}

int _compareMemoryClassSummary(
  ProfileMemoryClassSummary left,
  ProfileMemoryClassSummary right,
) {
  final allocationBytesCompare = right.allocationBytesDelta.compareTo(
    left.allocationBytesDelta,
  );
  if (allocationBytesCompare != 0) {
    return allocationBytesCompare;
  }

  final liveBytesDeltaCompare = right.liveBytesDelta.compareTo(
    left.liveBytesDelta,
  );
  if (liveBytesDeltaCompare != 0) {
    return liveBytesDeltaCompare;
  }

  final allocationInstancesCompare = right.allocationInstancesDelta.compareTo(
    left.allocationInstancesDelta,
  );
  if (allocationInstancesCompare != 0) {
    return allocationInstancesCompare;
  }

  return left.className.compareTo(right.className);
}

int _sanitizeMemoryValue(int? value) => value == null || value < 0 ? 0 : value;

final class _MutableMemoryClassStats {
  _MutableMemoryClassStats({required this.className, required this.libraryUri});

  final String className;
  final String? libraryUri;

  int accumulatedBytes = 0;
  int accumulatedInstances = 0;
  int liveBytes = 0;
  int liveInstances = 0;
}
