import 'dart:io';

import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> main() async {
  final parentPid = int.parse(
    Platform.environment['DEVTOOLS_PROFILER_TEST_PARENT_PID']!,
  );
  await profileRegion(
    'interrupt-ready',
    () async {},
    options: const ProfileRegionOptions(captureKinds: [ProfileCaptureKind.cpu]),
  );
  Process.killPid(parentPid, ProcessSignal.sigint);

  final stopwatch = Stopwatch()..start();
  var state = 1;
  while (stopwatch.elapsed < const Duration(seconds: 30)) {
    for (var i = 0; i < 100_000; i++) {
      state = ((state * 1664525) + i) & 0x7fffffff;
    }
    await Future<void>.delayed(Duration.zero);
  }
  if (state == -1) {
    throw StateError('unreachable');
  }
}
