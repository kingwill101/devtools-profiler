/// Pure-Dart profiling backend for DevTools-inspired automation flows.
///
/// This library is the programmatic entrypoint behind the profiler CLI and MCP
/// server. It can launch or attach to VM-service targets, capture whole-session
/// and region-scoped CPU and memory data, persist session artifacts, and build
/// higher-level summaries such as call trees, method tables, hotspot
/// explanations, comparisons, and trend analyses.
///
/// Most users should start with `devtools_profiler_cli`. Import this library
/// directly when you are building another automation layer that needs the same
/// capture and analysis primitives without terminal or MCP transport code.
///
/// ```dart
/// import 'package:devtools_profiler_core/devtools_profiler_core.dart';
///
/// Future<void> main() async {
///   final runner = ProfileRunner();
///   final result = await runner.run(
///     const ProfileRunRequest(
///       command: ['dart', 'run', 'bin/main.dart'],
///       workingDirectory: '/path/to/app',
///     ),
///   );
///
///   print(result.sessionId);
///   print(result.overallProfile?.sampleCount);
/// }
/// ```
///
/// The most common starting points are [ProfileRunner], [ProfileRunRequest],
/// [ProfileAttachRequest], [ProfileRunResult], and [ProfileRegionResult].
library;

export 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';

export 'src/analysis/profile_comparison.dart';
export 'src/analysis/profile_hotspots.dart';
export 'src/analysis/profile_method_comparison.dart';
export 'src/analysis/profile_method_inspector.dart';
export 'src/analysis/profile_method_search.dart';
export 'src/analysis/profile_trends.dart';
export 'src/capture/artifacts.dart';
export 'src/capture/models.dart';
export 'src/capture/profile_runner.dart';
export 'src/cpu/call_tree.dart';
export 'src/cpu/cpu_profile_summary.dart';
export 'src/cpu/cpu_samples_merge.dart';
export 'src/cpu/method_table.dart';
export 'src/cpu/profile_frames.dart';
export 'src/memory/memory_models.dart';
export 'src/memory/memory_profile_summary.dart';
