import 'package:devtools_profiler_core/src/capture/runner/cpu_snapshot_cache.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  CpuSamples source(List<int> times) => CpuSamples(
    samplePeriod: 1000,
    functions: [],
    samples: [for (final time in times) CpuSample(timestamp: time, stack: [])],
  );

  test(
    'cache replaces polls and clips exited workers to the region window',
    () {
      final cache = CpuSnapshotCache();
      cache.record('worker', source([5, 10]));
      cache.record('worker', source([5, 10, 20, 30]));
      final result = cache.withMissingIsolates(
        {
          'main': source([15]),
        },
        startTimestampMicros: 10,
        timeExtentMicros: 10,
      );
      expect(result.keys, containsAll(['main', 'worker']));
      expect(result['worker']!.samples!.map((sample) => sample.timestamp), [
        10,
        20,
      ]);
      expect(result['worker']!.sampleCount, 2);
      final live = source([19]);
      expect(
        cache.withMissingIsolates(
          {'worker': live},
          startTimestampMicros: 10,
          timeExtentMicros: 10,
        )['worker'],
        same(live),
      );
      expect(
        cache.withMissingIsolates(
          {},
          startTimestampMicros: 100,
          timeExtentMicros: 10,
        ),
        isEmpty,
      );
    },
  );

  test('cache evicts least recently observed isolates at its capacity', () {
    final cache = CpuSnapshotCache(capacity: 2);
    cache.record('old', source([10]));
    cache.record('live', source([10]));
    cache.record('live', source([20]));
    expect(cache.record('new', source([20])), ['old']);
    expect(
      cache
          .withMissingIsolates(
            {},
            startTimestampMicros: 0,
            timeExtentMicros: 50,
          )
          .keys,
      ['live', 'new'],
    );
  });

  test('cache also bounds retained stack entries', () {
    final cache = CpuSnapshotCache(maxStackEntries: 2);
    final large = CpuSamples(
      samples: [
        CpuSample(timestamp: 10, stack: [0, 1, 2]),
      ],
    );
    expect(cache.record('large', large), ['large']);
    expect(
      cache.withMissingIsolates(
        {},
        startTimestampMicros: 0,
        timeExtentMicros: 20,
      ),
      isEmpty,
    );
  });
}
