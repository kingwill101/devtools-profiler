import 'dart:async';

import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:vm_service/vm_service.dart';

import '../../cpu/cpu_samples_merge.dart';
import '../../memory/memory_models.dart';
import '../../memory/memory_profile_summary.dart';
import 'capture_state.dart';
import 'cpu_snapshot_cache.dart';
import 'profile_runner_shared.dart';
import 'profile_session_context.dart';

// Flutter startup and large profile response decoding can delay even getVM.
// Keep metadata requests bounded without treating a busy healthy VM as gone.
const _vmServiceRequestTimeout = Duration(seconds: 10);
// CPU and allocation responses contain the complete profile payload. They can
// be substantially larger than ordinary VM-service requests and need a longer
// bound during shutdown so a healthy target is not reported as failed merely
// because a large response took time to transfer.
const _vmServiceProfileRequestTimeout = Duration(seconds: 30);

/// Captures CPU and memory snapshots for one profiling session.
final class ProfileSessionSnapshotCapture {
  ProfileSessionSnapshotCapture(this.context);

  final ProfileSessionContext context;
  final _cpuCache = CpuSnapshotCache();
  bool _reportedCachedCpuFallback = false;
  bool _reportedCpuCacheEviction = false;

  /// Ensures the whole-session profile artifact has been captured.
  Future<void> captureOverallProfile() async {
    context.overallProfileCaptureOperation ??= captureOverallProfileImpl();
    await context.overallProfileCaptureOperation;
  }

  /// Captures or materializes the whole-session profile artifact.
  Future<void> captureOverallProfileImpl() async {
    if (context.overallProfile != null) {
      if (!context.overallProfileReady.isCompleted) {
        context.overallProfileReady.complete();
      }
      return;
    }

    final vmService = context.vmService;
    if (vmService == null) {
      if (!context.overallProfileReady.isCompleted) {
        context.overallProfileReady.complete();
      }
      return;
    }

    CpuCaptureSnapshot? cpuSnapshot;
    ProfileMemoryResult? memory;
    Map<String, Object?>? rawMemoryPayload;
    final isolateIds = <String>{};
    final failures = <String>[];

    try {
      try {
        // A cached poll may predate a completed region. Attempt one final live
        // snapshot before falling back to retained data.
        try {
          cpuSnapshot = await captureCpuSnapshotForAllAppIsolates(
            startTimestampMicros: 0,
            timeExtentMicros: maxSafeJsInt,
            warningContext: 'Whole-session profiling',
          );
        } catch (_) {
          cpuSnapshot =
              await captureCpuSnapshotForIsolates(
                isolateIds: const [],
                startTimestampMicros: 0,
                timeExtentMicros: maxSafeJsInt,
                includePreviouslySeenIsolates: true,
              ).catchError((Object error) {
                final cached = context.latestOverallSnapshot;
                if (cached != null) return cached;
                throw error;
              });
        }
        isolateIds.addAll(cpuSnapshot.isolateIds);
      } catch (error) {
        failures.add('cpu: $error');
        context.warnings.add(
          'Failed to capture the whole-session CPU profile: $error',
        );
      }

      final overallMemoryStartSnapshot = context.overallMemoryStartSnapshot;
      if (overallMemoryStartSnapshot != null) {
        try {
          final endSnapshot =
              context.latestOverallMemorySnapshot ??
              await captureMemorySnapshotForAllAppIsolates(
                timestampMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
                warningContext: 'Whole-session memory stop',
              );
          final missingIsolates = overallMemoryStartSnapshot.isolateIds
              .toSet()
              .difference(endSnapshot.isolateIds.toSet());
          if (missingIsolates.isNotEmpty) {
            context.warnings.add(
              'Whole-session memory diff lost ${missingIsolates.length} '
              'isolate(s) before shutdown: ${missingIsolates.join(', ')}',
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
          rawMemoryPayload = buildRawMemoryPayload(
            startSnapshot: overallMemoryStartSnapshot,
            endSnapshot: endSnapshot,
          );
        } catch (error) {
          failures.add('memory: $error');
          context.warnings.add(
            'Failed to capture the whole-session memory profile: $error',
          );
        }
      }

      if (cpuSnapshot != null || memory != null) {
        final resolvedIsolateIds = isolateIds.isEmpty
            ? const ['unknown']
            : isolateIds.toList(growable: false);
        context.overallProfile = await context.artifactStore
            .writeOverallSuccess(
              isolateId: resolvedIsolateIds.first,
              isolateIds: resolvedIsolateIds,
              cpuSamples: cpuSnapshot?.cpuSamples,
              memory: memory,
              rawMemoryPayload: rawMemoryPayload,
            );
      } else {
        final resolvedIsolateIds =
            context.latestOverallSnapshot?.isolateIds ?? const ['unknown'];
        context.overallProfile = await context.artifactStore
            .writeOverallFailure(
              isolateId: resolvedIsolateIds.first,
              isolateIds: resolvedIsolateIds,
              error: failures.isEmpty
                  ? 'No whole-session profile data could be captured.'
                  : failures.join('; '),
            );
      }
    } finally {
      if (!context.overallProfileReady.isCompleted) {
        context.overallProfileReady.complete();
      }
    }
  }

  /// Waits for the whole-session capture to finish or triggers it eagerly.
  Future<void> awaitOverallProfileCapture() async {
    context.overallProfilePoller?.cancel();
    if (context.vmService == null) {
      return;
    }
    if (context.overallProfileReady.isCompleted) {
      return context.overallProfileReady.future;
    }

    try {
      await context.overallProfileReady.future.timeout(
        const Duration(milliseconds: 750),
      );
    } on TimeoutException {
      await captureOverallProfile();
    }
  }

  /// Starts polling lightweight overall snapshots while the target is running.
  void startOverallProfilePolling() {
    context.overallProfilePoller?.cancel();
    unawaited(refreshOverallProfileSnapshot());
    context.overallProfilePoller = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(refreshOverallProfileSnapshot()),
    );
  }

  /// Refreshes the cached whole-session CPU and memory snapshots.
  Future<void> refreshOverallProfileSnapshot() async {
    if (context.processExited || context.overallSnapshotInProgress) {
      return;
    }

    final vmService = context.vmService;
    if (vmService == null) {
      return;
    }

    context.overallSnapshotInProgress = true;
    try {
      // Capture CPU first: allocation profiles can be large enough for workers
      // to exit while we are waiting for memory responses.
      try {
        final snapshot = await captureCpuSnapshotForAllAppIsolates(
          startTimestampMicros: 0,
          timeExtentMicros: maxSafeJsInt,
        );
        final sampleCount =
            snapshot.cpuSamples.sampleCount ??
            snapshot.cpuSamples.samples?.length ??
            0;
        if (sampleCount > 0) {
          context.latestOverallSnapshot = snapshot;
        }
      } catch (_) {
        // Polling is best-effort while isolates start or shut down.
      }
      try {
        final memorySnapshot = await captureMemorySnapshotForAllAppIsolates(
          timestampMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
        );
        context.latestOverallMemorySnapshot = memorySnapshot;
        context.overallMemoryStartSnapshot ??= memorySnapshot;
      } catch (_) {
        // Best-effort. Memory capture should not block CPU snapshot polling.
      }
    } finally {
      context.overallSnapshotInProgress = false;
    }
  }

  /// Validates region options against the capabilities of this backend.
  void validateRequestedRegionOptions(ProfileRegionOptions options) {
    final unsupportedCaptureKinds = [
      for (final kind in options.captureKinds)
        if (!supportedCaptureKinds.contains(kind)) kind.name,
    ];
    if (unsupportedCaptureKinds.isNotEmpty) {
      throw RpcException.invalidParams(
        'Unsupported capture kinds requested: '
        '${unsupportedCaptureKinds.join(', ')}.',
      );
    }
    if (!supportedIsolateScopes.contains(options.isolateScope)) {
      throw RpcException.invalidParams(
        'Unsupported isolate scope requested: '
        '${options.isolateScope.name}.',
      );
    }
  }

  /// Captures the requested CPU and memory data for one explicit region.
  Future<RegionCaptureSnapshot> captureRegionSnapshot(
    ActiveProfileRegion region,
    int stopTimestampMicros,
  ) async {
    final isolateIds = await resolveCaptureIsolateIds(
      isolateScope: region.options.isolateScope,
      originIsolateId: region.isolateId,
    );

    final cpuSnapshot =
        region.options.captureKinds.contains(ProfileCaptureKind.cpu)
        ? await captureCpuSnapshotForIsolates(
            isolateIds: isolateIds,
            startTimestampMicros: region.startTimestampMicros,
            timeExtentMicros: nonZeroDuration(
              stopTimestampMicros - region.startTimestampMicros,
            ),
            warningContext: 'Region "${region.name}"',
            includePreviouslySeenIsolates:
                region.options.isolateScope == ProfileIsolateScope.all,
          )
        : null;

    ProfileMemoryResult? memory;
    Map<String, Object?>? rawMemoryPayload;
    if (region.options.captureKinds.contains(ProfileCaptureKind.memory)) {
      final startSnapshot = region.memoryStartSnapshot;
      if (startSnapshot == null) {
        throw StateError(
          'Memory capture for region "${region.name}" was requested without '
          'a start snapshot.',
        );
      }
      final endSnapshot = await captureMemorySnapshotForIsolates(
        isolateIds: isolateIds,
        timestampMicros: stopTimestampMicros,
        warningContext: 'Region "${region.name}" memory stop',
      );
      final missingIsolates = startSnapshot.isolateIds.toSet().difference(
        endSnapshot.isolateIds.toSet(),
      );
      if (missingIsolates.isNotEmpty) {
        context.warnings.add(
          'Region "${region.name}" memory diff lost '
          '${missingIsolates.length} isolate(s) before stop: '
          '${missingIsolates.join(', ')}',
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
      rawMemoryPayload = buildRawMemoryPayload(
        startSnapshot: startSnapshot,
        endSnapshot: endSnapshot,
      );
    }

    return RegionCaptureSnapshot(
      cpuSamples: cpuSnapshot?.cpuSamples,
      isolateIds: List.unmodifiable({
        ...isolateIds,
        ...?cpuSnapshot?.isolateIds,
      }),
      memory: memory,
      rawMemoryPayload: rawMemoryPayload,
    );
  }

  /// Seeds whole-session memory capture once a VM service is available.
  Future<void> initializeOverallMemoryCapture() async {
    Object? lastError;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        context.overallMemoryStartSnapshot =
            await captureMemorySnapshotForAllAppIsolates(
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
      context.warnings.add(
        'Failed to initialize whole-session memory capture: $lastError',
      );
    }
  }

  /// Resolves isolate ids for one capture scope request.
  Future<List<String>> resolveCaptureIsolateIds({
    required ProfileIsolateScope isolateScope,
    required String originIsolateId,
  }) {
    return switch (isolateScope) {
      ProfileIsolateScope.current => Future.value([originIsolateId]),
      ProfileIsolateScope.all => resolveAppIsolateIds(),
    };
  }

  /// Resolves the non-system isolates currently visible to the VM service.
  Future<List<String>> resolveAppIsolateIds() async {
    try {
      final vm = await context.vmService!.getVM().timeout(
        _vmServiceRequestTimeout,
      );
      return [
        for (final isolate in vm.isolates ?? const <IsolateRef>[])
          if (!(isolate.isSystemIsolate ?? false) && isolate.id != null)
            isolate.id!,
      ];
    } catch (error) {
      throw StateError('Failed to resolve app isolates: $error');
    }
  }

  /// Captures memory for all currently visible application isolates.
  Future<MemoryCaptureSnapshot> captureMemorySnapshotForAllAppIsolates({
    required int timestampMicros,
    String? warningContext,
  }) async {
    final isolateIds = await resolveAppIsolateIds();
    return captureMemorySnapshotForIsolates(
      isolateIds: isolateIds,
      timestampMicros: timestampMicros,
      warningContext: warningContext,
    );
  }

  /// Captures memory for the isolate set implied by one scope request.
  Future<MemoryCaptureSnapshot> captureMemorySnapshotForScope({
    required String originIsolateId,
    required ProfileIsolateScope isolateScope,
    required int timestampMicros,
    String? warningContext,
  }) async {
    final isolateIds = await resolveCaptureIsolateIds(
      isolateScope: isolateScope,
      originIsolateId: originIsolateId,
    );
    return captureMemorySnapshotForIsolates(
      isolateIds: isolateIds,
      timestampMicros: timestampMicros,
      warningContext: warningContext,
    );
  }

  /// Captures memory for the requested [isolateIds].
  Future<MemoryCaptureSnapshot> captureMemorySnapshotForIsolates({
    required List<String> isolateIds,
    required int timestampMicros,
    String? warningContext,
  }) async {
    if (isolateIds.isEmpty) {
      throw StateError(
        'No application isolates were available for memory capture.',
      );
    }

    final capturedSnapshots = <AllocationProfileSnapshot>[];
    final failures = <String>[];

    await Future.wait([
      for (final isolateId in isolateIds)
        () async {
          try {
            final allocationProfile = await context.vmService!
                .getAllocationProfile(isolateId)
                .timeout(_vmServiceProfileRequestTimeout);
            capturedSnapshots.add(
              AllocationProfileSnapshot(
                isolateId: isolateId,
                profile: allocationProfile,
              ),
            );
          } catch (error) {
            failures.add('$isolateId: $error');
          }
        }(),
    ]);

    if (capturedSnapshots.isEmpty) {
      throw StateError(
        'Memory snapshots could not be captured for any isolate.'
        '${failures.isEmpty ? '' : ' Failures: ${failures.join('; ')}'}',
      );
    }
    if (failures.isNotEmpty && warningContext != null) {
      context.warnings.add(
        '$warningContext skipped ${failures.length} isolate(s): '
        '${failures.join('; ')}',
      );
    }

    return MemoryCaptureSnapshot(
      heapSample: heapSampleFromMemoryUsage(
        memoryUsage: mergeMemoryUsage([
          for (final snapshot in capturedSnapshots)
            snapshot.profile.memoryUsage,
        ]),
        timestampMicros: timestampMicros,
      ),
      isolateIds: List.unmodifiable([
        for (final snapshot in capturedSnapshots) snapshot.isolateId,
      ]),
      profiles: List.unmodifiable(capturedSnapshots),
    );
  }

  /// Captures CPU samples for all currently visible application isolates.
  Future<CpuCaptureSnapshot> captureCpuSnapshotForAllAppIsolates({
    required int startTimestampMicros,
    required int timeExtentMicros,
    String? warningContext,
  }) async {
    final isolateIds = await resolveAppIsolateIds();
    return captureCpuSnapshotForIsolates(
      isolateIds: isolateIds,
      startTimestampMicros: startTimestampMicros,
      timeExtentMicros: timeExtentMicros,
      warningContext: warningContext,
      includePreviouslySeenIsolates: true,
    );
  }

  /// Clears any existing CPU samples for all currently visible isolates.
  Future<void> clearCpuSamplesForAllAppIsolates() async {
    try {
      final isolateIds = await resolveAppIsolateIds();
      final failures = <String>[];
      await Future.wait([
        for (final isolateId in isolateIds)
          () async {
            try {
              await context.vmService!
                  .clearCpuSamples(isolateId)
                  .timeout(_vmServiceRequestTimeout);
            } catch (error) {
              failures.add('$isolateId: $error');
            }
          }(),
      ]);
      if (failures.isNotEmpty) {
        context.warnings.add(
          'Failed to clear existing CPU samples for ${failures.length} '
          'isolate(s): ${failures.join('; ')}',
        );
      }
    } catch (error) {
      context.warnings.add(
        'Failed to clear existing CPU samples before the attach window: '
        '$error',
      );
    }
  }

  /// Captures CPU samples for the requested [isolateIds].
  Future<CpuCaptureSnapshot> captureCpuSnapshotForIsolates({
    required List<String> isolateIds,
    required int startTimestampMicros,
    required int timeExtentMicros,
    String? warningContext,
    bool includePreviouslySeenIsolates = false,
  }) async {
    if (isolateIds.isEmpty && !includePreviouslySeenIsolates) {
      throw StateError('No application isolates were available for capture.');
    }

    final capturedById = <String, CpuSamples>{};
    final failures = <String>[];

    await Future.wait([
      for (final isolateId in isolateIds)
        () async {
          try {
            final rawSamples = await context.vmService!
                .getCpuSamples(
                  isolateId,
                  includePreviouslySeenIsolates ? 0 : startTimestampMicros,
                  includePreviouslySeenIsolates
                      ? maxSafeJsInt
                      : timeExtentMicros,
                )
                .timeout(_vmServiceProfileRequestTimeout);
            final cpuSamples = compactCpuSamples(rawSamples);
            capturedById[isolateId] = includePreviouslySeenIsolates
                ? clipCpuSnapshot(
                    cpuSamples,
                    startTimestampMicros: startTimestampMicros,
                    timeExtentMicros: timeExtentMicros,
                  )
                : cpuSamples;
            if (includePreviouslySeenIsolates) {
              final evicted = _cpuCache.record(isolateId, cpuSamples);
              if (evicted.isNotEmpty && !_reportedCpuCacheEviction) {
                _reportedCpuCacheEviction = true;
                context.warnings.add(
                  'CPU snapshot retention reached its bound of '
                  '${_cpuCache.capacity} isolates or '
                  '${_cpuCache.maxStackEntries} stack entries. Earlier samples '
                  'from evicted isolates may be unavailable.',
                );
              }
            }
          } catch (error) {
            failures.add('$isolateId: $error');
          }
        }(),
    ]);

    final sources = includePreviouslySeenIsolates
        ? _cpuCache.withMissingIsolates(
            capturedById,
            startTimestampMicros: startTimestampMicros,
            timeExtentMicros: timeExtentMicros,
          )
        : capturedById;
    if (sources.length > capturedById.length && !_reportedCachedCpuFallback) {
      _reportedCachedCpuFallback = true;
      context.warnings.add(
        'Retained earlier CPU snapshots for exited or unavailable isolates. '
        'Samples after their last successful poll may be missing. OS thread '
        'ids are not isolate ids and can be shared or change over time.',
      );
    }
    if (sources.isEmpty) {
      throw StateError(
        'CPU samples could not be captured for any isolate.'
        '${failures.isEmpty ? '' : ' Failures: ${failures.join('; ')}'}',
      );
    }
    if (failures.isNotEmpty && warningContext != null) {
      context.warnings.add(
        '$warningContext skipped ${failures.length} isolate(s): '
        '${failures.join('; ')}',
      );
    }

    final capturedIsolateIds = sources.keys.toList()..sort();
    return CpuCaptureSnapshot(
      cpuSamples: mergeCpuSamples([
        for (final id in capturedIsolateIds) sources[id]!,
      ], isolateIds: capturedIsolateIds),
      isolateIds: List.unmodifiable(capturedIsolateIds),
    );
  }
}
