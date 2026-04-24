
import 'dart:convert';

import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';

import 'memory_models.dart';

/// A request to launch and profile a Dart or Flutter command.
class ProfileRunRequest {
  /// Creates a profiling request.
  const ProfileRunRequest({
    required this.command,
    this.workingDirectory,
    this.artifactDirectory,
    this.forwardOutput = false,
    this.environment = const {},
    this.runDuration,
    this.vmServiceTimeout,
  });

  /// The command to launch.
  ///
  /// The first argument must be `dart` or `flutter`.
  final List<String> command;

  /// The working directory to use for the launched process.
  final String? workingDirectory;

  /// The directory where profiling artifacts should be written.
  ///
  /// When omitted, a session directory will be created under `.dart_tool`.
  final String? artifactDirectory;

  /// Whether stdout and stderr from the profiled process should be echoed.
  final bool forwardOutput;

  /// Extra environment variables to inject into the launched process.
  final Map<String, String> environment;

  /// Optional duration to profile before terminating the launched process.
  ///
  /// This is useful for long-running apps such as `flutter run`, where the
  /// process would otherwise keep running until a user stops it manually.
  final Duration? runDuration;

  /// Optional timeout for waiting for the launched process to expose a VM
  /// service URI.
  ///
  /// This is separate from [runDuration]. The profiler starts [runDuration]
  /// only after the VM service is available and attached.
  final Duration? vmServiceTimeout;
}

/// A request to profile an already-running Dart or Flutter VM service.
class ProfileAttachRequest {
  /// Creates an attach profiling request.
  const ProfileAttachRequest({
    required this.vmServiceUri,
    required this.duration,
    this.workingDirectory,
    this.artifactDirectory,
  });

  /// The HTTP URI printed by the Dart or Flutter VM service.
  final Uri vmServiceUri;

  /// How long to collect profile data after attaching.
  final Duration duration;

  /// The working directory associated with the profiled target.
  final String? workingDirectory;

  /// The directory where profiling artifacts should be written.
  ///
  /// When omitted, a session directory will be created under `.dart_tool`.
  final String? artifactDirectory;
}

/// A summary of a single frame observed during CPU sampling.
class ProfileFrameSummary {
  /// Creates a frame summary.
  const ProfileFrameSummary({
    required this.name,
    required this.kind,
    required this.selfSamples,
    required this.totalSamples,
    required this.selfPercent,
    required this.totalPercent,
    this.location,
  });

  /// Deserializes a frame summary from JSON.
  factory ProfileFrameSummary.fromJson(Map<String, Object?> json) {
    return ProfileFrameSummary(
      name: json['name'] as String? ?? 'unknown',
      kind: json['kind'] as String? ?? 'unknown',
      location: json['location'] as String?,
      selfSamples: json['selfSamples'] as int? ?? 0,
      totalSamples: json['totalSamples'] as int? ?? 0,
      selfPercent: (json['selfPercent'] as num?)?.toDouble() ?? 0.0,
      totalPercent: (json['totalPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// The display name of the frame.
  final String name;

  /// The VM-reported frame kind.
  final String kind;

  /// The resolved source location, when available.
  final String? location;

  /// The number of times the frame was observed at the top of the stack.
  final int selfSamples;

  /// The number of times the frame was observed anywhere in the stack.
  final int totalSamples;

  /// The percentage of samples attributed to [selfSamples].
  final double selfPercent;

  /// The percentage of samples attributed to [totalSamples].
  final double totalPercent;

  /// Converts this frame summary to JSON.
  Map<String, Object?> toJson() => {
        'name': name,
        'kind': kind,
        'location': location,
        'selfSamples': selfSamples,
        'totalSamples': totalSamples,
        'selfPercent': selfPercent,
        'totalPercent': totalPercent,
      };
}

/// A summary of profiling data for a marked region.
class ProfileRegionResult {
  /// Creates a region profiling result.
  ProfileRegionResult({
    required this.regionId,
    required this.name,
    required this.attributes,
    required this.isolateId,
    required this.startTimestampMicros,
    required this.endTimestampMicros,
    required this.durationMicros,
    required this.sampleCount,
    required this.samplePeriodMicros,
    required this.topSelfFrames,
    required this.topTotalFrames,
    required this.summaryPath,
    this.memory,
    this.parentRegionId,
    List<String>? isolateIds,
    List<ProfileCaptureKind> captureKinds = defaultProfileCaptureKinds,
    this.isolateScope = ProfileIsolateScope.current,
    this.rawProfilePath,
    this.error,
  })  : isolateIds = List.unmodifiable(
          isolateIds ??
              (isolateId.isEmpty ? const <String>[] : <String>[isolateId]),
        ),
        captureKinds =
            List.unmodifiable(normalizeProfileCaptureKinds(captureKinds));

  /// Deserializes a region profiling result from JSON.
  factory ProfileRegionResult.fromJson(Map<String, Object?> json) {
    return ProfileRegionResult(
      regionId: json['regionId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      attributes: _castStringMap(json['attributes']),
      isolateId: json['isolateId'] as String? ?? '',
      isolateIds: _castStringList(json['isolateIds']) ??
          _legacyIsolateIds(json['isolateId'] as String?),
      parentRegionId: json['parentRegionId'] as String?,
      captureKinds: switch (json['captureKinds']) {
        final List<Object?> values => [
            for (final value in values)
              ProfileCaptureKind.parse(value.toString()),
          ],
        _ => defaultProfileCaptureKinds,
      },
      isolateScope: switch (json['isolateScope']) {
        final String value => ProfileIsolateScope.parse(value),
        _ => ProfileIsolateScope.current,
      },
      startTimestampMicros: json['startTimestampMicros'] as int? ?? 0,
      endTimestampMicros: json['endTimestampMicros'] as int? ?? 0,
      durationMicros: json['durationMicros'] as int? ?? 0,
      sampleCount: json['sampleCount'] as int? ?? 0,
      samplePeriodMicros: json['samplePeriodMicros'] as int? ?? 0,
      topSelfFrames: (json['topSelfFrames'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map((frame) => ProfileFrameSummary.fromJson(_castJsonMap(frame)))
          .toList(),
      topTotalFrames: (json['topTotalFrames'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map((frame) => ProfileFrameSummary.fromJson(_castJsonMap(frame)))
          .toList(),
      memory: switch (json['memory']) {
        final Map<Object?, Object?> memory =>
          ProfileMemoryResult.fromJson(_castJsonMap(memory)),
        _ => null,
      },
      summaryPath: json['summaryPath'] as String? ?? '',
      rawProfilePath: json['rawProfilePath'] as String?,
      error: json['error'] as String?,
    );
  }

  /// The region identifier generated by the helper package.
  final String regionId;

  /// The user-provided region name.
  final String name;

  /// Extra attributes attached to the region.
  final Map<String, String> attributes;

  /// The isolate ID that emitted the region markers.
  final String isolateId;

  /// The isolate IDs included in the capture.
  final List<String> isolateIds;

  /// The capture kinds included in the region result.
  final List<ProfileCaptureKind> captureKinds;

  /// The isolate scope used for the capture.
  final ProfileIsolateScope isolateScope;

  /// The parent region id when this region was started inside another region.
  final String? parentRegionId;

  /// The region start timestamp from `Timeline.now`.
  final int startTimestampMicros;

  /// The region stop timestamp from `Timeline.now`.
  final int endTimestampMicros;

  /// The total duration of the region.
  final int durationMicros;

  /// The number of CPU samples captured for the region.
  final int sampleCount;

  /// The profiler sample period reported by the VM.
  final int samplePeriodMicros;

  /// The highest self-cost frames for the region.
  final List<ProfileFrameSummary> topSelfFrames;

  /// The highest inclusive-cost frames for the region.
  final List<ProfileFrameSummary> topTotalFrames;

  /// Memory and allocation summary data, when captured.
  final ProfileMemoryResult? memory;

  /// The path to the raw CPU profile artifact when capture succeeded.
  final String? rawProfilePath;

  /// The path to the JSON summary artifact for this region.
  final String summaryPath;

  /// The capture error, when the region could not be profiled successfully.
  final String? error;

  /// Whether the region captured successfully.
  bool get succeeded => error == null;

  /// Converts this region result to JSON.
  Map<String, Object?> toJson() => {
        'regionId': regionId,
        'name': name,
        'attributes': attributes,
        'isolateId': isolateId,
        'isolateIds': isolateIds,
        'captureKinds': [for (final kind in captureKinds) kind.name],
        'isolateScope': isolateScope.name,
        'parentRegionId': parentRegionId,
        'startTimestampMicros': startTimestampMicros,
        'endTimestampMicros': endTimestampMicros,
        'durationMicros': durationMicros,
        'sampleCount': sampleCount,
        'samplePeriodMicros': samplePeriodMicros,
        'topSelfFrames': topSelfFrames.map((frame) => frame.toJson()).toList(),
        'topTotalFrames':
            topTotalFrames.map((frame) => frame.toJson()).toList(),
        if (memory != null) 'memory': memory!.toJson(),
        'summaryPath': summaryPath,
        'rawProfilePath': rawProfilePath,
        'error': error,
      };
}

/// A full profiling session result.
class ProfileRunResult {
  /// Creates a profiling session result.
  ProfileRunResult({
    required this.sessionId,
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
    required this.artifactDirectory,
    required this.regions,
    required this.warnings,
    List<ProfileCaptureKind> supportedCaptureKinds = defaultProfileCaptureKinds,
    List<ProfileIsolateScope> supportedIsolateScopes = const [
      ProfileIsolateScope.current,
      ProfileIsolateScope.all,
    ],
    this.terminatedByProfiler = false,
    this.overallProfile,
    this.vmServiceUri,
  })  : supportedCaptureKinds = List.unmodifiable(
          normalizeProfileCaptureKinds(supportedCaptureKinds),
        ),
        supportedIsolateScopes = List.unmodifiable(
          normalizeProfileIsolateScopes(supportedIsolateScopes),
        );

  /// Deserializes a profiling session result from JSON.
  factory ProfileRunResult.fromJson(Map<String, Object?> json) {
    return ProfileRunResult(
      sessionId: json['sessionId'] as String? ?? '',
      command: (json['command'] as List<Object?>? ?? const [])
          .map((value) => value as String)
          .toList(),
      workingDirectory: json['workingDirectory'] as String? ?? '',
      exitCode: json['exitCode'] as int? ?? 0,
      artifactDirectory: json['artifactDirectory'] as String? ?? '',
      vmServiceUri: json['vmServiceUri'] as String?,
      terminatedByProfiler: json['terminatedByProfiler'] as bool? ?? false,
      supportedCaptureKinds: switch (json['supportedCaptureKinds']) {
        final List<Object?> values => [
            for (final value in values)
              ProfileCaptureKind.parse(value.toString()),
          ],
        _ => defaultProfileCaptureKinds,
      },
      supportedIsolateScopes: switch (json['supportedIsolateScopes']) {
        final List<Object?> values => [
            for (final value in values)
              ProfileIsolateScope.parse(value.toString()),
          ],
        _ => const [ProfileIsolateScope.current, ProfileIsolateScope.all],
      },
      overallProfile: switch (json['overallProfile']) {
        final Map<Object?, Object?> profile =>
          ProfileRegionResult.fromJson(_castJsonMap(profile)),
        _ => null,
      },
      regions: (json['regions'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map((region) => ProfileRegionResult.fromJson(_castJsonMap(region)))
          .toList(),
      warnings: (json['warnings'] as List<Object?>? ?? const [])
          .map((value) => value as String)
          .toList(),
    );
  }

  /// The session identifier shared with the launched process.
  final String sessionId;

  /// The launched command.
  final List<String> command;

  /// The working directory used for the process.
  final String workingDirectory;

  /// The process exit code.
  final int exitCode;

  /// Whether the profiler stopped the process after a requested run duration.
  final bool terminatedByProfiler;

  /// The directory containing the session artifacts.
  final String artifactDirectory;

  /// The VM service URI used for the profiling session.
  final String? vmServiceUri;

  /// Capture kinds supported by the profiler backend.
  final List<ProfileCaptureKind> supportedCaptureKinds;

  /// Isolate scopes supported by the profiler backend.
  final List<ProfileIsolateScope> supportedIsolateScopes;

  /// The whole-session profile captured across the supported isolate scope.
  final ProfileRegionResult? overallProfile;

  /// The regions captured during the session.
  final List<ProfileRegionResult> regions;

  /// Any warnings recorded during profiling.
  final List<String> warnings;

  /// Converts this session result to JSON.
  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'command': command,
        'workingDirectory': workingDirectory,
        'exitCode': exitCode,
        'terminatedByProfiler': terminatedByProfiler,
        'artifactDirectory': artifactDirectory,
        'vmServiceUri': vmServiceUri,
        'supportedCaptureKinds': [
          for (final kind in supportedCaptureKinds) kind.name,
        ],
        'supportedIsolateScopes': [
          for (final scope in supportedIsolateScopes) scope.name,
        ],
        if (overallProfile != null) 'overallProfile': overallProfile!.toJson(),
        'regions': regions.map((region) => region.toJson()).toList(),
        'warnings': warnings,
      };

  /// Encodes this session result as pretty-printed JSON.
  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

Map<String, String> _castStringMap(Object? value) {
  final raw = value as Map<Object?, Object?>? ?? const {};
  return {
    for (final entry in raw.entries)
      entry.key.toString(): entry.value?.toString() ?? '',
  };
}

List<String>? _castStringList(Object? value) {
  final raw = value as List<Object?>?;
  if (raw == null) {
    return null;
  }
  return [for (final entry in raw) entry?.toString() ?? ''];
}

List<String> _legacyIsolateIds(String? isolateId) {
  if (isolateId == null || isolateId.isEmpty) {
    return const [];
  }
  return [isolateId];
}

Map<String, Object?> _castJsonMap(Map<Object?, Object?> value) {
  return value.map((key, mappedValue) => MapEntry(key.toString(), mappedValue));
}
