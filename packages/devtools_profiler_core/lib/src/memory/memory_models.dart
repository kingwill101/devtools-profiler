import 'package:devtools_shared/devtools_shared.dart';

/// A per-class memory summary for a profiled region or session.
class ProfileMemoryClassSummary {
  /// Creates a memory class summary.
  const ProfileMemoryClassSummary({
    required this.className,
    required this.allocationBytesDelta,
    required this.allocationInstancesDelta,
    required this.liveBytes,
    required this.liveBytesDelta,
    required this.liveInstances,
    required this.liveInstancesDelta,
    this.libraryUri,
  });

  /// Deserializes a memory class summary from JSON.
  factory ProfileMemoryClassSummary.fromJson(Map<String, Object?> json) {
    return ProfileMemoryClassSummary(
      className: json['className'] as String? ?? 'unknown',
      libraryUri: json['libraryUri'] as String?,
      allocationBytesDelta: json['allocationBytesDelta'] as int? ?? 0,
      allocationInstancesDelta: json['allocationInstancesDelta'] as int? ?? 0,
      liveBytes: json['liveBytes'] as int? ?? 0,
      liveBytesDelta: json['liveBytesDelta'] as int? ?? 0,
      liveInstances: json['liveInstances'] as int? ?? 0,
      liveInstancesDelta: json['liveInstancesDelta'] as int? ?? 0,
    );
  }

  /// The class display name.
  final String className;

  /// The owning library URI when the VM reported one.
  final String? libraryUri;

  /// The change in accumulated allocated bytes across the region window.
  final int allocationBytesDelta;

  /// The change in accumulated allocated instances across the region window.
  final int allocationInstancesDelta;

  /// The live bytes reported at the end of the region window.
  final int liveBytes;

  /// The change in live bytes across the region window.
  final int liveBytesDelta;

  /// The live instance count reported at the end of the region window.
  final int liveInstances;

  /// The change in live instances across the region window.
  final int liveInstancesDelta;

  /// Converts this class summary to JSON.
  Map<String, Object?> toJson() => {
    'className': className,
    'libraryUri': libraryUri,
    'allocationBytesDelta': allocationBytesDelta,
    'allocationInstancesDelta': allocationInstancesDelta,
    'liveBytes': liveBytes,
    'liveBytesDelta': liveBytesDelta,
    'liveInstances': liveInstances,
    'liveInstancesDelta': liveInstancesDelta,
  };
}

/// Memory summary data captured for a profiled region or session.
class ProfileMemoryResult {
  /// Creates a memory summary result.
  ProfileMemoryResult({
    required this.start,
    required this.end,
    required this.deltaHeapBytes,
    required this.deltaExternalBytes,
    required this.deltaCapacityBytes,
    required this.classCount,
    required List<ProfileMemoryClassSummary> topClasses,
    this.rawProfilePath,
  }) : topClasses = List.unmodifiable(topClasses);

  /// Deserializes a memory summary result from JSON.
  factory ProfileMemoryResult.fromJson(Map<String, Object?> json) {
    return ProfileMemoryResult(
      start: HeapSample.fromJson(
        (json['start'] as Map<Object?, Object?>).cast<String, Object?>(),
      ),
      end: HeapSample.fromJson(
        (json['end'] as Map<Object?, Object?>).cast<String, Object?>(),
      ),
      deltaHeapBytes: json['deltaHeapBytes'] as int? ?? 0,
      deltaExternalBytes: json['deltaExternalBytes'] as int? ?? 0,
      deltaCapacityBytes: json['deltaCapacityBytes'] as int? ?? 0,
      classCount: json['classCount'] as int? ?? 0,
      topClasses: (json['topClasses'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (entry) => ProfileMemoryClassSummary.fromJson(
              entry.cast<String, Object?>(),
            ),
          )
          .toList(),
      rawProfilePath: json['rawProfilePath'] as String?,
    );
  }

  /// Heap usage at the start of the region window.
  final HeapSample start;

  /// Heap usage at the end of the region window.
  final HeapSample end;

  /// The change in used heap bytes across the region window.
  final int deltaHeapBytes;

  /// The change in external bytes across the region window.
  final int deltaExternalBytes;

  /// The change in heap capacity across the region window.
  final int deltaCapacityBytes;

  /// The total number of classes represented by the raw allocation diff.
  final int classCount;

  /// The highest-signal classes from the region memory diff.
  final List<ProfileMemoryClassSummary> topClasses;

  /// The path to the raw memory artifact, when one was written.
  final String? rawProfilePath;

  /// Returns a copy with selected fields replaced.
  ProfileMemoryResult copyWith({
    HeapSample? start,
    HeapSample? end,
    int? deltaHeapBytes,
    int? deltaExternalBytes,
    int? deltaCapacityBytes,
    int? classCount,
    List<ProfileMemoryClassSummary>? topClasses,
    String? rawProfilePath,
    bool clearRawProfilePath = false,
  }) {
    return ProfileMemoryResult(
      start: start ?? this.start,
      end: end ?? this.end,
      deltaHeapBytes: deltaHeapBytes ?? this.deltaHeapBytes,
      deltaExternalBytes: deltaExternalBytes ?? this.deltaExternalBytes,
      deltaCapacityBytes: deltaCapacityBytes ?? this.deltaCapacityBytes,
      classCount: classCount ?? this.classCount,
      topClasses: topClasses ?? this.topClasses,
      rawProfilePath: clearRawProfilePath
          ? null
          : rawProfilePath ?? this.rawProfilePath,
    );
  }

  /// Converts this memory result to JSON.
  Map<String, Object?> toJson() => {
    'start': start.toJson(),
    'end': end.toJson(),
    'deltaHeapBytes': deltaHeapBytes,
    'deltaExternalBytes': deltaExternalBytes,
    'deltaCapacityBytes': deltaCapacityBytes,
    'classCount': classCount,
    'topClasses': [for (final item in topClasses) item.toJson()],
    'rawProfilePath': rawProfilePath,
  };
}
