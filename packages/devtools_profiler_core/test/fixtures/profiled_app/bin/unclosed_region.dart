import 'dart:async';

import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> main() async {
  await startProfileRegion(
    'unfinished-region',
    attributes: const {'phase': 'fixture'},
  );
  _burnCpu(const Duration(milliseconds: 400));
}

void _burnCpu(Duration duration) {
  final stopwatch = Stopwatch()..start();
  var state = 1;
  while (stopwatch.elapsed < duration) {
    for (var i = 0; i < 25000; i++) {
      state = ((state * 1103515245) + i) & 0x7fffffff;
    }
  }

  if (state == -1) {
    throw StateError('unreachable');
  }
}
