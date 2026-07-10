import 'dart:async';
import 'package:vm_service/vm_service.dart';

const _kFrameBudgetUs = 16666;
const _kDefaultFrameProfileDuration = Duration(seconds: 5);

/// A timeline event related to shader compilation.
final class ShaderCompilationEvent {
  /// Creates a shader compilation event.
  const ShaderCompilationEvent({
    required this.name,
    required this.durationUs,
    required this.category,
  });

  /// The event name (e.g. GrGLProgramBuilder, Program::compile).
  final String name;

  /// Duration in microseconds.
  final double durationUs;

  /// Category: 'skia', 'impeller', 'gpu', or 'other'.
  final String category;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'name': name,
    'durationUs': durationUs,
    'category': category,
  };
}

/// A hotspot insight extracted from the VM timeline.
final class TimelineHotspot {
  /// Creates a timeline hotspot.
  const TimelineHotspot({
    required this.name,
    required this.selfDurationUs,
    required this.totalDurationUs,
    required this.callCount,
    required this.maxDurationUs,
  });

  /// The event name.
  final String name;

  /// Self (exclusive) duration in microseconds.
  final double selfDurationUs;

  /// Total (inclusive) duration in microseconds.
  final double totalDurationUs;

  /// Number of times this event occurred.
  final int callCount;

  /// Maximum single duration in microseconds.
  final double maxDurationUs;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'name': name,
    'selfDurationUs': selfDurationUs,
    'totalDurationUs': totalDurationUs,
    'callCount': callCount,
    'maxDurationUs': maxDurationUs,
  };
}

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
    this.shaderCompilationEvents = const [],
    this.timelineHotspots = const [],
    this.detectedFps = 60.0,
  });

  /// Total duration of the profiling window in microseconds.
  final int durationMicros;

  /// Total number of frame events captured.
  final int totalFrames;

  /// Number of frames that exceeded the budget.
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

  /// Detected shader compilation events.
  final List<ShaderCompilationEvent> shaderCompilationEvents;

  /// Timeline hotspot events sorted by total duration.
  final List<TimelineHotspot> timelineHotspots;

  /// Detected display refresh rate in fps.
  final double detectedFps;

  /// Whether shader compilation jank was detected.
  bool get hasShaderJank => shaderCompilationEvents.isNotEmpty;

  /// Total time spent in shader compilation.
  double get totalShaderCompilationTimeUs {
    if (shaderCompilationEvents.isEmpty) return 0;
    return shaderCompilationEvents
        .map((e) => e.durationUs)
        .reduce((a, b) => a + b);
  }

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
    'detectedFps': detectedFps,
    'hasShaderJank': hasShaderJank,
    'totalShaderCompilationTimeUs': totalShaderCompilationTimeUs,
    if (shaderCompilationEvents.isNotEmpty)
      'shaderCompilationEvents': [
        for (final e in shaderCompilationEvents) e.toJson(),
      ],
    if (timelineHotspots.isNotEmpty)
      'timelineHotspots': [
        for (final h in timelineHotspots.take(10)) h.toJson(),
      ],
  };
}

/// Captures frame timing data from a running Dart VM service.
///
/// Enables the VM timeline, samples for a duration, then parses frame events
/// to compute rendering performance metrics including jank detection.
///
/// When [detectRefreshRate] is true (default), the analyzer calls the
/// `ext.flutter.getDisplayRefreshRate` extension to determine the target
/// frame budget dynamically. Falls back to 60fps (16.6ms) when unavailable.
class FrameAnalyzer {
  /// Creates a frame analyzer backed by [vmService].
  FrameAnalyzer({required VmService vmService}) : _vmService = vmService;

  final VmService _vmService;

  /// Profiles frame timing for [duration] and returns the analysis result.
  ///
  /// Defaults to 5 seconds when [duration] is omitted.
  ///
  /// When [detectRefreshRate] is true (default), attempts to detect the
  /// display refresh rate via Flutter's service extension and adjusts the
  /// frame budget accordingly.
  Future<FrameAnalysisResult> profileFrames({
    Duration? duration,
    bool detectRefreshRate = true,
    String? isolateId,
  }) async {
    final profileDuration = duration ?? _kDefaultFrameProfileDuration;

    // Detect display refresh rate for dynamic frame budget
    double detectedFps = 60.0;
    if (detectRefreshRate && isolateId != null) {
      try {
        final response = await _vmService.callServiceExtension(
          'ext.flutter.getDisplayRefreshRate',
          isolateId: isolateId,
        );
        final fps = response.json?['fps'] as num?;
        if (fps != null && fps > 0) {
          detectedFps = fps.toDouble();
        }
      } catch (_) {
        // Extension not available — use default 60fps
      }
    }

    await _vmService.setVMTimelineFlags(['Embedder', 'Dart', 'GC', 'API']);
    await _vmService.clearVMTimeline();

    await Future<void>.delayed(profileDuration);

    final timeline = await _vmService.getVMTimeline();
    try {
      await _vmService.setVMTimelineFlags([]);
    } catch (_) {}

    final events = timeline.traceEvents ?? [];
    return _analyzeFrameEvents(
      events,
      profileDuration,
      frameBudgetUs: (1000000 / detectedFps).round(),
      detectedFps: detectedFps,
    );
  }

  FrameAnalysisResult _analyzeFrameEvents(
    List<TimelineEvent> events,
    Duration profileDuration, {
    int frameBudgetUs = _kFrameBudgetUs,
    double detectedFps = 60.0,
  }) {
    var totalFrames = 0;
    var jankyFrames = 0;
    var maxFrameTimeUs = 0.0;
    final frameDurations = <double>[];
    final jankyFrameEvents = <Map<String, Object?>>[];
    final shaderEvents = <ShaderCompilationEvent>[];
    final hotspotMap = <String, _HotspotAccumulator>{};
    var buildTimeTotal = 0.0;
    var layoutTimeTotal = 0.0;
    var paintTimeTotal = 0.0;
    var shaderJankInCurrentFrame = false;

    for (final event in events) {
      final name = event.json?['name'] as String?;
      final ph = event.json?['ph'] as String?;
      final dur = event.json?['dur'] as num?;
      if (name == null || ph != 'X' || dur == null) continue;

      final lowerName = name.toLowerCase();
      final durationUs = dur.toDouble();

      // Track per-event-name totals for hotspot detection
      hotspotMap.putIfAbsent(name, () => _HotspotAccumulator()).add(durationUs);

      // Detect shader compilation events
      if (_isShaderCompilationEvent(lowerName)) {
        final category = _shaderEventCategory(lowerName);
        shaderEvents.add(
          ShaderCompilationEvent(
            name: name,
            durationUs: durationUs,
            category: category,
          ),
        );
        shaderJankInCurrentFrame =
            shaderJankInCurrentFrame || durationUs > 1000;
      }

      // Detect frame events
      if (_isFrameEvent(lowerName)) {
        totalFrames++;
        frameDurations.add(durationUs);
        if (durationUs > maxFrameTimeUs) maxFrameTimeUs = durationUs;

        if (durationUs > frameBudgetUs) {
          jankyFrames++;
          final severity = durationUs > frameBudgetUs * 2
              ? 'critical'
              : 'warning';
          jankyFrameEvents.add({
            'name': name,
            'durationUs': durationUs,
            'severity': severity,
            'shaderJank': shaderJankInCurrentFrame,
          });
        }
        shaderJankInCurrentFrame = false;
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

    // Build hotspot list sorted by total duration descending
    final hotspots =
        hotspotMap.entries
            .map(
              (e) => TimelineHotspot(
                name: e.key,
                selfDurationUs: e.value.self,
                totalDurationUs: e.value.total,
                callCount: e.value.count,
                maxDurationUs: e.value.max,
              ),
            )
            .toList()
          ..sort((a, b) => b.totalDurationUs.compareTo(a.totalDurationUs));

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
      shaderCompilationEvents: shaderEvents,
      timelineHotspots: hotspots,
      detectedFps: detectedFps,
    );
  }

  bool _isShaderCompilationEvent(String name) {
    return name.contains('grglprogrambuilder') ||
        name.contains('program::compile') ||
        name.contains('programcompilation') ||
        name.contains('shadercompile') ||
        name.contains('shader') && name.contains('compile') ||
        name.contains('impeller::shader') ||
        name.contains('pipeline::build') ||
        name.contains('pipelinebuild') ||
        name.contains('grprogram') ||
        name.contains('skia::gpu') && name.contains('compile');
  }

  String _shaderEventCategory(String name) {
    if (name.contains('impeller')) return 'impeller';
    if (name.contains('skia') || name.contains('gr')) return 'skia';
    if (name.contains('gpu') || name.contains('pipeline')) return 'gpu';
    return 'other';
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

/// Accumulator for per-event-name timing during frame analysis.
class _HotspotAccumulator {
  double self = 0;
  double total = 0;
  int count = 0;
  double max = 0;

  void add(double duration) {
    self += duration;
    total += duration;
    count++;
    if (duration > max) max = duration;
  }
}
