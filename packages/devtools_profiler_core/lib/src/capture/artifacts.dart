import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';
import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';

import '../cpu/call_tree.dart';
import '../cpu/cpu_profile_summary.dart';
import '../memory/memory_models.dart';
import '../memory/memory_profile_summary.dart';
import 'models.dart';

/// Utilities for reading and summarizing profiler artifacts.
///
/// These helpers are useful for tools that need to inspect stored profiling
/// output without rerunning the target process. The supported inputs are:
///
/// - session directories written by [ProfileArtifactStore]
/// - region `summary.json` files
/// - raw `cpu_profile.json` files
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
  ///
  /// Directory targets resolve to the stored session JSON. File targets return
  /// raw text and parsed JSON when the file contains valid JSON.
  static Future<Map<String, Object?>> readArtifact(String targetPath) async {
    final entityType = FileSystemEntity.typeSync(targetPath);
    switch (entityType) {
      case FileSystemEntityType.directory:
        final sessionFile = _sessionFileFor(targetPath);
        if (sessionFile.existsSync()) {
          return (await readSession(targetPath)).toJson();
        }
        final summaryFile = _summaryFileFor(targetPath);
        if (summaryFile.existsSync()) {
          return readArtifact(summaryFile.path);
        }
        final rawCpuFile = _rawCpuFileFor(targetPath);
        if (rawCpuFile.existsSync()) {
          return readArtifact(rawCpuFile.path);
        }
        final rawMemoryFile = _rawMemoryFileFor(targetPath);
        if (rawMemoryFile.existsSync()) {
          return readArtifact(rawMemoryFile.path);
        }
        throw ArgumentError.value(
          targetPath,
          'targetPath',
          'No profiler artifact found in directory',
        );
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
          targetPath,
          'targetPath',
          'Artifact not found',
        );
    }
  }

  /// Summarizes an artifact directory or raw CPU profile JSON file.
  ///
  /// Session directories, per-profile artifact directories, `session.json`,
  /// region `summary.json` files, and raw CPU profile files are accepted. Raw
  /// CPU profile files are lifted into a synthesized [ProfileRegionResult]-
  /// style summary so downstream tools can treat them like other profiler
  /// artifacts.
  static Future<Map<String, Object?>> summarizeArtifact(
    String targetPath,
  ) async {
    final entityType = FileSystemEntity.typeSync(targetPath);
    if (entityType == FileSystemEntityType.directory) {
      final sessionFile = _sessionFileFor(targetPath);
      if (sessionFile.existsSync()) {
        return (await readSession(targetPath)).toJson();
      }
      final summaryFile = _summaryFileFor(targetPath);
      if (summaryFile.existsSync()) {
        return summarizeArtifact(summaryFile.path);
      }
      final rawCpuFile = _rawCpuFileFor(targetPath);
      if (rawCpuFile.existsSync()) {
        return summarizeArtifact(rawCpuFile.path);
      }
      throw ArgumentError.value(
        targetPath,
        'targetPath',
        'No profiler summary found in directory',
      );
    }
    if (entityType != FileSystemEntityType.file) {
      throw ArgumentError.value(targetPath, 'targetPath', 'Artifact not found');
    }

    final json = jsonDecode(await File(targetPath).readAsString()) as Map;
    final map = json.cast<String, Object?>();
    if (map['type'] == 'CpuSamples') {
      final cpuSamples = CpuSamples.parse(
        map.map((key, value) => MapEntry(key, value as dynamic)),
      );
      if (cpuSamples == null) {
        throw StateError(
          'Failed to parse CPU samples artifact at $targetPath.',
        );
      }
      return summarizeCpuSamples(
        regionId: path.basenameWithoutExtension(targetPath),
        name: path.basenameWithoutExtension(targetPath),
        attributes: const {},
        isolateId: 'unknown',
        isolateIds: const ['unknown'],
        captureKinds: const [ProfileCaptureKind.cpu],
        startTimestampMicros: cpuSamples.timeOriginMicros ?? 0,
        endTimestampMicros:
            (cpuSamples.timeOriginMicros ?? 0) +
            (cpuSamples.timeExtentMicros ?? 0),
        cpuSamples: cpuSamples,
        summaryPath: targetPath,
        rawProfilePath: targetPath,
      ).toJson();
    }
    return map;
  }

  /// Reads raw CPU samples from a region summary or raw CPU profile artifact.
  ///
  /// Region summaries are resolved through their `rawProfilePath` link.
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
  ///
  /// This always returns a top-down tree built by [buildCallTree].
  static Future<ProfileCallTree> readCallTree(String targetPath) async {
    return buildCallTree(cpuSamples: await readCpuSamples(targetPath));
  }

  /// Reads and filters memory class data from a stored profiling artifact.
  ///
  /// [targetPath] may be a session directory, a region `summary.json` file,
  /// or a raw `memory_profile.json` file. Session directories resolve to the
  /// whole-session overall profile.
  ///
  /// When [classQuery] is provided, only classes whose name contains the query
  /// (case-insensitive) are included. When [minLiveBytes] is provided, only
  /// classes with at least that many live bytes at the end of the window are
  /// included. When both are provided, both conditions must hold.
  ///
  /// Pass [topClassCount] as 0 for unlimited results; otherwise the result is
  /// truncated to that many classes after sorting by allocation-bytes delta.
  static Future<ProfileMemoryResult> readMemoryClasses(
    String targetPath, {
    String? classQuery,
    int? minLiveBytes,
    int topClassCount = 50,
  }) async {
    final rawMemoryPath = await _resolveRawMemoryPath(targetPath);

    ProfileMemoryClassPredicate? predicate;
    final query = classQuery?.toLowerCase().trim();
    if (query != null && query.isNotEmpty && minLiveBytes != null) {
      predicate = (s) =>
          s.className.toLowerCase().contains(query) &&
          s.liveBytes >= minLiveBytes;
    } else if (query != null && query.isNotEmpty) {
      predicate = (s) => s.className.toLowerCase().contains(query);
    } else if (minLiveBytes != null) {
      predicate = (s) => s.liveBytes >= minLiveBytes;
    }

    return readMemoryClassesFromArtifact(
      rawMemoryPath,
      includeClass: predicate,
      topClassCount: topClassCount,
    );
  }

  static Future<String> _resolveRawMemoryPath(String targetPath) async {
    final entityType = FileSystemEntity.typeSync(targetPath);
    if (entityType == FileSystemEntityType.directory) {
      final sessionFile = _sessionFileFor(targetPath);
      if (sessionFile.existsSync()) {
        final session = await readSession(targetPath);
        final rawPath = session.overallProfile?.memory?.rawProfilePath;
        if (rawPath == null || rawPath.isEmpty) {
          throw StateError(
            'No memory profile is available for the session at "$targetPath". '
            'Re-run the target with memory capture enabled.',
          );
        }
        return rawPath;
      }
      final summaryFile = _summaryFileFor(targetPath);
      if (summaryFile.existsSync()) {
        return _resolveRawMemoryPath(summaryFile.path);
      }
      final rawMemoryFile = _rawMemoryFileFor(targetPath);
      if (rawMemoryFile.existsSync()) {
        return rawMemoryFile.path;
      }
      throw ArgumentError.value(targetPath, 'targetPath', 'Artifact not found');
    }
    if (entityType != FileSystemEntityType.file) {
      throw ArgumentError.value(targetPath, 'targetPath', 'Artifact not found');
    }

    final json =
        jsonDecode(await File(targetPath).readAsString())
            as Map<Object?, Object?>;
    final map = json.cast<String, Object?>();

    if (map['type'] == 'ProfileMemoryArtifact') {
      return targetPath;
    }

    if (map case {'topSelfFrames': final Object? _}) {
      final region = ProfileRegionResult.fromJson(map);
      final rawPath = region.memory?.rawProfilePath;
      if (rawPath == null || rawPath.isEmpty) {
        throw StateError(
          'No memory profile is available for the region at "$targetPath". '
          'Re-run the target with memory capture enabled.',
        );
      }
      return rawPath;
    }

    throw ArgumentError.value(
      targetPath,
      'targetPath',
      'Unsupported artifact type for memory class inspection.',
    );
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

  static File _sessionFileFor(String directoryPath) {
    return File(
      path.join(directoryPath, ProfileArtifactStore._sessionFileName),
    );
  }

  static File _summaryFileFor(String directoryPath) {
    return File(
      path.join(directoryPath, ProfileArtifactStore._summaryFileName),
    );
  }

  static File _rawCpuFileFor(String directoryPath) {
    return File(
      path.join(directoryPath, ProfileArtifactStore._rawProfileFileName),
    );
  }

  static File _rawMemoryFileFor(String directoryPath) {
    return File(
      path.join(directoryPath, ProfileArtifactStore._rawMemoryProfileFileName),
    );
  }
}

/// Writes session and region artifacts for a profiling run.
///
/// A store instance owns one session directory. It writes the session summary,
/// whole-session profile artifacts, and per-region summaries under stable file
/// names that [ProfileArtifacts] can read back later.
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
    final sessionFile = File(
      path.join(sessionDirectory.path, _sessionFileName),
    );
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
      final rawProfileFile = File(
        path.join(directory.path, _rawProfileFileName),
      );
      final rawJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(cpuSamples.toJson());
      await rawProfileFile.writeAsString(rawJson);
      rawProfilePath = rawProfileFile.path;
    }

    ProfileMemoryResult? storedMemory = memory;
    if (memory != null) {
      final rawMemoryFile = File(
        path.join(directory.path, _rawMemoryProfileFileName),
      );
      await rawMemoryFile.writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(rawMemoryPayload ?? memory.toJson()),
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
