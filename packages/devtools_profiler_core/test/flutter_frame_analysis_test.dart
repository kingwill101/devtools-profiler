import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('FrameAnalysisResult', () {
    test('constructs and computes jank metrics', () {
      final result = FrameAnalysisResult(
        durationMicros: 5_000_000,
        totalFrames: 60,
        jankyFrames: 3,
        averageFrameTimeUs: 15000,
        maxFrameTimeUs: 35000,
        p90FrameTimeUs: 16500,
        p99FrameTimeUs: 22000,
        buildPhaseTimeUs: 500_000,
        layoutPhaseTimeUs: 200_000,
        paintPhaseTimeUs: 300_000,
        jankyFrameEvents: [
          {
            'name': 'GPURasterizer::Draw',
            'durationUs': 35000,
            'severity': 'critical',
          },
          {
            'name': 'GPURasterizer::Draw',
            'durationUs': 18000,
            'severity': 'warning',
          },
        ],
        rawTimelineEventCount: 120,
      );

      expect(result.durationMicros, 5_000_000);
      expect(result.totalFrames, 60);
      expect(result.jankyFrames, 3);
      expect(result.jankPercentage, closeTo(5.0, 0.01));
      expect(result.jankRatio, closeTo(0.05, 0.001));
      expect(result.averageFrameTimeUs, 15000);
      expect(result.maxFrameTimeUs, 35000);
      expect(result.p90FrameTimeUs, 16500);
      expect(result.p99FrameTimeUs, 22000);
      expect(result.buildPhaseTimeUs, 500_000);
      expect(result.layoutPhaseTimeUs, 200_000);
      expect(result.paintPhaseTimeUs, 300_000);
      expect(result.jankyFrameEvents, hasLength(2));
      expect(result.rawTimelineEventCount, 120);

      // JSON round-trip
      final json = result.toJson();
      expect(json['totalFrames'], 60);
      expect(json['jankPercentage'], closeTo(5.0, 0.01));
    });

    test('handles no frames', () {
      final result = FrameAnalysisResult(
        durationMicros: 5_000_000,
        totalFrames: 0,
        jankyFrames: 0,
        averageFrameTimeUs: 0,
        maxFrameTimeUs: 0,
        p90FrameTimeUs: 0,
        p99FrameTimeUs: 0,
        buildPhaseTimeUs: 0,
        layoutPhaseTimeUs: 0,
        paintPhaseTimeUs: 0,
        jankyFrameEvents: [],
        rawTimelineEventCount: 0,
      );

      expect(result.totalFrames, 0);
      expect(result.jankyFrames, 0);
      expect(result.jankPercentage, 0);
      expect(result.jankRatio, 0);
    });

    test('parses fixture timeline data', () {
      final fixturePath = path.join(
        _fixtureDirectory().path,
        'data',
        'timeline_response.json',
      );
      final json =
          jsonDecode(File(fixturePath).readAsStringSync())
              as Map<String, dynamic>;
      final traceEvents = (json['traceEvents'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      // Verify the fixture structure
      expect(traceEvents, hasLength(18));

      // Count frame events (GPURasterizer::Draw or Animator::BeginFrame)
      final frameEvents = traceEvents.where((e) {
        final name = e['name'] as String;
        return name == 'GPURasterizer::Draw' || name == 'Animator::BeginFrame';
      });
      expect(frameEvents, hasLength(12));

      // Identify janky frames (duration > 16666us)
      final janky = frameEvents.where((e) {
        final dur = e['dur'] as num;
        return dur > 16666;
      });
      expect(janky, hasLength(2)); // two janky frames at 18000us and 32000us

      // Count build/layout/paint phase events
      final buildEvents = traceEvents.where(
        (e) => (e['name'] as String).contains('build'),
      );
      final layoutEvents = traceEvents.where(
        (e) => (e['name'] as String).contains('performLayout'),
      );
      final paintEvents = traceEvents.where(
        (e) => (e['name'] as String).contains('flushPaint'),
      );

      expect(buildEvents, hasLength(2));
      expect(layoutEvents, hasLength(2));
      expect(paintEvents, hasLength(2));
    });

    test('hasShaderJank is false when no shader events', () {
      final result = FrameAnalysisResult(
        durationMicros: 5_000_000,
        totalFrames: 60,
        jankyFrames: 3,
        averageFrameTimeUs: 15000,
        maxFrameTimeUs: 35000,
        p90FrameTimeUs: 16500,
        p99FrameTimeUs: 22000,
        buildPhaseTimeUs: 500_000,
        layoutPhaseTimeUs: 200_000,
        paintPhaseTimeUs: 300_000,
        jankyFrameEvents: [],
        rawTimelineEventCount: 120,
      );
      expect(result.hasShaderJank, false);
      expect(result.shaderCompilationEvents, isEmpty);
    });

    test('hasShaderJank is true with shader events', () {
      final result = FrameAnalysisResult(
        durationMicros: 5_000_000,
        totalFrames: 60,
        jankyFrames: 3,
        averageFrameTimeUs: 15000,
        maxFrameTimeUs: 35000,
        p90FrameTimeUs: 16500,
        p99FrameTimeUs: 22000,
        buildPhaseTimeUs: 500_000,
        layoutPhaseTimeUs: 200_000,
        paintPhaseTimeUs: 300_000,
        jankyFrameEvents: [],
        rawTimelineEventCount: 120,
        shaderCompilationEvents: [
          ShaderCompilationEvent(
            name: 'GrGLProgramBuilder',
            durationUs: 25000,
            category: 'skia',
          ),
        ],
      );
      expect(result.hasShaderJank, true);
      expect(result.shaderCompilationEvents, hasLength(1));
      expect(result.totalShaderCompilationTimeUs, 25000);
    });

    test('timelineHotspots sorted by total duration', () {
      final result = FrameAnalysisResult(
        durationMicros: 5_000_000,
        totalFrames: 60,
        jankyFrames: 0,
        averageFrameTimeUs: 15000,
        maxFrameTimeUs: 20000,
        p90FrameTimeUs: 16500,
        p99FrameTimeUs: 18000,
        buildPhaseTimeUs: 500_000,
        layoutPhaseTimeUs: 200_000,
        paintPhaseTimeUs: 300_000,
        jankyFrameEvents: [],
        rawTimelineEventCount: 50,
        timelineHotspots: [
          TimelineHotspot(
            name: 'GPURasterizer::Draw',
            selfDurationUs: 300_000,
            totalDurationUs: 300_000,
            callCount: 20,
            maxDurationUs: 35000,
          ),
          TimelineHotspot(
            name: 'Build',
            selfDurationUs: 100_000,
            totalDurationUs: 100_000,
            callCount: 15,
            maxDurationUs: 12000,
          ),
        ],
      );
      expect(result.timelineHotspots, hasLength(2));
      expect(result.timelineHotspots.first.name, 'GPURasterizer::Draw');
      expect(result.timelineHotspots.first.totalDurationUs, 300_000);

      final json = result.toJson();
      expect(json['hasShaderJank'], false);
      expect(json['timelineHotspots'], hasLength(2));
    });
  });
}

Directory _fixtureDirectory() {
  final candidates = [
    path.join(Directory.current.path, 'test', 'fixtures'),
    path.join(
      Directory.current.path,
      'packages',
      'devtools_profiler_core',
      'test',
      'fixtures',
    ),
  ];

  for (final candidate in candidates) {
    final directory = Directory(candidate);
    if (directory.existsSync()) {
      return directory;
    }
  }

  throw StateError(
    'Could not find fixtures directory. Searched: ${candidates.join(", ")}',
  );
}
