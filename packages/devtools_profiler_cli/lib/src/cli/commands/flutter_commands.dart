import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'vm_service_discovery.dart';

import '../constants.dart';
import 'profiler_command.dart';

abstract class _FrameTimingCommand extends ProfilerCommand
    with VmServiceDiscovery {
  _FrameTimingCommand(
    super.profileRunner, {
    required this.commandName,
    required this.commandDescription,
    required this.commandTitle,
    required this.examples,
  }) {
    argParser.addOption(
      'duration',
      defaultsTo: '5',
      help: 'Duration to profile frames in seconds (default: 5).',
    );
  }

  final String commandName;
  final String commandDescription;
  final String commandTitle;
  final List<String> examples;

  @override
  String get name => commandName;

  @override
  String get description => commandDescription;

  @override
  String get invocation =>
      '${runner!.executableName} $commandName [options] <vm-service-uri>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    examples,
  );

  @override
  Future<int> run() async {
    final vmServiceUri = await resolveVmServiceUri();
    final duration =
        int.tryParse(argResults!['duration'] as String? ?? '5') ?? 5;

    final wsUri = vmServiceUri
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final cleanWs = wsUri.endsWith('/ws') ? wsUri : '$wsUri/ws';

    final vmService = await vmServiceConnectUri(cleanWs);
    try {
      // Resolve the main isolate for FPS detection
      final vm = await vmService.getVM();
      final isolates = vm.isolates ?? [];
      final active = isolates.where((i) => i.isSystemIsolate != true).toList();
      if (active.isEmpty) {
        error('No active application isolates found.');
        return softwareExitCode;
      }
      final isolateId = active.first.id!;

      final analyzer = FrameAnalyzer(vmService: vmService);
      final result = await analyzer.profileFrames(
        duration: Duration(seconds: duration),
        isolateId: isolateId,
      );

      if (printJson) {
        line(jsonEncoder.convert(result.toJson()));
      } else {
        final jankPct = result.jankPercentage.toStringAsFixed(1);
        final avgMs = (result.averageFrameTimeUs / 1000).toStringAsFixed(2);
        final maxMs = (result.maxFrameTimeUs / 1000).toStringAsFixed(2);
        final buildMs = (result.buildPhaseTimeUs / 1000).toStringAsFixed(2);
        final layoutMs = (result.layoutPhaseTimeUs / 1000).toStringAsFixed(2);
        final paintMs = (result.paintPhaseTimeUs / 1000).toStringAsFixed(2);

        io.title(commandTitle);
        io.components.definitionList({
          'Duration': '${result.durationMicros ~/ 1000000}s',
          'Total Frames': '${result.totalFrames}',
          'Janky Frames': '${result.jankyFrames} ($jankPct%)',
          'Average Frame': '$avgMs ms',
          'Max Frame': '$maxMs ms',
          'Detected FPS': '${result.detectedFps.toStringAsFixed(0)}',
          'P90 Frame':
              '${(result.p90FrameTimeUs / 1000).toStringAsFixed(2)} ms',
          'P99 Frame':
              '${(result.p99FrameTimeUs / 1000).toStringAsFixed(2)} ms',
          'Build Phase': '$buildMs ms',
          'Layout Phase': '$layoutMs ms',
          'Paint Phase': '$paintMs ms',
        });

        if (result.hasShaderJank) {
          warn(
            'Shader jank detected: ${result.shaderCompilationEvents.length} '
            'compilation events '
            '(${(result.totalShaderCompilationTimeUs / 1000).toStringAsFixed(1)}ms total). '
            'Consider SkSL warmup or Impeller for consistent frame times.',
          );
        }

        if (result.timelineHotspots.isNotEmpty) {
          io.section('Timeline Hotspots');
          io.table(
            headers: const ['Event', 'Total (ms)', 'Count', 'Max (ms)'],
            rows: [
              for (final hotspot in result.timelineHotspots.take(8))
                [
                  hotspot.name,
                  (hotspot.totalDurationUs / 1000).toStringAsFixed(1),
                  '${hotspot.callCount}',
                  (hotspot.maxDurationUs / 1000).toStringAsFixed(1),
                ],
            ],
          );
        }

        comment('VM Service URI: $vmServiceUri');
      }
    } finally {
      await vmService.dispose();
    }

    return successExitCode;
  }
}

/// Command that profiles frame timing from a running Flutter app.
final class FrameProfileCommand extends _FrameTimingCommand {
  /// Creates a frame profile command.
  FrameProfileCommand(super.profileRunner)
    : super(
        commandName: 'flutter:frame-profile',
        commandDescription:
            'Profile frame timing from a running Flutter app '
            'via its VM service URI.',
        commandTitle: 'Frame Profile',
        examples: const [
          'devtools-profiler flutter:frame-profile '
              'ws://127.0.0.1:8181/abc123/ws',
          'devtools-profiler flutter:frame-profile --duration 10 '
              'ws://127.0.0.1:8181/abc123/ws',
        ],
      );
}

/// Command that profiles VM timeline frame timing from a running Flutter app.
final class TimelineProfileCommand extends _FrameTimingCommand {
  /// Creates a timeline profile command.
  TimelineProfileCommand(super.profileRunner)
    : super(
        commandName: 'flutter:timeline',
        commandDescription:
            'Profile VM timeline frame timing from a running Flutter app '
            'via its VM service URI.',
        commandTitle: 'Timeline Profile',
        examples: const [
          'devtools-profiler flutter:timeline '
              'ws://127.0.0.1:8181/abc123/ws',
          'devtools-profiler flutter:timeline --duration 10 '
              'ws://127.0.0.1:8181/abc123/ws',
        ],
      );
}

/// Command that profiles VM timeline frame timing from any running VM service.
final class TimelineCommand extends _FrameTimingCommand {
  /// Creates a timeline command.
  TimelineCommand(super.profileRunner)
    : super(
        commandName: 'timeline',
        commandDescription:
            'Profile VM timeline frame timing from a running app via its '
            'VM service URI.',
        commandTitle: 'Timeline Profile',
        examples: const [
          'devtools-profiler timeline ws://127.0.0.1:8181/abc123/ws',
          'devtools-profiler timeline --duration 10 '
              'ws://127.0.0.1:8181/abc123/ws',
        ],
      );
}

/// Command that captures a memory snapshot from a running Flutter/Dart app.
class MemorySnapshotCommand extends ProfilerCommand with VmServiceDiscovery {
  /// Creates a memory-snapshot command.
  MemorySnapshotCommand(super.profileRunner) {
    argParser
      ..addOption(
        'name',
        help: 'Optional name for this snapshot. Auto-generates when omitted.',
      )
      ..addFlag(
        'no-gc',
        negatable: false,
        help: 'Skip forcing garbage collection before the snapshot.',
      )
      ..addFlag(
        'save',
        negatable: false,
        help: 'Save the snapshot for later comparison.',
      );
  }

  @override
  String get name => 'flutter:memory-snapshot';

  @override
  String get description =>
      'Capture an allocation profile from a running app via its VM service URI.';

  @override
  String get invocation =>
      '${runner!.executableName} flutter:memory-snapshot [options] <vm-service-uri>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler flutter:memory-snapshot ws://127.0.0.1:8181/abc123/ws',
      'devtools-profiler flutter:memory-snapshot --name before-opt --no-gc ws://127.0.0.1:8181/abc123/ws',
    ],
  );

  @override
  Future<int> run() async {
    final vmServiceUri = await resolveVmServiceUri();
    final requestedName = argResults!['name'] as String?;
    final forceGc = !(argResults!['no-gc'] as bool? ?? false);
    final save = argResults!['save'] as bool? ?? false;

    final wsUri = vmServiceUri
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final cleanWs = wsUri.endsWith('/ws') ? wsUri : '$wsUri/ws';

    final vmService = await vmServiceConnectUri(cleanWs);
    try {
      final vm = await vmService.getVM();
      final isolates = vm.isolates ?? [];
      final activeIsolates = isolates
          .where((i) => i.isSystemIsolate != true)
          .toList();
      if (activeIsolates.isEmpty) {
        error('No active application isolates found.');
        return softwareExitCode;
      }
      final isolateId = activeIsolates.first.id!;

      final profile = await vmService.getAllocationProfile(
        isolateId,
        gc: forceGc,
        reset: false,
      );

      final members = profile.members ?? [];
      final classEntries =
          members
              .map((stats) => MemoryClassEntry.fromClassHeapStats(stats))
              .toList()
            ..sort((a, b) => b.sizeCurrent.compareTo(a.sizeCurrent));

      final snapshotName =
          requestedName ??
          'cli-snapshot-${DateTime.now().millisecondsSinceEpoch}';

      if (save) {
        await _saveSnapshot(
          vmServiceUri: vmServiceUri,
          requestedName: requestedName,
          isolateId: isolateId,
          memoryUsage: profile.memoryUsage,
          members: members,
          profile: profile,
          save: save,
        );
      }

      if (printJson) {
        line(
          jsonEncoder.convert({
            'name': snapshotName,
            'totalHeapUsage': profile.memoryUsage?.heapUsage ?? 0,
            'capacity': profile.memoryUsage?.heapCapacity ?? 0,
            'externalUsage': profile.memoryUsage?.externalUsage ?? 0,
            'classCount': classEntries.length,
            'classes': [
              for (final entry in classEntries.take(50)) entry.toJson(),
            ],
          }),
        );
      } else {
        io.title('Memory Snapshot');
        io.components.definitionList({
          'Name': snapshotName,
          'Total Heap Usage': '${profile.memoryUsage?.heapUsage ?? 0} bytes',
          'Heap Capacity': '${profile.memoryUsage?.heapCapacity ?? 0} bytes',
          'External Usage': '${profile.memoryUsage?.externalUsage ?? 0} bytes',
          'Class Count': '${classEntries.length}',
        });

        io.section('Top Allocations');
        io.table(
          headers: const ['Class', 'Instances', 'Size (bytes)'],
          rows: [
            for (final entry in classEntries.take(20))
              [
                entry.className,
                '${entry.instancesCurrent}',
                '${entry.sizeCurrent}',
              ],
          ],
        );

        if (classEntries.length > 20) {
          comment('... and ${classEntries.length - 20} more classes.');
        }
      }
    } finally {
      await vmService.dispose();
    }

    return successExitCode;
  }

  Future<void> _saveSnapshot({
    required String vmServiceUri,
    required String? requestedName,
    required String isolateId,
    required MemoryUsage? memoryUsage,
    required List<ClassHeapStats> members,
    required AllocationProfile profile,
    required bool save,
  }) async {
    final timestampMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    final heapSample = heapSampleFromMemoryUsage(
      memoryUsage: memoryUsage,
      timestampMicros: timestampMicros,
    );
    final memory = summarizeMemoryProfile(
      start: heapSample,
      end: heapSample,
      startClasses: members,
      endClasses: members,
      rawProfilePath: '',
      topClassCount: 50,
    );
    final rawMemoryPayload = _buildRawMemoryPayload(
      timestampMicros: timestampMicros,
      memoryUsage: memoryUsage,
      isolateId: isolateId,
      profile: profile,
    );
    final sessionId = _generateSessionId();
    final sessionDirectory = Directory(
      path.join(
        Directory.current.path,
        '.dart_tool',
        'devtools_profiler',
        'sessions',
        sessionId,
      ),
    );
    final artifactStore = ProfileArtifactStore(sessionDirectory);
    await artifactStore.create();
    final overallProfile = await artifactStore.writeOverallSuccess(
      isolateId: isolateId,
      isolateIds: [isolateId],
      memory: memory,
      rawMemoryPayload: rawMemoryPayload,
    );
    final sessionResult = ProfileRunResult(
      sessionId: sessionId,
      command: [
        'flutter:memory-snapshot',
        if (save) '--save',
        if (requestedName != null) ...['--name', requestedName],
        vmServiceUri,
      ],
      workingDirectory: Directory.current.path,
      exitCode: 0,
      artifactDirectory: sessionDirectory.path,
      regions: const [],
      warnings: const [],
      overallProfile: overallProfile,
      vmServiceUri: vmServiceUri,
    );
    await artifactStore.writeSession(sessionResult);
  }

  Map<String, Object?> _buildRawMemoryPayload({
    required int timestampMicros,
    required MemoryUsage? memoryUsage,
    required String isolateId,
    required AllocationProfile profile,
  }) {
    final start = {
      'heapSample': heapSampleFromMemoryUsage(
        memoryUsage: memoryUsage,
        timestampMicros: timestampMicros,
      ).toJson(),
      'profiles': [
        {'isolateId': isolateId, 'allocationProfile': profile.toJson()},
      ],
    };
    return {
      'type': 'ProfileMemoryArtifact',
      'isolateIds': [isolateId],
      'start': start,
      'end': start,
    };
  }

  String _generateSessionId() {
    return 'memory-${DateTime.now().toUtc().microsecondsSinceEpoch}';
  }
}

/// Command that captures the widget tree from a running Flutter app.
class WidgetTreeCommand extends ProfilerCommand with VmServiceDiscovery {
  /// Creates a widget-tree command.
  WidgetTreeCommand(super.profileRunner) {
    argParser
      ..addOption(
        'depth',
        defaultsTo: '15',
        help: 'Maximum tree depth (default: 15).',
      )
      ..addFlag(
        'summary',
        negatable: false,
        help: 'Use the summary tree (Flutter widgets only).',
      )
      ..addFlag(
        'project-only',
        negatable: false,
        help: 'Filter to project widgets only.',
      );
  }

  @override
  String get name => 'flutter:widget-tree';

  @override
  String get description =>
      'Capture the widget tree from a running Flutter app via its VM service URI.';

  @override
  String get invocation =>
      '${runner!.executableName} flutter:widget-tree [options] <vm-service-uri>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler flutter:widget-tree ws://127.0.0.1:8181/abc123/ws',
      'devtools-profiler flutter:widget-tree --summary --depth 10 ws://127.0.0.1:8181/abc123/ws',
    ],
  );

  @override
  Future<int> run() async {
    final vmServiceUri = await resolveVmServiceUri();
    final maxDepth =
        int.tryParse(argResults!['depth'] as String? ?? '15') ?? 15;
    final useSummary = argResults!['summary'] as bool? ?? false;
    final projectOnly = argResults!['project-only'] as bool? ?? false;

    final wsUri = vmServiceUri
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final cleanWs = wsUri.endsWith('/ws') ? wsUri : '$wsUri/ws';

    final vmService = await vmServiceConnectUri(cleanWs);
    try {
      final vm = await vmService.getVM();
      final isolates = vm.isolates ?? [];
      final activeIsolates = isolates
          .where((i) => i.isSystemIsolate != true)
          .toList();
      if (activeIsolates.isEmpty) {
        error('No active application isolates found.');
        return softwareExitCode;
      }
      final isolateId = activeIsolates.first.id!;

      final captureService = WidgetTreeCaptureService(vmService: vmService);
      final tree = useSummary
          ? await captureService.captureSummaryWidgetTree(
              isolateId: isolateId,
              maxDepth: maxDepth,
              projectOnly: projectOnly,
            )
          : await captureService.captureWidgetTree(
              isolateId: isolateId,
              maxDepth: maxDepth,
              projectOnly: projectOnly,
            );

      if (printJson) {
        line(jsonEncoder.convert(tree.toJson()));
      } else {
        io.title('Widget Tree');
        io.components.definitionList({
          'Nodes': '${tree.nodeCount}',
          'Max Depth': '${tree.maxDepth}',
          'Timestamp': '${tree.timestamp}',
        });

        io.section('Tree');
        _renderWidgetNode(tree.root, depth: 0);
      }
    } finally {
      await vmService.dispose();
    }

    return successExitCode;
  }

  void _renderWidgetNode(WidgetTreeNode node, {required int depth}) {
    final indent = '  ' * depth;
    final label = node.details.isNotEmpty
        ? '${node.name} (${node.details})'
        : node.name;
    line('$indent- $label');
    for (final child in node.children) {
      if (depth < 10) {
        _renderWidgetNode(child, depth: depth + 1);
      }
    }
  }
}

/// Command that captures a screenshot from a running Flutter app.
class ScreenshotCommand extends ProfilerCommand with VmServiceDiscovery {
  /// Creates a screenshot command.
  ScreenshotCommand(super.profileRunner) {
    argParser
      ..addOption(
        'output',
        defaultsTo: 'screenshot.png',
        help: 'Output file path (default: screenshot.png).',
      )
      ..addOption('width', defaultsTo: '800', help: 'Image width in pixels.')
      ..addOption('height', defaultsTo: '600', help: 'Image height in pixels.');
  }

  @override
  String get name => 'flutter:screenshot';

  @override
  String get description =>
      'Capture a screenshot from a running Flutter app via its VM service URI.';

  @override
  String get invocation =>
      '${runner!.executableName} flutter:screenshot [options] <vm-service-uri>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler flutter:screenshot ws://127.0.0.1:8181/abc123/ws',
      'devtools-profiler flutter:screenshot --output app.png --width 1920 ws://127.0.0.1:8181/abc123/ws',
    ],
  );

  @override
  Future<int> run() async {
    final vmServiceUri = await resolveVmServiceUri();
    final outputPath = argResults!['output'] as String? ?? 'screenshot.png';
    final width = int.tryParse(argResults!['width'] as String? ?? '800') ?? 800;
    final height =
        int.tryParse(argResults!['height'] as String? ?? '600') ?? 600;

    final wsUri = vmServiceUri
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final cleanWs = wsUri.endsWith('/ws') ? wsUri : '$wsUri/ws';

    final vmService = await vmServiceConnectUri(cleanWs);
    try {
      final vm = await vmService.getVM();
      final isolateId = _resolveMainIsolate(vm);
      final service = ScreenshotCaptureService(vmService: vmService);
      final file = await service.captureScreenshotToFile(
        isolateId: isolateId,
        outputPath: outputPath,
        width: width.toDouble(),
        height: height.toDouble(),
      );
      comment('Screenshot saved to ${file.path}');
    } finally {
      await vmService.dispose();
    }

    return successExitCode;
  }

  String _resolveMainIsolate(VM vm) {
    final isolates = vm.isolates ?? [];
    final active = isolates.where((i) => i.isSystemIsolate != true).toList();
    if (active.isEmpty) {
      throw StateError('No active application isolates found.');
    }
    return active.first.id!;
  }
}

/// Command that dumps Flutter debug diagnostics.
class DebugDumpCommand extends ProfilerCommand with VmServiceDiscovery {
  /// Creates a debug-dump command.
  DebugDumpCommand(super.profileRunner) {
    argParser.addOption(
      'kind',
      defaultsTo: 'app',
      allowed: DebugDumpService.availableKinds,
      help:
          'What to dump: ${DebugDumpService.availableKinds.join(", ")} (default: app).',
    );
  }

  @override
  String get name => 'flutter:debug-dump';

  @override
  String get description =>
      'Dump Flutter diagnostic information from a running app via its VM service URI.';

  @override
  String get invocation =>
      '${runner!.executableName} flutter:debug-dump [options] <vm-service-uri>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler flutter:debug-dump ws://127.0.0.1:8181/abc123/ws',
      'devtools-profiler flutter:debug-dump --kind render ws://127.0.0.1:8181/abc123/ws',
    ],
  );

  @override
  Future<int> run() async {
    final vmServiceUri = await resolveVmServiceUri();
    final kind = argResults!['kind'] as String? ?? 'app';

    final wsUri = vmServiceUri
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final cleanWs = wsUri.endsWith('/ws') ? wsUri : '$wsUri/ws';

    final vmService = await vmServiceConnectUri(cleanWs);
    try {
      final vm = await vmService.getVM();
      final isolateId = _resolveMainIsolate(vm);
      final service = DebugDumpService(vmService: vmService);

      if (printJson) {
        final result = await service.dump(isolateId: isolateId, kind: kind);
        line(jsonEncoder.convert(result.toJson()));
      } else {
        io.title('Debug Dump ($kind)');
        final result = await service.dump(isolateId: isolateId, kind: kind);
        line(result.content);
      }
    } finally {
      await vmService.dispose();
    }

    return successExitCode;
  }

  String _resolveMainIsolate(VM vm) {
    final isolates = vm.isolates ?? [];
    final active = isolates.where((i) => i.isSystemIsolate != true).toList();
    if (active.isEmpty) {
      throw StateError('No active application isolates found.');
    }
    return active.first.id!;
  }
}

/// Command that captures logs from a running Flutter/Dart app.
class LogsCommand extends ProfilerCommand with VmServiceDiscovery {
  /// Creates a logs command.
  LogsCommand(super.profileRunner) {
    argParser
      ..addOption(
        'duration',
        defaultsTo: '10',
        help: 'Duration to capture logs in seconds (default: 10).',
      )
      ..addOption(
        'output',
        help: 'Output file for captured logs. Prints to stdout when omitted.',
      )
      ..addFlag(
        'follow',
        negatable: false,
        help:
            'Continuously stream logs until interrupted (ignores --duration).',
      );
  }

  @override
  String get name => 'flutter:logs';

  @override
  String get description =>
      'Capture log and output streams from a running app via its VM service URI.';

  @override
  String get invocation =>
      '${runner!.executableName} flutter:logs [options] <vm-service-uri>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler flutter:logs ws://127.0.0.1:8181/abc123/ws',
      'devtools-profiler flutter:logs --duration 30 --output session.log ws://127.0.0.1:8181/abc123/ws',
    ],
  );

  @override
  Future<int> run() async {
    final vmServiceUri = await resolveVmServiceUri();
    final duration =
        int.tryParse(argResults!['duration'] as String? ?? '10') ?? 10;
    final outputPath = argResults!['output'] as String?;
    final follow = argResults!['follow'] as bool;

    final wsUri = vmServiceUri
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final cleanWs = wsUri.endsWith('/ws') ? wsUri : '$wsUri/ws';

    final vmService = await vmServiceConnectUri(cleanWs);
    try {
      final capture = LogStreamCapture(vmService: vmService);
      await capture.start();

      if (follow) {
        comment('Streaming logs. Press Ctrl+C to stop.');
        await Future<void>.delayed(const Duration(days: 365));
      } else {
        await Future<void>.delayed(Duration(seconds: duration));
      }

      final entries = await capture.stop();

      if (outputPath != null) {
        final file = File(outputPath);
        await capture.writeToFile(file);
        comment('Logs written to ${file.path}');
      } else {
        if (printJson) {
          line(
            jsonEncoder.convert([for (final entry in entries) entry.toJson()]),
          );
        } else {
          io.title('Captured Logs (${entries.length} entries)');
          for (final entry in entries) {
            line('[${entry.kind}] ${entry.message}');
          }
        }
      }
    } finally {
      await vmService.dispose();
    }

    return successExitCode;
  }
}
