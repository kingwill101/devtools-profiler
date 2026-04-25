import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:vm_service/vm_service.dart';

import '../artifacts.dart';
import '../models.dart';
import 'capture_state.dart';

/// Mutable state and shared dependencies for one profiling session.
final class ProfileSessionContext {
  ProfileSessionContext({
    required this.artifactStore,
    required this.childProcessId,
    required this.dtd,
    required this.sessionId,
  });

  final ProfileArtifactStore artifactStore;

  /// Whether to start the Dart Tooling Daemon for this attach session.
  ///
  /// When null, region markers are unavailable but whole-session VM-service
  /// capture still works.
  final DartToolingDaemon? dtd;
  final String sessionId;

  final List<ProfileRegionResult> regions = [];
  final List<String> warnings = [];
  final Map<String, ActiveProfileRegion> activeRegions = {};

  final Completer<void> vmServiceReady = Completer<void>();
  final Completer<void> overallProfileReady = Completer<void>();

  VmService? vmService;
  String? vmServiceUri;
  ProfileRegionResult? overallProfile;
  Future<void>? overallProfileCaptureOperation;
  Timer? overallProfilePoller;
  CpuCaptureSnapshot? latestOverallSnapshot;
  MemoryCaptureSnapshot? overallMemoryStartSnapshot;
  MemoryCaptureSnapshot? latestOverallMemorySnapshot;
  bool overallSnapshotInProgress = false;

  int eventSequence = 0;
  bool processExited = false;
  int? childProcessId;
}
