# DevTools Profiler CLI

`devtools_profiler_cli` is the terminal and MCP front end for the pure-Dart
profiler package set.

Use it when you want to profile a Dart or Flutter VM command without opening
the DevTools UI. It can capture the whole run, capture marked regions emitted
by the target program, print readable terminal output, write JSON for
automation, and serve the same capabilities to AI agents over stdio MCP.

For the full CLI guide, see [the profiler README](../../README.md).

## Browse And Compare Stored Runs

```bash
devtools-profiler browse --cwd /path/to/project
devtools-profiler compare --hide-sdk --frame-limit 20 baseline middle current
devtools-profiler trends --last 5 --json
```

`browse` is an explicit, read-only terminal UI. Use `/` to search session IDs,
commands, directories, and region names; arrows or `j`/`k` to move; `b` to set
the baseline; and `c` or Enter to set the current profile. Regions are listed
with their run-local IDs, so repeated names are not silently matched.
Press `d` for scrollable comparison details, `e` to exit and print the full
POSIX-shell comparison command, or `q`/Ctrl+C to quit.

The browser reads stored summaries only, not large raw CPU artifacts. It
requires terminal stdin/stdout and does not accept JSON, CSV, or frame filters.
Use its exported command for full filtered analysis. No profile is modified.

Multi-run `compare` rebuilds frame lists from raw CPU data when available,
applies filters, aligns by name/kind/exact location, then limits output rows.
Different checkout paths are not guessed to be equivalent. Missing entries
mean **not listed**, not eliminated; stored summaries may be incomplete.
Terminal output shows kind and location; CSV adds `kind` and `location` columns
and uses blank cells for missing observations. JSON has aligned `rows` with
nullable observations. MCP `profile_compare` accepts `paths` for the same
cross-run CPU alignment; pairwise baseline/current selectors remain supported.

Self percentages describe share of sampled CPU stacks, not elapsed time.
Browser deltas are percentage points. Verify workloads, capture settings,
build mode, and isolate coverage before interpreting a change as a regression.
Repeated-run statistics and live capture controls are not part of this browser.

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
  --cwd /path/to/app \
  bin/main.dart
```

For full Dart or Flutter commands, put profiler options before the target
command. Use `--` when the target command has its own options:

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

Bare Dart files are expanded to `dart run <file>`. Dart launches are held at
isolate exit long enough for final CPU and memory snapshots, so short scripts
can still produce a whole-session profile.

Profile the bundled terminal UI fixture:

```bash
devtools-profiler run \
  --terminal \
  --cwd packages/devtools_profiler_core/test/fixtures/profiled_app \
  -- dart run bin/artisanal_widget_app.dart
```

Use `--terminal` when the target needs direct stdin, raw-mode input, mouse
tracking, or alternate-screen rendering. It cannot be combined with `--json`
because the target writes directly to the terminal. If you press Ctrl+C while
the CLI is running, the profiler writes the diagnostics captured so far before
printing the session summary.

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
whole-session VM service view for a bounded duration, and does not stop the
target process. It defaults to 15s, and attach sessions skip DTD by default
because explicit region markers are unavailable in attach mode.
If exactly one app is running, `attach` can auto-discover its VM service URI.

## Live Flutter Analysis

The CLI includes commands that connect directly to a running Flutter or Dart
application via its VM service URI. Use `discover` to find available URIs on
this machine, then run the live-analysis commands.

Discover running apps:

```bash
devtools-profiler discover
```

This scans OS processes for Flutter/Dart development services and lists their
VM service WebSocket URIs. Pass `--json` for machine-readable output.

All flutter commands below auto-discover the VM service URI when omitted.
Just run them while your app is running and they connect automatically:

```bash
devtools-profiler timeline                  # auto-discovers URI
devtools-profiler flutter:timeline          # compatibility alias
devtools-profiler flutter:screenshot        # same
```

When multiple apps are running, the command lists them and asks you to pick
one by passing the URI explicitly.

Profile frame timing and detect jank:

```bash
devtools-profiler flutter:timeline \
  --duration 5 \
  ws://127.0.0.1:8181/abc123/ws
```

Returns frame timing metrics including total/janky frame counts, average, P90,
P99, and max frame times, plus a breakdown of build, layout, and paint phases.
Auto-detects display refresh rate and shader compilation events.
`flutter:timeline` and `flutter:frame-profile` are available as
compatibility aliases.

Capture a memory snapshot:

```bash
devtools-profiler flutter:memory-snapshot \
  --name before-optimization \
  --save \
  --no-gc \
  ws://127.0.0.1:8181/abc123/ws
```

Returns top allocation classes sorted by current heap size. Omit `--no-gc` to
force garbage collection before the capture. Use `--save` to persist the
snapshot under `.dart_tool/devtools_profiler/sessions` for later comparison.

Capture the widget tree:

```bash
devtools-profiler flutter:widget-tree \
  --depth 15 \
  --summary \
  ws://127.0.0.1:8181/abc123/ws
```

Use `--summary` for a condensed Flutter-only view. Use `--project-only` to
filter framework widgets and show only project code in either tree shape.

Query widget inspector RPCs:

```bash
devtools-profiler flutter:inspector \
  --method getSelectedWidget \
  ws://127.0.0.1:8181/abc123/ws
```

Supported methods include `getSelectedWidget`, `getSelectedSummaryWidget`,
`getParentChain`, `getProperties`, `getChildren`, `getChildrenSummaryTree`,
`getChildrenDetailsSubtree`, `getDetailsSubtree`, and
`getLayoutExplorerNode`.

Capture a screenshot:

```bash
devtools-profiler flutter:screenshot \
  --output app.png --width 1920 \
  ws://127.0.0.1:8181/abc123/ws
```

Uses the Flutter inspector screenshot service extension.

Dump diagnostic information:

```bash
devtools-profiler flutter:debug-dump --kind render \
  ws://127.0.0.1:8181/abc123/ws
```

Available kinds: `app`, `render`, `layer`, `focus`, `semantics`.

Capture log and output streams:

```bash
devtools-profiler flutter:logs \
  --duration 30 --output session.log \
  ws://127.0.0.1:8181/abc123/ws
```

Captures Logging, Stdout, and Stderr streams. Use `--follow` for continuous
streaming until interrupted.

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

List stored profiling sessions:

```bash
devtools-profiler profiles
```

By default this shows a compact listing of session id, modified time, and
command. Use `--extended` for the full table with working directory, exit
code, region count, and warnings. Use `--limit` to control how many sessions
are shown; `--limit 0` shows all stored sessions.

Almost every analysis command below works without a path when at least one
stored session exists — it falls back to the latest session automatically.
Use `--session-id latest`, `--session-id previous`, or `--session-id <id>`
to pick a different stored session explicitly.

Positional arguments accept session ids in addition to file paths, so you can
pass a session id directly instead of its on-disk path:

```bash
devtools-profiler summarize 0712060003-8c410
devtools-profiler compare 0712060003-8c410 0711235455-ebfb3
devtools-profiler trends session-a session-b session-c
devtools-profiler inspect --method Parser.parseFile 0712060003-8c410
devtools-profiler inspect-classes --class String 0712060003-8c410
```

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

# Or use the N most recent stored sessions:
devtools-profiler trends --last 5
```

Check for regressions against a known-good baseline (useful in CI):

```bash
devtools-profiler regress path/to/baseline-session
devtools-profiler regress 0712060003-8c410 0711235455-ebfb3
```

Exits with code 1 when regressions are found. Use `--warn-only` to exit 0.

Compare three or more sessions with an aligned hotspot table:

```bash
devtools-profiler compare session-a session-b session-c
devtools-profiler compare --csv session-a session-b session-c
```

## Important Flags

- `--json` emits machine-readable JSON.
- `run --json` sends forwarded target stdout and stderr to the profiler's
  stderr, keeping stdout parseable. `--no-forward-output` suppresses target logs.
- `--csv` outputs compact CSV tables instead of formatted terminal output.
- `--call-tree` includes the top-down call tree.
- `--bottom-up` includes the bottom-up caller tree.
- `--method-table` includes DevTools-style caller and callee context.
- `--hide-sdk` hides Dart and Flutter SDK frames.
- `--hide-runtime-helpers` hides profiler transport and runtime helper frames.
- `--collapse-async` categorizes `dart:async` frames by type (normal
  completions, error completions, listener dispatch, microtask scheduling,
  zone overhead) and attributes async cost to the calling function when
  raw CPU samples are available (e.g. `async (await _executeFrame)`).
- `--include-package <prefix>` keeps only matching package prefixes.
- `--exclude-package <prefix>` removes matching package prefixes.
- `--full-locations` keeps full source locations instead of compact labels.
- `--frame-limit 0`, `--tree-depth 0`, `--tree-children 0`, and
  `--method-limit 0` disable the corresponding output limits.
- `--duration <duration>` stops long-running targets after profiling for that
  duration. Examples: `15s`, `2m`, `500ms`.
- `--warm-up <duration>` waits this long after VM service connection before
  starting the profiling timer. Useful for Flutter apps to skip startup and
  first-frame rendering. Examples: `5s`, `30s`.
- `--flutter` sets `--warm-up 3s`, `--hide-sdk`, and `--hide-runtime-helpers`
  together as Flutter-friendly defaults.
- `--vm-service-timeout <duration>` controls startup wait time before the VM
  service is available. Examples: `3m`, `300s`.
- `--terminal` gives the launched process direct terminal access for TUI and
  alternate-screen apps. It cannot be combined with `--json`.
- `--min-live-bytes <n>` filters memory class rows for `compare` and
  `inspect-classes`.
- `--memory-class-limit <n>` controls compared memory class rows for `compare`.
  `0` means unlimited.
- `--last <n>` on `trends` uses the `n` most recent stored sessions.
  Example: `devtools-profiler trends --last 5`.

Commands that operate on one profile use `--profile-id overall` for the
whole-session profile or a generated region id for a marked region. Region names
are labels; region ids are printed in session summaries and exposed by MCP.

Use `--session-id latest`, `--session-id previous`, or `--session-id <id>`
instead of a path to reference stored sessions directly. The `profiles` command
lists available session ids.

The `profiles` command accepts `--extended`, `--limit`, and `--json`:

```bash
devtools-profiler profiles               # compact list (default limit 12)
devtools-profiler profiles --extended     # full table
devtools-profiler profiles --limit 0      # all stored sessions
devtools-profiler profiles --json         # machine-readable output
```

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
- `profile_discover_apps`
- `profile_frame_profile`
- `timeline`
- `profile_memory_snapshot`
- `profile_widget_tree`
- `profile_widget_inspector_query`
- `profile_screenshot`
- `profile_debug_dump`
- `profile_stream_logs`
- `profile_compare`
- `profile_compare_method`
- `profile_find_regressions`
- `profile_analyze_trends`

## Limits

- Attach mode captures a fixed whole-session VM-service window from an existing
  process, but explicit region markers normally require launch mode.
- Dart and Flutter VM-service commands only.
- Supported Flutter subcommands are `flutter run`, `flutter attach`,
  `flutter drive`, and `flutter test`.
- Flutter release mode, AOT profiling, and `dart compile ...` targets are
  not supported.
- Flutter region markers require the target process to reach the profiler's
  local DTD URI. This works for host-side Flutter tests and desktop runs, but
  device runs may need additional networking.
- MCP transport is local stdio.
- If an MCP client does not inherit the Pub global executable path, configure
  the client with the resolved `devtools-profiler` executable path.
