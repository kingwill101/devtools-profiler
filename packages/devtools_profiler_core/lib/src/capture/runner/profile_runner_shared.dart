import 'dart:math';

import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';

/// Environment variable carrying the tooling-daemon URI to the target process.
const profilerDtdUriEnvVar = 'DEVTOOLS_PROFILER_DTD_URI';

/// Environment variable carrying the active profiler session identifier.
const profilerSessionIdEnvVar = 'DEVTOOLS_PROFILER_SESSION_ID';

/// Environment variable carrying the profiler protocol version.
const profilerProtocolVersionEnvVar = 'DEVTOOLS_PROFILER_PROTOCOL_VERSION';

/// DTD service name used for profiler control requests.
const profilerControlService = 'DevToolsProfiler';

/// DTD stream name used for profiler region events.
const regionEventStream = 'DevToolsProfilerRegion';

/// DTD method name for querying session capabilities.
const getSessionInfoMethod = 'getSessionInfo';

/// DTD method name for liveness checks.
const pingMethod = 'ping';

/// DTD method name for opening a profile region.
const startRegionMethod = 'startRegion';

/// DTD method name for closing a profile region.
const stopRegionMethod = 'stopRegion';

/// Region event kind emitted when a region starts.
const regionStartEventKind = 'region.start';

/// Region event kind emitted when a region stops.
const regionStopEventKind = 'region.stop';

/// Region event kind emitted when a region fails.
const regionErrorEventKind = 'region.error';

/// Largest integer that can round-trip safely through JavaScript numbers.
const maxSafeJsInt = 0x1FFFFFFFFFFFFF;

/// Capture kinds implemented by this backend.
const supportedCaptureKinds = defaultProfileCaptureKinds;

/// Isolate scopes implemented by this backend.
const supportedIsolateScopes = <ProfileIsolateScope>[
  ProfileIsolateScope.current,
  ProfileIsolateScope.all,
];

/// Default VM-service startup timeout for Dart commands.
const defaultDartVmServiceTimeout = Duration(seconds: 30);

/// Default VM-service startup timeout for Flutter commands.
const defaultFlutterVmServiceTimeout = Duration(minutes: 3);

/// Formats a timeout or duration for user-facing error messages.
String formatProfileDuration(Duration duration) {
  if (duration.inMilliseconds < Duration.millisecondsPerSecond) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inSeconds < Duration.secondsPerMinute) {
    return '${duration.inSeconds}s';
  }
  if (duration.inMinutes < Duration.minutesPerHour) {
    return '${duration.inMinutes}m';
  }
  return '${duration.inHours}h';
}

/// Generates a compact, time-ordered, collision-resistant profiler session
/// identifier.
///
/// Format: `MMDDHHmmss-XXXXX` — 16 characters. The first 10 digits are the
/// local month, day, hour, minute, and second, so the result is both
/// human-readable (you can see when the session was created at a glance) and
/// sortable by creation time. The last 5 hex characters are a random suffix
/// that prevents collisions when multiple sessions are created in the same
/// second.
///
/// Example identifier: `0709143000-a1b2c`
String generateProfileSessionId() {
  final now = DateTime.now();
  final random = Random();
  final time =
      '${_twoDigits(now.month)}${_twoDigits(now.day)}'
      '${_twoDigits(now.hour)}${_twoDigits(now.minute)}'
      '${_twoDigits(now.second)}';
  final suffix = random.nextInt(0xFFFFF).toRadixString(16).padLeft(5, '0');
  return '$time-$suffix';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// Coerces an unknown JSON-like value into a string map.
Map<String, String> stringMap(Object? value) {
  final raw = value as Map<Object?, Object?>? ?? const {};
  return {
    for (final entry in raw.entries)
      entry.key.toString(): entry.value?.toString() ?? '',
  };
}

/// Clamps [value] to at least `1`.
int nonZeroDuration(int value) => value <= 0 ? 1 : value;

/// Supported top-level command families for profiled launches.
enum ProfileCommandKind { dart, flutter }
