# Changelog

## 0.2.0

- Added `profileRegionSync<T>()` — synchronous overload of `profileRegion` that
  accepts `T Function()` instead of `Future<T> Function()`. DTD start/stop
  events are sent asynchronously (fire-and-forget) so synchronous code is not
  blocked by profiler transport. Timestamps are captured at the call site.
- Added `startProfileRegionSync()` — synchronous variant of `startProfileRegion`
  that returns a `ProfileRegionHandle` immediately.

## 0.1.0

- Initial release of the app-side region profiling helper.
- Added closure-based and manual region APIs for Dart and Flutter targets.
- Added protocol-based capture and isolate-scope options for marked regions.
