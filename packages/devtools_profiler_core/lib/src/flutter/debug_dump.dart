import 'package:vm_service/vm_service.dart';

/// Results from a Flutter debug dump call.
final class DebugDumpResult {
  /// Creates a debug dump result.
  const DebugDumpResult({
    required this.kind,
    required this.content,
  });

  /// The kind of dump (app, render, layer, focus, semantics).
  final String kind;

  /// The dumped text content.
  final String content;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'kind': kind,
    'content': content,
  };
}

/// Calls Flutter debug dump service extensions for diagnostics.
class DebugDumpService {
  /// Creates a debug dump service.
  DebugDumpService({required VmService vmService})
    : _vmService = vmService;

  final VmService _vmService;

  static const _dumpExtensions = {
    'app': 'ext.flutter.debugDumpApp',
    'render': 'ext.flutter.debugDumpRenderTree',
    'layer': 'ext.flutter.debugDumpLayerTree',
    'focus': 'ext.flutter.debugDumpFocusTree',
    'semantics': 'ext.flutter.debugDumpSemanticsTreeInTraversalOrder',
  };

  /// Available dump kinds.
  static List<String> get availableKinds =>
      _dumpExtensions.keys.toList(growable: false);

  /// Calls a debug dump extension and returns the result.
  Future<DebugDumpResult> dump({
    required String isolateId,
    required String kind,
  }) async {
    final extension = _dumpExtensions[kind];
    if (extension == null) {
      throw ArgumentError(
        'Unknown dump kind "$kind". Available: ${availableKinds.join(", ")}',
      );
    }

    final response = await _vmService.callServiceExtension(
      extension,
      isolateId: isolateId,
    );

    final content = response.json?.toString() ?? '(no output)';
    return DebugDumpResult(kind: kind, content: content);
  }
}
