import 'package:vm_service/vm_service.dart';

/// A VM CPU sample with profiler-recorded isolate provenance.
///
/// [tid] identifies an OS thread, not a Dart isolate. An isolate can migrate
/// between threads, and a thread can execute multiple isolates over time.
final class ProfileCpuSample extends CpuSample {
  /// Copies a VM sample without losing tags, truncation or allocation metadata.
  ProfileCpuSample(CpuSample sample, {required this.isolateId})
    : super(
        tid: sample.tid,
        timestamp: sample.timestamp,
        stack: sample.stack,
        vmTag: sample.vmTag,
        userTag: sample.userTag,
        truncated: sample.truncated,
        identityHashCode: sample.identityHashCode,
        classId: sample.classId,
      );

  /// The VM isolate id recorded at capture time, or null for legacy artifacts.
  final String? isolateId;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    if (isolateId != null) 'profilerIsolateId': isolateId,
  };
}

/// Parses a stored VM CPU profile, restoring untyped function names and origins.
///
/// VM [NativeFunction.toJson] emits a name without a type discriminator.
/// The generic VM parser does not restore these objects on an artifact
/// round-trip. Only explicit names from the artifact are restored here.
CpuSamples? parseProfileCpuSamples(Map<String, dynamic> json) {
  final result = CpuSamples.parse(json);
  if (result == null) return null;
  final rawFunctions = json['functions'] as List? ?? const [];
  final functions = result.functions ?? const <ProfileFunction>[];
  for (var i = 0; i < functions.length; i++) {
    final raw = (rawFunctions[i] as Map)['function'];
    if (functions[i].function == null && raw is Map && raw['name'] is String) {
      functions[i].function = NativeFunction(name: raw['name'] as String);
    }
  }
  final rawSamples = json['samples'] as List? ?? const [];
  final samples = result.samples ?? const <CpuSample>[];
  result.samples = [
    for (var i = 0; i < samples.length; i++)
      ProfileCpuSample(
        samples[i],
        isolateId: (rawSamples[i] as Map)['profilerIsolateId'] as String?,
      ),
  ];
  return result;
}

/// Removes unreferenced functions from a CPU snapshot without changing stacks.
///
/// The VM may return its entire compiled-function table for each isolate.
/// Compact snapshots before retaining them so short-lived workers do not each
/// keep thousands of unrelated Flutter framework functions alive.
CpuSamples compactCpuSamples(CpuSamples source) {
  final functions = source.functions ?? const <ProfileFunction>[];
  final samples = source.samples ?? const <CpuSample>[];
  final referenced = <int>{
    for (final sample in samples)
      for (final index in sample.stack ?? const <int>[])
        if (index >= 0 && index < functions.length) index,
  }.toList()..sort();
  final indices = {
    for (var i = 0; i < referenced.length; i++) referenced[i]: i,
  };
  return CpuSamples(
    sampleCount: source.sampleCount,
    samplePeriod: source.samplePeriod,
    maxStackDepth: source.maxStackDepth,
    pid: source.pid,
    timeOriginMicros: source.timeOriginMicros,
    timeExtentMicros: source.timeExtentMicros,
    functions: [for (final index in referenced) functions[index]],
    samples: [
      for (final sample in samples)
        ProfileCpuSample(
            sample,
            isolateId: sample is ProfileCpuSample ? sample.isolateId : null,
          )
          ..stack = sample.stack == null
              ? null
              : [for (final index in sample.stack!) indices[index] ?? -1],
    ],
  );
}

/// Merges multiple isolate-local CPU sample payloads into one synthetic profile.
///
/// The merged profile preserves every source function by appending function
/// tables and rewriting sample stack indices to the new offsets.
CpuSamples mergeCpuSamples(
  Iterable<CpuSamples> cpuSamplesByIsolate, {
  List<String>? isolateIds,
}) {
  final cpuSamplesList = cpuSamplesByIsolate.toList(growable: false);
  if (isolateIds != null && isolateIds.length != cpuSamplesList.length) {
    throw ArgumentError('Expected one isolate id per CPU sample payload.');
  }
  final periods = {
    for (final source in cpuSamplesList)
      if (source.samplePeriod case final period? when period > 0) period,
  };
  final pids = {
    for (final source in cpuSamplesList)
      if (source.pid case final pid? when pid >= 0) pid,
  };
  if (periods.length > 1 || pids.length > 1) {
    throw ArgumentError(
      'CPU payloads must come from one VM with a common sampling period.',
    );
  }
  if (cpuSamplesList.isEmpty) {
    return CpuSamples(
      sampleCount: 0,
      samplePeriod: 0,
      timeOriginMicros: 0,
      timeExtentMicros: 0,
      functions: const [],
      samples: const [],
    );
  }
  if (cpuSamplesList.length == 1 && isolateIds == null) {
    return cpuSamplesList.single;
  }

  final mergedFunctions = <ProfileFunction>[];
  final mergedSamples = <CpuSample>[];

  var sampleCount = 0;
  int? timeOriginMicros;
  int? endTimestampMicros;

  for (
    var sourceIndex = 0;
    sourceIndex < cpuSamplesList.length;
    sourceIndex++
  ) {
    final cpuSamples = cpuSamplesList[sourceIndex];
    final functions = cpuSamples.functions ?? const <ProfileFunction>[];
    final samples = cpuSamples.samples ?? const <CpuSample>[];
    final functionIndexOffset = mergedFunctions.length;
    mergedFunctions.addAll(functions);
    mergedSamples.addAll([
      for (final sample in samples)
        ProfileCpuSample(
            sample,
            isolateId:
                isolateIds?[sourceIndex] ??
                (sample is ProfileCpuSample ? sample.isolateId : null),
          )
          ..stack = switch (sample.stack) {
            final List<int> stack => [
              for (final frameIndex in stack)
                if (frameIndex >= 0 && frameIndex < functions.length)
                  frameIndex + functionIndexOffset
                else
                  -1,
            ],
            _ => null,
          },
    ]);

    sampleCount += switch (cpuSamples.sampleCount) {
      final count? when count >= 0 => count,
      _ => samples.length,
    };

    final candidateOrigin = cpuSamples.timeOriginMicros;
    if (candidateOrigin != null && candidateOrigin >= 0) {
      timeOriginMicros = switch (timeOriginMicros) {
        final int current when current <= candidateOrigin => current,
        _ => candidateOrigin,
      };
    }

    final candidateEnd = switch ((
      cpuSamples.timeOriginMicros,
      cpuSamples.timeExtentMicros,
    )) {
      (final int origin, final int extent) when origin >= 0 && extent >= 0 =>
        origin + extent,
      _ => null,
    };
    if (candidateEnd != null) {
      endTimestampMicros = switch (endTimestampMicros) {
        final int current when current >= candidateEnd => current,
        _ => candidateEnd,
      };
    }
  }

  mergedSamples.sort(
    (left, right) => (left.timestamp ?? 0).compareTo(right.timestamp ?? 0),
  );

  final normalizedOrigin = timeOriginMicros ?? 0;
  final normalizedEnd = endTimestampMicros ?? normalizedOrigin;
  return CpuSamples(
    pid: pids.singleOrNull,
    maxStackDepth: cpuSamplesList
        .map((samples) => samples.maxStackDepth ?? 0)
        .fold<int>(0, (max, value) => value > max ? value : max),
    sampleCount: sampleCount == 0 ? mergedSamples.length : sampleCount,
    samplePeriod: periods.singleOrNull ?? 0,
    timeOriginMicros: normalizedOrigin,
    timeExtentMicros: normalizedEnd - normalizedOrigin,
    functions: mergedFunctions,
    samples: mergedSamples,
  );
}
