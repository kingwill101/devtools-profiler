import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';
import 'package:devtools_shared/devtools_shared.dart';

import '../capture/models.dart';
import '../cpu/method_table.dart';
import '../memory/memory_models.dart';
import 'profile_comparison_models.dart';

/// Builds a structured comparison between two prepared profile summaries.
ProfileRegionComparison compareProfileRegions({
  required ProfileRegionResult baseline,
  required ProfileRegionResult current,
  ProfileMethodTable? baselineMethodTable,
  ProfileMethodTable? currentMethodTable,
  int? frameLimit,
  int? methodLimit,
  int? memoryClassLimit,
  ProfileMemoryResult? baselineMemoryOverride,
  ProfileMemoryResult? currentMemoryOverride,
}) {
  final warnings = <String>[];
  if (baseline.name != current.name) {
    warnings.add(
      'The compared profile names differ: '
      '"${baseline.name}" vs "${current.name}".',
    );
  }
  if (!_sameStringMap(baseline.attributes, current.attributes)) {
    warnings.add('The compared profile attributes differ.');
  }
  if (!_sameCaptureKinds(baseline.captureKinds, current.captureKinds)) {
    warnings.add('The compared capture kinds differ.');
  }
  if (baseline.isolateScope != current.isolateScope) {
    warnings.add(
      'The compared isolate scopes differ: '
      '${baseline.isolateScope.name} vs ${current.isolateScope.name}.',
    );
  }
  if ((baseline.memory == null) != (current.memory == null)) {
    warnings.add('Memory data was only available for one compared profile.');
  }
  if ((baselineMethodTable == null) != (currentMethodTable == null)) {
    warnings.add(
      'Method table data was only available for one compared profile.',
    );
  }

  final topSelfFrames = _limitList(
    _buildFrameDeltas(
      baseline.topSelfFrames,
      current.topSelfFrames,
      baseline.topTotalFrames,
      current.topTotalFrames,
      sortBySelf: true,
    ),
    frameLimit,
  );
  final topTotalFrames = _limitList(
    _buildFrameDeltas(
      baseline.topSelfFrames,
      current.topSelfFrames,
      baseline.topTotalFrames,
      current.topTotalFrames,
      sortBySelf: false,
    ),
    frameLimit,
  );
  final methods = (baselineMethodTable == null && currentMethodTable == null)
      ? const <ProfileMethodDelta>[]
      : _limitList(
          _buildMethodDeltas(
            baselineMethodTable?.methods ?? const [],
            currentMethodTable?.methods ?? const [],
          ),
          methodLimit,
        );

  final memory = switch ((
    baselineMemoryOverride ?? baseline.memory,
    currentMemoryOverride ?? current.memory,
  )) {
    (null, null) => null,
    (final ProfileMemoryResult left, final ProfileMemoryResult right) =>
      _buildMemoryComparison(left, right, memoryClassLimit: memoryClassLimit),
    (final ProfileMemoryResult left, null) => _buildMemoryComparison(
      left,
      _emptyMemoryResult(left.start.timestamp, left.end.timestamp),
      memoryClassLimit: memoryClassLimit,
    ),
    (null, final ProfileMemoryResult right) => _buildMemoryComparison(
      _emptyMemoryResult(right.start.timestamp, right.end.timestamp),
      right,
      memoryClassLimit: memoryClassLimit,
    ),
  };

  return ProfileRegionComparison(
    baselineRegionId: baseline.regionId,
    currentRegionId: current.regionId,
    baselineName: baseline.name,
    currentName: current.name,
    baselineAttributes: baseline.attributes,
    currentAttributes: current.attributes,
    durationMicros: ProfileNumericDelta(
      baseline: baseline.durationMicros,
      current: current.durationMicros,
    ),
    sampleCount: ProfileNumericDelta(
      baseline: baseline.sampleCount,
      current: current.sampleCount,
    ),
    samplePeriodMicros: ProfileNumericDelta(
      baseline: baseline.samplePeriodMicros,
      current: current.samplePeriodMicros,
    ),
    topSelfFrames: topSelfFrames,
    topTotalFrames: topTotalFrames,
    methods: methods,
    memory: memory,
    warnings: warnings,
  );
}

List<ProfileFrameDelta> _buildFrameDeltas(
  List<ProfileFrameSummary> baselineSelfFrames,
  List<ProfileFrameSummary> currentSelfFrames,
  List<ProfileFrameSummary> baselineTotalFrames,
  List<ProfileFrameSummary> currentTotalFrames, {
  required bool sortBySelf,
}) {
  final baselineSelfById = {
    for (final frame in baselineSelfFrames) _frameId(frame): frame,
  };
  final currentSelfById = {
    for (final frame in currentSelfFrames) _frameId(frame): frame,
  };
  final baselineTotalById = {
    for (final frame in baselineTotalFrames) _frameId(frame): frame,
  };
  final currentTotalById = {
    for (final frame in currentTotalFrames) _frameId(frame): frame,
  };
  final frameIds = <String>{
    ...baselineSelfById.keys,
    ...currentSelfById.keys,
    ...baselineTotalById.keys,
    ...currentTotalById.keys,
  };

  final deltas = <ProfileFrameDelta>[
    for (final frameId in frameIds)
      _buildFrameDelta(
        frameId,
        baselineSelfById[frameId],
        currentSelfById[frameId],
        baselineTotalById[frameId],
        currentTotalById[frameId],
      ),
  ];

  deltas.sort(sortBySelf ? _compareSelfFrameDeltas : _compareTotalFrameDeltas);
  return deltas;
}

ProfileFrameDelta _buildFrameDelta(
  String frameId,
  ProfileFrameSummary? baselineSelf,
  ProfileFrameSummary? currentSelf,
  ProfileFrameSummary? baselineTotal,
  ProfileFrameSummary? currentTotal,
) {
  final sampleFrame =
      baselineSelf ?? currentSelf ?? baselineTotal ?? currentTotal;
  return ProfileFrameDelta(
    frameId: frameId,
    name: sampleFrame?.name ?? 'unknown',
    kind: sampleFrame?.kind ?? 'unknown',
    location: sampleFrame?.location,
    selfSamples: ProfileNumericDelta(
      baseline: baselineSelf?.selfSamples ?? 0,
      current: currentSelf?.selfSamples ?? 0,
    ),
    totalSamples: ProfileNumericDelta(
      baseline: baselineTotal?.totalSamples ?? 0,
      current: currentTotal?.totalSamples ?? 0,
    ),
    selfPercent: ProfileNumericDelta(
      baseline: baselineSelf?.selfPercent ?? 0.0,
      current: currentSelf?.selfPercent ?? 0.0,
    ),
    totalPercent: ProfileNumericDelta(
      baseline: baselineTotal?.totalPercent ?? 0.0,
      current: currentTotal?.totalPercent ?? 0.0,
    ),
  );
}

List<ProfileMethodDelta> _buildMethodDeltas(
  List<ProfileMethodSummary> baselineMethods,
  List<ProfileMethodSummary> currentMethods,
) {
  final baselineById = {
    for (final method in baselineMethods) _methodId(method): method,
  };
  final currentById = {
    for (final method in currentMethods) _methodId(method): method,
  };
  final methodIds = <String>{...baselineById.keys, ...currentById.keys};

  final deltas = <ProfileMethodDelta>[
    for (final methodId in methodIds)
      _buildMethodDelta(
        methodId,
        baselineById[methodId],
        currentById[methodId],
      ),
  ];
  deltas.sort(_compareMethodDeltas);
  return deltas;
}

ProfileMethodDelta _buildMethodDelta(
  String methodId,
  ProfileMethodSummary? baseline,
  ProfileMethodSummary? current,
) {
  final sampleMethod = baseline ?? current;
  return ProfileMethodDelta(
    methodId: methodId,
    name: sampleMethod?.name ?? 'unknown',
    kind: sampleMethod?.kind ?? 'unknown',
    location: sampleMethod?.location,
    selfSamples: ProfileNumericDelta(
      baseline: baseline?.selfSamples ?? 0,
      current: current?.selfSamples ?? 0,
    ),
    totalSamples: ProfileNumericDelta(
      baseline: baseline?.totalSamples ?? 0,
      current: current?.totalSamples ?? 0,
    ),
    selfPercent: ProfileNumericDelta(
      baseline: baseline?.selfPercent ?? 0.0,
      current: current?.selfPercent ?? 0.0,
    ),
    totalPercent: ProfileNumericDelta(
      baseline: baseline?.totalPercent ?? 0.0,
      current: current?.totalPercent ?? 0.0,
    ),
    selfMicros: ProfileNumericDelta(
      baseline: baseline?.selfMicros ?? 0,
      current: current?.selfMicros ?? 0,
    ),
    totalMicros: ProfileNumericDelta(
      baseline: baseline?.totalMicros ?? 0,
      current: current?.totalMicros ?? 0,
    ),
  );
}

ProfileMemoryComparison _buildMemoryComparison(
  ProfileMemoryResult baseline,
  ProfileMemoryResult current, {
  int? memoryClassLimit,
}) {
  final baselineById = {
    for (final item in baseline.topClasses) _memoryClassId(item): item,
  };
  final currentById = {
    for (final item in current.topClasses) _memoryClassId(item): item,
  };
  final classIds = <String>{...baselineById.keys, ...currentById.keys};
  final topClasses = <ProfileMemoryClassDelta>[
    for (final classId in classIds)
      _buildMemoryClassDelta(
        classId,
        baselineById[classId],
        currentById[classId],
      ),
  ]..sort(_compareMemoryClassDeltas);

  return ProfileMemoryComparison(
    heapBytes: ProfileNumericDelta(
      baseline: baseline.deltaHeapBytes,
      current: current.deltaHeapBytes,
    ),
    externalBytes: ProfileNumericDelta(
      baseline: baseline.deltaExternalBytes,
      current: current.deltaExternalBytes,
    ),
    capacityBytes: ProfileNumericDelta(
      baseline: baseline.deltaCapacityBytes,
      current: current.deltaCapacityBytes,
    ),
    classCount: ProfileNumericDelta(
      baseline: baseline.classCount,
      current: current.classCount,
    ),
    topClasses: _limitList(topClasses, memoryClassLimit),
  );
}

ProfileMemoryClassDelta _buildMemoryClassDelta(
  String classId,
  ProfileMemoryClassSummary? baseline,
  ProfileMemoryClassSummary? current,
) {
  final sampleClass = baseline ?? current;
  return ProfileMemoryClassDelta(
    className: sampleClass?.className ?? classId,
    libraryUri: sampleClass?.libraryUri,
    allocationBytesDelta: ProfileNumericDelta(
      baseline: baseline?.allocationBytesDelta ?? 0,
      current: current?.allocationBytesDelta ?? 0,
    ),
    allocationInstancesDelta: ProfileNumericDelta(
      baseline: baseline?.allocationInstancesDelta ?? 0,
      current: current?.allocationInstancesDelta ?? 0,
    ),
    liveBytes: ProfileNumericDelta(
      baseline: baseline?.liveBytes ?? 0,
      current: current?.liveBytes ?? 0,
    ),
    liveBytesDelta: ProfileNumericDelta(
      baseline: baseline?.liveBytesDelta ?? 0,
      current: current?.liveBytesDelta ?? 0,
    ),
    liveInstances: ProfileNumericDelta(
      baseline: baseline?.liveInstances ?? 0,
      current: current?.liveInstances ?? 0,
    ),
    liveInstancesDelta: ProfileNumericDelta(
      baseline: baseline?.liveInstancesDelta ?? 0,
      current: current?.liveInstancesDelta ?? 0,
    ),
  );
}

ProfileMemoryResult _emptyMemoryResult(int startTimestamp, int endTimestamp) {
  return ProfileMemoryResult(
    start: HeapSample(startTimestamp, 0, 0, 0, 0, false, null, null, null),
    end: HeapSample(endTimestamp, 0, 0, 0, 0, false, null, null, null),
    deltaHeapBytes: 0,
    deltaExternalBytes: 0,
    deltaCapacityBytes: 0,
    classCount: 0,
    topClasses: const [],
  );
}

String _frameId(ProfileFrameSummary frame) =>
    '${frame.name}|${frame.kind}|${frame.location ?? ''}';

String _methodId(ProfileMethodSummary method) {
  if (method.methodId.isNotEmpty) {
    return method.methodId;
  }
  return '${method.name}|${method.kind}|${method.location ?? ''}';
}

String _memoryClassId(ProfileMemoryClassSummary item) =>
    '${item.className}|${item.libraryUri ?? ''}';

int _compareSelfFrameDeltas(ProfileFrameDelta left, ProfileFrameDelta right) {
  final selfCompare = _compareByAbsoluteDelta(
    left.selfSamples.delta,
    right.selfSamples.delta,
  );
  if (selfCompare != 0) {
    return selfCompare;
  }
  final totalCompare = _compareByAbsoluteDelta(
    left.totalSamples.delta,
    right.totalSamples.delta,
  );
  if (totalCompare != 0) {
    return totalCompare;
  }
  return left.name.compareTo(right.name);
}

int _compareTotalFrameDeltas(ProfileFrameDelta left, ProfileFrameDelta right) {
  final totalCompare = _compareByAbsoluteDelta(
    left.totalSamples.delta,
    right.totalSamples.delta,
  );
  if (totalCompare != 0) {
    return totalCompare;
  }
  final selfCompare = _compareByAbsoluteDelta(
    left.selfSamples.delta,
    right.selfSamples.delta,
  );
  if (selfCompare != 0) {
    return selfCompare;
  }
  return left.name.compareTo(right.name);
}

int _compareMethodDeltas(ProfileMethodDelta left, ProfileMethodDelta right) {
  final totalCompare = _compareByAbsoluteDelta(
    left.totalSamples.delta,
    right.totalSamples.delta,
  );
  if (totalCompare != 0) {
    return totalCompare;
  }
  final selfCompare = _compareByAbsoluteDelta(
    left.selfSamples.delta,
    right.selfSamples.delta,
  );
  if (selfCompare != 0) {
    return selfCompare;
  }
  return left.name.compareTo(right.name);
}

int _compareMemoryClassDeltas(
  ProfileMemoryClassDelta left,
  ProfileMemoryClassDelta right,
) {
  final allocationCompare = _compareByAbsoluteDelta(
    left.allocationBytesDelta.delta,
    right.allocationBytesDelta.delta,
  );
  if (allocationCompare != 0) {
    return allocationCompare;
  }
  final liveCompare = _compareByAbsoluteDelta(
    left.liveBytesDelta.delta,
    right.liveBytesDelta.delta,
  );
  if (liveCompare != 0) {
    return liveCompare;
  }
  return left.className.compareTo(right.className);
}

int _compareByAbsoluteDelta(num left, num right) {
  final absoluteCompare = right.abs().compareTo(left.abs());
  if (absoluteCompare != 0) {
    return absoluteCompare;
  }
  return right.compareTo(left);
}

List<T> _limitList<T>(List<T> items, int? limit) {
  if (limit == null || items.length <= limit) {
    return items;
  }
  return items.take(limit).toList(growable: false);
}

bool _sameCaptureKinds(
  List<ProfileCaptureKind> baseline,
  List<ProfileCaptureKind> current,
) {
  if (baseline.length != current.length) {
    return false;
  }
  for (var index = 0; index < baseline.length; index++) {
    if (baseline[index] != current[index]) {
      return false;
    }
  }
  return true;
}

bool _sameStringMap(Map<String, String> baseline, Map<String, String> current) {
  if (baseline.length != current.length) {
    return false;
  }
  for (final entry in baseline.entries) {
    if (current[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
