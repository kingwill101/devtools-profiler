import 'package:devtools_region_profiler/devtools_region_profiler.dart';
import 'package:test/test.dart';

void main() {
  test('throws a configuration exception outside a profiler session', () async {
    await expectLater(
      startProfileRegion('outside-session'),
      throwsA(isA<ProfileRegionConfigurationException>()),
    );
  });
}
