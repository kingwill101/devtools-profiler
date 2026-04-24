import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> main() async {
  final first = await startProfileRegion(
    'first-region',
    attributes: const {'phase': 'first'},
  );
  final second = await startProfileRegion(
    'second-region',
    attributes: const {'phase': 'second'},
  );

  try {
    _burnCpu();
  } finally {
    await second.stop();
    await first.stop();
  }
}

void _burnCpu() {
  final stopwatch = Stopwatch()..start();
  var accumulator = 0;
  while (stopwatch.elapsedMilliseconds < 400) {
    accumulator = (accumulator * 19 + stopwatch.elapsedMicroseconds) & 0xFFFFFF;
  }
  if (accumulator == -1) {
    throw StateError('unreachable');
  }
}
