import 'dart:async';
import 'dart:isolate';

Future<void> main() async {
  final workerDone = ReceivePort();
  await Isolate.spawn(_worker, workerDone.sendPort);
  await workerDone.first;
  workerDone.close();

  final stopwatch = Stopwatch()..start();
  var state = 1;
  while (stopwatch.elapsed < const Duration(milliseconds: 500)) {
    for (var i = 0; i < 10000; i++) {
      state = ((state * 1664525) + i) & 0x7fffffff;
    }
    await Future<void>.delayed(Duration.zero);
  }
  if (state == -1) {
    throw StateError('unreachable');
  }
}

void _worker(SendPort sendPort) {
  sendPort.send(null);
}
