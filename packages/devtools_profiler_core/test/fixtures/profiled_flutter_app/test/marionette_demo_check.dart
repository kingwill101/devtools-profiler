import 'package:devtools_profiler_flutter_fixture/marionette_demo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seeded workload produces repeatable nonempty results', () {
    final first = searchChecksum(seed: 42, items: 200, passes: 10);
    expect(first, greaterThan(0));
    expect(searchChecksum(seed: 42, items: 200, passes: 10), first);
  });

  test(
    'standalone scenario completes, rejects overlap, and can repeat',
    () async {
      final scenario = SearchScenario();
      addTearDown(scenario.dispose);
      final first = scenario.run(items: 200, passes: 10);
      expect(scenario.running, isTrue);
      await expectLater(scenario.run(), throwsStateError);
      final result = await first;
      expect(result['regionCaptured'], isFalse);
      expect(scenario.running, isFalse);
      expect(await scenario.run(items: 200, passes: 10), result);
      await expectLater(scenario.run(items: 0), throwsArgumentError);
      expect(scenario.running, isFalse);
    },
  );
}
