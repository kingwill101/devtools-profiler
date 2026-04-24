
import 'dart:isolate';

import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> main() async {
  final handshakePort = ReceivePort();
  final isolate = await Isolate.spawn(_workerMain, handshakePort.sendPort);
  final workerPort = await handshakePort.first as SendPort;

  try {
    await profileRegion(
      'multi-isolate-burn',
      () async {
        final workerDonePort = ReceivePort();
        workerPort.send(workerDonePort.sendPort);
        _burnCpu(Duration(milliseconds: 500));
        await workerDonePort.first;
      },
      attributes: const {'phase': 'fixture'},
      options: const ProfileRegionOptions(
        isolateScope: ProfileIsolateScope.all,
      ),
    );
  } finally {
    workerPort.send(null);
    isolate.kill(priority: Isolate.immediate);
    handshakePort.close();
  }
}

void _workerMain(SendPort handshakePort) {
  final commandPort = ReceivePort();
  handshakePort.send(commandPort.sendPort);

  commandPort.listen((message) {
    if (message == null) {
      commandPort.close();
      return;
    }
    final replyPort = message as SendPort;
    _burnCpu(Duration(milliseconds: 500));
    replyPort.send(true);
  });
}

void _burnCpu(Duration duration) {
  final stopwatch = Stopwatch()..start();
  var accumulator = 0;
  while (stopwatch.elapsed < duration) {
    accumulator = (accumulator * 33 + stopwatch.elapsedMicroseconds) & 0xFFFFFF;
  }
  if (accumulator == -1) {
    throw StateError('unreachable');
  }
}
