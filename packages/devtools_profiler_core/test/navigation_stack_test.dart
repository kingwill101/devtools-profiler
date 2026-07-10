import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('NavigationStackService', () {
    test(
      'fails with a clear error when the route stack extension is missing',
      () async {
        final vmService = _FakeNavigationVmService(
          isolate: Isolate(id: 'isolate', extensionRPCs: const []),
        );

        await expectLater(
          NavigationStackService(
            vmService: vmService,
          ).getNavigationStack(isolateId: 'isolate'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('ext.flutter.inspector.getRouteStack'),
            ),
          ),
        );
        expect(vmService.extensionCalls, isEmpty);
      },
    );

    test(
      'parses route stack responses when the extension is available',
      () async {
        final vmService = _FakeNavigationVmService(
          isolate: Isolate(
            id: 'isolate',
            extensionRPCs: const ['ext.flutter.inspector.getRouteStack'],
          ),
          responseJson: {
            'result': [
              {
                'name': 'PageRoute<dynamic>',
                'path': '/home',
                'settingsName': 'home',
                'isCurrent': false,
                'isFirst': true,
              },
              {
                'name': 'PageRoute<dynamic>',
                'path': '/details',
                'settingsName': 'details',
                'isCurrent': true,
                'isFirst': false,
              },
            ],
          },
        );

        final stack = await NavigationStackService(
          vmService: vmService,
        ).getNavigationStack(isolateId: 'isolate');

        expect(stack.routes, hasLength(2));
        expect(stack.currentRoute?.path, '/details');
        expect(stack.routes.first.isFirst, isTrue);
        expect(stack.routes.last.isCurrent, isTrue);
        expect(vmService.extensionCalls, hasLength(1));
      },
    );
  });
}

final class _FakeNavigationVmService extends VmService {
  _FakeNavigationVmService({required this.isolate, this.responseJson})
    : super(Stream.empty(), (_) {});

  final Isolate isolate;
  final Map<String, Object?>? responseJson;
  final List<String> extensionCalls = [];

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
    extensionCalls.add(method);
    expect(isolateId, isolate.id);
    expect(method, 'ext.flutter.inspector.getRouteStack');
    final response = Response();
    response.json = responseJson ?? const {'result': []};
    return response;
  }
}
