import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';
import 'package:dtd/dtd.dart';

const _profilerDtdUriEnvVar = 'DEVTOOLS_PROFILER_DTD_URI';
const _profilerSessionIdEnvVar = 'DEVTOOLS_PROFILER_SESSION_ID';
const _profilerDtdUriDefine = String.fromEnvironment(_profilerDtdUriEnvVar);
const _profilerSessionIdDefine = String.fromEnvironment(
  _profilerSessionIdEnvVar,
);

const _profilerControlService = 'DevToolsProfiler';
const _getSessionInfoMethod = 'getSessionInfo';
const _startRegionMethod = 'startRegion';
const _stopRegionMethod = 'stopRegion';
final _activeRegionStackZoneKey = Object();

/// Runs [body] while reporting a named profiling region.
///
/// This starts a region before [body] runs and always attempts to stop that
/// region before this future completes. If [body] throws, this method still
/// stops the region and then rethrows the original error.
///
/// Nested calls inherit the current region as
/// [ProfileRegionOptions.parentRegionId] when [options] does not provide an
/// explicit parent. Use [attributes] for stable, low-cardinality metadata that
/// helps distinguish similar regions across runs.
///
/// Throws a [ProfileRegionConfigurationException] when this process was not
/// started by the profiler CLI in a session that can receive region events.
Future<T> profileRegion<T>(
  String name,
  Future<T> Function() body, {
  Map<String, String> attributes = const {},
  ProfileRegionOptions options = const ProfileRegionOptions(),
}) async {
  final inheritedOptions = options.parentRegionId == null
      ? options.copyWith(parentRegionId: _currentRegionId())
      : options;
  final handle = await startProfileRegion(
    name,
    attributes: attributes,
    options: inheritedOptions,
  );
  final regionStack = [..._currentRegionStack(), handle.regionId];

  return runZoned(
    () async {
      Object? pendingError;
      StackTrace? pendingStackTrace;
      T? result;

      try {
        result = await body();
      } catch (error, stackTrace) {
        pendingError = error;
        pendingStackTrace = stackTrace;
      }

      try {
        await handle.stop();
      } catch (error, stackTrace) {
        if (pendingError == null) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      }

      if (pendingError != null) {
        Error.throwWithStackTrace(pendingError, pendingStackTrace!);
      }

      return result as T;
    },
    zoneValues: {_activeRegionStackZoneKey: regionStack},
  );
}

/// Starts a profiling region and returns a handle that can stop it later.
///
/// Use this when the measured work spans multiple control-flow paths or cannot
/// be wrapped in one closure. Always stop the returned [ProfileRegionHandle] in
/// a `finally` block so the region closes even when the measured work fails.
///
/// When [ProfileRegionOptions.parentRegionId] is omitted, this method inherits
/// the current active region from the surrounding [Zone]. This keeps nested
/// manual regions attached to the correct parent by default.
///
/// Throws a [ProfileRegionConfigurationException] when the current process is
/// not connected to a matching profiler session.
Future<ProfileRegionHandle> startProfileRegion(
  String name, {
  Map<String, String> attributes = const {},
  ProfileRegionOptions options = const ProfileRegionOptions(),
}) async {
  final controlClient = _ProfilerControlClient.fromEnvironment();
  final inheritedOptions = options.parentRegionId == null
      ? options.copyWith(parentRegionId: _currentRegionId())
      : options;
  return controlClient.startRegion(
    name: name,
    attributes: attributes,
    options: inheritedOptions,
  );
}

/// A handle for an in-flight profiling region.
///
/// Instances are returned by [startProfileRegion] and represent one active
/// region in the profiler backend. Call [stop] exactly once when the measured
/// work finishes. Repeated calls are ignored so cleanup code can safely call
/// [stop] defensively.
class ProfileRegionHandle {
  ProfileRegionHandle._({
    required this.attributes,
    required this.name,
    required this.regionId,
    required Future<void> Function() stopImpl,
  }) : _stopImpl = stopImpl;

  final Future<void> Function() _stopImpl;
  bool _stopped = false;

  /// Extra attributes attached to this region.
  final Map<String, String> attributes;

  /// The user-visible name of this region.
  final String name;

  /// The profiler-generated identifier for this region.
  ///
  /// This identifier is stable for the lifetime of this region and can be used
  /// by CLI or MCP tooling that needs to select one specific region later.
  final String regionId;

  /// Stops this region.
  ///
  /// Calling this more than once is a no-op.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _stopImpl();
  }
}

/// A configuration failure for region profiling.
///
/// Region helpers throw this exception when the current process does not have
/// the profiler session values needed to talk to the backend, or when those
/// values do not match the active profiler session.
class ProfileRegionConfigurationException implements Exception {
  /// Creates a configuration exception with [message].
  const ProfileRegionConfigurationException(this.message);

  /// A human-readable description of the configuration problem.
  final String message;

  @override
  String toString() => 'ProfileRegionConfigurationException: $message';
}

/// Connects region helpers to the profiler control service for one session.
class _ProfilerControlClient {
  _ProfilerControlClient._(this._dtdUri, this._sessionId);

  final Uri _dtdUri;
  final String _sessionId;

  /// Creates a control client from profiler-provided environment values.
  ///
  /// The CLI injects these values through process environment variables for
  /// Dart targets and through compile-time defines for Flutter targets.
  factory _ProfilerControlClient.fromEnvironment() {
    final envDtdUri = _environmentValue(_profilerDtdUriEnvVar);
    final sessionId = _environmentValue(_profilerSessionIdEnvVar);
    if (envDtdUri == null ||
        envDtdUri.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      throw const ProfileRegionConfigurationException(
        'Profiling regions require a session launched by devtools-profiler.',
      );
    }

    return _ProfilerControlClient._(Uri.parse(envDtdUri), sessionId);
  }

  /// Starts a backend region and returns the local handle for it.
  Future<ProfileRegionHandle> startRegion({
    required String name,
    required Map<String, String> attributes,
    required ProfileRegionOptions options,
  }) async {
    final isolateId = developer.Service.getIsolateId(Isolate.current);
    if (isolateId == null) {
      throw const ProfileRegionConfigurationException(
        'The current Dart runtime does not expose a service protocol isolate ID.',
      );
    }

    final regionId = _generateRegionId();
    await _withValidatedSession((dtd) {
      return dtd.call(
        _profilerControlService,
        _startRegionMethod,
        params: {
          'attributes': attributes,
          'captureKinds': [for (final kind in options.captureKinds) kind.name],
          'isolateId': isolateId,
          'isolateScope': options.isolateScope.name,
          'name': name,
          if (options.parentRegionId != null)
            'parentRegionId': options.parentRegionId,
          'regionId': regionId,
          'sessionId': _sessionId,
          'timestampMicros': developer.Timeline.now,
        },
      );
    });
    return ProfileRegionHandle._(
      attributes: attributes,
      name: name,
      regionId: regionId,
      stopImpl: () async {
        await _withValidatedSession((dtd) {
          return dtd.call(
            _profilerControlService,
            _stopRegionMethod,
            params: {
              'isolateId': isolateId,
              'regionId': regionId,
              'sessionId': _sessionId,
              'timestampMicros': developer.Timeline.now,
            },
          );
        });
      },
    );
  }

  /// Verifies that the configured session still exists on [dtd].
  Future<void> _validateSession(DartToolingDaemon dtd) async {
    final response = await dtd.call(
      _profilerControlService,
      _getSessionInfoMethod,
      params: {'sessionId': _sessionId},
    );
    final returnedSessionId = response.result['sessionId'] as String?;
    if (returnedSessionId != _sessionId) {
      throw const ProfileRegionConfigurationException(
        'The configured profiler session did not match the active backend.',
      );
    }
  }

  /// Connects to the DTD backend, validates the session, and runs [action].
  Future<void> _withValidatedSession(
    Future<Object?> Function(DartToolingDaemon dtd) action,
  ) async {
    final dtd = await DartToolingDaemon.connect(_dtdUri);
    try {
      await _validateSession(dtd);
      await action(dtd);
    } finally {
      await dtd.close();
    }
  }
}

/// Returns a unique identifier for a new region.
String _generateRegionId() {
  final random = Random();
  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  final suffix = random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return 'region-$timestamp-$suffix';
}

/// Returns the configured profiler value for [key], if present.
///
/// Runtime environment variables take precedence over compile-time defines so
/// CLI launchers can override baked values when needed.
String? _environmentValue(String key) {
  final environmentValue = Platform.environment[key];
  if (environmentValue != null && environmentValue.isNotEmpty) {
    return environmentValue;
  }

  return switch (key) {
    _profilerDtdUriEnvVar =>
      _profilerDtdUriDefine.isEmpty ? null : _profilerDtdUriDefine,
    _profilerSessionIdEnvVar =>
      _profilerSessionIdDefine.isEmpty ? null : _profilerSessionIdDefine,
    _ => null,
  };
}

/// The active nested region stack for this [Zone].
List<String> _currentRegionStack() {
  final stack = Zone.current[_activeRegionStackZoneKey] as List<String>?;
  return stack == null ? const [] : List.unmodifiable(stack);
}

/// The current active parent region identifier, if any.
String? _currentRegionId() {
  final stack = _currentRegionStack();
  if (stack.isEmpty) {
    return null;
  }
  return stack.last;
}
