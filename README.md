# Dart DevTools Profiler CLI

Profile Dart VM programs from the terminal and get results that are useful to
humans and AI agents without opening the DevTools UI.

This package set is for CLI-first profiling:

- run a Dart or Flutter command under the VM profiler
- capture the whole process even when the target code is not instrumented
- mark named regions inside the target program when you want narrower results
- collect CPU call trees and memory summaries for the whole run and each region
- summarize, explain, compare, and inspect stored profile artifacts
- expose the same workflow through a local stdio MCP server for agents

It intentionally does not use the DevTools Flutter or web UI.

## Fast Start

Install the CLI once:

```bash
dart pub global activate devtools_profiler_cli
devtools-profiler help
```

When testing an unpublished checkout, activate the local CLI package instead:

```bash
dart pub global activate --source path packages/devtools_profiler_cli
devtools-profiler help
```

Run the bundled sample app:

```bash
devtools-profiler run \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd packages/devtools_profiler_core/test/fixtures/profiled_app \
  -- dart run bin/profiled_app.dart
```

Profile your own Dart command:

```bash
devtools-profiler run \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --bottom-up \
  --method-table \
  --cwd /path/to/your/dart/app \
  -- dart run bin/main.dart
```

Everything after `--` is the command being profiled. The first token must be
`dart` or `flutter`.

Profile a Flutter test run:

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
  --duration 15s \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd /path/to/flutter/app \
  -- flutter run -d linux
```

Flutter profiling supports VM-service targets exposed by `flutter run` and
`flutter test`. Flutter release mode, browser/web targets, and AOT builds do not
expose the VM service needed by this profiler.

`--duration` starts after the VM service is available, so Flutter build time is
not counted as profiling time. Flutter commands get a longer default VM-service
startup wait than Dart commands. Use `--vm-service-timeout 5m` if the first
build takes longer.

Attach to an already-running Dart or Flutter app when you want to avoid
rebuilding or relaunching for every profiling window:

```bash
flutter run -d linux -t lib/main_relic_breach.dart --host-vmservice-port=0
```

Copy the VM service URI printed by Flutter, then run:

```bash
devtools-profiler attach \
  --duration 15s \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd /path/to/flutter/app \
  http://127.0.0.1:8181/abcd/
```

Attach mode clears the VM's existing CPU samples, profiles a fixed window from
the existing VM service, and leaves the app running. It captures the
whole-session profile view. Explicit region markers require launch mode because
the target must be started with the profiler's DTD session configuration.

The run writes a session directory under:

```text
.dart_tool/devtools_profiler/sessions/<session-id>/
```

That session contains the whole-run profile plus any explicit regions emitted by
the target program.

Region names such as `checkout` or `startup` are user-visible labels. Region
selectors use generated `regionId` values from the session output. The CLI
prints region ids in summaries, and the MCP server exposes them through
`profile_list_regions`.

## When To Use It

Use this profiler when you want to answer questions like:

- Which methods are taking the most CPU in this Dart script?
- What changed between yesterday's run and today's run?
- Which code path became slower in a marked region such as `startup`,
  `checkout`, `parse-file`, or `render-report`?
- What does the call tree look like below a hot function?
- Which callers lead to this expensive leaf method?
- Did memory usage change across a region?
- Can an AI agent run a script, profile it, and inspect the result without a
  browser?

You do not need to mark regions to get value. If the target program has no
regions, the profiler still captures the full session. If the target program
does mark regions, the session includes both the full view and each region view.

## Mark A Region In Your Code

Add the helper package to the target app:

```bash
dart pub add devtools_region_profiler
```

When testing an unpublished checkout, use a path dependency to the local
`packages/devtools_region_profiler` directory instead.

Wrap the code you want to measure:

```dart
import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> main() async {
  await profileRegion(
    'startup',
    attributes: {'phase': 'bootstrap'},
    () async {
      await loadConfiguration();
      await warmUpCache();
      await startServer();
    },
  );
}
```

A region includes the work done by functions it calls. If `startup` calls
`warmUpCache`, and `warmUpCache` calls `readIndex`, sampled stack frames for all
of those methods can appear in the region's call tree.

Use the manual handle form when the region cannot be expressed as a single
closure:

```dart
import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> handleCheckout() async {
  final region = await startProfileRegion(
    'checkout',
    attributes: {'phase': 'pricing'},
    options: const ProfileRegionOptions(
      isolateScope: ProfileIsolateScope.current,
    ),
  );

  try {
    await validateCart();
    await priceCart();
    await persistOrder();
  } finally {
    await region.stop();
  }
}
```

Regions can be nested:

```dart
await profileRegion('request', () async {
  await profileRegion('load-user', () async {
    await loadUser();
  });

  await profileRegion('render-response', () async {
    await renderResponse();
  });
});
```

Default region behavior:

- CPU and memory are captured.
- Only the current isolate is captured.
- Nested regions inherit the active parent region.
- Calling the helper outside a profiler-launched run throws
  `ProfileRegionConfigurationException`.

Use all-isolate capture for regions that intentionally fan out work:

```dart
await profileRegion(
  'parallel-build',
  options: const ProfileRegionOptions(
    isolateScope: ProfileIsolateScope.all,
  ),
  () async {
    await buildInWorkerIsolates();
  },
);
```

## Read The Output

Human output is designed for terminal scanning. JSON output is designed for
automation and AI agents.

Use human output while exploring:

```bash
devtools-profiler summarize \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  /path/to/session
```

Use JSON output when another tool or agent will consume the result:

```bash
devtools-profiler summarize \
  --json \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --bottom-up \
  --method-table \
  /path/to/session
```

JSON responses include a `cliCommand` field for the command that can reproduce
the same analysis selection.

Important result sections:

- `overallProfile`: the whole run from process start to process exit.
- `regions`: profiles for named regions emitted by the target app.
- `topSelfFrames`: where samples stopped. This is the best first view for
  exclusive CPU cost.
- `topTotalFrames`: methods that appeared in sampled stacks. This is useful for
  finding broad inclusive influence, but totals are not additive.
- `callTree`: top-down view from roots to callees. Use this to see what a region
  or whole session did.
- `bottomUpTree`: leaf-to-caller view. Use this when you know the hot leaf and
  need to find the caller chain that led there.
- `methodTable`: DevTools-style method context with callers and callees.
- `memory`: heap and allocation summary when memory capture was available.
- `classes`: memory class rows from `inspect-classes`.
- `regressions` and `trends`: comparison output for reasoning across sessions.

Filtering options keep the output readable:

```bash
--hide-sdk
--hide-runtime-helpers
--include-package my_app
--exclude-package test
```

Use a full, unfiltered view when you need every frame:

```bash
--frame-limit 0 --tree-depth 0 --tree-children 0 --method-limit 0
```

Use `--full-locations` when exact source paths matter. Leave it off when you
want shorter terminal output.

## Common Workflows

### Profile A Whole Script

```bash
devtools-profiler run \
  --json \
  --duration 15s \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd /path/to/app \
  -- dart run bin/script.dart --input data.json
```

This works even if the script has no region instrumentation.

### Profile A Flutter Test Or App

```bash
devtools-profiler run \
  --json \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --method-table \
  --cwd /path/to/flutter/app \
  -- flutter test test/widget_test.dart
```

For `flutter test`, the profiler enables the VM service automatically. For
`flutter run`, the profiler requests a random host VM-service port. The
`--duration` timer starts only after the backend attaches to that VM service.
If the app takes longer to build or start, pass a larger value such as
`--vm-service-timeout 5m`.

The backend also injects profiler session values through `--dart-define` so
`devtools_region_profiler` can mark regions in Flutter targets that can connect
back to the local DTD server.

Device and mobile runs can still provide whole-session CPU data when Flutter
prints a VM-service URI. Region markers require the app process to reach the
profiler's local DTD URI, which is straightforward for host-side Flutter tests
and desktop runs but may require additional networking for device runs.

### Attach To An Already Running Flutter App

Use attach mode when the app is already running and you want repeated profiling
windows without paying Flutter build/startup cost each time.

Start the app once:

```bash
flutter run -d linux -t lib/main_relic_breach.dart --host-vmservice-port=0
```

For a lower-overhead runtime closer to deployed Flutter behavior, use profile
mode instead of debug mode when your target supports it:

```bash
flutter run --profile -d linux -t lib/main_relic_breach.dart \
  --host-vmservice-port=0
```

Then copy the VM service URI from Flutter's output and attach:

```bash
devtools-profiler attach \
  --json \
  --duration 15s \
  --hide-sdk \
  --hide-runtime-helpers \
  --call-tree \
  --bottom-up \
  --method-table \
  --cwd /path/to/flutter/app \
  http://127.0.0.1:8181/abcd/
```

Repeat the `attach` command for another 15-second window. Each attach clears the
VM's existing CPU sample buffer before collecting the new window. The profiler
does not stop the Flutter app, so this is the preferred workflow for exploratory
profiling of long-running games, desktop apps, servers, and demos.

### Profile Both Whole Session And Regions

Run the app normally through the profiler:

```bash
devtools-profiler run \
  --json \
  --call-tree \
  --bottom-up \
  --method-table \
  --cwd /path/to/app \
  -- dart run bin/server.dart
```

The session contains `overall` plus each emitted region. Commands that analyze a
single profile accept `--profile-id overall` or a generated region id from the
session output.

### Explain The Hottest Code

```bash
devtools-profiler explain \
  --json \
  --profile-id overall \
  /path/to/session
```

Use a generated region id instead of `overall` to explain only that region:

```bash
devtools-profiler explain \
  --json \
  --profile-id <checkout-region-id> \
  /path/to/session
```

`explain` returns prioritized hotspot insights, representative top-down paths,
representative bottom-up paths, and method context for likely problem areas.

### Search And Inspect A Method

Find candidate methods:

```bash
devtools-profiler search-methods \
  --json \
  --query Checkout \
  --sort total \
  /path/to/session
```

Inspect one method:

```bash
devtools-profiler inspect \
  --json \
  --method CheckoutService.priceCart \
  --profile-id <checkout-region-id> \
  /path/to/session
```

Inspection shows self cost, inclusive cost, callers, callees, and representative
paths.

### Inspect Memory Classes

```bash
devtools-profiler inspect-classes \
  --json \
  --class Cart \
  --min-live-bytes 1048576 \
  /path/to/session
```

`inspect-classes` re-reads the stored memory artifact and reports retained class
rows, live instances, and allocation deltas. Use `--limit 0` for an unlimited
class list.

### Compare Two Runs

```bash
devtools-profiler compare \
  --json \
  --method-table \
  /path/to/baseline-session \
  /path/to/current-session
```

Select specific profiles inside session directories:

```bash
--baseline-profile-id overall --current-profile-id overall
```

or compare specific regions by copying their generated ids from each session:

```bash
--baseline-profile-id <baseline-checkout-region-id> \
  --current-profile-id <current-checkout-region-id>
```

### Compare One Method Across Two Runs

```bash
devtools-profiler compare-method \
  --json \
  --method CheckoutService.priceCart \
  --baseline-profile-id <baseline-checkout-region-id> \
  --current-profile-id <current-checkout-region-id> \
  /path/to/baseline-session \
  /path/to/current-session
```

### Analyze Trends Across Many Runs

Pass sessions oldest to newest:

```bash
devtools-profiler trends \
  --json \
  /path/to/session-1 \
  /path/to/session-2 \
  /path/to/session-3
```

Trend output includes per-run points, adjacent comparisons, first-to-last
comparison, recurring regressions, and prioritized overall regressions.

## CLI Reference

Run:

```bash
devtools-profiler <command>
```

Show built-in help:

```bash
devtools-profiler help
```

Commands:

- `run -- <command...>` launches and profiles a Dart or Flutter command.
- `attach <vm-service-uri>` profiles an already-running VM service for a fixed
  `--duration`.
- `summarize <path>` summarizes a session directory or profile artifact.
- `explain <path>` explains likely hotspots in one selected profile.
- `compare <baseline> <current>` compares two profiles or sessions.
- `trends <path>...` analyzes a sequence of profiles or sessions.
- `inspect <path>` inspects one method in one profile.
- `inspect-classes <path>` inspects memory classes in one profile.
- `search-methods <path>` searches methods in one profile.
- `compare-method <baseline> <current>` compares one method across two profiles.
- `mcp` starts the local stdio MCP server.

Common presentation flags:

- `--json` emits structured JSON instead of human output.
- `--call-tree` includes a top-down call tree.
- `--expand` is an alias for `--call-tree`.
- `--bottom-up` includes a bottom-up call tree.
- `--method-table` includes a DevTools-style method table.
- `--hide-sdk` hides Dart and Flutter SDK frames.
- `--hide-runtime-helpers` hides common profiler/runtime helper packages.
- `--include-package <prefix>` keeps only matching package prefixes. May be
  repeated.
- `--exclude-package <prefix>` excludes matching package prefixes. May be
  repeated.
- `--full-locations` shows full file locations instead of shortened labels.
- `--frame-limit <n>` controls self/total rows. `0` means unlimited.
- `--tree-depth <n>` controls call-tree depth. `0` means unlimited.
- `--tree-children <n>` controls children per tree node. `0` means unlimited.
- `--method-limit <n>` controls method rows and relations. `0` means unlimited.
- `--min-live-bytes <n>` filters memory class rows for `compare` and
  `inspect-classes`.
- `--memory-class-limit <n>` controls compared memory class rows for `compare`.
  `0` means unlimited.

`run` options:

- `--cwd <dir>` sets the working directory for the launched process.
- `--artifact-dir <dir>` sets an explicit artifact output directory.
- `--duration <duration>` stops the launched process after profiling for that
  duration. Examples: `15s`, `2m`, `500ms`.
- `--vm-service-timeout <duration>` controls how long to wait for the launched
  process to expose a VM service URI before profiling starts. Examples: `3m`,
  `300s`.
- `--forward-output` forwards child stdout/stderr. Defaults to `true`.

`attach` options:

- `--duration <duration>` is required and controls the attached profiling
  window. Examples: `15s`, `2m`, `500ms`.
- `--cwd <dir>` sets the working directory used for relative artifact display
  and the default `.dart_tool/devtools_profiler` location.
- `--artifact-dir <dir>` sets an explicit artifact output directory.

Path arguments accepted by read/analyze commands:

- a session directory
- a region `summary.json`
- a raw `cpu_profile.json`
- a raw `memory_profile.json` for memory-class inspection

## MCP For AI Agents

Start the server:

```bash
devtools-profiler mcp
```

The MCP server uses local stdio transport. A client configuration usually points
at the same command:

```json
{
  "command": "devtools-profiler",
  "args": ["mcp"]
}
```

Tools by workflow:

- Capture: `profile_run`, `profile_attach`.
- Navigate stored runs: `profile_list_sessions`, `profile_latest_session`,
  `profile_get_session`, `profile_list_regions`, `profile_get_region`.
- Read artifacts: `profile_summarize`, `profile_read_artifact`.
- Explain and drill down: `profile_explain_hotspots`,
  `profile_search_methods`, `profile_inspect_method`,
  `profile_inspect_classes`.
- Compare: `profile_compare`, `profile_compare_method`,
  `profile_find_regressions`, `profile_analyze_trends`.

Useful agent pattern:

1. Call `profile_run` with `includeCallTree`, `includeBottomUpTree`, and
   `includeMethodTable`, or call `profile_attach` with the same presentation
   flags when the target app is already running.
2. Call `profile_explain_hotspots` for `overall`.
3. If regions exist, call `profile_explain_hotspots` for the hottest region.
4. Use `profile_search_methods` and `profile_inspect_method` for named
   functions mentioned by the explanation.
5. Use `profile_inspect_classes` when memory summaries show retained growth.
6. Use `profile_compare` or `profile_find_regressions` after a code change.

Most read-only tools accept either direct paths or stored-session selectors:

- direct path selectors: `path`, `baselinePath`, `currentPath`
- session selectors: `rootDirectory`, `sessionsDirectory`, `sessionId`,
  `sessionPath`

Session ids also support `latest` and `previous`.

For trends, `profile_analyze_trends` accepts explicit `paths`, explicit
`sessionIds`, or a session directory plus `limit`. When `limit` is used, the
server chooses the newest `N` sessions and analyzes them oldest-to-newest.

## Artifact Layout

Each `run` or `attach` creates a session directory:

```text
.dart_tool/devtools_profiler/sessions/<session-id>/
  session.json
  overall/
    summary.json
    cpu_profile.json
    memory_profile.json
  regions/
    <region-id>/
      summary.json
      cpu_profile.json
      memory_profile.json
```

Important files:

- `session.json` contains run metadata, region metadata, warnings, and artifact
  paths.
- `summary.json` contains one profile summary with top frames and optional
  memory summary.
- `cpu_profile.json` contains raw VM CPU samples used to rebuild trees and
  method tables.
- `memory_profile.json` contains memory snapshot and diff data when memory
  capture was available.

## Package Layout

This repository contains:

- [`packages/devtools_profiler_cli`](packages/devtools_profiler_cli/README.md):
  CLI executable and local stdio MCP server.
- [Region profiler](packages/devtools_region_profiler/README.md):
  helper package used by target programs to mark profiling regions.
- [Profiler core](packages/devtools_profiler_core/README.md):
  pure-Dart backend for launch, VM service attachment, DTD coordination, region
  handling, artifacts, comparison, hotspot explanation, and trend analysis.
- [Profiler protocol](packages/devtools_profiler_protocol/README.md):
  shared protocol models used between the helper and backend.

The profiler uses the hosted `devtools_shared` package for shared VM and memory
models. It does not depend on `packages/devtools_app`,
`packages/devtools_app_shared`, or other Flutter/web UI packages.

## Current Limits

- Attach mode captures a fixed whole-session VM-service window from an existing
  process, but explicit region markers normally require launch mode.
- The launched command must start with `dart` or `flutter`.
- `dart compile ...` targets and Flutter release/AOT targets are not supported.
- Flutter support is limited to VM-service targets from `flutter run` and
  `flutter test`; browser/web profiling is not supported.
- CPU and memory capture are implemented. The protocol reserves a `timeline`
  capture kind, but timeline capture is not implemented.
- MCP is local stdio only.

## Development Checks

Run these from `profiler/` when changing the profiler packages:

```bash
dart analyze .
dart test packages/devtools_profiler_core
dart test packages/devtools_profiler_cli
dart test packages/devtools_region_profiler
dart test packages/devtools_profiler_protocol
```
