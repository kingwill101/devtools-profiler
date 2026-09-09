# Flutter stress validation

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
