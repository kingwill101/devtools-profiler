# Flutter stress validation

## Marionette + Profiler Demo

`lib/marionette_demo.dart` is a separate entrypoint showing a custom Marionette
action, seeded worker-isolate work, and region metadata. Existing stress
entrypoints are unchanged.

From this fixture directory, install dependencies:

```bash
flutter pub get
```

From the repository root, launch through the profiler:

```bash
dart run packages/devtools_profiler_cli/bin/devtools_profiler.dart run \
  --duration 3m \
  --vm-service-timeout 5m \
  --call-tree --bottom-up --method-table \
  --artifact-dir "$PWD/.dart_tool/marionette-demo" \
  --cwd packages/devtools_profiler_core/test/fixtures/profiled_flutter_app \
  -- flutter run --debug -d linux -t lib/marionette_demo.dart \
  --host-vmservice-port=0
```

On headless Linux, prefix the entire command with `xvfb-run -a`. Configure
Marionette MCP using the [combined guide][], then connect it to the VM service
of this app. Do not launch a second app or a second profiler.

Ask your agent:

> Discover the custom extensions. Call profiler_demo_search with seed 42,
> items 20000, and passes 100. Wait for completion. Repeat with the same inputs
> and verify both checksums match. Then try items 0 and verify it is rejected.

The original extension name for `call_custom_extension` is
`profilerDemo.search`. Clients with schema-aware discovery expose
`profiler_demo_search`. If your installed Marionette server predates custom
extensions, update it following upstream setup instructions.

The UI also offers **Run seeded search** with those defaults. Both paths execute
the same action. A busy guard rejects overlapping runs; bounded inputs prevent
accidentally requesting unlimited work. The custom action returns completion,
inputs, checksum, and whether a region was captured. These results are not
custom profiler metrics.

Each measured action creates `marionette-search` with string attributes
`scenarioVersion`, `seed`, `items`, and `passes`. The worker stays alive until
the all-isolate region stop completes, then is terminated. Open the saved
session using `devtools-profiler browse` and select matching region IDs.
Repeated region names have separate IDs. For cross-run comparisons, repeat the
launch and compare matching inputs; use a fresh artifact directory per launch.

For Marionette-only use, run this instead:

```bash
flutter run --debug -d linux -t lib/marionette_demo.dart
```

Without the profiler's injected defines the demo runs the same workload but
explicitly skips region calls. Rebuild without old session defines when
switching modes. The screen reports whether region capture is configured;
stale configuration or transport failures remain errors, not silent fallbacks.

Run the demo checks from this fixture directory:

```bash
flutter test test/marionette_demo_check.dart
```

The explicit `_check.dart` filename keeps Flutter-only checks out of the
parent pure-Dart package's recursive `dart test` discovery.

This debug-mode example demonstrates orchestration and attribution, not a
release-performance benchmark. CPU samples are statistical, and an all-isolate
region includes unrelated work in the same interval.

Locally verified on Linux under Xvfb using Flutter 3.47.1 / Dart 3.13.1 and
`marionette_flutter` 0.6.0: Marionette MCP discovered the action, invoked it twice
through `call_custom_extension`, and rejected an invalid item count. Both runs
returned checksum `2152479` for the defaults. Saved regions contained the input
attributes, main/worker isolate IDs, and 2,710 / 1,030 CPU samples respectively.
Sample counts are observations, not test expectations. The whole-session capture
warned that earlier snapshots were retained for exited workers; worker shutdown
after each region makes that expected and does not guarantee lossless capture.

[combined guide]: ../../../../devtools_profiler_cli/MARIONETTE.md

## Stress Workload

This is a real Linux desktop Flutter workload, not a mocked VM service or web
app. `lib/stress_main.dart` renders 240 animated grid cells, allocates and
processes JSON on the main isolate, runs two named persistent CPU workers, and
periodically creates short-lived worker isolates.

Use debug mode for this recipe. Release/AOT and browser targets do not expose
the Dart VM CPU profiler. The profiler packages themselves remain pure Dart.

## Repeated attach and worker exit

From this fixture directory:

```bash
flutter run -d linux --debug -t lib/stress_main.dart
```

On a headless Linux host with Xvfb installed, prefix that command with
`xvfb-run -a`. Copy the VM service URI from its output. From the repository root:

```bash
dart run packages/devtools_profiler_core/tool/validate_flutter_stress.dart \
  http://127.0.0.1:PORT/TOKEN=/ \
  .dart_tool/flutter-stress-attach
```

The driver uses `ext.profilerFixture.start`, `status`, `retireWorker`, and
`stop` RPCs to:

1. Start the UI/CPU workload.
2. Attach for an eight-second profiling window.
3. Retire a persistent worker four seconds after requesting attachment.
4. Check that samples retain main/worker isolate identities and OS thread ids.
5. Confirm the app is still running with one worker, then stop the workload.
6. Repeat with fresh workers and a fresh profiling session.

Each window writes normal profiler artifacts plus `validation.json`, including
unknown/unsymbolized leaf counts, truncated samples, and the observed
isolate-to-thread sample counts. The timing-based retirement check can fail on
a severely overloaded host if attachment has not captured the worker before it
exits. That is a real observability limit, not a reason to fabricate samples.

## CLI launch and all-isolate region

From the repository root:

```bash
dart run packages/devtools_profiler_cli/bin/devtools_profiler.dart run \
  --json \
  --duration 25s \
  --vm-service-timeout 3m \
  --artifact-dir "$PWD/.dart_tool/flutter-stress-launch" \
  --cwd packages/devtools_profiler_core/test/fixtures/profiled_flutter_app \
  -- flutter run -d linux --debug -t lib/stress_main.dart \
  --dart-define=STRESS_AUTOSTART=true \
  --dart-define=STRESS_DURATION_SECONDS=8
```

This exercises DTD region wiring as well as CPU and memory capture. The workload
requests an all-isolate `flutter-stress` region and stops it before terminating
its workers. The duration limit triggers finalization before process termination;
outstanding region captures can make shutdown take longer than the limit.

Do not reuse an auto-start binary built with another session's baked DTD
configuration for the attach recipe. Rebuild without the defines.

## Observed results

Validated locally with Flutter 3.47.1 / Dart 3.13.1, Linux x64, debug mode and
Impeller under Xvfb:

| Scenario | Result |
| --- | --- |
| Two normal attach windows | 9,429 and 12,178 summarized samples; app stayed alive |
| Unknown leaf samples in those windows | 1 and 0; native addresses without symbols counted separately |
| Two worker-retirement windows | 9,703 and 9,260 summarized samples; exited worker samples retained |
| Final CLI launch | Exit 0; whole session 30,872 samples; marked region 24,509 samples |
| Launch provenance | Both profiles contained 3 sampled isolates and 4 OS thread ids |

In the original first artifact, the old reader reported 5,112 unknown leaf
samples out of 9,921. Only five leaf samples were genuinely unnamed/unknown in
the stored raw data. The rest were mostly names lost while parsing untyped
native/stub/tag function objects.

Removing unreferenced function entries reduced observed CPU artifacts from
about 64 MiB to 8–11 MiB in comparable runs. Workloads and sample counts differ,
so this is not an exact compression benchmark.

## Interpretation limits

- A Dart isolate is **not** an OS thread. The workers were observed migrating
  between threads, and threads were reused by different isolates.
- `profilerIsolateId` is a profiler extension on each stored CPU sample;
  `tid`, VM/user tags, and `truncated` retain their VM meanings. Use the core
  artifact reader or `parseProfileCpuSamples` to preserve the extension.
- Legacy artifacts whose merge already erased `tid` cannot recover it.
  Named native/stub/tag frames can be recovered when their raw names remain.
- Retention replaces cumulative snapshots rather than concatenating polls.
  It is bounded by 64 isolates and two million stack entries. Eviction and
  fallback to an earlier snapshot produce explicit warnings.
- Workers that live entirely between successful polls may still be missed;
  the 180 ms transient workers are intentionally difficult cases. Retained
  snapshots cannot recover the interval after an isolate's final successful poll.
- Truncated stacks and collected Dart functions remain incomplete. Native
  module-plus-offset frames still need symbols for function-level attribution.
- These CPU samples are not a complete OS-thread trace or a raster/GPU profile.
  This validation does not establish cross-isolate memory-diff accuracy when
  workers exit; those cases retain the existing missing-isolate warnings.
