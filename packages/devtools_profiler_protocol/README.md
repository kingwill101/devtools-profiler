<!--
Copyright 2026 The Flutter Authors
Use of this source code is governed by a BSD-style license that can be
found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.
-->

# DevTools Profiler Protocol

`devtools_profiler_protocol` contains the small set of shared types used by the
region helper and profiler backend.

Most users should not need this package directly. Import
`devtools_region_profiler` when marking regions in an app, or use
`devtools_profiler_cli` when running the profiler. Use this package directly
only when you are building another integration that needs to share the same
region options and wire values.

For the full workspace guide, see [the profiler README](../../README.md).

## Shared Types

The package exports:

- `ProfileCaptureKind`: capture kinds requested for a region.
- `ProfileIsolateScope`: whether a region captures the current isolate or all
  app isolates.
- `ProfileRegionOptions`: JSON-friendly region options shared between the
  helper and backend.
- `defaultProfileCaptureKinds`: the default region capture kinds.
- `normalizeProfileCaptureKinds`: removes duplicate capture kinds while
  preserving order.
- `normalizeProfileIsolateScopes`: removes duplicate isolate scopes while
  preserving order.

## Capture Kinds

```dart
const options = ProfileRegionOptions(
  captureKinds: [
    ProfileCaptureKind.cpu,
    ProfileCaptureKind.memory,
  ],
);
```

Supported by the current backend:

- `ProfileCaptureKind.cpu`
- `ProfileCaptureKind.memory`

Reserved for the protocol, but not implemented by the current backend:

- `ProfileCaptureKind.timeline`

## Isolate Scope

Capture only the isolate that starts the region:

```dart
const options = ProfileRegionOptions(
  isolateScope: ProfileIsolateScope.current,
);
```

Capture all non-system app isolates:

```dart
const options = ProfileRegionOptions(
  isolateScope: ProfileIsolateScope.all,
);
```

Use all-isolate capture only when the profiled work intentionally crosses
isolate boundaries. Current-isolate capture is easier to interpret for most
regions.

## JSON Round Trip

`ProfileRegionOptions` can be serialized and deserialized:

```dart
const options = ProfileRegionOptions(
  captureKinds: [ProfileCaptureKind.cpu],
  isolateScope: ProfileIsolateScope.current,
  parentRegionId: 'parent-region-id',
);

final json = options.toJson();
final restored = ProfileRegionOptions.fromJson(json);
```

The region helper uses this shape when it notifies the profiler backend through
DTD.

## Defaults

When no options are provided, a region uses:

- `captureKinds`: `cpu` and `memory`
- `isolateScope`: `current`
- `parentRegionId`: inherited by `devtools_region_profiler` when regions are
  nested

Empty capture-kind lists normalize back to the default CPU and memory capture
kinds.

## Package Role

This package intentionally has no dependency on the CLI, backend, DTD, VM
service, Flutter, or web UI packages. It is the shared contract between packages
inside the profiler workspace.
