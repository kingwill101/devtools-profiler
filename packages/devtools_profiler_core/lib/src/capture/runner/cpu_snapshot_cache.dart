import 'package:vm_service/vm_service.dart';

/// Retains the latest full payload per observed isolate, not repeated polls.
///
/// Exited isolates cannot be queried through getCpuSamples. Retaining a bounded
/// set preserves workers seen in earlier polls. This is best-effort: workers
/// that start and exit entirely between polls are still unobservable.
final class CpuSnapshotCache {
  CpuSnapshotCache({this.capacity = 64, this.maxStackEntries = 2_000_000}) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
    if (maxStackEntries < 1) {
      throw ArgumentError.value(maxStackEntries, 'maxStackEntries');
    }
  }

  final int capacity;
  final int maxStackEntries;
  final Map<String, CpuSamples> _samples = {};
  final Map<String, int> _weights = {};
  int _stackEntries = 0;

  /// Replaces a cumulative payload and returns ids evicted by either bound.
  List<String> record(String isolateId, CpuSamples samples) {
    _samples.remove(isolateId);
    _stackEntries -= _weights.remove(isolateId) ?? 0;
    _samples[isolateId] = samples;
    final weight = (samples.samples ?? const <CpuSample>[]).fold<int>(
      0,
      (total, sample) => total + (sample.stack?.length ?? 0),
    );
    _weights[isolateId] = weight;
    _stackEntries += weight;
    final evicted = <String>[];
    while (_samples.length > capacity || _stackEntries > maxStackEntries) {
      final id = _samples.keys.first;
      _samples.remove(id);
      _stackEntries -= _weights.remove(id)!;
      evicted.add(id);
    }
    return evicted;
  }

  /// Adds cached, nonempty windows for isolates missing from [current].
  ///
  /// Current responses always win. Window clipping prevents samples from an
  /// earlier region from leaking into a later one.
  Map<String, CpuSamples> withMissingIsolates(
    Map<String, CpuSamples> current, {
    required int startTimestampMicros,
    required int timeExtentMicros,
  }) {
    final result = {...current};
    for (final entry in _samples.entries) {
      if (result.containsKey(entry.key)) continue;
      final clipped = clipCpuSnapshot(
        entry.value,
        startTimestampMicros: startTimestampMicros,
        timeExtentMicros: timeExtentMicros,
      );
      if (clipped.samples!.isNotEmpty) result[entry.key] = clipped;
    }
    return result;
  }
}

/// Clips current and retained snapshots with the same inclusive time bounds.
CpuSamples clipCpuSnapshot(
  CpuSamples source, {
  required int startTimestampMicros,
  required int timeExtentMicros,
}) {
  final end = startTimestampMicros + timeExtentMicros;
  final samples = [
    for (final sample in source.samples ?? const <CpuSample>[])
      if (sample.timestamp case final timestamp?
          when timestamp >= startTimestampMicros && timestamp <= end)
        sample,
  ];
  final times = samples.map((sample) => sample.timestamp!);
  final first = samples.isEmpty
      ? startTimestampMicros
      : times.reduce((a, b) => a < b ? a : b);
  final last = samples.isEmpty ? first : times.reduce((a, b) => a > b ? a : b);
  return CpuSamples(
    sampleCount: samples.length,
    samplePeriod: source.samplePeriod,
    maxStackDepth: source.maxStackDepth,
    pid: source.pid,
    timeOriginMicros: first,
    timeExtentMicros: last - first,
    functions: source.functions,
    samples: samples,
  );
}
