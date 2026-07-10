import 'dart:convert';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('WidgetInspectorQueryService', () {
    test('decodes JSON string responses from inspector extensions', () async {
      final vmService = _FakeWidgetInspectorVmService(
        isolate: Isolate(
          id: 'isolate',
          extensionRPCs: const ['ext.flutter.inspector.getSelectedWidget'],
        ),
        responseJson: jsonEncode({
          'type': 'DiagnosticsNode',
          'description': 'Selected widget',
          'name': 'Text',
        }),
      );

      final result = await WidgetInspectorQueryService(vmService: vmService)
          .query(
            isolateId: 'isolate',
            method: 'ext.flutter.inspector.getSelectedWidget',
            args: const {'groupName': 'inspector', 'objectGroup': 'inspector'},
          );

      expect(result.method, 'ext.flutter.inspector.getSelectedWidget');
      expect(result.isolateId, 'isolate');
      expect(result.result, isA<Map<String, dynamic>>());
      expect(result.result, containsPair('description', 'Selected widget'));
      expect(vmService.calls, hasLength(1));
    });

    test('fails clearly when the inspector extension is unavailable', () async {
      final vmService = _FakeWidgetInspectorVmService(
        isolate: Isolate(id: 'isolate', extensionRPCs: const []),
      );

      await expectLater(
        WidgetInspectorQueryService(vmService: vmService).query(
          isolateId: 'isolate',
          method: 'ext.flutter.inspector.getParentChain',
          args: const {'groupName': 'inspector', 'objectGroup': 'inspector'},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('ext.flutter.inspector.getParentChain'),
          ),
        ),
      );
      expect(vmService.calls, isEmpty);
    });
  });
}

final class _FakeWidgetInspectorVmService extends VmService {
  _FakeWidgetInspectorVmService({required this.isolate, this.responseJson})
    : super(Stream.empty(), (_) {});

  final Isolate isolate;
  final String? responseJson;
  final List<String> calls = [];

  @override
  Future<Isolate> getIsolate(String isolateId) async {
    expect(isolateId, isolate.id);
    return isolate;
  }

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    calls.add(method);
    expect(isolateId, isolate.id);
    final response = Response();
    response.json = {'result': responseJson};
    return response;
  }
}
