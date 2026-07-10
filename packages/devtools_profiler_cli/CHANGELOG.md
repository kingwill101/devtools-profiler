# Changelog

## 0.4.0

- Added `profiles` command that lists stored profiling sessions in a
  compact format by default. Use `--extended` for the full session table.
- Analysis commands no longer require a profile path — default to latest.
- Added `--session-id`, `--cwd`, `--limit` for session selection.
- Compacted session identifiers to `MMDDHHmmss-XXXXX`.
- Added `discover` command to scan for running Dart/Flutter VM services.
- Added `flutter:frame-profile` for live frame timing and jank detection
  with dynamic FPS, shader jank, and timeline hotspot analysis.
- Added top-level `timeline` as a first-class alias for frame timing
  analysis.
- Added `flutter:timeline` as a first-class alias for frame timing analysis
  and MCP support for the same surface.
- Added top-level `timeline` as an MCP alias for the same analysis surface.
- Added `flutter attach` launch support for whole-session profiling of an
  already-running Flutter app.
- Added `flutter drive` launch support for profiled Flutter app launches.
- `attach` can auto-discover a single running VM service when no URI is
  provided explicitly.
- Added `flutter:memory-snapshot` for allocation profile capture.
- Added `flutter:widget-tree` for Flutter widget tree inspection.
- Added `flutter:screenshot` for app screenshot capture.
- Added `flutter:debug-dump` for app/render/layer/focus/semantics dumps.
- Added `flutter:logs` for log and output stream capture.
- Added `--warm-up` flag with Flutter readiness detection (polls for
  `ext.flutter.*` extensions instead of a fixed delay).
- Added `--flutter` flag that sets `--warm-up 3s`, `--hide-sdk`, and
  `--hide-runtime-helpers` together.
- Added shader compilation event detection to frame analysis.
- Frame analysis now auto-detects display refresh rate for accurate
  frame budgets (supports 60Hz, 90Hz, 120Hz displays).
- Frame locations now prefer `package:` URIs for portable output.
- Added MCP tools: `profile_discover_apps`, `profile_frame_profile`,
  `profile_memory_snapshot`, `profile_widget_tree`, `profile_screenshot`,
  `profile_debug_dump`, `profile_stream_logs`.
- Flutter fixture app for manual profiling and testing.
- Flutter commands now auto-discover the VM service URI when none is
  provided — works with a single running app without typing the URI.

## 0.3.0

- Added `run --terminal` for profiling terminal UI and alternate-screen apps
  with direct stdin, stdout, and stderr access.
- Added Ctrl+C/SIGTERM handling for launched runs so the CLI prints available
  diagnostics before stopping an interrupted target.
- Preserved terminal mode in reproduction commands for captured sessions.
- Documented terminal-mode profiling in the root README, package READMEs, and
  local profiler skill.

## 0.2.1

- Added `devtools-profiler run <file>.dart` shorthand for profiling Dart files
  without spelling out `dart run`.
- Improved Dart run behavior for short-lived scripts by using the backend's
  exit-pause capture path instead of reporting a disposed VM service error.

## 0.2.0

- Added `inspect-classes` and the `profile_inspect_classes` MCP tool for
  inspecting memory class allocations from stored artifacts.
- Added comparison filters for memory class output, including minimum live bytes
  and memory class count limits.
- Attach sessions now default to a 15s window and skip DTD because explicit
  region markers are unavailable in attach mode.
- Improved CLI and JSON output by surfacing region preparation warnings,
  baseline/current comparison warnings, and sample-count fallback warnings.
- Added warnings when active frame filters remove every CPU frame, plus
  reproduction blocks and matching CLI commands in agent-facing JSON responses.
- Improved memory summary tables to show live bytes, live instances, new
  instances, and allocation deltas without requiring external JSON tools.
- Improved package-filtered output for local checkout frames when used with a
  backend that recognizes local package file paths.

## 0.1.0

- Initial release of the terminal and MCP profiler frontend.
- Added CLI commands for capture, artifact inspection, comparison, and trends.
- Added MCP tools for agent-driven profiling and artifact analysis.
