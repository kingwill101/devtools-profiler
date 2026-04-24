import 'dart:async';

import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> main() async {
  await profileRegion(
    'cpu-burn',
    attributes: const {'phase': 'fixture'},
    () async {
      _burnCpu(const Duration(milliseconds: 900));
    },
  );
}

void _burnCpu(Duration duration) {
  final stopwatch = Stopwatch()..start();
  var state = 1;
  while (stopwatch.elapsed < duration) {
    for (var i = 0; i < 50000; i++) {
      state = ((state * 1664525) + i) & 0x7fffffff;
    }
  }

  if (state == -1) {
    throw StateError('unreachable');
  }
}
