import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';

void main() {
  group('DiscoveredApp', () {
    test('toJson produces expected map', () {
      final app = DiscoveredApp(
        vmServiceUri: 'ws://127.0.0.1:8181/abc/ws',
        projectName: 'my_app',
      );

      final json = app.toJson();
      expect(json['vmServiceUri'], 'ws://127.0.0.1:8181/abc/ws');
      expect(json['projectName'], 'my_app');
    });
  });
}
