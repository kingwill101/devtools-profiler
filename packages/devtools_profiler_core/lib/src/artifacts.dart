
import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';
import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';

import 'call_tree.dart';
import 'cpu_profile_summary.dart';
import 'memory_models.dart';
import 'models.dart';

/// Utilities for reading and summarizing profiler artifacts.
class ProfileArtifacts {
  /// Reads a session artifact directory and returns the stored session result.
  static Future<ProfileRunResult> readSession(String directoryPath) async {
    final sessionFile = File(
      path.join(directoryPath, ProfileArtifactStore._sessionFileName),
    );
    final decoded = jsonDecode(await sessionFile.readAsString()) as Map;
    return ProfileRunResult.fromJson(decoded.cast<String, Object?>());
  }

  /// Reads an artifact and returns a structured map suitable for CLI and MCP
  /// output.
  static Future<Map<String, Object?>> readArtifact(String targetPath) async {
    final entityType = FileSystemEntity.typeSync(targetPath);
    switch (entityType) {
      case FileSystemEntityType.directory:
        return (await readSession(targetPath)).toJson();
      case FileSystemEntityType.file:
        final text = await File(targetPath).readAsString();
        Object? decoded;
        try {
          decoded = jsonDecode(text);
        } catch (_) {
          decoded = null;
        }
        return {
          'path': targetPath,
          'text': text,
          if (decoded != null) 'json': decoded,
        };
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.link:
      case FileSystemEntityType.unixDomainSock:
      case FileSystemEntityType.pipe:
      default:
        throw ArgumentError.value(
            targetPath, 'targetPath', 'Artifact not found');
    }
  }

  /// Summarizes an artifact directory or raw CPU profile JSON file.
  static Future<Map<String, Object?>> summarizeArtifact(
      String targetPath) async {
    final entityType = FileSystemEntity.typeSync(targetPath);
    if (entityType == FileSystemEntityType.directory) {
      return (await readSession(targetPath)).toJson();
    }

    final json = jsonDecode(await File(targetPath).readAsString()) as Map;
    final map = json.cast<String, Object?>();
    if (map['type'] == 'CpuSamples') {
      final cpuSamples = CpuSamples.parse(
        map.map((key, value) => MapEntry(key, value as dynamic)),
      );
      if (cpuSamples == null) {
        throw StateError(
            'Failed to parse CPU samples artifact at $targetPath.');
      }
      return summarizeCpuSamples(
        regionId: path.basenameWithoutExtension(targetPath),
        name: path.basenameWithoutExtension(targetPath),
        attributes: const {},
        isolateId: 'unknown',
        isolateIds: const ['unknown'],
        captureKinds: const [ProfileCaptureKind.cpu],
        startTimestampMicros: cpuSamples.timeOriginMicros ?? 0,
        endTimestampMicros: (cpuSamples.timeOriginMicros ?? 0) +
            (cpuSamples.timeExtentMicros ?? 0),
        cpuSamples: cpuSamples,
        summaryPath: targetPath,
        rawProfilePath: targetPath,
      ).toJson();
    }
    return map;
  }

  /// Reads raw CPU samples from a region summary or raw CPU profile artifact.
  static Future<CpuSamples> readCpuSamples(String targetPath) async {
    final entityType = FileSystemEntity.typeSync(targetPath);
    if (entityType != FileSystemEntityType.file) {
      throw ArgumentError.value(
        targetPath,
        'targetPath',
        'CPU samples are only available for region summary files or raw CPU profile artifacts.',
      );
    }

    final json = jsonDecode(await File(targetPath).readAsString()) as Map;
    final map = json.cast<String, Object?>();
    return _cpuSamplesFromArtifact(map, targetPath: targetPath);
  }

  /// Reads a call tree for a region summary or raw CPU profile artifact.
  static Future<ProfileCallTree> readCallTree(String targetPath) async {
    return buildCallTree(cpuSamples: await readCpuSamples(targetPath));
  }

  static Future<CpuSamples> _cpuSamplesFromArtifact(
    Map<String, Object?> map, {
    required String targetPath,
  }) async {
    if (map['type'] == 'CpuSamples') {
      final cpuSamples = CpuSamples.parse(
        map.map((key, value) => MapEntry(key, value as dynamic)),
      );
      if (cpuSamples == null) {
        throw StateError(
          'Failed to parse CPU samples artifact at $targetPath.',
        );
      }
      return cpuSamples;
    }

    if (map case {'topSelfFrames': final Object? _}) {
      final region = ProfileRegionResult.fromJson(map);
      final rawProfilePath = region.rawProfilePath;
      if (rawProfilePath == null || rawProfilePath.isEmpty) {
        throw StateError(
          'CPU samples are unavailable for region "${region.name}" because no raw CPU profile artifact was captured.',
        );
      }
      return readCpuSamples(rawProfilePath);
    }

    throw ArgumentError.value(
      targetPath,
      'targetPath',
      'Unsupported artifact type for CPU sample loading.',
    );
  }
}

/// Writes session and region artifacts for a profiling run.
class ProfileArtifactStore {
  /// Creates an artifact store rooted at [sessionDirectory].
  ProfileArtifactStore(this.sessionDirectory);

  static const _sessionFileName = 'session.json';
  static const _overallDirectoryName = 'overall';
  static const _regionsDirectoryName = 'regions';
  static const _summaryFileName = 'summary.json';
  static const _rawProfileFileName = 'cpu_profile.json';
  static const _rawMemoryProfileFileName = 'memory_profile.json';

  /// The session directory where artifacts will be written.
  final Directory sessionDirectory;

  /// Ensures the session directory exists.
  Future<void> create() => sessionDirectory.create(recursive: true);

  /// Writes the overall session CPU profile to disk and returns its summary.
  Future<ProfileRegionResult> writeOverallSuccess({
    required String isolateId,
    required List<String> isolateIds,
    CpuSamples? cpuSamples,
    ProfileMemoryResult? memory,
    Map<String, Object?>? rawMemoryPayload,
  }) {
    final startTimestampMicros =
        cpuSamples?.timeOriginMicros ?? memory?.start.timestamp ?? 0;
    final endTimestampMicros = cpuSamples == null
        ? memory?.end.timestamp ?? startTimestampMicros
        : startTimestampMicros + (cpuSamples.timeExtentMicros ?? 0);
    return _writeProfileSuccess(
      profileDirectory: _ensureOverallDirectory(),
      regionId: 'overall',
      name: 'whole-session',
      attributes: const {'scope': 'session'},
      isolateId: isolateId,
      isolateIds: isolateIds,
      isolateScope: ProfileIsolateScope.all,
      startTimestampMicros: startTimestampMicros,
      endTimestampMicros: endTimestampMicros,
      cpuSamples: cpuSamples,
      memory: memory,
      rawMemoryPayload: rawMemoryPayload,
    );
  }

  /// Writes a failed overall session summary to disk.
  Future<ProfileRegionResult> writeOverallFailure({
    required String isolateId,
    required List<String> isolateIds,
    required String error,
  }) {
    return _writeProfileFailure(
      profileDirectory: _ensureOverallDirectory(),
      regionId: 'overall',
      name: 'whole-session',
      attributes: const {'scope': 'session'},
      isolateId: isolateId,
      isolateIds: isolateIds,
      isolateScope: ProfileIsolateScope.all,
      startTimestampMicros: 0,
      endTimestampMicros: 0,
      error: error,
    );
  }

  /// Writes a successful region capture to disk and returns its summary.
  Future<ProfileRegionResult> writeRegionSuccess({
    required String regionId,
    required String name,
    required Map<String, String> attributes,
    required String isolateId,
    String? parentRegionId,
    required List<String> isolateIds,
    required List<ProfileCaptureKind> captureKinds,
    required ProfileIsolateScope isolateScope,
    required int startTimestampMicros,
    required int endTimestampMicros,
    CpuSamples? cpuSamples,
    ProfileMemoryResult? memory,
    Map<String, Object?>? rawMemoryPayload,
  }) async {
    return _writeProfileSuccess(
      profileDirectory: _ensureRegionDirectory(regionId),
      regionId: regionId,
      name: name,
      attributes: attributes,
      isolateId: isolateId,
      parentRegionId: parentRegionId,
      isolateIds: isolateIds,
      captureKinds: captureKinds,
      isolateScope: isolateScope,
      startTimestampMicros: startTimestampMicros,
      endTimestampMicros: endTimestampMicros,
      cpuSamples: cpuSamples,
      memory: memory,
      rawMemoryPayload: rawMemoryPayload,
    );
  }

  /// Writes a failed region capture summary to disk.
  Future<ProfileRegionResult> writeRegionFailure({
    required String regionId,
    required String name,
    required Map<String, String> attributes,
    required String isolateId,
    String? parentRegionId,
    required List<String> isolateIds,
    required List<ProfileCaptureKind> captureKinds,
    required ProfileIsolateScope isolateScope,
    required int startTimestampMicros,
    required int endTimestampMicros,
    required String error,
  }) async {
    return _writeProfileFailure(
      profileDirectory: _ensureRegionDirectory(regionId),
      regionId: regionId,
      name: name,
      attributes: attributes,
      isolateId: isolateId,
      parentRegionId: parentRegionId,
      isolateIds: isolateIds,
      captureKinds: captureKinds,
      isolateScope: isolateScope,
      startTimestampMicros: startTimestampMicros,
      endTimestampMicros: endTimestampMicros,
      error: error,
    );
  }

  /// Writes the session summary file.
  Future<void> writeSession(ProfileRunResult result) async {
    final sessionFile =
        File(path.join(sessionDirectory.path, _sessionFileName));
    await sessionFile.writeAsString(result.toPrettyJson());
  }

  Future<Directory> _ensureRegionDirectory(String regionId) async {
    final directory = Directory(
      path.join(sessionDirectory.path, _regionsDirectoryName, regionId),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _ensureOverallDirectory() async {
    final directory = Directory(
      path.join(sessionDirectory.path, _overallDirectoryName),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<ProfileRegionResult> _writeProfileSuccess({
    required Future<Directory> profileDirectory,
    required String regionId,
    required String name,
    required Map<String, String> attributes,
    required String isolateId,
    String? parentRegionId,
    required List<String> isolateIds,
    List<ProfileCaptureKind> captureKinds = defaultProfileCaptureKinds,
    ProfileIsolateScope isolateScope = ProfileIsolateScope.current,
    required int startTimestampMicros,
    required int endTimestampMicros,
    CpuSamples? cpuSamples,
    ProfileMemoryResult? memory,
    Map<String, Object?>? rawMemoryPayload,
  }) async {
    if (cpuSamples == null && memory == null) {
      throw ArgumentError(
        'At least one capture result must be provided for a successful profile.',
      );
    }
    final directory = await profileDirectory;
    final summaryFile = File(path.join(directory.path, _summaryFileName));
    String? rawProfilePath;
    if (cpuSamples != null) {
      final rawProfileFile =
          File(path.join(directory.path, _rawProfileFileName));
      final rawJson =
          const JsonEncoder.withIndent('  ').convert(cpuSamples.toJson());
      await rawProfileFile.writeAsString(rawJson);
      rawProfilePath = rawProfileFile.path;
    }

    ProfileMemoryResult? storedMemory = memory;
    if (memory != null) {
      final rawMemoryFile = File(
        path.join(directory.path, _rawMemoryProfileFileName),
      );
      await rawMemoryFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          rawMemoryPayload ?? memory.toJson(),
        ),
      );
      storedMemory = memory.copyWith(rawProfilePath: rawMemoryFile.path);
    }

    final summary = cpuSamples == null
        ? ProfileRegionResult(
            regionId: regionId,
            name: name,
            attributes: attributes,
            isolateId: isolateId,
            parentRegionId: parentRegionId,
            isolateIds: isolateIds,
            captureKinds: captureKinds,
            isolateScope: isolateScope,
            memory: storedMemory,
            startTimestampMicros: startTimestampMicros,
            endTimestampMicros: endTimestampMicros,
            durationMicros: endTimestampMicros - startTimestampMicros,
            sampleCount: 0,
            samplePeriodMicros: 0,
            topSelfFrames: const [],
            topTotalFrames: const [],
            summaryPath: summaryFile.path,
          )
        : summarizeCpuSamples(
            regionId: regionId,
            name: name,
            attributes: attributes,
            isolateId: isolateId,
            parentRegionId: parentRegionId,
            isolateIds: isolateIds,
            captureKinds: captureKinds,
            isolateScope: isolateScope,
            memory: storedMemory,
            startTimestampMicros: startTimestampMicros,
            endTimestampMicros: endTimestampMicros,
            cpuSamples: cpuSamples,
            summaryPath: summaryFile.path,
            rawProfilePath: rawProfilePath,
          );
    await summaryFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary.toJson()),
    );
    return summary;
  }

  Future<ProfileRegionResult> _writeProfileFailure({
    required Future<Directory> profileDirectory,
    required String regionId,
    required String name,
    required Map<String, String> attributes,
    required String isolateId,
    String? parentRegionId,
    required List<String> isolateIds,
    List<ProfileCaptureKind> captureKinds = defaultProfileCaptureKinds,
    ProfileIsolateScope isolateScope = ProfileIsolateScope.current,
    required int startTimestampMicros,
    required int endTimestampMicros,
    required String error,
  }) async {
    final directory = await profileDirectory;
    final summaryFile = File(path.join(directory.path, _summaryFileName));
    final summary = ProfileRegionResult(
      regionId: regionId,
      name: name,
      attributes: attributes,
      isolateId: isolateId,
      parentRegionId: parentRegionId,
      isolateIds: isolateIds,
      captureKinds: captureKinds,
      isolateScope: isolateScope,
      startTimestampMicros: startTimestampMicros,
      endTimestampMicros: endTimestampMicros,
      durationMicros: endTimestampMicros - startTimestampMicros,
      sampleCount: 0,
      samplePeriodMicros: 0,
      topSelfFrames: const [],
      topTotalFrames: const [],
      summaryPath: summaryFile.path,
      error: error,
    );
    await summaryFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary.toJson()),
    );
    return summary;
  }
}
