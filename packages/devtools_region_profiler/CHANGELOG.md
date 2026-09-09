# Changelog

## 0.3.0

- Reported synchronous start, stop, and cleanup failures at their own operation,
  without relabeling failed starts as failed stops or masking a stop failure
  with a cleanup failure.
- Required Dart 3.13 or later and refreshed test dependencies. Flutter targets
  using this helper need a Flutter SDK that includes Dart 3.13 or later.

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
