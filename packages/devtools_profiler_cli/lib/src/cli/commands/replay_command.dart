import 'dart:async';

import 'package:artisanal/terminal.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:vm_service/vm_service.dart';

import '../constants.dart';
import 'profile_target_command.dart';

/// Command that replays a stored profiling session as a live flame chart.
///
/// Reads the CPU samples from a stored session and animates through them
/// in time-order, showing a flame-chart-style bar for each time window.
/// Uses carriage return to update the bar in place on the terminal.
class ReplayCommand extends ProfileTargetCommand {
  /// Creates a replay command.
  ReplayCommand(super.profileRunner) {
    argParser
      ..addOption(
        'window',
        defaultsTo: '500',
        help: 'Time window in milliseconds for each flame chart frame.',
      )
      ..addOption(
        'speed',
        defaultsTo: '1.0',
        help: 'Replay speed multiplier. 0.5 = half speed (slower).',
      )
      ..addOption(
        'top',
        defaultsTo: '5',
        help: 'Number of top frames to show in each bar.',
      );
  }

  @override
  String get name => 'replay';

  @override
  String get description =>
      'Replay a stored profiling session as an animated flame chart.';

  @override
  String get invocation => '${runner!.executableName} replay [options] <path>';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler replay path/to/session',
      'devtools-profiler replay --window 200 0712060003-8c410',
      'devtools-profiler replay --speed 0.5 path/to/session',
    ],
  );

  @override
  Future<int> run() async {
    final targetPath = await resolveTargetPath();
    final windowMs =
        int.tryParse(argResults!['window'] as String? ?? '500') ?? 500;
    final speed =
        double.tryParse(argResults!['speed'] as String? ?? '1.0') ?? 1.0;
    final topCount = int.tryParse(argResults!['top'] as String? ?? '5') ?? 5;

    final displayDelay = (windowMs / speed).round();

    // Load the session data.
    final summary = await profileRunner.summarizeArtifact(targetPath);

    final CpuSamples? cpuSamples;
    final int timeOrigin;
    final int timeExtent;
    final String? sessionLabel;

    if (summary case {'regions': final Object? _}) {
      final session = ProfileRunResult.fromJson(summary);
      sessionLabel = session.sessionId;
      final profile =
          session.overallProfile ??
          (session.regions.isNotEmpty ? session.regions.first : null);
      if (profile?.rawProfilePath == null) {
        throw ArgumentError(
          'No raw CPU profile data available in this session. '
          'Re-run with CPU profiling enabled.',
        );
      }
      cpuSamples = await profileRunner.readCpuSamples(profile!.rawProfilePath!);
      timeOrigin = profile.startTimestampMicros;
      timeExtent = profile.durationMicros;
    } else if (summary case {'topSelfFrames': final Object? _}) {
      final region = ProfileRegionResult.fromJson(summary);
      sessionLabel = region.name;
      if (region.rawProfilePath == null) {
        throw ArgumentError('No raw CPU profile data available.');
      }
      cpuSamples = await profileRunner.readCpuSamples(region.rawProfilePath!);
      timeOrigin = region.startTimestampMicros;
      timeExtent = region.durationMicros;
    } else {
      throw ArgumentError('Unsupported target. Use a session or region.');
    }

    if (cpuSamples.samples == null || cpuSamples.samples!.isEmpty) {
      warn('No CPU samples found in this session.');
      return successExitCode;
    }

    final functions = cpuSamples.functions ?? const [];
    final samples = cpuSamples.samples!;
    final windowMicros = windowMs * 1000;
    final totalDuration = timeExtent > 0 ? timeExtent : 1;

    line('Replay: $sessionLabel');
    line('Duration: ${_formatDuration(totalDuration)}');
    line('Samples: ${samples.length}');
    line('Window: ${windowMs}ms (display delay: ${displayDelay}ms)');
    line('');
    line('Flame Chart:');
    line('');

    // Sort samples by timestamp.
    final sortedSamples = samples.toList()
      ..sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));

    final sampleStart = sortedSamples.first.timestamp ?? timeOrigin;
    final sampleEnd = sortedSamples.last.timestamp ?? (timeOrigin + timeExtent);
    final totalSpan = sampleEnd - sampleStart;

    // Group samples into windows and render each window.
    final term = StdioTerminal();
    var windowStart = sampleStart;
    var windowIndex = 0;
    var totalFramesRendered = 0;

    while (windowStart < sampleEnd) {
      final windowEnd = windowStart + windowMicros;
      final windowSamples = sortedSamples.where((s) {
        final t = s.timestamp ?? 0;
        return t >= windowStart && t < windowEnd;
      }).toList();

      // Count top frames in this window.
      final frameCounts = <String, int>{};
      for (final sample in windowSamples) {
        final stack = sample.stack ?? const <int>[];
        if (stack.isEmpty) continue;
        final funcIdx = stack.first;
        if (funcIdx < 0 || funcIdx >= functions.length) continue;
        final func = functions[funcIdx];
        final name = _resolveFrameLabel(func);
        frameCounts[name] = (frameCounts[name] ?? 0) + 1;
      }

      // Build the flame chart bar.
      final elapsedPct = totalSpan > 0
          ? ((windowStart - sampleStart) / totalSpan * 100).toStringAsFixed(0)
          : '0';
      final sorted = frameCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final bar = StringBuffer('[$elapsedPct%] ');
      final maxCount = sorted.isEmpty || sorted.first.value == 0
          ? 1
          : sorted.first.value;
      var remaining = 40;

      for (var i = 0; i < sorted.length && i < topCount; i++) {
        final entry = sorted[i];
        final barLen = ((entry.value / maxCount) * remaining).round().clamp(
          1,
          remaining,
        );
        final label = '${entry.key}(${entry.value})';
        if (bar.length + label.length > 80) break;
        bar.write('█' * barLen);
        bar.write('$label ');
        remaining -=
            barLen + entry.key.length + entry.value.toString().length + 3;
        if (remaining <= 5) break;
      }

      if (sorted.isEmpty) {
        bar.write('(idle)');
      }

      // Update the terminal using artisanal's Terminal API.
      if (windowIndex > 0) {
        term.cursorUp(1);
        term.clearLine();
      }
      term.writeln(bar.toString());

      windowStart = windowEnd;
      windowIndex++;
      totalFramesRendered++;

      // Delay for replay effect.
      if (displayDelay > 0 && windowStart < sampleEnd) {
        await Future.delayed(Duration(milliseconds: displayDelay));
      }
    }

    // Print summary.
    line('');
    line('=== Replay Complete ===');
    line('Frames rendered: $totalFramesRendered');
    line('Time span: ${_formatDuration(totalSpan)}');
    line('');

    // Aggregate summary.
    final totalFrameCounts = <String, int>{};
    for (final sample in sortedSamples) {
      final stack = sample.stack ?? const <int>[];
      if (stack.isEmpty) continue;
      final idx = stack.first;
      if (idx < 0 || idx >= functions.length) continue;
      final name = _resolveFrameLabel(functions[idx]);
      totalFrameCounts[name] = (totalFrameCounts[name] ?? 0) + 1;
    }
    final sortedTotal = totalFrameCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxTotal = sortedTotal.isEmpty ? 1 : sortedTotal.first.value;

    for (final entry in sortedTotal.take(10)) {
      final pct = (entry.value / sortedSamples.length * 100).toStringAsFixed(1);
      final barLen = ((entry.value / maxTotal) * 20).round().clamp(1, 20);
      line(
        '  ${entry.value.toString().padLeft(5)} ($pct%) '
        '${'█' * barLen} ${entry.key}',
      );
    }

    line('');
    return successExitCode;
  }

  /// Resolves a frame label from a ProfileFunction, showing the function
  /// kind (Native, Stub, etc.) when the Dart name is unavailable.
  String _resolveFrameLabel(ProfileFunction func) {
    final name = displayNameForFunction(func);
    if (name.isNotEmpty && name != 'unknown' && !name.startsWith('dart::')) {
      return name;
    }
    // Fall back to the function kind when no name is available.
    final kind = func.kind;
    if (kind != null && kind.isNotEmpty && kind != 'unknown') {
      return '[$kind]';
    }
    return '[native]';
  }

  String _formatDuration(int micros) {
    final ms = micros ~/ 1000;
    if (ms >= 60000) {
      return '${ms ~/ 60000}m${(ms % 60000) ~/ 1000}s';
    }
    if (ms >= 1000) {
      return '${(ms / 1000).toStringAsFixed(1)}s';
    }
    return '${ms}ms';
  }
}
