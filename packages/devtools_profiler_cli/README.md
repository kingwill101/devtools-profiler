# DevTools Profiler CLI

`devtools_profiler_cli` is the terminal and MCP front end for the pure-Dart
profiler package set.

Use it when you want to profile a Dart or Flutter VM command without opening
the DevTools UI. It can capture the whole run, capture marked regions emitted
by the target program, print readable terminal output, write JSON for
automation, and serve the same capabilities to AI agents over stdio MCP.

For the full CLI guide, see [the profiler README](../../README.md).

## Install And Run

Install the CLI once:

```bash
dart pub global activate devtools_profiler_cli
devtools-profiler help
```

When testing an unpublished checkout, activate the local package instead:

```bash
dart pub global activate --source path packages/devtools_profiler_cli
devtools-profiler help
```

Profile the bundled fixture app:

```bash
devtools-profiler run \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd packages/devtools_profiler_core/test/fixtures/profiled_app \
  -- dart run bin/profiled_app.dart
```

Profile your own app:

```bash
devtools-profiler run \
  --json \
  --duration 15s \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --bottom-up \
  --method-table \
  --cwd /path/to/app \
  -- dart run bin/main.dart
```

Everything after `--` is the command being profiled. The command must start
with `dart` or `flutter`.

Profile a Flutter test:

```bash
devtools-profiler run \
  --json \
  --duration 15s \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd /path/to/flutter/app \
  -- flutter test test/widget_test.dart
```

Profile a Flutter app run:

```bash
devtools-profiler run \
  --json \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd /path/to/flutter/app \
  -- flutter run -d linux
```

`--duration` starts after the VM service is available. Flutter builds can take
longer than Dart scripts before a VM service URI is printed, so use
`--vm-service-timeout 5m` when profiling a cold build.

Attach to an already-running VM service:

```bash
devtools-profiler attach \
  --json \
  --duration 15s \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd /path/to/flutter/app \
  http://127.0.0.1:8181/abcd/
```

Use attach mode when `flutter run` is already active and you want repeated
profiling windows without rebuilding. Start Flutter with a host VM-service port
when needed:

```bash
flutter run -d linux -t lib/main_relic_breach.dart --host-vmservice-port=0
```

The `attach` command clears the VM's existing CPU samples, captures the
whole-session VM service view for the requested duration, and does not stop the
target process. Explicit region markers normally require `run` mode because the
target must be launched with the profiler's DTD/session configuration.

## What You Get Back

Each `run` or `attach` writes a session directory:

```text
.dart_tool/devtools_profiler/sessions/<session-id>/
```

A session can contain:

- `overall`: the whole process profile.
- `regions`: profiles for marked regions emitted by
  `devtools_region_profiler`.
- CPU summaries: top self frames, top total frames, top-down call trees,
  bottom-up call trees, and method tables.
- Memory summaries when memory capture was available.
- Warnings and artifact paths needed by later commands.

If the target app has no marked regions, the CLI still captures the whole
session.

JSON responses include a `cliCommand` field for the command that can reproduce
the same analysis selection.

## Read Existing Artifacts

Summarize a session:

```bash
devtools-profiler summarize \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  /path/to/session
```

Explain likely hotspots:

```bash
devtools-profiler explain \
  --json \
  --profile-id overall \
  /path/to/session
```

Search for methods:

```bash
devtools-profiler search-methods \
  --json \
  --query Parser \
  --sort total \
  /path/to/session
```

Inspect one method:

```bash
devtools-profiler inspect \
  --json \
  --method Parser.parseFile \
  --profile-id overall \
  /path/to/session
```

Inspect memory classes:

```bash
devtools-profiler inspect-classes \
  --json \
  --class String \
  --min-live-bytes 1048576 \
  /path/to/session
```

Use `--limit 0` for an unlimited class list. The command can read a session
directory, a region `summary.json`, or a raw `memory_profile.json` artifact.

Compare two sessions:

```bash
devtools-profiler compare \
  --json \
  --method-table \
  /path/to/baseline-session \
  /path/to/current-session
```

Analyze a series oldest to newest:

```bash
devtools-profiler trends \
  --json \
  /path/to/session-1 \
  /path/to/session-2 \
  /path/to/session-3
```

## Important Flags

- `--json` emits machine-readable JSON.
- `--call-tree` includes the top-down call tree.
- `--bottom-up` includes the bottom-up caller tree.
- `--method-table` includes DevTools-style caller and callee context.
- `--hide-sdk` hides Dart and Flutter SDK frames.
- `--hide-runtime-helpers` hides profiler transport and runtime helper frames.
- `--include-package <prefix>` keeps only matching package prefixes.
- `--exclude-package <prefix>` removes matching package prefixes.
- `--full-locations` keeps full source locations instead of compact labels.
- `--frame-limit 0`, `--tree-depth 0`, `--tree-children 0`, and
  `--method-limit 0` disable the corresponding output limits.
- `--duration <duration>` stops long-running targets after profiling for that
  duration. Examples: `15s`, `2m`, `500ms`.
- `--vm-service-timeout <duration>` controls startup wait time before the VM
  service is available. Examples: `3m`, `300s`.
- `--min-live-bytes <n>` filters memory class rows for `compare` and
  `inspect-classes`.
- `--memory-class-limit <n>` controls compared memory class rows for `compare`.
  `0` means unlimited.

Commands that operate on one profile use `--profile-id overall` for the
whole-session profile or a generated region id for a marked region. Region names
are labels; region ids are printed in session summaries and exposed by MCP.

## MCP Server

Start the local stdio MCP server:

```bash
devtools-profiler mcp
```

Example client configuration:

```json
{
  "command": "devtools-profiler",
  "args": ["mcp"]
}
```

Agent-facing tools include:

- `profile_run`
- `profile_attach`
- `profile_summarize`
- `profile_read_artifact`
- `profile_list_sessions`
- `profile_latest_session`
- `profile_get_session`
- `profile_list_regions`
- `profile_get_region`
- `profile_explain_hotspots`
- `profile_search_methods`
- `profile_inspect_method`
- `profile_inspect_classes`
- `profile_compare`
- `profile_compare_method`
- `profile_find_regressions`
- `profile_analyze_trends`

## Limits

- Attach mode captures a fixed whole-session VM-service window from an existing
  process, but explicit region markers normally require launch mode.
- Dart and Flutter VM-service commands only.
- Supported Flutter subcommands are `flutter run` and `flutter test`.
- Flutter release mode, browser profiling, AOT profiling, and
  `dart compile ...` targets are not supported.
- Flutter region markers require the target process to reach the profiler's
  local DTD URI. This works for host-side Flutter tests and desktop runs, but
  device runs may need additional networking.
- MCP transport is local stdio.
- If an MCP client does not inherit the Pub global executable path, configure
  the client with the resolved `devtools-profiler` executable path.
