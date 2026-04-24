import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> main() async {
  await profileRegion('outer-region', () async {
    _burnCpu();
    await profileRegion('inner-region', () async {
      _burnCpu();
    }, attributes: const {'phase': 'inner'});
    _burnCpu();
  }, attributes: const {'phase': 'outer'});
}

void _burnCpu() {
  final stopwatch = Stopwatch()..start();
  var accumulator = 0;
  while (stopwatch.elapsedMilliseconds < 300) {
    accumulator = (accumulator * 17 + stopwatch.elapsedMicroseconds) & 0xFFFFFF;
  }
  if (accumulator == -1) {
    throw StateError('unreachable');
  }
}
