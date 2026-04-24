
import 'package:vm_service/vm_service.dart';

import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';

import 'memory_models.dart';
import 'models.dart';
import 'profile_frames.dart';

/// Builds a [ProfileRegionResult] from raw VM CPU samples.
ProfileRegionResult summarizeCpuSamples({
  required String regionId,
  required String name,
  required Map<String, String> attributes,
  required String isolateId,
  List<String>? isolateIds,
  List<ProfileCaptureKind> captureKinds = defaultProfileCaptureKinds,
  ProfileIsolateScope isolateScope = ProfileIsolateScope.current,
  String? parentRegionId,
  ProfileMemoryResult? memory,
  required int startTimestampMicros,
  required int endTimestampMicros,
  required CpuSamples cpuSamples,
  required String summaryPath,
  String? rawProfilePath,
  int topFrameCount = 10,
  ProfileFramePredicate? includeFrame,
}) {
  final functions = cpuSamples.functions ?? const <ProfileFunction>[];
  final samples = cpuSamples.samples ?? const <CpuSample>[];
  final statsByFrameKey = <String, _MutableFrameStats>{};
  var sampleCount = 0;

  for (final sample in samples) {
    final frames = filterStackFrames(
      sample.stack ?? const <int>[],
      functions,
      includeFrame: includeFrame,
    );
    if (frames.isEmpty) continue;

    sampleCount++;

    final selfFrame = frames.first;
    statsByFrameKey
        .putIfAbsent(
          selfFrame.key,
          () => _MutableFrameStats.fromFrame(selfFrame),
        )
        .selfSamples++;

    final seenFrames = <String>{};
    for (final frame in frames) {
      if (!seenFrames.add(frame.key)) continue;
      statsByFrameKey
          .putIfAbsent(
            frame.key,
            () => _MutableFrameStats.fromFrame(frame),
          )
          .totalSamples++;
    }
  }

  final summaries = [
    for (final stats in statsByFrameKey.values)
      stats.freeze(totalSampleCount: sampleCount),
  ];

  final topSelfFrames = summaries.toList()
    ..sort(_compareSelfDescending)
    .._truncateTo(topFrameCount);

  final topTotalFrames = summaries.toList()
    ..sort(_compareTotalDescending)
    .._truncateTo(topFrameCount);

  return ProfileRegionResult(
    regionId: regionId,
    name: name,
    attributes: attributes,
    isolateId: isolateId,
    isolateIds: isolateIds,
    captureKinds: captureKinds,
    isolateScope: isolateScope,
    parentRegionId: parentRegionId,
    memory: memory,
    startTimestampMicros: startTimestampMicros,
    endTimestampMicros: endTimestampMicros,
    durationMicros: endTimestampMicros - startTimestampMicros,
    sampleCount: sampleCount,
    samplePeriodMicros: cpuSamples.samplePeriod ?? 0,
    topSelfFrames: topSelfFrames,
    topTotalFrames: topTotalFrames,
    rawProfilePath: rawProfilePath,
    summaryPath: summaryPath,
  );
}

int _compareSelfDescending(ProfileFrameSummary a, ProfileFrameSummary b) {
  final selfCompare = b.selfSamples.compareTo(a.selfSamples);
  if (selfCompare != 0) return selfCompare;

  final totalCompare = b.totalSamples.compareTo(a.totalSamples);
  if (totalCompare != 0) return totalCompare;

  return a.name.compareTo(b.name);
}

int _compareTotalDescending(ProfileFrameSummary a, ProfileFrameSummary b) {
  final totalCompare = b.totalSamples.compareTo(a.totalSamples);
  if (totalCompare != 0) return totalCompare;

  final selfCompare = b.selfSamples.compareTo(a.selfSamples);
  if (selfCompare != 0) return selfCompare;

  return a.name.compareTo(b.name);
}

class _MutableFrameStats {
  _MutableFrameStats({
    required this.name,
    required this.kind,
    required this.location,
  });

  factory _MutableFrameStats.fromFrame(ProfileFrame frame) {
    return _MutableFrameStats(
      name: frame.name,
      kind: frame.kind,
      location: frame.location,
    );
  }

  final String name;
  final String kind;
  final String? location;

  int selfSamples = 0;
  int totalSamples = 0;

  ProfileFrameSummary freeze({required int totalSampleCount}) {
    final divisor = totalSampleCount == 0 ? 1 : totalSampleCount;
    return ProfileFrameSummary(
      name: name,
      kind: kind,
      location: location,
      selfSamples: selfSamples,
      totalSamples: totalSamples,
      selfPercent: selfSamples / divisor,
      totalPercent: totalSamples / divisor,
    );
  }
}

extension on List<ProfileFrameSummary> {
  void _truncateTo(int count) {
    if (count <= 0 || count >= length) {
      return;
    }
    removeRange(count, length);
  }
}
