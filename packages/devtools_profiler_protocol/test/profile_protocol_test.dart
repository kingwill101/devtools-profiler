import 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';
import 'package:test/test.dart';

void main() {
  test(
    'profile region options default to current-isolate cpu and memory capture',
    () {
      const options = ProfileRegionOptions();

      expect(options.captureKinds, [
        ProfileCaptureKind.cpu,
        ProfileCaptureKind.memory,
      ]);
      expect(options.isolateScope, ProfileIsolateScope.current);
      expect(options.capturesCpu, isTrue);
      expect(options.capturesMemory, isTrue);
    },
  );

  test('profile region options deserialize and normalize duplicates', () {
    final options = ProfileRegionOptions.fromJson({
      'captureKinds': ['cpu', 'memory', 'cpu'],
      'isolateScope': 'all',
    });

    expect(options.captureKinds, [
      ProfileCaptureKind.cpu,
      ProfileCaptureKind.memory,
    ]);
    expect(options.isolateScope, ProfileIsolateScope.all);
  });
}
