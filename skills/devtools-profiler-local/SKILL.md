---
name: devtools-profiler-local
description: >-
  Help users get the Dart and Flutter profiler CLI, MCP server, and
  region-marking library working in their local environments. Use when a user
  asks how to install or run the profiler, profile a Dart script or Flutter
  app, add profiling regions to app code, configure agent/MCP access,
  troubleshoot VM service startup, or understand generated profiling artifacts.
---

# DevTools Profiler Local Setup

Use this skill to get a user from "I want to profile this app" to a working
local capture with useful output.

## First Response

Start by identifying the user's target:

- Dart script: use `run path/to/file.dart` for a bare file, or `run -- dart
  run ...` when the target has its own arguments.
- Flutter app or test: use `run` with `flutter run` or `flutter test`.
- Already-running VM service: use `attach`.
- Application code can be edited: offer region markers.
- Agent automation: offer the stdio MCP server.

Prefer one working command over a broad explanation. Once the first capture
works, help the user add filters, regions, method inspection, or comparisons.
Use `inspect-classes` when the question is about retained memory classes or
allocation deltas.

## Install The CLI

Assume end users install the CLI with `dart pub global activate` and run the
installed executable:

```bash
dart pub global activate devtools_profiler_cli
devtools-profiler help
```

For local source checkouts before publishing, use a path activation from the
profiler workspace:

```bash
dart pub global activate --source path packages/devtools_profiler_cli
devtools-profiler help
```

If `devtools-profiler` is not found after activation, ask the user to add the
Pub global executable directory to `PATH`.

If `dart` is wrapped by a local toolchain manager and fails before running the
command, ask the user to use their direct Dart SDK binary for `pub get`,
`run`, `analyze`, and `test`.

## Profile A Dart Program

Use the bare-file shorthand for a first Dart capture when the target is a
single script:

```bash
devtools-profiler run \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd path/to/app \
  bin/main.dart
```

Bare Dart files are expanded to `dart run <file>`. The profiler holds Dart
launches at isolate exit long enough to capture final CPU and memory snapshots,
so short scripts can still produce a whole-session profile.

Use terminal mode for TUI applications that need direct stdin/stdout/stderr,
raw input, mouse tracking, or alternate-screen rendering:

```bash
devtools-profiler run \
  --terminal \
  --cwd path/to/app \
  -- dart run bin/tui.dart
```

Do not combine `--terminal` with `--json`. The target owns stdout and stderr
while it runs, and the CLI prints the normal profiler summary after the TUI
exits. If the user stops the profiler with Ctrl+C or SIGTERM, the CLI should
finalize and print whatever diagnostics were captured before stopping the
target.

Use the full command shape when the target command has its own arguments or
needs a Dart subcommand:

```bash
devtools-profiler run \
  --duration 15s \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --bottom-up \
  --method-table \
  --cwd path/to/app \
  -- dart run bin/main.dart
```

Everything after `--` is the target command. Keep profiler options before the
target, and keep `--cwd` pointed at the target package or app directory.

## Profile A Flutter Target

Use this shape for Flutter apps or tests:

```bash
devtools-profiler run \
  --duration 15s \
  --vm-service-timeout 5m \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd path/to/flutter_app \
  -- flutter run -d linux
```

For tests, replace the target command with:

```bash
-- flutter test test/widget_test.dart
```

Do not use Flutter release mode, AOT builds, or browser/web targets. They do
not expose the Dart VM service needed by this profiler.

## Attach To An Existing VM

Use attach mode when the app is already running and the user wants repeated
profiling windows without rebuilding:

```bash
devtools-profiler attach \
  --duration 15s \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd path/to/app \
  http://127.0.0.1:8181/example/
```

Tell the user to copy the VM service URI printed by `dart` or `flutter`.
Attach mode clears existing CPU samples, captures a fixed window, and leaves
the target process running.

## Add Region Markers

When the user can edit target code, add `devtools_region_profiler` to that
target package and mark the important section:

```dart
import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> loadLevel() async {
  await profileRegion(
    'load-level',
    attributes: {'phase': 'startup'},
    () async {
      await parseAssets();
      await buildWorld();
    },
  );
}
```

Regions can span nested calls. The profiler captures samples while the region
is active, so work done by callees appears in the region's call tree, method
table, and memory summaries.

Use `run` mode for region capture because the profiler launches the target with
the session and DTD configuration needed by the region library.

## Read Existing Artifacts

Summarize a stored session:

```bash
devtools-profiler summarize \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  path/to/session
```

Inspect a method:

```bash
devtools-profiler inspect \
  --json \
  --method Parser.parseFile \
  --profile-id overall \
  path/to/session
```

Inspect memory classes:

```bash
devtools-profiler inspect-classes \
  --json \
  --class String \
  --min-live-bytes 1048576 \
  path/to/session
```

Use `--limit 0` when the agent needs the complete class list. The command can
read a session directory, a region `summary.json`, or a raw
`memory_profile.json` artifact.

Compare two sessions:

```bash
devtools-profiler compare \
  --json \
  --method-table \
  --min-live-bytes 1048576 \
  path/to/baseline-session \
  path/to/current-session
```

Use `--profile-id overall` for the whole session. Use the printed region id to
inspect a marked region.

For memory comparisons, use `--memory-class-limit 0` when the agent needs an
unlimited class list. Negative memory thresholds and limits are invalid.
JSON responses include a `cliCommand` field that reproduces the same analysis
selection.

## MCP Server

Use MCP when an AI agent should run or inspect profiles directly:

```bash
devtools-profiler mcp
```

Tell the agent to prefer JSON output and to request call trees, bottom-up
trees, method tables, and memory summaries when diagnosing performance. Those
views give enough context to explain both where time is spent and how callers
reach the hot method.

Useful MCP tools:

- Capture: `profile_run`, `profile_attach`.
- Navigate stored runs: `profile_list_sessions`, `profile_latest_session`,
  `profile_get_session`, `profile_list_regions`, `profile_get_region`.
- Explain and drill down: `profile_explain_hotspots`,
  `profile_search_methods`, `profile_inspect_method`,
  `profile_inspect_classes`.
- Compare: `profile_compare`, `profile_compare_method`,
  `profile_find_regressions`, `profile_analyze_trends`.

When using session directories, pass `profileId: overall` or a generated
region id. For trend analysis, keep the selected region consistent across
sessions when comparing region-scoped runs.

## Troubleshooting

- If startup times out, increase `--vm-service-timeout`.
- If Flutter rebuilds are too slow, start the app once and use `attach`.
- If no regions appear, confirm the target was launched with `run` mode and
  imports `devtools_region_profiler`.
- If output is dominated by SDK frames, add `--hide-sdk`.
- If output is dominated by profiler transport frames, add
  `--hide-runtime-helpers`.
- If a Dart script has its own flags, use `--` before the target command, for
  example `devtools-profiler run --cwd path/to/app -- dart run bin/main.dart
  --input data.json`.
- If a TUI app does not render, add `--terminal` so the target receives direct
  terminal IO instead of profiler-managed pipes.
- If locations are too compact, add `--full-locations`.
- If an agent needs complete data, set limits to `0`, such as
  `--tree-depth 0`, `--tree-children 0`, `--method-limit 0`,
  `--limit 0`, and `--memory-class-limit 0`.
