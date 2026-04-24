import 'dart:math';

import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:vm_service/vm_service.dart';

import '../../memory/memory_models.dart';

/// Mutable state for a currently open explicit region capture.
final class ActiveProfileRegion {
  const ActiveProfileRegion({
    required this.attributes,
    required this.isolateId,
    required this.memoryStartSnapshot,
    required this.name,
    required this.options,
    required this.parentRegionId,
    required this.regionId,
    required this.startTimestampMicros,
  });

  final Map<String, String> attributes;
  final String isolateId;
  final MemoryCaptureSnapshot? memoryStartSnapshot;
  final String name;
  final ProfileRegionOptions options;
  final String? parentRegionId;
  final String regionId;
  final int startTimestampMicros;
}

/// Aggregated CPU and memory snapshot data for one capture window.
final class RegionCaptureSnapshot {
  const RegionCaptureSnapshot({
    required this.cpuSamples,
    required this.isolateIds,
    required this.memory,
    required this.rawMemoryPayload,
  });

  final CpuSamples? cpuSamples;
  final List<String> isolateIds;
  final ProfileMemoryResult? memory;
  final Map<String, Object?>? rawMemoryPayload;
}

/// Raw CPU samples captured for one set of isolates.
final class CpuCaptureSnapshot {
  const CpuCaptureSnapshot({
    required this.cpuSamples,
    required this.isolateIds,
  });

  final CpuSamples cpuSamples;
  final List<String> isolateIds;
}

/// Raw memory state captured for one set of isolates.
final class MemoryCaptureSnapshot {
  const MemoryCaptureSnapshot({
    required this.heapSample,
    required this.isolateIds,
    required this.profiles,
  });

  final HeapSample heapSample;
  final List<String> isolateIds;
  final List<AllocationProfileSnapshot> profiles;
}

/// Allocation-profile data captured for a single isolate.
final class AllocationProfileSnapshot {
  const AllocationProfileSnapshot({
    required this.isolateId,
    required this.profile,
  });

  final String isolateId;
  final AllocationProfile profile;
}

/// Builds the stored raw memory artifact payload for a capture window.
Map<String, Object?> buildRawMemoryPayload({
  required MemoryCaptureSnapshot startSnapshot,
  required MemoryCaptureSnapshot endSnapshot,
}) {
  return {
    'type': 'ProfileMemoryArtifact',
    'isolateIds': [
      for (final isolateId in {
        ...startSnapshot.isolateIds,
        ...endSnapshot.isolateIds,
      })
        isolateId,
    ],
    'start': {
      'heapSample': startSnapshot.heapSample.toJson(),
      'profiles': [
        for (final snapshot in startSnapshot.profiles)
          {
            'isolateId': snapshot.isolateId,
            'allocationProfile': snapshot.profile.toJson(),
          },
      ],
    },
    'end': {
      'heapSample': endSnapshot.heapSample.toJson(),
      'profiles': [
        for (final snapshot in endSnapshot.profiles)
          {
            'isolateId': snapshot.isolateId,
            'allocationProfile': snapshot.profile.toJson(),
          },
      ],
    },
  };
}

/// Merges per-isolate memory usage into one non-negative aggregate.
MemoryUsage mergeMemoryUsage(Iterable<MemoryUsage?> usages) {
  var externalUsage = 0;
  var heapCapacity = 0;
  var heapUsage = 0;
  for (final usage in usages) {
    externalUsage += max(usage?.externalUsage ?? 0, 0);
    heapCapacity += max(usage?.heapCapacity ?? 0, 0);
    heapUsage += max(usage?.heapUsage ?? 0, 0);
  }
  return MemoryUsage(
    externalUsage: externalUsage,
    heapCapacity: heapCapacity,
    heapUsage: heapUsage,
  );
}
