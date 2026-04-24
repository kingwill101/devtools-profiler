
import 'dart:async';

import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> main() async {
  final retained = <List<int>>[];

  await profileRegion(
    'memory-burn',
    () async {
      for (var index = 0; index < 192; index++) {
        retained.add(List<int>.filled(1024, index));
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    },
    options: const ProfileRegionOptions(
      captureKinds: [ProfileCaptureKind.memory],
    ),
  );

  if (retained.isEmpty) {
    throw StateError('Expected retained allocations for the memory fixture.');
  }
}
