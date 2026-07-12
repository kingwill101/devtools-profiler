# Changelog

## 0.5.0

- Added `replay` command that animates through stored CPU samples as a
  live flame chart. Shows time-windowed frame samples with visual bars.
  Use `--window` to control the time slice, `--speed` for playback rate,
  and `--top` for number of frames shown.
- Added `annotate` command that shows per-file hotspot breakdowns with
  sample counts, percentages, and visual bars. Use `--file` to filter to
  one source file, `--top` and `--min-samples` to control output.
  Package URIs are resolved via package_config.json.
- Added `lineForFunction()` helper to extract line numbers from VM
  profile function data.

- Positional arguments can now be session ids in addition to file paths.
  Commands like `summarize`, `compare`, `explain`, `trends`, `inspect`,
  `search-methods`, `inspect-classes`, and `compare-method` first try to
  match a positional argument against stored session ids before falling
  back to file-path treatment.
- Improved error output when an artifact is not found — a tip now suggests
  `devtools-profiler profiles` to list available sessions or to pass a
  session id as a positional argument.
- Added `--csv` flag for compact machine-readable table output. Supports
  `summarize`, `compare`, `trends`, and multi-compare modes.
- Added `--last N` flag to `trends` for analyzing the N most recent stored
  sessions without specifying explicit paths.
- Added `--collapse-async` flag that replaces individual `dart:async` frames
  with categorized entries grouped by async type (normal completions, error
  completions, listener dispatch, microtask scheduling, zone overhead).
  When raw CPU samples are available, async cost is further attributed to
  the first non-async caller in the stack, producing actionable entries like
  `async (await _runFrame)` that show which calling function triggered the
  async cost.
- Added what-if async removal estimation to `--collapse-async`: when raw
  CPU samples are available, the profiler estimates how much time could be
  saved by converting specific functions from async to sync. Warnings appear
  for functions where normal completions dominate the async cost, making
  them prime candidates for sync conversion.
- Multi-compare mode: `compare` now accepts 3+ positional arguments and
  produces an aligned hotspot table showing each method's self-percentage
  across all sessions, with "eliminated" for absent entries.
- Added `isAsyncOverhead` getter to `ProfileFrame` for identifying
  `dart:async` frames.
- Added `regress` command that compares the current profile against a
  known-good baseline and reports regressions. Exits with code 1 when
  regressions are found. Use `--warn-only` to always exit 0.
  Examples:
  ```
  devtools-profiler regress path/to/baseline
  devtools-profiler regress 0712060003-8c410 0711235455-ebfb3
  devtools-profiler regress --warn-only path/to/baseline
  ```
- Updated `--csv` output: now also supports the multi-compare mode and
  the `regress` command.

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
- Added `flutter:inspector` for generic Flutter widget inspector queries.
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
  `profile_memory_snapshot`, `profile_widget_tree`,
  `profile_widget_inspector_query`, `profile_screenshot`, `profile_debug_dump`,
  `profile_stream_logs`.
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
