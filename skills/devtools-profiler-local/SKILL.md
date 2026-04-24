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

- Dart script: use `run` with `dart run ...`.
- Flutter app or test: use `run` with `flutter run` or `flutter test`.
- Already-running VM service: use `attach`.
- Application code can be edited: offer region markers.
- Agent automation: offer the stdio MCP server.

Prefer one working command over a broad explanation. Once the first capture
works, help the user add filters, regions, method inspection, or comparisons.

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

Use this shape for a first Dart capture:

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

Everything after `--` is the target command. Keep `--cwd` pointed at the
target package or app directory.

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

Compare two sessions:

```bash
devtools-profiler compare \
  --json \
  --method-table \
  path/to/baseline-session \
  path/to/current-session
```

Use `--profile-id overall` for the whole session. Use the printed region id to
inspect a marked region.

## MCP Server

Use MCP when an AI agent should run or inspect profiles directly:

```bash
devtools-profiler mcp
```

Tell the agent to prefer JSON output and to request call trees, bottom-up
trees, method tables, and memory summaries when diagnosing performance. Those
views give enough context to explain both where time is spent and how callers
reach the hot method.

## Troubleshooting

- If startup times out, increase `--vm-service-timeout`.
- If Flutter rebuilds are too slow, start the app once and use `attach`.
- If no regions appear, confirm the target was launched with `run` mode and
  imports `devtools_region_profiler`.
- If output is dominated by SDK frames, add `--hide-sdk`.
- If output is dominated by profiler transport frames, add
  `--hide-runtime-helpers`.
- If locations are too compact, add `--full-locations`.
- If an agent needs complete data, set limits to `0`, such as
  `--tree-depth 0`, `--tree-children 0`, and `--method-limit 0`.
