import 'dart:async';
import 'package:vm_service/vm_service.dart';

const _kFrameBudgetUs = 16666;
const _kDefaultFrameProfileDuration = Duration(seconds: 5);

/// Results from a frame/jank analysis session.
final class FrameAnalysisResult {
  /// Creates a frame analysis result.
  const FrameAnalysisResult({
    required this.durationMicros,
    required this.totalFrames,
    required this.jankyFrames,
    required this.averageFrameTimeUs,
    required this.maxFrameTimeUs,
    required this.p90FrameTimeUs,
    required this.p99FrameTimeUs,
    required this.buildPhaseTimeUs,
    required this.layoutPhaseTimeUs,
    required this.paintPhaseTimeUs,
    required this.jankyFrameEvents,
    required this.rawTimelineEventCount,
  });

  /// Total duration of the profiling window in microseconds.
  final int durationMicros;

  /// Total number of frame events captured.
  final int totalFrames;

  /// Number of frames that exceeded the 16.6ms budget.
  final int jankyFrames;

  /// Average frame time in microseconds.
  final double averageFrameTimeUs;

  /// Maximum frame time in microseconds.
  final double maxFrameTimeUs;

  /// P90 frame time in microseconds.
  final double p90FrameTimeUs;

  /// P99 frame time in microseconds.
  final double p99FrameTimeUs;

  /// Total time spent in build phase events in microseconds.
  final double buildPhaseTimeUs;

  /// Total time spent in layout phase events in microseconds.
  final double layoutPhaseTimeUs;

  /// Total time spent in paint phase events in microseconds.
  final double paintPhaseTimeUs;

  /// Details of frames that exceeded the budget.
  final List<Map<String, Object?>> jankyFrameEvents;

  /// Total number of timeline events inspected.
  final int rawTimelineEventCount;

  /// Ratio of janky frames to total frames.
  double get jankRatio => totalFrames > 0 ? jankyFrames / totalFrames : 0.0;

  /// Jank ratio as a percentage.
  double get jankPercentage => jankRatio * 100;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'durationMicros': durationMicros,
    'totalFrames': totalFrames,
    'jankyFrames': jankyFrames,
    'jankPercentage': jankPercentage,
    'averageFrameTimeUs': averageFrameTimeUs,
    'maxFrameTimeUs': maxFrameTimeUs,
    'p90FrameTimeUs': p90FrameTimeUs,
    'p99FrameTimeUs': p99FrameTimeUs,
    'buildPhaseTimeUs': buildPhaseTimeUs,
    'layoutPhaseTimeUs': layoutPhaseTimeUs,
    'paintPhaseTimeUs': paintPhaseTimeUs,
    'jankyFrameEvents': jankyFrameEvents,
    'rawTimelineEventCount': rawTimelineEventCount,
  };
}

/// Captures frame timing data from a running Dart VM service.
///
/// Enables the VM timeline, samples for a duration, then parses frame events
/// to compute rendering performance metrics including jank detection.
class FrameAnalyzer {
  /// Creates a frame analyzer backed by [vmService].
  FrameAnalyzer({required VmService vmService}) : _vmService = vmService;

  final VmService _vmService;

  /// Profiles frame timing for [duration] and returns the analysis result.
  ///
  /// Defaults to 5 seconds when [duration] is omitted.
  Future<FrameAnalysisResult> profileFrames({Duration? duration}) async {
    final profileDuration = duration ?? _kDefaultFrameProfileDuration;

    await _vmService.setVMTimelineFlags(['Embedder', 'Dart', 'GC', 'API']);
    await _vmService.clearVMTimeline();

    await Future<void>.delayed(profileDuration);

    final timeline = await _vmService.getVMTimeline();
    try {
      await _vmService.setVMTimelineFlags([]);
    } catch (_) {}

    final events = timeline.traceEvents ?? [];
    return _analyzeFrameEvents(events, profileDuration);
  }

  FrameAnalysisResult _analyzeFrameEvents(
    List<TimelineEvent> events,
    Duration profileDuration,
  ) {
    var totalFrames = 0;
    var jankyFrames = 0;
    var maxFrameTimeUs = 0.0;
    final frameDurations = <double>[];
    final jankyFrameEvents = <Map<String, Object?>>[];
    var buildTimeTotal = 0.0;
    var layoutTimeTotal = 0.0;
    var paintTimeTotal = 0.0;

    for (final event in events) {
      final name = event.json?['name'] as String?;
      final ph = event.json?['ph'] as String?;
      final dur = event.json?['dur'] as num?;
      if (name == null || ph != 'X' || dur == null) continue;

      final lowerName = name.toLowerCase();
      final durationUs = dur.toDouble();

      // Detect frame events
      if (_isFrameEvent(lowerName)) {
        totalFrames++;
        frameDurations.add(durationUs);
        if (durationUs > maxFrameTimeUs) maxFrameTimeUs = durationUs;

        if (durationUs > _kFrameBudgetUs) {
          jankyFrames++;
          final severity = durationUs > _kFrameBudgetUs * 2
              ? 'critical'
              : 'warning';
          jankyFrameEvents.add({
            'name': name,
            'durationUs': durationUs,
            'severity': severity,
          });
        }
      }

      // Phase breakdowns
      if (lowerName.contains('build') ||
          lowerName.contains('widget') ||
          lowerName.contains('createelement') ||
          lowerName.contains('updatechild') ||
          lowerName.contains('performrebuild')) {
        buildTimeTotal += durationUs;
      } else if (lowerName.contains('layout') ||
          lowerName.contains('performlayout') ||
          lowerName.contains('flushlayout') ||
          lowerName.contains('renderflex') ||
          lowerName.contains('renderbox')) {
        layoutTimeTotal += durationUs;
      } else if (lowerName.contains('paint') ||
          lowerName.contains('flushpaint') ||
          lowerName.contains('compositeframe') ||
          lowerName.contains('rasterizer')) {
        paintTimeTotal += durationUs;
      }
    }

    frameDurations.sort();
    final avgFrameTime = frameDurations.isNotEmpty
        ? frameDurations.reduce((a, b) => a + b) / frameDurations.length
        : 0.0;
    final p90 = frameDurations.isNotEmpty
        ? frameDurations[(frameDurations.length * 0.9).floor()]
        : 0.0;
    final p99 = frameDurations.isNotEmpty
        ? frameDurations[(frameDurations.length * 0.99).floor()]
        : 0.0;

    return FrameAnalysisResult(
      durationMicros: profileDuration.inMicroseconds,
      totalFrames: totalFrames,
      jankyFrames: jankyFrames,
      averageFrameTimeUs: avgFrameTime,
      maxFrameTimeUs: maxFrameTimeUs,
      p90FrameTimeUs: p90,
      p99FrameTimeUs: p99,
      buildPhaseTimeUs: buildTimeTotal,
      layoutPhaseTimeUs: layoutTimeTotal,
      paintPhaseTimeUs: paintTimeTotal,
      jankyFrameEvents: jankyFrameEvents,
      rawTimelineEventCount: events.length,
    );
  }

  bool _isFrameEvent(String name) {
    return switch (name) {
      'frame' ||
      'vsync' ||
      'gpurasterizer::draw' ||
      'rasterizer::dodraw' => true,
      _
          when name.contains('animator') ||
              name.contains('beginframe') ||
              name.contains('pipeline produce') ||
              name.contains('pipeline consume') =>
        true,
      _ => false,
    };
  }
}
