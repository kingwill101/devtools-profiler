/// Shared protocol types for the pure-Dart profiler workspace.
///
/// This library defines the small JSON-friendly contract shared by the app-side
/// region helper and the profiler backend. Most applications should import
/// `package:devtools_region_profiler/devtools_region_profiler.dart` instead of
/// depending on this package directly.
///
/// Use this library when another integration needs to serialize or interpret
/// region options in the same shape as the profiler CLI and backend.
///
/// ```dart
/// const options = ProfileRegionOptions(
///   captureKinds: [ProfileCaptureKind.cpu],
///   isolateScope: ProfileIsolateScope.current,
/// );
///
/// final json = options.toJson();
/// final restored = ProfileRegionOptions.fromJson(json);
/// ```
///
/// [ProfileRegionOptions] is the main entrypoint. It combines requested capture
/// kinds, isolate scope, and optional parent-region linkage.
library;

export 'src/profile_protocol.dart';
