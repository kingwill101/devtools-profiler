import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';
import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

import 'capture_state.dart';
import 'profile_runner_shared.dart';
import 'profile_session_context.dart';
import 'profile_session_snapshot_capture.dart';
import 'profile_session_vm_hookup.dart';

/// Handles DTD-facing region RPCs for a profiling session.
final class ProfileSessionRegionRpcHandler {
  ProfileSessionRegionRpcHandler({
    required this.context,
    required this.snapshotCapture,
    required this.vmHookup,
  });

  final ProfileSessionContext context;
  final ProfileSessionSnapshotCapture snapshotCapture;
  final ProfileSessionVmHookup vmHookup;

  /// Handles the DTD session-info request.
  Future<Map<String, Object?>> handleGetSessionInfo(Parameters params) async {
    vmHookup.validateSession(
      params['sessionId'].valueOr(context.sessionId) as String?,
    );
    return {
      DtdParameters.type: 'GetSessionInfoResult',
      'sessionId': context.sessionId,
      'protocolVersion': 1,
      'supportedCaptureKinds': [
        for (final kind in supportedCaptureKinds) kind.name,
      ],
      'supportedIsolateScopes': [
        for (final scope in supportedIsolateScopes) scope.name,
      ],
    };
  }

  /// Handles the DTD ping request.
  Future<Map<String, Object?>> handlePing(Parameters params) async {
    vmHookup.validateSession(
      params['sessionId'].valueOr(context.sessionId) as String?,
    );
    return {
      DtdParameters.type: 'PingResult',
      'sessionId': context.sessionId,
    };
  }

  /// Handles the DTD region-start request.
  Future<Map<String, Object?>> handleStartRegion(Parameters params) async {
    await vmHookup.waitForVmService();
    vmHookup.validateSession(params['sessionId'].asString);
    if (context.processExited) {
      throw RpcException.invalidParams(
        'Cannot start a profiling region after the target process exited.',
      );
    }
    final regionId = params['regionId'].asString;
    if (context.activeRegions.containsKey(regionId)) {
      throw RpcException.invalidParams(
        'A profiling region with id "$regionId" is already active.',
      );
    }

    final options = ProfileRegionOptions.fromJson({
      'captureKinds': params['captureKinds'].valueOr(null),
      'isolateScope': params['isolateScope'].valueOr(null),
      'parentRegionId': params['parentRegionId'].valueOr(null),
    });
    snapshotCapture.validateRequestedRegionOptions(options);

    final isolateId = params['isolateId'].asString;
    final name = params['name'].asString;
    final startTimestampMicros = params['timestampMicros'].asInt;
    final parentRegionId = params['parentRegionId'].valueOr(null) as String?;
    final memoryStartSnapshot = options.captureKinds.contains(
      ProfileCaptureKind.memory,
    )
        ? await snapshotCapture.captureMemorySnapshotForScope(
            originIsolateId: isolateId,
            isolateScope: options.isolateScope,
            timestampMicros: startTimestampMicros,
            warningContext: 'Region "$name" memory start',
          )
        : null;
    if (context.overallMemoryStartSnapshot == null) {
      try {
        context.overallMemoryStartSnapshot =
            await snapshotCapture.captureMemorySnapshotForAllAppIsolates(
          timestampMicros: startTimestampMicros,
          warningContext: 'Whole-session memory start',
        );
      } catch (_) {
        context.overallMemoryStartSnapshot ??= memoryStartSnapshot;
      }
    }

    final region = ActiveProfileRegion(
      attributes: stringMap(params['attributes'].valueOr(const {})),
      isolateId: isolateId,
      memoryStartSnapshot: memoryStartSnapshot,
      name: name,
      options: options,
      parentRegionId: parentRegionId,
      regionId: regionId,
      startTimestampMicros: startTimestampMicros,
    );

    context.activeRegions[region.regionId] = region;
    await postRegionEvent(
      kind: regionStartEventKind,
      region: region,
      timestampMicros: region.startTimestampMicros,
    );
    return {
      DtdParameters.type: 'StartRegionResult',
      'sessionId': context.sessionId,
      'regionId': region.regionId,
      'captureKinds': [for (final kind in options.captureKinds) kind.name],
      'isolateScope': options.isolateScope.name,
    };
  }

  /// Handles the DTD region-stop request.
  Future<Map<String, Object?>> handleStopRegion(Parameters params) async {
    await vmHookup.waitForVmService();
    vmHookup.validateSession(params['sessionId'].asString);
    final regionId = params['regionId'].asString;
    final region = context.activeRegions[regionId];
    if (region == null) {
      throw RpcException.invalidParams(
        'No active profiling region with id "$regionId" exists for this '
        'session.',
      );
    }

    final isolateId = params['isolateId'].asString;
    final stopTimestampMicros = params['timestampMicros'].asInt;
    if (region.isolateId != isolateId) {
      throw RpcException.invalidParams(
        'Stop requested from isolate "$isolateId" but "${region.isolateId}" '
        'started the region.',
      );
    }
    if (stopTimestampMicros < region.startTimestampMicros) {
      throw RpcException.invalidParams(
        'The stop timestamp must be greater than or equal to the start '
        'timestamp.',
      );
    }

    context.activeRegions.remove(region.regionId);

    try {
      final snapshot = await snapshotCapture.captureRegionSnapshot(
        region,
        stopTimestampMicros,
      );
      await postRegionEvent(
        kind: regionStopEventKind,
        region: region,
        timestampMicros: stopTimestampMicros,
        extraData: {'capturedIsolateIds': snapshot.isolateIds},
      );
      final result = await context.artifactStore.writeRegionSuccess(
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
      context.regions.add(result);
      return {
        DtdParameters.type: 'StopRegionResult',
        'sessionId': context.sessionId,
        'regionId': region.regionId,
        'capturedIsolateIds': snapshot.isolateIds,
        'rawProfilePath': result.rawProfilePath,
        'rawMemoryProfilePath': result.memory?.rawProfilePath,
        'sampleCount': result.sampleCount,
      };
    } catch (error) {
      final failure = await context.artifactStore.writeRegionFailure(
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
      context.regions.add(failure);
      await postRegionErrorEvent(region: region, error: error.toString());
      throw RpcException.invalidParams(
        'Failed to capture requested profile data: $error',
      );
    }
  }

  /// Finalizes this session when the profiled process exits.
  Future<void> handleProcessExit() async {
    context.processExited = true;
    await finishProfilingWindow(
      warningForRegion: (region) =>
          'Region "${region.name}" was still active when the target process '
          'exited.',
      errorForRegion: (_) =>
          'The target process exited before the region was stopped.',
    );
  }

  /// Finalizes this session when attach-mode profiling ends.
  Future<void> finishAttachedWindow() async {
    await finishProfilingWindow(
      warningForRegion: (region) =>
          'Region "${region.name}" was still active when the attach profiling '
          'window ended.',
      errorForRegion: (_) =>
          'The attach profiling window ended before the region was stopped.',
    );
  }

  /// Closes active regions and finalizes whole-session capture.
  Future<void> finishProfilingWindow({
    required String Function(ActiveProfileRegion region) warningForRegion,
    required String Function(ActiveProfileRegion region) errorForRegion,
  }) async {
    final activeRegions = context.activeRegions.values.toList()
      ..sort(
        (left, right) =>
            left.startTimestampMicros.compareTo(right.startTimestampMicros),
      );
    context.activeRegions.clear();

    for (final region in activeRegions) {
      context.warnings.add(warningForRegion(region));
      final failure = await context.artifactStore.writeRegionFailure(
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
      context.regions.add(failure);
    }

    await snapshotCapture.awaitOverallProfileCapture();
  }

  /// Posts a region event to the DTD event stream.
  Future<void> postRegionEvent({
    required String kind,
    required ActiveProfileRegion region,
    required int timestampMicros,
    Map<String, Object?> extraData = const {},
  }) async {
    try {
      await context.dtd.postEvent(regionEventStream, kind, {
        'sessionId': context.sessionId,
        'regionId': region.regionId,
        'name': region.name,
        'attributes': region.attributes,
        'captureKinds': [
          for (final kind in region.options.captureKinds) kind.name,
        ],
        'isolateId': region.isolateId,
        'isolateScope': region.options.isolateScope.name,
        'parentRegionId': region.parentRegionId,
        'pid': context.childProcessId,
        'sequence': context.eventSequence++,
        'timestampMicros': timestampMicros,
        ...extraData,
      });
    } catch (error) {
      context.warnings.add('Failed to post $kind event to DTD: $error');
    }
  }

  /// Posts a failed-region event and records the failure as a warning.
  Future<void> postRegionErrorEvent({
    required ActiveProfileRegion region,
    required String error,
  }) {
    return postRegionEvent(
      kind: regionErrorEventKind,
      region: region,
      timestampMicros: region.startTimestampMicros,
      extraData: {'error': error},
    ).then((_) {
      context.warnings.add('Region "${region.name}" failed: $error');
    });
  }
}
