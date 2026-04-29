import 'dart:async';
import 'dart:isolate';

Future<void> main() async {
  final workerReady = ReceivePort();
  await Isolate.spawn(_worker, workerReady.sendPort);
  final workerControlPort = await workerReady.first as SendPort;
  workerReady.close();

  final stopwatch = Stopwatch()..start();
  var state = 1;
  while (stopwatch.elapsed < const Duration(milliseconds: 500)) {
    for (var i = 0; i < 10_000; i++) {
      state = ((state * 1_664_525) + i) & 0x7fff_ffff;
    }
    await Future<void>.delayed(Duration.zero);
  }
  if (state == -1) {
    throw StateError('unreachable');
  }
  workerControlPort.send(null);
}

Future<void> _worker(SendPort readyPort) async {
  final controlPort = ReceivePort();
  var shouldStop = false;
  final controlSubscription = controlPort.listen((_) {
    shouldStop = true;
  });
  readyPort.send(controlPort.sendPort);

  var state = 1;
  while (!shouldStop) {
    for (var i = 0; i < 10_000; i++) {
      state = ((state * 1_664_525) + i) & 0x7fff_ffff;
    }
    await Future<void>.delayed(Duration.zero);
  }
  await controlSubscription.cancel();
  controlPort.close();
  if (state == -1) {
    throw StateError('unreachable');
  }
}
