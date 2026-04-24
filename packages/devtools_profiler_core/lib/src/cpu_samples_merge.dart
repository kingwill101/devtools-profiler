
import 'package:vm_service/vm_service.dart';

/// Merges multiple isolate-local CPU sample payloads into one synthetic profile.
///
/// The merged profile preserves every source function by appending function
/// tables and rewriting sample stack indices to the new offsets.
CpuSamples mergeCpuSamples(Iterable<CpuSamples> cpuSamplesByIsolate) {
  final cpuSamplesList = cpuSamplesByIsolate.toList(growable: false);
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
  if (cpuSamplesList.length == 1) {
    return cpuSamplesList.single;
  }

  final mergedFunctions = <ProfileFunction>[];
  final mergedSamples = <CpuSample>[];

  var sampleCount = 0;
  int? samplePeriodMicros;
  int? timeOriginMicros;
  int? endTimestampMicros;

  for (final cpuSamples in cpuSamplesList) {
    final functions = cpuSamples.functions ?? const <ProfileFunction>[];
    final samples = cpuSamples.samples ?? const <CpuSample>[];
    final functionIndexOffset = mergedFunctions.length;
    mergedFunctions.addAll(functions);
    mergedSamples.addAll(
      [
        for (final sample in samples)
          CpuSample(
            timestamp: sample.timestamp,
            stack: switch (sample.stack) {
              final List<int> stack => [
                  for (final frameIndex in stack)
                    frameIndex + functionIndexOffset
                ],
              _ => null,
            },
          ),
      ],
    );

    sampleCount += cpuSamples.sampleCount ?? samples.length;

    final candidateSamplePeriod = cpuSamples.samplePeriod;
    if (samplePeriodMicros == null ||
        samplePeriodMicros == 0 && candidateSamplePeriod != null) {
      samplePeriodMicros = candidateSamplePeriod;
    }

    final candidateOrigin = cpuSamples.timeOriginMicros;
    if (candidateOrigin != null) {
      timeOriginMicros = switch (timeOriginMicros) {
        final int current when current <= candidateOrigin => current,
        _ => candidateOrigin,
      };
    }

    final candidateEnd = switch ((
      cpuSamples.timeOriginMicros,
      cpuSamples.timeExtentMicros,
    )) {
      (final int origin, final int extent) => origin + extent,
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
    sampleCount: sampleCount == 0 ? mergedSamples.length : sampleCount,
    samplePeriod: samplePeriodMicros ?? 0,
    timeOriginMicros: normalizedOrigin,
    timeExtentMicros: normalizedEnd - normalizedOrigin,
    functions: mergedFunctions,
    samples: mergedSamples,
  );
}
