import 'dart:convert';

import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';

import 'model_json_utils.dart';
import 'profile_region_result.dart';

/// A full profiling session result.
///
/// This is the primary session artifact produced by [ProfileRunner.run] and
/// [ProfileRunner.attach]. It ties together launch metadata, the whole-session
/// profile, explicit region captures, backend capability metadata, and any
/// warnings that callers should surface to humans or agents.
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
  }) : supportedCaptureKinds = List.unmodifiable(
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
        final Map<Object?, Object?> profile => ProfileRegionResult.fromJson(
          castJsonMap(profile),
        ),
        _ => null,
      },
      regions: (json['regions'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map((region) => ProfileRegionResult.fromJson(castJsonMap(region)))
          .toList(),
      warnings: (json['warnings'] as List<Object?>? ?? const [])
          .map((value) => value as String)
          .toList(),
    );
  }

  /// The session identifier shared with the launched process.
  final String sessionId;

  /// The launched command.
  ///
  /// Attach sessions store `['attach', vmServiceUri]` here instead of a real
  /// process command.
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
  ///
  /// This is present even when no explicit regions were emitted.
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
  ///
  /// This matches the JSON shape written to `session.json` artifacts.
  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
