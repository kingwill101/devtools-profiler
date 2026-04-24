
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:path/path.dart' as path;
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'artifacts.dart';
import 'call_tree.dart';
import 'models.dart';
import 'cpu_samples_merge.dart';
import 'memory_models.dart';
import 'memory_profile_summary.dart';

const _profilerDtdUriEnvVar = 'DEVTOOLS_PROFILER_DTD_URI';
const _profilerSessionIdEnvVar = 'DEVTOOLS_PROFILER_SESSION_ID';
const _profilerProtocolVersionEnvVar = 'DEVTOOLS_PROFILER_PROTOCOL_VERSION';

const _profilerControlService = 'DevToolsProfiler';
const _regionEventStream = 'DevToolsProfilerRegion';

const _getSessionInfoMethod = 'getSessionInfo';
const _pingMethod = 'ping';
const _startRegionMethod = 'startRegion';
const _stopRegionMethod = 'stopRegion';

const _regionStartEventKind = 'region.start';
const _regionStopEventKind = 'region.stop';
const _regionErrorEventKind = 'region.error';
const _maxSafeJsInt = 0x1FFFFFFFFFFFFF;
const _supportedCaptureKinds = defaultProfileCaptureKinds;
const _supportedIsolateScopes = <ProfileIsolateScope>[
  ProfileIsolateScope.current,
  ProfileIsolateScope.all,
];
const _defaultDartVmServiceTimeout = Duration(seconds: 30);
const _defaultFlutterVmServiceTimeout = Duration(minutes: 3);

/// Launches profiled Dart processes and reads stored artifacts.
class ProfileRunner {
  /// Profiles the Dart [request] and returns the captured session result.
  Future<ProfileRunResult> run(ProfileRunRequest request) async {
    _validateCommand(request.command);

    final sessionId = _generateSessionId();
    final workingDirectory = path.normalize(
      request.workingDirectory ?? Directory.current.path,
    );
    final artifactDirectory = Directory(
      request.artifactDirectory ??
          path.join(
            workingDirectory,
            '.dart_tool',
            'devtools_profiler',
            'sessions',
            sessionId,
          ),
    );
    final artifactStore = ProfileArtifactStore(artifactDirectory);
    await artifactStore.create();

    final dtdSession = await _DtdProcessSession.start();
    final sessionController = _ProfileSessionController(
      artifactStore: artifactStore,
      childProcessId: null,
      dtd: dtdSession.daemon,
      sessionId: sessionId,
    );

    StreamSubscription<String>? stdoutSubscription;
    StreamSubscription<String>? stderrSubscription;
    Process? process;
    Timer? runDurationTimer;
    var processExited = false;
    var terminatedByProfiler = false;

    try {
      await sessionController.registerServices();

      final launchedProcess = await _launchProcess(
        request: request,
        sessionId: sessionId,
        dtdUri: dtdSession.info.localUri.toString(),
        workingDirectory: workingDirectory,
      );
      process = launchedProcess.process;
      sessionController.childProcessId = process.pid;
      stdoutSubscription = launchedProcess.stdoutSubscription;
      stderrSubscription = launchedProcess.stderrSubscription;

      final vmServiceTimeout =
          request.vmServiceTimeout ?? _defaultVmServiceTimeout(request.command);
      final serviceUri = await launchedProcess.serviceUri.future.timeout(
        vmServiceTimeout,
        onTimeout: () {
          throw StateError(
            'Timed out after ${_formatDuration(vmServiceTimeout)} waiting for the Dart VM service URI from the profiled process. '
            'If the target is still building or starting, increase --vm-service-timeout.',
          );
        },
      );
      await sessionController.attachToVmService(serviceUri);

      final runDuration = request.runDuration;
      if (runDuration != null) {
        runDurationTimer = Timer(runDuration, () {
          terminatedByProfiler = true;
          sessionController.addWarning(
            'Profile run duration of ${runDuration.inMilliseconds}ms elapsed; terminating the target process.',
          );
          if (process != null && !process.kill()) {
            sessionController.addWarning(
              'Failed to terminate the target process after the profile run duration elapsed.',
            );
          }
        });
      }

      final exitCode = await process.exitCode;
      processExited = true;
      runDurationTimer?.cancel();
      await sessionController.handleProcessExit();

      final result = sessionController.buildResult(
        artifactDirectory: artifactDirectory.path,
        command: request.command,
        exitCode: exitCode,
        terminatedByProfiler: terminatedByProfiler,
        workingDirectory: workingDirectory,
      );
      await artifactStore.writeSession(result);
      return result;
    } finally {
      await stdoutSubscription?.cancel();
      await stderrSubscription?.cancel();
      runDurationTimer?.cancel();
      if (process != null && !processExited) {
        process.kill();
        await process.exitCode;
      }
      await sessionController.dispose();
      await dtdSession.dispose();
    }
  }

  /// Profiles an already-running Dart or Flutter VM service for a fixed window.
  ///
  /// The target process is not launched or terminated by this method. Region
  /// markers are only available when the target process was already configured
  /// to talk to this profiler session, so attach mode primarily captures the
  /// whole-session VM service profile.
  Future<ProfileRunResult> attach(ProfileAttachRequest request) async {
    if (request.duration <= Duration.zero) {
      throw ArgumentError('The attach profiling duration must be positive.');
    }

    final sessionId = _generateSessionId();
    final workingDirectory = path.normalize(
      request.workingDirectory ?? Directory.current.path,
    );
    final artifactDirectory = Directory(
      request.artifactDirectory ??
          path.join(
            workingDirectory,
            '.dart_tool',
            'devtools_profiler',
            'sessions',
            sessionId,
          ),
    );
    final artifactStore = ProfileArtifactStore(artifactDirectory);
    await artifactStore.create();

    final dtdSession = await _DtdProcessSession.start();
    final sessionController = _ProfileSessionController(
      artifactStore: artifactStore,
      childProcessId: null,
      dtd: dtdSession.daemon,
      sessionId: sessionId,
    );

    try {
      await sessionController.registerServices();
      sessionController.addWarning(
        'Attached to an existing VM service. Explicit region markers are only available if the target process was started with this profiler session configuration.',
      );
      await sessionController.attachToVmService(
        request.vmServiceUri,
        clearCpuSamples: true,
      );
      await Future<void>.delayed(request.duration);
      await sessionController.finishAttachedWindow();

      final result = sessionController.buildResult(
        artifactDirectory: artifactDirectory.path,
        command: ['attach', request.vmServiceUri.toString()],
        exitCode: 0,
        terminatedByProfiler: false,
        workingDirectory: workingDirectory,
      );
      await artifactStore.writeSession(result);
      return result;
    } finally {
      await sessionController.dispose();
      await dtdSession.dispose();
    }
  }

  /// Reads an artifact from disk for direct consumption.
  Future<Map<String, Object?>> readArtifact(String targetPath) {
    return ProfileArtifacts.readArtifact(targetPath);
  }

  /// Summarizes an artifact directory or a raw CPU profile artifact.
  Future<Map<String, Object?>> summarizeArtifact(String targetPath) {
    return ProfileArtifacts.summarizeArtifact(targetPath);
  }

  /// Reads raw CPU samples for a region summary or raw CPU profile.
  Future<CpuSamples> readCpuSamples(String targetPath) {
    return ProfileArtifacts.readCpuSamples(targetPath);
  }

  /// Reads a top-down call tree for a region summary or raw CPU profile.
  Future<ProfileCallTree> readCallTree(String targetPath) {
    return ProfileArtifacts.readCallTree(targetPath);
  }
}

class _ProfileSessionController {
  _ProfileSessionController({
    required this.artifactStore,
    required this.childProcessId,
    required this.dtd,
    required this.sessionId,
  });

  final ProfileArtifactStore artifactStore;
  final DartToolingDaemon dtd;
  final String sessionId;

  final List<ProfileRegionResult> _regions = [];
  final List<String> _warnings = [];
  final Map<String, _ActiveRegion> _activeRegions = {};

  final Completer<void> _vmServiceReady = Completer<void>();
  final Completer<void> _overallProfileReady = Completer<void>();

  VmService? _vmService;
  String? _vmServiceUri;
  ProfileRegionResult? _overallProfile;
  Future<void>? _overallProfileCaptureOperation;
  Timer? _overallProfilePoller;
  _CpuCaptureSnapshot? _latestOverallSnapshot;
  _MemoryCaptureSnapshot? _overallMemoryStartSnapshot;
  _MemoryCaptureSnapshot? _latestOverallMemorySnapshot;
  bool _overallSnapshotInProgress = false;

  int _eventSequence = 0;
  bool _processExited = false;
  int? childProcessId;

  Future<void> registerServices() async {
    await dtd.registerService(
      _profilerControlService,
      _getSessionInfoMethod,
      _handleGetSessionInfo,
    );
    await dtd.registerService(
      _profilerControlService,
      _pingMethod,
      _handlePing,
    );
    await dtd.registerService(
      _profilerControlService,
      _startRegionMethod,
      _handleStartRegion,
    );
    await dtd.registerService(
      _profilerControlService,
      _stopRegionMethod,
      _handleStopRegion,
    );
  }

  Future<void> attachToVmService(
    Uri serviceUri, {
    bool clearCpuSamples = false,
  }) async {
    final wsUri = convertToWebSocketUrl(serviceProtocolUrl: serviceUri);
    _vmService = await vmServiceConnectUri(wsUri.toString());
    _vmServiceUri = serviceUri.toString();

    try {
      await _vmService!.setFlag('profiler', 'true');
    } catch (error) {
      _warnings.add('Failed to enable the CPU profiler: $error');
    }

    if (clearCpuSamples) {
      await _clearCpuSamplesForAllAppIsolates();
    }
    _startOverallProfilePolling();
    await _initializeOverallMemoryCapture();

    if (!_vmServiceReady.isCompleted) {
      _vmServiceReady.complete();
    }
  }

  Future<Map<String, Object?>> _handleGetSessionInfo(Parameters params) async {
    _validateSession(params['sessionId'].valueOr(sessionId) as String?);
    return {
      DtdParameters.type: 'GetSessionInfoResult',
      'sessionId': sessionId,
      'protocolVersion': 1,
      'supportedCaptureKinds': [
        for (final kind in _supportedCaptureKinds) kind.name,
      ],
      'supportedIsolateScopes': [
        for (final scope in _supportedIsolateScopes) scope.name,
      ],
    };
  }

  Future<Map<String, Object?>> _handlePing(Parameters params) async {
    _validateSession(params['sessionId'].valueOr(sessionId) as String?);
    return {
      DtdParameters.type: 'PingResult',
      'sessionId': sessionId,
    };
  }

  Future<Map<String, Object?>> _handleStartRegion(Parameters params) async {
    await _waitForVmService();
    _validateSession(params['sessionId'].asString);
    if (_processExited) {
      throw RpcException.invalidParams(
        'Cannot start a profiling region after the target process exited.',
      );
    }
    final regionId = params['regionId'].asString;
    if (_activeRegions.containsKey(regionId)) {
      throw RpcException.invalidParams(
        'A profiling region with id "$regionId" is already active.',
      );
    }

    final options = ProfileRegionOptions.fromJson({
      'captureKinds': params['captureKinds'].valueOr(null),
      'isolateScope': params['isolateScope'].valueOr(null),
      'parentRegionId': params['parentRegionId'].valueOr(null),
    });
    _validateRequestedRegionOptions(options);

    final isolateId = params['isolateId'].asString;
    final name = params['name'].asString;
    final startTimestampMicros = params['timestampMicros'].asInt;
    final parentRegionId = params['parentRegionId'].valueOr(null) as String?;
    final memoryStartSnapshot = options.captureKinds.contains(
      ProfileCaptureKind.memory,
    )
        ? await _captureMemorySnapshotForScope(
            originIsolateId: isolateId,
            isolateScope: options.isolateScope,
            timestampMicros: startTimestampMicros,
            warningContext: 'Region "$name" memory start',
          )
        : null;
    if (_overallMemoryStartSnapshot == null) {
      try {
        _overallMemoryStartSnapshot =
            await _captureMemorySnapshotForAllAppIsolates(
          timestampMicros: startTimestampMicros,
          warningContext: 'Whole-session memory start',
        );
      } catch (_) {
        _overallMemoryStartSnapshot ??= memoryStartSnapshot;
      }
    }

    final region = _ActiveRegion(
      attributes: _stringMap(params['attributes'].valueOr(const {})),
      isolateId: isolateId,
      memoryStartSnapshot: memoryStartSnapshot,
      name: name,
      options: options,
      parentRegionId: parentRegionId,
      regionId: regionId,
      startTimestampMicros: startTimestampMicros,
    );

    _activeRegions[region.regionId] = region;
    await _postRegionEvent(
      kind: _regionStartEventKind,
      region: region,
      timestampMicros: region.startTimestampMicros,
    );
    return {
      DtdParameters.type: 'StartRegionResult',
      'sessionId': sessionId,
      'regionId': region.regionId,
      'captureKinds': [for (final kind in options.captureKinds) kind.name],
      'isolateScope': options.isolateScope.name,
    };
  }

  Future<Map<String, Object?>> _handleStopRegion(Parameters params) async {
    await _waitForVmService();
    _validateSession(params['sessionId'].asString);
    final regionId = params['regionId'].asString;
    final region = _activeRegions[regionId];
    if (region == null) {
      throw RpcException.invalidParams(
        'No active profiling region with id "$regionId" exists for this session.',
      );
    }

    final isolateId = params['isolateId'].asString;
    final stopTimestampMicros = params['timestampMicros'].asInt;
    if (region.isolateId != isolateId) {
      throw RpcException.invalidParams(
        'Stop requested from isolate "$isolateId" but "${region.isolateId}" started the region.',
      );
    }
    if (stopTimestampMicros < region.startTimestampMicros) {
      throw RpcException.invalidParams(
        'The stop timestamp must be greater than or equal to the start timestamp.',
      );
    }

    _activeRegions.remove(region.regionId);

    try {
      final snapshot =
          await _captureRegionSnapshot(region, stopTimestampMicros);
      await _postRegionEvent(
        kind: _regionStopEventKind,
        region: region,
        timestampMicros: stopTimestampMicros,
        extraData: {'capturedIsolateIds': snapshot.isolateIds},
      );
      final result = await artifactStore.writeRegionSuccess(
        regionId: region.regionId,
        name: region.name,
        attributes: region.attributes,
        isolateId: region.isolateId,
        parentRegionId: region.parentRegionId,
        isolateIds: snapshot.isolateIds,
        captureKinds: region.options.captureKinds,
        isolateScope: region.options.isolateScope,
        startTimestampMicros: region.startTimestampMicros,
        endTimestampMicros: stopTimestampMicros,
        cpuSamples: snapshot.cpuSamples,
        memory: snapshot.memory,
        rawMemoryPayload: snapshot.rawMemoryPayload,
      );
      _regions.add(result);
      return {
        DtdParameters.type: 'StopRegionResult',
        'sessionId': sessionId,
        'regionId': region.regionId,
        'capturedIsolateIds': snapshot.isolateIds,
        'rawProfilePath': result.rawProfilePath,
        'rawMemoryProfilePath': result.memory?.rawProfilePath,
        'sampleCount': result.sampleCount,
      };
    } catch (error) {
      final failure = await artifactStore.writeRegionFailure(
        regionId: region.regionId,
        name: region.name,
        attributes: region.attributes,
        isolateId: region.isolateId,
        parentRegionId: region.parentRegionId,
        isolateIds: [region.isolateId],
        captureKinds: region.options.captureKinds,
        isolateScope: region.options.isolateScope,
        startTimestampMicros: region.startTimestampMicros,
        endTimestampMicros: stopTimestampMicros,
        error: error.toString(),
      );
      _regions.add(failure);
      await _postRegionErrorEvent(region: region, error: error.toString());
      throw RpcException.invalidParams(
        'Failed to capture requested profile data: $error',
      );
    }
  }

  Future<void> handleProcessExit() async {
    _processExited = true;
    await _finishProfilingWindow(
      warningForRegion: (region) =>
          'Region "${region.name}" was still active when the target process exited.',
      errorForRegion: (_) =>
          'The target process exited before the region was stopped.',
    );
  }

  Future<void> finishAttachedWindow() async {
    await _finishProfilingWindow(
      warningForRegion: (region) =>
          'Region "${region.name}" was still active when the attach profiling window ended.',
      errorForRegion: (_) =>
          'The attach profiling window ended before the region was stopped.',
    );
  }

  Future<void> _finishProfilingWindow({
    required String Function(_ActiveRegion region) warningForRegion,
    required String Function(_ActiveRegion region) errorForRegion,
  }) async {
    final activeRegions = _activeRegions.values.toList()
      ..sort(
        (left, right) =>
            left.startTimestampMicros.compareTo(right.startTimestampMicros),
      );
    _activeRegions.clear();

    for (final region in activeRegions) {
      _warnings.add(warningForRegion(region));
      final failure = await artifactStore.writeRegionFailure(
        regionId: region.regionId,
        name: region.name,
        attributes: region.attributes,
        isolateId: region.isolateId,
        parentRegionId: region.parentRegionId,
        isolateIds: [region.isolateId],
        captureKinds: region.options.captureKinds,
        isolateScope: region.options.isolateScope,
        startTimestampMicros: region.startTimestampMicros,
        endTimestampMicros: region.startTimestampMicros,
        error: errorForRegion(region),
      );
      _regions.add(failure);
    }

    await _awaitOverallProfileCapture();
  }

  void addWarning(String warning) {
    _warnings.add(warning);
  }

  ProfileRunResult buildResult({
    required String artifactDirectory,
    required List<String> command,
    required int exitCode,
    required bool terminatedByProfiler,
    required String workingDirectory,
  }) {
    final sortedRegions = [..._regions]..sort((left, right) {
        final startCompare =
            left.startTimestampMicros.compareTo(right.startTimestampMicros);
        if (startCompare != 0) {
          return startCompare;
        }
        final endCompare =
            left.endTimestampMicros.compareTo(right.endTimestampMicros);
        if (endCompare != 0) {
          return endCompare;
        }
        return left.regionId.compareTo(right.regionId);
      });
    return ProfileRunResult(
      sessionId: sessionId,
      command: command,
      workingDirectory: workingDirectory,
      exitCode: exitCode,
      terminatedByProfiler: terminatedByProfiler,
      artifactDirectory: artifactDirectory,
      vmServiceUri: _vmServiceUri,
      supportedCaptureKinds: _supportedCaptureKinds,
      supportedIsolateScopes: _supportedIsolateScopes,
      overallProfile: _overallProfile,
      regions: List.unmodifiable(sortedRegions),
      warnings: List.unmodifiable(_warnings),
    );
  }

  Future<void> dispose() async {
    _overallProfilePoller?.cancel();
    await _vmService?.dispose();
  }

  Future<void> _waitForVmService() {
    return _vmServiceReady.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw RpcException.invalidParams(
          'The profiling backend has not attached to the VM service yet.',
        );
      },
    );
  }

  Future<void> _postRegionEvent({
    required String kind,
    required _ActiveRegion region,
    required int timestampMicros,
    Map<String, Object?> extraData = const {},
  }) async {
    try {
      await dtd.postEvent(_regionEventStream, kind, {
        'sessionId': sessionId,
        'regionId': region.regionId,
        'name': region.name,
        'attributes': region.attributes,
        'captureKinds': [
          for (final kind in region.options.captureKinds) kind.name
        ],
        'isolateId': region.isolateId,
        'isolateScope': region.options.isolateScope.name,
        'parentRegionId': region.parentRegionId,
        'pid': childProcessId,
        'sequence': _eventSequence++,
        'timestampMicros': timestampMicros,
        ...extraData,
      });
    } catch (error) {
      _warnings.add('Failed to post $kind event to DTD: $error');
    }
  }

  Future<void> _postRegionErrorEvent({
    required _ActiveRegion region,
    required String error,
  }) {
    return _postRegionEvent(
      kind: _regionErrorEventKind,
      region: region,
      timestampMicros: region.startTimestampMicros,
      extraData: {'error': error},
    ).then((_) {
      _warnings.add('Region "${region.name}" failed: $error');
    });
  }

  void _validateSession(String? providedSessionId) {
    if (providedSessionId != null && providedSessionId != sessionId) {
      throw RpcException.invalidParams(
        'Session mismatch. Expected "$sessionId" but received "$providedSessionId".',
      );
    }
  }

  Future<void> _captureOverallProfile() async {
    _overallProfileCaptureOperation ??= _captureOverallProfileImpl();
    await _overallProfileCaptureOperation;
  }

  Future<void> _captureOverallProfileImpl() async {
    if (_overallProfile != null) {
      if (!_overallProfileReady.isCompleted) {
        _overallProfileReady.complete();
      }
      return;
    }

    final vmService = _vmService;
    if (vmService == null) {
      if (!_overallProfileReady.isCompleted) {
        _overallProfileReady.complete();
      }
      return;
    }

    _CpuCaptureSnapshot? cpuSnapshot;
    ProfileMemoryResult? memory;
    Map<String, Object?>? rawMemoryPayload;
    final isolateIds = <String>{};
    final failures = <String>[];

    try {
      try {
        cpuSnapshot = _latestOverallSnapshot ??
            await _captureCpuSnapshotForAllAppIsolates(
              startTimestampMicros: 0,
              timeExtentMicros: _maxSafeJsInt,
              warningContext: 'Whole-session profiling',
            );
        isolateIds.addAll(cpuSnapshot.isolateIds);
      } catch (error) {
        failures.add('cpu: $error');
        _warnings
            .add('Failed to capture the whole-session CPU profile: $error');
      }

      final overallMemoryStartSnapshot = _overallMemoryStartSnapshot;
      if (overallMemoryStartSnapshot != null) {
        try {
          final endSnapshot = _latestOverallMemorySnapshot ??
              await _captureMemorySnapshotForAllAppIsolates(
                timestampMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
                warningContext: 'Whole-session memory stop',
              );
          final missingIsolates = overallMemoryStartSnapshot.isolateIds
              .toSet()
              .difference(endSnapshot.isolateIds.toSet());
          if (missingIsolates.isNotEmpty) {
            _warnings.add(
              'Whole-session memory diff lost ${missingIsolates.length} isolate(s) before shutdown: ${missingIsolates.join(', ')}',
            );
          }
          isolateIds
            ..addAll(overallMemoryStartSnapshot.isolateIds)
            ..addAll(endSnapshot.isolateIds);
          memory = summarizeMemoryProfile(
            start: overallMemoryStartSnapshot.heapSample,
            end: endSnapshot.heapSample,
            startClasses: [
              for (final snapshot in overallMemoryStartSnapshot.profiles)
                ...(snapshot.profile.members ?? const <ClassHeapStats>[]),
            ],
            endClasses: [
              for (final snapshot in endSnapshot.profiles)
                ...(snapshot.profile.members ?? const <ClassHeapStats>[]),
            ],
            rawProfilePath: '',
          );
          rawMemoryPayload = _buildRawMemoryPayload(
            startSnapshot: overallMemoryStartSnapshot,
            endSnapshot: endSnapshot,
          );
        } catch (error) {
          failures.add('memory: $error');
          _warnings.add(
            'Failed to capture the whole-session memory profile: $error',
          );
        }
      }

      if (cpuSnapshot != null || memory != null) {
        final resolvedIsolateIds = isolateIds.isEmpty
            ? const ['unknown']
            : isolateIds.toList(growable: false);
        _overallProfile = await artifactStore.writeOverallSuccess(
          isolateId: resolvedIsolateIds.first,
          isolateIds: resolvedIsolateIds,
          cpuSamples: cpuSnapshot?.cpuSamples,
          memory: memory,
          rawMemoryPayload: rawMemoryPayload,
        );
      } else {
        final resolvedIsolateIds =
            _latestOverallSnapshot?.isolateIds ?? const ['unknown'];
        _overallProfile = await artifactStore.writeOverallFailure(
          isolateId: resolvedIsolateIds.first,
          isolateIds: resolvedIsolateIds,
          error: failures.isEmpty
              ? 'No whole-session profile data could be captured.'
              : failures.join('; '),
        );
      }
    } finally {
      if (!_overallProfileReady.isCompleted) {
        _overallProfileReady.complete();
      }
    }
  }

  Future<void> _awaitOverallProfileCapture() async {
    _overallProfilePoller?.cancel();
    if (_vmService == null) {
      return;
    }
    if (_overallProfileReady.isCompleted) {
      return _overallProfileReady.future;
    }

    try {
      await _overallProfileReady.future.timeout(
        const Duration(milliseconds: 750),
      );
    } on TimeoutException {
      await _captureOverallProfile();
    }
  }

  void _startOverallProfilePolling() {
    _overallProfilePoller?.cancel();
    unawaited(_refreshOverallProfileSnapshot());
    _overallProfilePoller = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(_refreshOverallProfileSnapshot()),
    );
  }

  Future<void> _refreshOverallProfileSnapshot() async {
    if (_processExited || _overallSnapshotInProgress) {
      return;
    }

    final vmService = _vmService;
    if (vmService == null) {
      return;
    }

    _overallSnapshotInProgress = true;
    try {
      if (_overallMemoryStartSnapshot == null) {
        try {
          _overallMemoryStartSnapshot =
              await _captureMemorySnapshotForAllAppIsolates(
            timestampMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
            warningContext: 'Whole-session memory start',
          );
        } catch (_) {
          // Best-effort. A later poll or region start can still seed memory.
        }
      }
      try {
        final memorySnapshot = await _captureMemorySnapshotForAllAppIsolates(
          timestampMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
        );
        _latestOverallMemorySnapshot = memorySnapshot;
        _overallMemoryStartSnapshot ??= memorySnapshot;
      } catch (_) {
        // Best-effort. Memory capture should not block CPU snapshot polling.
      }
      final snapshot = await _captureCpuSnapshotForAllAppIsolates(
        startTimestampMicros: 0,
        timeExtentMicros: _maxSafeJsInt,
      );
      final sampleCount = snapshot.cpuSamples.sampleCount ??
          snapshot.cpuSamples.samples?.length ??
          0;
      if (sampleCount > 0) {
        _latestOverallSnapshot = snapshot;
      }
    } catch (_) {
      // Polling is best-effort. The isolate can be briefly unrunnable while
      // the target is starting or shutting down.
    } finally {
      _overallSnapshotInProgress = false;
    }
  }

  void _validateRequestedRegionOptions(ProfileRegionOptions options) {
    final unsupportedCaptureKinds = [
      for (final kind in options.captureKinds)
        if (!_supportedCaptureKinds.contains(kind)) kind.name,
    ];
    if (unsupportedCaptureKinds.isNotEmpty) {
      throw RpcException.invalidParams(
        'Unsupported capture kinds requested: ${unsupportedCaptureKinds.join(', ')}.',
      );
    }
    if (!_supportedIsolateScopes.contains(options.isolateScope)) {
      throw RpcException.invalidParams(
        'Unsupported isolate scope requested: ${options.isolateScope.name}.',
      );
    }
  }

  Future<_RegionCaptureSnapshot> _captureRegionSnapshot(
    _ActiveRegion region,
    int stopTimestampMicros,
  ) async {
    final isolateIds = await _resolveCaptureIsolateIds(
      isolateScope: region.options.isolateScope,
      originIsolateId: region.isolateId,
    );

    final cpuSamples =
        region.options.captureKinds.contains(ProfileCaptureKind.cpu)
            ? (await _captureCpuSnapshotForIsolates(
                isolateIds: isolateIds,
                startTimestampMicros: region.startTimestampMicros,
                timeExtentMicros: _nonZeroDuration(
                    stopTimestampMicros - region.startTimestampMicros),
                warningContext: 'Region "${region.name}"',
              ))
                .cpuSamples
            : null;

    ProfileMemoryResult? memory;
    Map<String, Object?>? rawMemoryPayload;
    if (region.options.captureKinds.contains(ProfileCaptureKind.memory)) {
      final startSnapshot = region.memoryStartSnapshot;
      if (startSnapshot == null) {
        throw StateError(
          'Memory capture for region "${region.name}" was requested without a start snapshot.',
        );
      }
      final endSnapshot = await _captureMemorySnapshotForIsolates(
        isolateIds: isolateIds,
        timestampMicros: stopTimestampMicros,
        warningContext: 'Region "${region.name}" memory stop',
      );
      final missingIsolates = startSnapshot.isolateIds.toSet().difference(
            endSnapshot.isolateIds.toSet(),
          );
      if (missingIsolates.isNotEmpty) {
        _warnings.add(
          'Region "${region.name}" memory diff lost ${missingIsolates.length} isolate(s) before stop: ${missingIsolates.join(', ')}',
        );
      }
      memory = summarizeMemoryProfile(
        start: startSnapshot.heapSample,
        end: endSnapshot.heapSample,
        startClasses: [
          for (final snapshot in startSnapshot.profiles)
            ...(snapshot.profile.members ?? const <ClassHeapStats>[]),
        ],
        endClasses: [
          for (final snapshot in endSnapshot.profiles)
            ...(snapshot.profile.members ?? const <ClassHeapStats>[]),
        ],
        rawProfilePath: '',
      );
      rawMemoryPayload = _buildRawMemoryPayload(
        startSnapshot: startSnapshot,
        endSnapshot: endSnapshot,
      );
    }

    return _RegionCaptureSnapshot(
      cpuSamples: cpuSamples,
      isolateIds: List.unmodifiable(isolateIds),
      memory: memory,
      rawMemoryPayload: rawMemoryPayload,
    );
  }

  Future<void> _initializeOverallMemoryCapture() async {
    Object? lastError;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        _overallMemoryStartSnapshot =
            await _captureMemorySnapshotForAllAppIsolates(
          timestampMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
          warningContext: 'Whole-session memory start',
        );
        return;
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    if (lastError != null) {
      _warnings.add(
        'Failed to initialize whole-session memory capture: $lastError',
      );
    }
  }

  Future<List<String>> _resolveCaptureIsolateIds({
    required ProfileIsolateScope isolateScope,
    required String originIsolateId,
  }) {
    return switch (isolateScope) {
      ProfileIsolateScope.current => Future.value([originIsolateId]),
      ProfileIsolateScope.all => _resolveAppIsolateIds(),
    };
  }

  Future<List<String>> _resolveAppIsolateIds() async {
    try {
      final vm = await _vmService!.getVM();
      return [
        for (final isolate in vm.isolates ?? const <IsolateRef>[])
          if (!(isolate.isSystemIsolate ?? false) && isolate.id != null)
            isolate.id!,
      ];
    } catch (error) {
      throw StateError('Failed to resolve app isolates: $error');
    }
  }

  Future<_MemoryCaptureSnapshot> _captureMemorySnapshotForAllAppIsolates({
    required int timestampMicros,
    String? warningContext,
  }) async {
    final isolateIds = await _resolveAppIsolateIds();
    return _captureMemorySnapshotForIsolates(
      isolateIds: isolateIds,
      timestampMicros: timestampMicros,
      warningContext: warningContext,
    );
  }

  Future<_MemoryCaptureSnapshot> _captureMemorySnapshotForScope({
    required String originIsolateId,
    required ProfileIsolateScope isolateScope,
    required int timestampMicros,
    String? warningContext,
  }) async {
    final isolateIds = await _resolveCaptureIsolateIds(
      isolateScope: isolateScope,
      originIsolateId: originIsolateId,
    );
    return _captureMemorySnapshotForIsolates(
      isolateIds: isolateIds,
      timestampMicros: timestampMicros,
      warningContext: warningContext,
    );
  }

  Future<_MemoryCaptureSnapshot> _captureMemorySnapshotForIsolates({
    required List<String> isolateIds,
    required int timestampMicros,
    String? warningContext,
  }) async {
    if (isolateIds.isEmpty) {
      throw StateError(
          'No application isolates were available for memory capture.');
    }

    final capturedSnapshots = <_AllocationProfileSnapshot>[];
    final failures = <String>[];

    await Future.wait(
      [
        for (final isolateId in isolateIds)
          () async {
            try {
              final allocationProfile = await _vmService!.getAllocationProfile(
                isolateId,
              );
              capturedSnapshots.add(
                _AllocationProfileSnapshot(
                  isolateId: isolateId,
                  profile: allocationProfile,
                ),
              );
            } catch (error) {
              failures.add('$isolateId: $error');
            }
          }(),
      ],
    );

    if (capturedSnapshots.isEmpty) {
      throw StateError(
        'Memory snapshots could not be captured for any isolate.'
        '${failures.isEmpty ? '' : ' Failures: ${failures.join('; ')}'}',
      );
    }
    if (failures.isNotEmpty && warningContext != null) {
      _warnings.add(
        '$warningContext skipped ${failures.length} isolate(s): ${failures.join('; ')}',
      );
    }

    return _MemoryCaptureSnapshot(
      heapSample: heapSampleFromMemoryUsage(
        memoryUsage: _mergeMemoryUsage(
          [
            for (final snapshot in capturedSnapshots)
              snapshot.profile.memoryUsage,
          ],
        ),
        timestampMicros: timestampMicros,
      ),
      isolateIds: List.unmodifiable([
        for (final snapshot in capturedSnapshots) snapshot.isolateId,
      ]),
      profiles: List.unmodifiable(capturedSnapshots),
    );
  }

  Future<_CpuCaptureSnapshot> _captureCpuSnapshotForAllAppIsolates({
    required int startTimestampMicros,
    required int timeExtentMicros,
    String? warningContext,
  }) async {
    final isolateIds = await _resolveAppIsolateIds();
    return _captureCpuSnapshotForIsolates(
      isolateIds: isolateIds,
      startTimestampMicros: startTimestampMicros,
      timeExtentMicros: timeExtentMicros,
      warningContext: warningContext,
    );
  }

  Future<void> _clearCpuSamplesForAllAppIsolates() async {
    try {
      final isolateIds = await _resolveAppIsolateIds();
      final failures = <String>[];
      await Future.wait([
        for (final isolateId in isolateIds)
          () async {
            try {
              await _vmService!.clearCpuSamples(isolateId);
            } catch (error) {
              failures.add('$isolateId: $error');
            }
          }(),
      ]);
      if (failures.isNotEmpty) {
        _warnings.add(
          'Failed to clear existing CPU samples for ${failures.length} isolate(s): ${failures.join('; ')}',
        );
      }
    } catch (error) {
      _warnings.add(
        'Failed to clear existing CPU samples before the attach window: $error',
      );
    }
  }

  Future<_CpuCaptureSnapshot> _captureCpuSnapshotForIsolates({
    required List<String> isolateIds,
    required int startTimestampMicros,
    required int timeExtentMicros,
    String? warningContext,
  }) async {
    if (isolateIds.isEmpty) {
      throw StateError('No application isolates were available for capture.');
    }

    final capturedIsolateIds = <String>[];
    final capturedSamples = <CpuSamples>[];
    final failures = <String>[];

    await Future.wait(
      [
        for (final isolateId in isolateIds)
          () async {
            try {
              final cpuSamples = await _vmService!.getCpuSamples(
                isolateId,
                startTimestampMicros,
                timeExtentMicros,
              );
              capturedIsolateIds.add(isolateId);
              capturedSamples.add(cpuSamples);
            } catch (error) {
              failures.add('$isolateId: $error');
            }
          }(),
      ],
    );

    if (capturedSamples.isEmpty) {
      throw StateError(
        'CPU samples could not be captured for any isolate.'
        '${failures.isEmpty ? '' : ' Failures: ${failures.join('; ')}'}',
      );
    }
    if (failures.isNotEmpty && warningContext != null) {
      _warnings.add(
        '$warningContext skipped ${failures.length} isolate(s): ${failures.join('; ')}',
      );
    }

    return _CpuCaptureSnapshot(
      cpuSamples: mergeCpuSamples(capturedSamples),
      isolateIds: List.unmodifiable(capturedIsolateIds),
    );
  }
}

class _ActiveRegion {
  const _ActiveRegion({
    required this.attributes,
    required this.isolateId,
    required this.memoryStartSnapshot,
    required this.name,
    required this.options,
    required this.parentRegionId,
    required this.regionId,
    required this.startTimestampMicros,
  });

  final Map<String, String> attributes;
  final String isolateId;
  final _MemoryCaptureSnapshot? memoryStartSnapshot;
  final String name;
  final ProfileRegionOptions options;
  final String? parentRegionId;
  final String regionId;
  final int startTimestampMicros;
}

class _RegionCaptureSnapshot {
  const _RegionCaptureSnapshot({
    required this.cpuSamples,
    required this.isolateIds,
    required this.memory,
    required this.rawMemoryPayload,
  });

  final CpuSamples? cpuSamples;
  final List<String> isolateIds;
  final ProfileMemoryResult? memory;
  final Map<String, Object?>? rawMemoryPayload;
}

class _CpuCaptureSnapshot {
  const _CpuCaptureSnapshot({
    required this.cpuSamples,
    required this.isolateIds,
  });

  final CpuSamples cpuSamples;
  final List<String> isolateIds;
}

class _MemoryCaptureSnapshot {
  const _MemoryCaptureSnapshot({
    required this.heapSample,
    required this.isolateIds,
    required this.profiles,
  });

  final HeapSample heapSample;
  final List<String> isolateIds;
  final List<_AllocationProfileSnapshot> profiles;
}

class _AllocationProfileSnapshot {
  const _AllocationProfileSnapshot({
    required this.isolateId,
    required this.profile,
  });

  final String isolateId;
  final AllocationProfile profile;
}

Map<String, Object?> _buildRawMemoryPayload({
  required _MemoryCaptureSnapshot startSnapshot,
  required _MemoryCaptureSnapshot endSnapshot,
}) {
  return {
    'type': 'ProfileMemoryArtifact',
    'isolateIds': [
      for (final isolateId in {
        ...startSnapshot.isolateIds,
        ...endSnapshot.isolateIds,
      })
        isolateId,
    ],
    'start': {
      'heapSample': startSnapshot.heapSample.toJson(),
      'profiles': [
        for (final snapshot in startSnapshot.profiles)
          {
            'isolateId': snapshot.isolateId,
            'allocationProfile': snapshot.profile.toJson(),
          },
      ],
    },
    'end': {
      'heapSample': endSnapshot.heapSample.toJson(),
      'profiles': [
        for (final snapshot in endSnapshot.profiles)
          {
            'isolateId': snapshot.isolateId,
            'allocationProfile': snapshot.profile.toJson(),
          },
      ],
    },
  };
}

MemoryUsage _mergeMemoryUsage(Iterable<MemoryUsage?> usages) {
  var externalUsage = 0;
  var heapCapacity = 0;
  var heapUsage = 0;
  for (final usage in usages) {
    externalUsage += max(usage?.externalUsage ?? 0, 0);
    heapCapacity += max(usage?.heapCapacity ?? 0, 0);
    heapUsage += max(usage?.heapUsage ?? 0, 0);
  }
  return MemoryUsage(
    externalUsage: externalUsage,
    heapCapacity: heapCapacity,
    heapUsage: heapUsage,
  );
}

class _DtdProcessSession {
  _DtdProcessSession({
    required this.daemon,
    required this.info,
    required this.process,
    required this.stdoutSubscription,
  });

  final DartToolingDaemon daemon;
  final _DtdConnectionInfo info;
  final Process process;
  final StreamSubscription<List<int>> stdoutSubscription;

  static Future<_DtdProcessSession> start() async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      const ['tooling-daemon', '--machine'],
    );
    final completer = Completer<_DtdConnectionInfo>();

    final stdoutBuffer = StringBuffer();
    late final StreamSubscription<List<int>> stdoutSubscription;
    stdoutSubscription = process.stdout.listen((data) {
      if (completer.isCompleted) return;
      stdoutBuffer.write(utf8.decode(data));
      final decoded = stdoutBuffer.toString().trim();
      if (decoded.isEmpty) return;

      try {
        final json = jsonDecode(decoded) as Map<String, Object?>;
        final toolingDetails =
            json['tooling_daemon_details'] as Map<String, Object?>?;
        final uri = toolingDetails?['uri'] as String?;
        final secret = toolingDetails?['trusted_client_secret'] as String?;
        if (uri == null || secret == null) {
          completer.completeError(
            StateError('Unexpected tooling-daemon machine output: $decoded'),
          );
          return;
        }
        completer.complete(
          _DtdConnectionInfo(
            localUri: Uri.parse(uri),
            trustedClientSecret: secret,
          ),
        );
      } on FormatException {
        // Wait for more data if the tooling-daemon JSON arrived in chunks.
      }
    });

    final info = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw StateError('Timed out starting the tooling-daemon process.');
      },
    );
    final daemon = await DartToolingDaemon.connect(info.localUri);
    return _DtdProcessSession(
      daemon: daemon,
      info: info,
      process: process,
      stdoutSubscription: stdoutSubscription,
    );
  }

  Future<void> dispose() async {
    await daemon.close();
    await stdoutSubscription.cancel();
    process.kill();
    await process.exitCode;
  }
}

class _DtdConnectionInfo {
  const _DtdConnectionInfo({
    required this.localUri,
    required this.trustedClientSecret,
  });

  final Uri localUri;
  final String trustedClientSecret;
}

class _LaunchedProcess {
  const _LaunchedProcess({
    required this.process,
    required this.serviceUri,
    required this.stdoutSubscription,
    required this.stderrSubscription,
  });

  final Process process;
  final Completer<Uri> serviceUri;
  final StreamSubscription<String> stdoutSubscription;
  final StreamSubscription<String> stderrSubscription;
}

Future<_LaunchedProcess> _launchProcess({
  required ProfileRunRequest request,
  required String sessionId,
  required String dtdUri,
  required String workingDirectory,
}) async {
  final launchPlan = _instrumentedCommandLaunchPlan(
    request.command,
    dtdUri: dtdUri,
    sessionId: sessionId,
  );
  final process = await Process.start(
    launchPlan.executable,
    launchPlan.arguments,
    workingDirectory: workingDirectory,
    environment: {
      ...Platform.environment,
      ...request.environment,
      _profilerDtdUriEnvVar: dtdUri,
      _profilerSessionIdEnvVar: sessionId,
      _profilerProtocolVersionEnvVar: '1',
    },
  );

  final serviceUri = Completer<Uri>();
  late final StreamSubscription<String> stdoutSubscription;
  late final StreamSubscription<String> stderrSubscription;

  void handleLine(String line, IOSink sink) {
    final parsedUri = _parseVmServiceUri(line);
    if (parsedUri != null) {
      if (!serviceUri.isCompleted) {
        serviceUri.complete(parsedUri);
      }
      return;
    }

    if (request.forwardOutput) {
      sink.writeln(line);
    }
  }

  stdoutSubscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => handleLine(line, stdout));

  stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => handleLine(line, stderr));

  unawaited(process.exitCode.then((_) {
    if (!serviceUri.isCompleted) {
      serviceUri.completeError(
        StateError(
          'The profiled process exited before exposing a VM service URI.',
        ),
      );
    }
  }));

  return _LaunchedProcess(
    process: process,
    serviceUri: serviceUri,
    stdoutSubscription: stdoutSubscription,
    stderrSubscription: stderrSubscription,
  );
}

enum _ProfileCommandKind { dart, flutter }

class _CommandLaunchPlan {
  const _CommandLaunchPlan({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}

void _validateCommand(List<String> command) {
  if (command.isEmpty) {
    throw ArgumentError('A Dart or Flutter command is required.');
  }

  switch (_profileCommandKind(command)) {
    case _ProfileCommandKind.dart:
      _validateDartCommand(command);
    case _ProfileCommandKind.flutter:
      _validateFlutterCommand(command);
  }
}

void _validateDartCommand(List<String> command) {
  final firstNonOption = command.skip(1).firstWhere(
        (argument) => !argument.startsWith('-'),
        orElse: () => '',
      );
  if (firstNonOption.isEmpty) {
    throw ArgumentError('A Dart subcommand or script path is required.');
  }
  if (firstNonOption == 'compile') {
    throw ArgumentError(
      'Compiled AOT executables are out of scope for this profiler backend.',
    );
  }
}

void _validateFlutterCommand(List<String> command) {
  final subcommandIndex = _flutterSubcommandIndex(command);
  if (subcommandIndex == null) {
    throw ArgumentError(
      'A supported Flutter subcommand is required. Use "flutter run" or "flutter test".',
    );
  }

  final subcommand = command[subcommandIndex];
  if (!_supportedFlutterSubcommands.contains(subcommand)) {
    throw ArgumentError(
      'Only "flutter run" and "flutter test" are supported for Flutter profiling.',
    );
  }

  final subcommandArguments = command.sublist(subcommandIndex + 1);
  if (_hasOption(subcommandArguments, 'release')) {
    throw ArgumentError(
      'Flutter release mode does not expose a Dart VM service. Use debug or profile mode.',
    );
  }

  if (subcommand == 'test' &&
      _hasOption(subcommandArguments, 'experimental-faster-testing')) {
    throw ArgumentError(
      'Flutter experimental faster testing is not compatible with VM service profiling.',
    );
  }
}

_ProfileCommandKind _profileCommandKind(List<String> command) {
  final executableName = _executableName(command.first);
  return switch (executableName) {
    'dart' => _ProfileCommandKind.dart,
    'flutter' => _ProfileCommandKind.flutter,
    _ => throw ArgumentError(
        'Only Dart and Flutter VM commands are supported. Expected the first argument to be "dart" or "flutter".',
      ),
  };
}

String _executableName(String executable) {
  var name = path.basename(executable).toLowerCase();
  for (final extension in const ['.exe', '.bat', '.cmd']) {
    if (name.endsWith(extension)) {
      name = name.substring(0, name.length - extension.length);
      break;
    }
  }
  return name;
}

_CommandLaunchPlan _instrumentedCommandLaunchPlan(
  List<String> command, {
  required String dtdUri,
  required String sessionId,
}) {
  return switch (_profileCommandKind(command)) {
    _ProfileCommandKind.dart => _CommandLaunchPlan(
        executable:
            _executableName(command.first) == 'dart' && command.first == 'dart'
                ? Platform.resolvedExecutable
                : command.first,
        arguments: [
          '--observe=0',
          '--pause-isolates-on-exit=false',
          ...command.skip(1),
        ],
      ),
    _ProfileCommandKind.flutter => _flutterLaunchPlan(
        command,
        dtdUri: dtdUri,
        sessionId: sessionId,
      ),
  };
}

_CommandLaunchPlan _flutterLaunchPlan(
  List<String> command, {
  required String dtdUri,
  required String sessionId,
}) {
  final subcommandIndex = _flutterSubcommandIndex(command)!;
  final subcommand = command[subcommandIndex];
  final prefixArguments = command.sublist(1, subcommandIndex);
  final subcommandArguments = command.sublist(subcommandIndex + 1);
  final passthroughIndex = subcommandArguments.indexOf('--');
  final flutterArguments = passthroughIndex == -1
      ? subcommandArguments
      : subcommandArguments.sublist(0, passthroughIndex);
  final passthroughArguments = passthroughIndex == -1
      ? const <String>[]
      : subcommandArguments.sublist(passthroughIndex);
  final profilerArguments = _flutterProfilerArguments(
    subcommand,
    flutterArguments,
    dtdUri: dtdUri,
    sessionId: sessionId,
  );

  return _CommandLaunchPlan(
    executable: command.first,
    arguments: [
      ...prefixArguments,
      subcommand,
      ...flutterArguments,
      ...profilerArguments,
      ...passthroughArguments,
    ],
  );
}

List<String> _flutterProfilerArguments(
  String subcommand,
  List<String> arguments, {
  required String dtdUri,
  required String sessionId,
}) {
  return [
    if (subcommand == 'run' &&
        !_hasAnyOption(
          arguments,
          const ['host-vmservice-port', 'vm-service-port'],
        ))
      '--host-vmservice-port=0',
    if (subcommand == 'test' &&
        !_hasAnyOption(arguments, const ['enable-vmservice', 'start-paused']))
      '--enable-vmservice',
    '--dart-define=$_profilerDtdUriEnvVar=$dtdUri',
    '--dart-define=$_profilerSessionIdEnvVar=$sessionId',
    '--dart-define=$_profilerProtocolVersionEnvVar=1',
  ];
}

const _knownFlutterSubcommands = {
  'analyze',
  'assemble',
  'attach',
  'build',
  'channel',
  'clean',
  'config',
  'create',
  'custom-devices',
  'devices',
  'doctor',
  'downgrade',
  'drive',
  'emulators',
  'gen-l10n',
  'install',
  'logs',
  'precache',
  'pub',
  'run',
  'screenshot',
  'symbolize',
  'test',
  'upgrade',
};

const _supportedFlutterSubcommands = {'run', 'test'};

int? _flutterSubcommandIndex(List<String> command) {
  for (var i = 1; i < command.length; i++) {
    if (_knownFlutterSubcommands.contains(command[i])) {
      return i;
    }
  }
  return null;
}

bool _hasAnyOption(List<String> arguments, Iterable<String> names) {
  return names.any((name) => _hasOption(arguments, name));
}

bool _hasOption(List<String> arguments, String name) {
  final option = '--$name';
  return arguments.any(
    (argument) => argument == option || argument.startsWith('$option='),
  );
}

Duration _defaultVmServiceTimeout(List<String> command) {
  return switch (_profileCommandKind(command)) {
    _ProfileCommandKind.dart => _defaultDartVmServiceTimeout,
    _ProfileCommandKind.flutter => _defaultFlutterVmServiceTimeout,
  };
}

String _formatDuration(Duration duration) {
  if (duration.inMilliseconds < Duration.millisecondsPerSecond) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inSeconds < Duration.secondsPerMinute) {
    return '${duration.inSeconds}s';
  }
  if (duration.inMinutes < Duration.minutesPerHour) {
    return '${duration.inMinutes}m';
  }
  return '${duration.inHours}h';
}

Uri? _parseVmServiceUri(String line) {
  final match = RegExp(
    r'(?:Observatory|Dart VM service|VM service).*?((?:https?:)?//[a-zA-Z0-9:/=_\-\.\[\]%?&]+)',
    caseSensitive: false,
  ).firstMatch(line);
  if (match == null) return null;
  return _normalizeVmServiceUri(match.group(1)!);
}

Uri _normalizeVmServiceUri(String uriString) {
  final uri = Uri.parse(
    uriString.startsWith('//') ? 'http:$uriString' : uriString,
  );
  final normalizedPath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri.replace(path: normalizedPath);
}

String _generateSessionId() {
  final random = Random();
  final timestamp = DateTime.now().toUtc().toIso8601String();
  final suffix = random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return 'session-${timestamp.replaceAll(':', '-')}-$suffix';
}

Map<String, String> _stringMap(Object? value) {
  final raw = value as Map<Object?, Object?>? ?? const {};
  return {
    for (final entry in raw.entries)
      entry.key.toString(): entry.value?.toString() ?? '',
  };
}

int _nonZeroDuration(int value) => value <= 0 ? 1 : value;
