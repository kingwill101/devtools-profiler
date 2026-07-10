import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../constants.dart';
import 'profiler_command.dart';

/// Command that profiles frame timing from a running Flutter app.
class FrameProfileCommand extends ProfilerCommand {
  /// Creates a frame profile command.
  FrameProfileCommand(super.profileRunner) {
    argParser.addOption(
      'duration',
      defaultsTo: '5',
      help: 'Duration to profile frames in seconds (default: 5).',
    );
  }

  @override
  String get name => 'frame-profile';

  @override
  String get description =>
      'Profile frame timing from a running Flutter app '
      'via its VM service URI.';

  @override
  String get invocation =>
      '${runner!.executableName} frame-profile [options] <vm-service-uri>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler frame-profile ws://127.0.0.1:8181/abc123/ws',
      'devtools-profiler frame-profile --duration 10 ws://127.0.0.1:8181/abc123/ws',
    ],
  );

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('A VM service URI is required.');
    }

    final vmServiceUri = argResults!.rest.single;
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
      final isolateId = (active.isNotEmpty ? active.first : isolates.first).id;

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

        io.title('Frame Profile');
        io.components.definitionList({
          'Duration': '${result.durationMicros ~/ 1000000}s',
          'Total Frames': '${result.totalFrames}',
          'Janky Frames': '${result.jankyFrames} ($jankPct%)',
          'Average Frame': '$avgMs ms',
          'Max Frame': '$maxMs ms',
          'Detected FPS': '${result.detectedFps.toStringAsFixed(0)}',
          'P90 Frame': '${(result.p90FrameTimeUs / 1000).toStringAsFixed(2)} ms',
          'P99 Frame': '${(result.p99FrameTimeUs / 1000).toStringAsFixed(2)} ms',
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

/// Command that captures a memory snapshot from a running Flutter/Dart app.
class MemorySnapshotCommand extends ProfilerCommand {
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
  String get name => 'memory-snapshot';

  @override
  String get description =>
      'Capture an allocation profile from a running app via its VM service URI.';

  @override
  String get invocation =>
      '${runner!.executableName} memory-snapshot [options] <vm-service-uri>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler memory-snapshot ws://127.0.0.1:8181/abc123/ws',
      'devtools-profiler memory-snapshot --name before-opt --no-gc ws://127.0.0.1:8181/abc123/ws',
    ],
  );

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('A VM service URI is required.');
    }

    final vmServiceUri = argResults!.rest.single;
    final name = argResults!['name'] as String?;
    final forceGc = !(argResults!['no-gc'] as bool? ?? false);

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
          name ?? 'cli-snapshot-${DateTime.now().millisecondsSinceEpoch}';

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
}

/// Command that captures the widget tree from a running Flutter app.
class WidgetTreeCommand extends ProfilerCommand {
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
  String get name => 'widget-tree';

  @override
  String get description =>
      'Capture the widget tree from a running Flutter app via its VM service URI.';

  @override
  String get invocation =>
      '${runner!.executableName} widget-tree [options] <vm-service-uri>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler widget-tree ws://127.0.0.1:8181/abc123/ws',
      'devtools-profiler widget-tree --summary --depth 10 ws://127.0.0.1:8181/abc123/ws',
    ],
  );

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('A VM service URI is required.');
    }

    final vmServiceUri = argResults!.rest.single;
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

/// Command that inspects the Flutter navigation route stack.
class RouteStackCommand extends ProfilerCommand {
  /// Creates a route-stack command.
  RouteStackCommand(super.profileRunner);

  @override
  String get name => 'route-stack';

  @override
  String get description =>
      'Inspect the navigation stack from a running Flutter app '
      'via its VM service URI.';

  @override
  String get invocation =>
      '${runner!.executableName} route-stack [options] <vm-service-uri>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler route-stack ws://127.0.0.1:8181/abc123/ws',
    ],
  );

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('A VM service URI is required.');
    }

    final vmServiceUri = argResults!.rest.single;
    final wsUri = vmServiceUri
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final cleanWs = wsUri.endsWith('/ws') ? wsUri : '$wsUri/ws';

    final vmService = await vmServiceConnectUri(cleanWs);
    try {
      final vm = await vmService.getVM();
      final isolateId = _findMainIsolate(vm);
      final service = NavigationStackService(vmService: vmService);
      final stack = await service.getNavigationStack(isolateId: isolateId);

      if (printJson) {
        line(jsonEncoder.convert(stack.toJson()));
      } else {
        io.title('Navigation Stack');
        io.table(
          headers: const ['Route', 'Type', 'Settings Name', 'Current'],
          rows: [
            for (final route in stack.routes)
              [
                route.path,
                route.name,
                route.settingsName ?? '-',
                route.isCurrent ? '*' : '',
              ],
          ],
        );
        if (stack.currentRoute != null) {
          comment('Current route: ${stack.currentRoute!.path}');
        }
      }
    } finally {
      await vmService.dispose();
    }

    return successExitCode;
  }

  String _findMainIsolate(VM vm) {
    final isolates = vm.isolates ?? [];
    final active = isolates.where((i) => i.isSystemIsolate != true).toList();
    if (active.isEmpty && isolates.isEmpty) {
      throw StateError('No isolates found in the target VM.');
    }
    return (active.isNotEmpty ? active.first : isolates.first).id!;
  }
}
