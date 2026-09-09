import 'package:devtools_region_profiler/devtools_region_profiler.dart';
import 'package:test/test.dart';

void main() {
  test('throws a configuration exception outside a profiler session', () async {
    await expectLater(
      startProfileRegion('outside-session'),
      throwsA(isA<ProfileRegionConfigurationException>()),
    );
  });

  test('startProfileRegionSync throws outside a profiler session', () {
    expect(
      () => startProfileRegionSync('outside-session'),
      throwsA(isA<ProfileRegionConfigurationException>()),
    );
  });

  test('profileRegionSync throws outside a profiler session', () {
    expect(
      () => profileRegionSync('outside-session', () => 42),
      throwsA(isA<ProfileRegionConfigurationException>()),
    );
  });

  group('ProfileRegionOptions.extra', () {
    test('defaults to empty map', () {
      const options = ProfileRegionOptions();
      expect(options.extra, isEmpty);
    });

    test('serializes and deserializes extra metadata', () {
      const options = ProfileRegionOptions(
        extra: {'luaFile': 'calls.lua', 'version': 3, 'opt': true},
      );
      final json = options.toJson();
      expect(json['extra'], isA<Map<String, Object?>>());
      final restored = ProfileRegionOptions.fromJson(json);
      expect(restored.extra['luaFile'], 'calls.lua');
      expect(restored.extra['version'], 3);
      expect(restored.extra['opt'], true);
    });

    test('is not included in json when empty', () {
      const options = ProfileRegionOptions();
      final json = options.toJson();
      expect(json.containsKey('extra'), isFalse);
    });

    test('preserved by copyWith', () {
      const options = ProfileRegionOptions(extra: {'luaFile': 'bench.lua'});
      final copied = options.copyWith();
      expect(copied.extra['luaFile'], 'bench.lua');
    });

    test('can be replaced by copyWith', () {
      const options = ProfileRegionOptions(extra: {'luaFile': 'bench.lua'});
      final copied = options.copyWith(extra: {'luaFile': 'math.lua'});
      expect(copied.extra['luaFile'], 'math.lua');
    });
  });
}
