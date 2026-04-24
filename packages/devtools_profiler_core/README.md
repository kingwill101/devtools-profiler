<!--
Copyright 2026 The Flutter Authors
Use of this source code is governed by a BSD-style license that can be
found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.
-->

# DevTools Profiler Core

`devtools_profiler_core` is the pure-Dart backend used by the profiler CLI and
MCP server. Most users should start with
[the CLI package](../devtools_profiler_cli/README.md). Use this package directly
when you are building another tool that needs to launch Dart programs, collect
profile artifacts, or analyze stored profile data.

For the full workspace guide, see [the profiler README](../../README.md).

## What It Does

The core package can:

- launch a Dart or Flutter VM command with service protocol profiling enabled
- attach to an already-running Dart or Flutter VM service for a fixed profiling
  window
- start and own a Dart Tooling Daemon session for region coordination
- listen for region events emitted by `devtools_region_profiler`
- capture whole-session CPU and memory data
- capture region CPU and memory data
- write reusable JSON artifacts under `.dart_tool/devtools_profiler`
- rebuild top-down and bottom-up call trees from raw VM CPU samples
- build DevTools-style method tables
- explain hotspots
- compare profiles and detect regressions
- inspect, search, and compare individual methods
- analyze trend series across multiple sessions

It does not contain terminal rendering, MCP transport, Flutter UI code, or web UI
code.

## Launch And Profile A Command

```dart
import 'package:devtools_profiler_core/devtools_profiler_core.dart';

Future<void> main() async {
  final runner = ProfileRunner();
  final result = await runner.run(
    const ProfileRunRequest(
      command: ['dart', 'run', 'bin/main.dart'],
      workingDirectory: '/path/to/app',
      forwardOutput: true,
    ),
  );

  print('session: ${result.sessionId}');
  print('artifacts: ${result.artifactDirectory}');
  print('regions: ${result.regions.length}');
}
```

The launched command must start with `dart` or `flutter`. Compile targets,
Flutter release mode, and AOT targets are not supported.

Flutter examples:

```dart
await runner.run(
  const ProfileRunRequest(
    command: ['flutter', 'test', 'test/widget_test.dart'],
    workingDirectory: '/path/to/flutter/app',
  ),
);

await runner.run(
  const ProfileRunRequest(
    command: ['flutter', 'run', '-d', 'linux'],
    runDuration: Duration(seconds: 15),
    vmServiceTimeout: Duration(minutes: 5),
    workingDirectory: '/path/to/flutter/app',
  ),
);
```

For Flutter commands, the backend injects profiler session values through
`--dart-define` and enables the VM service for supported subcommands.
`runDuration` starts after the VM service is attached. `vmServiceTimeout`
controls the startup/build wait before profiling can begin.

## Attach To An Existing VM Service

Attach mode is for tools that already have a Dart VM service URI. This is useful
for long-running Flutter apps where the app should stay open across multiple
profiling windows.

```dart
import 'package:devtools_profiler_core/devtools_profiler_core.dart';

Future<void> main() async {
  final runner = ProfileRunner();
  final result = await runner.attach(
    ProfileAttachRequest(
      vmServiceUri: Uri.parse('http://127.0.0.1:8181/abcd/'),
      duration: const Duration(seconds: 15),
      workingDirectory: '/path/to/flutter/app',
    ),
  );

  print('session: ${result.sessionId}');
  print('overall samples: ${result.overallProfile?.sampleCount}');
}
```

`attach` clears the VM's existing CPU samples, captures the whole-session VM
service profile view for the requested duration, and does not stop the target
process. Explicit region markers normally require `run`, because the target must
be launched with the profiler's DTD URI and session id.

## Read Stored Artifacts

```dart
import 'package:devtools_profiler_core/devtools_profiler_core.dart';

Future<void> main() async {
  final runner = ProfileRunner();

  final summary = await runner.summarizeArtifact('/path/to/session');
  final artifact = await runner.readArtifact('/path/to/session');
  final tree = await runner.readCallTree(
    '/path/to/session/overall/summary.json',
  );

  print(summary.keys);
  print(artifact['sessionId']);
  print(tree.root.children.length);
}
```

Artifact readers accept session directories and JSON files. CPU-specific helpers
such as `readCallTree` accept profile `summary.json` files and raw
`cpu_profile.json` files.

## Main Models

- `ProfileRunRequest`: launch request for a profiled Dart or Flutter command.
- `ProfileAttachRequest`: attach request for an already-running Dart or Flutter
  VM service.
- `ProfileRunResult`: session metadata, exit code, whole-session profile,
  region profiles, warnings, and artifact paths.
- `ProfileRegionResult`: summary for the whole session or one marked region.
- `ProfileFrameSummary`: self and inclusive frame cost.
- `ProfileMemoryResult`: memory and allocation summary.
- `ProfileCallTree` and `ProfileCallTreeNode`: top-down or bottom-up tree data.
- `ProfileMethodTable`: method-centric caller and callee context.
- `ProfileHotspotSummary`: prioritized hotspot explanation.
- `ProfileRegionComparison`: baseline-to-current profile comparison.
- `ProfileTrendSummary`: historical reasoning across multiple runs.

All exported models provide JSON-friendly APIs so CLI and MCP layers can return
structured results without depending on UI code.

## Analysis Helpers

The package exports helpers for common profiler views:

- CPU summaries: top self frames and top total frames.
- Call trees: top-down execution view and bottom-up leaf-to-caller view.
- Method tables: per-method self cost, inclusive cost, callers, and callees.
- Hotspots: ranked explanations with representative call paths.
- Method search and inspection: find a method and inspect its context.
- Method comparison: compare one method across two profiles.
- Profile comparison: compare two sessions or regions.
- Trend analysis: compare ordered sessions and find recurring regressions.

The CLI uses these APIs to present both readable terminal output and JSON output.
Tool authors should prefer these higher-level summaries over parsing raw VM
service payloads directly.

## Relationship To DevTools Packages

This package reuses `packages/devtools_shared` for shared VM and memory models.
It intentionally does not depend on `packages/devtools_app`,
`packages/devtools_app_shared`, Flutter widgets, or web-only libraries.

## Limits

- Attach mode captures a fixed whole-session VM-service window from an existing
  process, but explicit region markers normally require launch mode.
- Dart and Flutter VM-service commands only.
- Supported Flutter subcommands are `flutter run` and `flutter test`.
- Flutter release mode, browser/web targets, and AOT targets are not supported.
- CPU and memory capture are implemented.
- Timeline capture is represented in the shared protocol enum but is not
  implemented by this backend.
- This package is local to the profiler workspace and is not published.
