# DevTools Region Profiler

`devtools_region_profiler` is the helper package you add to a Dart program when
you want named profiling windows in the CLI and MCP profiler output.

You do not need this package for whole-session profiling. Use it when the full
run is too broad and you want results for a specific section such as `startup`,
`parse-file`, `checkout`, or `render-report`.

For the full CLI workflow, see [the profiler README](../../README.md).

## Main API Surface

The package exports:

- `profileRegion()`: wraps one async closure and stops the region
  automatically
- `startProfileRegion()`: starts a region manually and returns a stop handle
- `ProfileRegionHandle`: the active region handle returned by manual starts
- `ProfileRegionConfigurationException`: thrown when the process is not running
  inside a compatible profiler session
- protocol types such as `ProfileRegionOptions`, `ProfileCaptureKind`, and
  `ProfileIsolateScope`

Use `profileRegion()` by default. Reach for `startProfileRegion()` only when
the measured work spans multiple branches, callbacks, or lifecycle hooks.

## Add It To A Target App

Add the region helper to the target package:

```bash
dart pub add devtools_region_profiler
```

When testing an unpublished checkout, use a path dependency to the local
`packages/devtools_region_profiler` directory instead.

Run the target app through the globally activated profiler CLI:

```bash
devtools-profiler run \
  --cwd /path/to/app \
  -- dart run bin/main.dart
```

For Flutter targets, run through `flutter test` or `flutter run`:

```bash
devtools-profiler run \
  --cwd /path/to/flutter/app \
  -- flutter test test/widget_test.dart
```

Calling the helper during a normal `dart run` session throws
`ProfileRegionConfigurationException` because there is no profiler backend to
receive the region events.

Attach mode is for whole-session profiling of an already-running VM service.
It normally cannot collect explicit regions because the target process was not
started with the profiler's DTD URI and session id. Use `run` mode when region
markers are required.

The helper reads profiler session values from process environment variables and
from Dart compile-time environment values. The CLI uses environment variables
for Dart commands and `--dart-define` for Flutter commands.

The API reference expands on this behavior, including how nested regions
inherit parent ids, how manual handles should be stopped, and how region
configuration failures are surfaced.

## Mark A Region With A Closure

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

The region includes work done by functions called inside the closure. If
`startup` calls `warmUpCache`, and `warmUpCache` calls `readIndex`, those
methods can appear in the region's top frames and call trees.

## Mark A Region Manually

Use a manual handle when the region cannot be expressed as one closure:

```dart
import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> handleCheckout() async {
  final region = await startProfileRegion(
    'checkout',
    attributes: {'phase': 'pricing'},
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

Always stop manual regions in a `finally` block. Calling `stop()` more than once
is safe.

## Nested Regions

Regions can be nested. The helper records parent-child relationships so the
session can show both the broad parent and narrower child windows:

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

Nested regions inherit the active parent automatically unless you pass an
explicit `parentRegionId`.

## Capture Options

Default options:

- capture kinds: CPU and memory
- isolate scope: current isolate
- parent region: inherited from the active zone when nested

Capture all app isolates when the region intentionally fans out work:

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

Capture only CPU when memory data is not needed:

```dart
await profileRegion(
  'hot-loop',
  options: const ProfileRegionOptions(
    captureKinds: [ProfileCaptureKind.cpu],
  ),
  () async {
    burnCpu();
  },
);
```

The protocol reserves `ProfileCaptureKind.timeline`, but the current backend
does not implement timeline capture.

## Names, IDs, And Attributes

The `name` is the human label you choose, such as `checkout`. The backend also
stores a generated `regionId`; CLI and MCP selectors use that generated id when
you ask for one specific region later.

Use `attributes` for compact context that helps humans and agents compare
regions:

```dart
attributes: {
  'phase': 'pricing',
  'mode': 'batch',
}
```

Prefer stable names and low-cardinality attributes. Avoid embedding request ids,
timestamps, or large values unless you specifically need one-off diagnostics.

## Practical Guidance

- Start with a few broad regions, then add narrower child regions around
  suspicious work.
- Keep region names stable across runs so comparisons and trend analysis are
  easier to interpret.
- Use all-isolate capture only when the measured work actually crosses isolate
  boundaries.
- Keep normal app behavior unchanged. Region helpers should wrap work, not
  change control flow.
- For Flutter device runs, ensure the app process can reach the profiler's local
  DTD URI before relying on region markers. Host-side widget tests and desktop
  runs are the simplest Flutter targets for region profiling.
