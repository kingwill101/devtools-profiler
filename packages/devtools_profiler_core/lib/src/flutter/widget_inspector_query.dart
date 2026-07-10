import 'dart:convert';

import 'package:vm_service/vm_service.dart';

/// The result of a Flutter widget inspector service query.
final class WidgetInspectorQueryResult {
  /// Creates a widget inspector query result.
  const WidgetInspectorQueryResult({
    required this.method,
    required this.isolateId,
    required this.result,
  });

  /// The service extension method that was invoked.
  final String method;

  /// The isolate that handled the query.
  final String isolateId;

  /// The decoded response payload.
  final Object? result;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'method': method,
    'isolateId': isolateId,
    'result': result,
  };
}

/// Queries Flutter widget inspector service extensions.
final class WidgetInspectorQueryService {
  /// Creates a widget inspector query service.
  WidgetInspectorQueryService({required VmService vmService})
    : _vmService = vmService;

  final VmService _vmService;

  /// Calls a Flutter widget inspector service extension.
  Future<WidgetInspectorQueryResult> query({
    required String isolateId,
    required String method,
    Map<String, Object?> args = const {},
  }) async {
    final isolate = await _vmService.getIsolate(isolateId);
    if (!(isolate.extensionRPCs?.contains(method) ?? false)) {
      throw StateError('This Flutter runtime does not expose $method.');
    }

    final response = await _vmService.callServiceExtension(
      method,
      isolateId: isolateId,
      args: args.isEmpty ? null : args.cast<String, dynamic>(),
    );

    final raw = response.json?['result'] ?? response.json;
    return WidgetInspectorQueryResult(
      method: method,
      isolateId: isolateId,
      result: _decodeResult(raw),
    );
  }

  Object? _decodeResult(Object? raw) {
    if (raw is! String) {
      return raw;
    }

    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }
}
