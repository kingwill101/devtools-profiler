
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

/// Runs [body] while marking it as a profiled region.
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
class ProfileRegionHandle {
  ProfileRegionHandle._({
    required this.attributes,
    required this.name,
    required this.regionId,
    required Future<void> Function() stopImpl,
  }) : _stopImpl = stopImpl;

  final Future<void> Function() _stopImpl;
  bool _stopped = false;

  /// Extra attributes attached to the region.
  final Map<String, String> attributes;

  /// The user-visible name of the region.
  final String name;

  /// The unique region identifier generated for the region.
  final String regionId;

  /// Stops the region.
  ///
  /// Calling this more than once is a no-op.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _stopImpl();
  }
}

/// Thrown when a profiling region is used outside a configured session.
class ProfileRegionConfigurationException implements Exception {
  /// Creates a configuration exception with [message].
  const ProfileRegionConfigurationException(this.message);

  /// A human-readable description of the configuration problem.
  final String message;

  @override
  String toString() => 'ProfileRegionConfigurationException: $message';
}

class _ProfilerControlClient {
  _ProfilerControlClient._(this._dtdUri, this._sessionId);

  final Uri _dtdUri;
  final String _sessionId;

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

String _generateRegionId() {
  final random = Random();
  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  final suffix = random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return 'region-$timestamp-$suffix';
}

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

List<String> _currentRegionStack() {
  final stack = Zone.current[_activeRegionStackZoneKey] as List<String>?;
  return stack == null ? const [] : List.unmodifiable(stack);
}

String? _currentRegionId() {
  final stack = _currentRegionStack();
  if (stack.isEmpty) {
    return null;
  }
  return stack.last;
}
