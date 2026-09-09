import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:devtools_region_profiler/devtools_region_profiler.dart';
import 'package:flutter/material.dart';

/// Desktop workload controlled by buttons or ext.profilerFixture RPCs.
void main() {
  runApp(const MaterialApp(home: StressScreen()));
}

class StressScreen extends StatefulWidget {
  const StressScreen({super.key});

  @override
  State<StressScreen> createState() => _StressScreenState();
}

class _StressScreenState extends State<StressScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  final workers = <Isolate>[];
  final replies = ReceivePort();
  final retained = <List<Object?>>[];
  Timer? timer;
  Timer? stopTimer;
  ProfileRegionHandle? region;
  var running = false;
  var transitioning = false;
  var ticks = 0;
  var workerResults = 0;
  var churnInFlight = false;

  @override
  void initState() {
    super.initState();
    replies.listen((_) => workerResults++);
    for (final action in ['start', 'stop', 'status', 'retireWorker']) {
      registerExtension('ext.profilerFixture.$action', (_, _) async {
        if (action == 'start') await start();
        if (action == 'stop') await stop();
        if (action == 'retireWorker' && workers.isNotEmpty) {
          workers.removeAt(0).kill(priority: Isolate.immediate);
        }
        return ServiceExtensionResponse.result(
          jsonEncode({
            'running': running,
            'ticks': ticks,
            'workers': workers.length,
            'workerResults': workerResults,
            'regionAvailable': region != null,
          }),
        );
      });
    }
    if (const bool.fromEnvironment('STRESS_AUTOSTART')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(start()));
    }
  }

  Future<void> start() async {
    if (running || transitioning) return;
    transitioning = true;
    try {
      for (var i = 0; i < 2; i++) {
        workers.add(
          await Isolate.spawn(
            persistentWorker,
            replies.sendPort,
            debugName: 'stress-worker-$i',
          ),
        );
      }
      try {
        region = await startProfileRegion(
          'flutter-stress',
          options: const ProfileRegionOptions(
            isolateScope: ProfileIsolateScope.all,
          ),
        );
      } on ProfileRegionConfigurationException {
        // Direct launches exercise attach mode, without region wiring.
      }
      running = true;
      animation.repeat();
      const seconds = int.fromEnvironment('STRESS_DURATION_SECONDS');
      if (seconds > 0) {
        stopTimer = Timer(Duration(seconds: seconds), () => unawaited(stop()));
      }
      timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        burnMainIsolate();
        retained.add(
          List<Object?>.from(
            jsonDecode(
              jsonEncode([
                for (var i = 0; i < 500; i++)
                  {'index': i, 'value': 'row-$ticks-$i'},
              ]),
            ) as List,
          ),
        );
        if (retained.length > 12) retained.removeAt(0);
        if (++ticks % 10 == 0 && !churnInFlight) {
          churnInFlight = true;
          unawaited(
            Isolate.run(transientWorker, debugName: 'stress-transient').then((
              _,
            ) {
              workerResults++;
              churnInFlight = false;
            }),
          );
        }
        if (mounted) setState(() {});
      });
      if (mounted) setState(() {});
    } catch (_) {
      for (final worker in workers) {
        worker.kill(priority: Isolate.immediate);
      }
      workers.clear();
      rethrow;
    } finally {
      transitioning = false;
    }
  }

  Future<void> stop() async {
    if (!running || transitioning) return;
    transitioning = true;
    try {
      timer?.cancel();
      stopTimer?.cancel();
      animation.stop();
      running = false;
      await region?.stop();
    } finally {
      region = null;
      for (final worker in workers) {
        worker.kill(priority: Isolate.immediate);
      }
      workers.clear();
      retained.clear();
      if (mounted) setState(() {});
      transitioning = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    stopTimer?.cancel();
    for (final worker in workers) {
      worker.kill(priority: Isolate.immediate);
    }
    replies.close();
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profiler stress validation')),
    body: Column(
      children: [
        Row(
          children: [
            FilledButton(onPressed: start, child: const Text('Start workload')),
            TextButton(onPressed: stop, child: const Text('Stop workload')),
            Text('Ticks $ticks · Worker replies $workerResults'),
          ],
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: animation,
            builder: (_, _) => GridView.builder(
              itemCount: 240,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 12,
              ),
              itemBuilder: (_, index) => Transform.rotate(
                angle: animation.value * math.pi * 2,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  color: Colors.primaries[index % Colors.primaries.length],
                  child: Center(child: Text('$index / $ticks')),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

@pragma('vm:never-inline')
void burnMainIsolate() => burnCpu(const Duration(milliseconds: 12));

@pragma('vm:never-inline')
void transientWorker() => burnCpu(const Duration(milliseconds: 180));

void persistentWorker(SendPort replies) {
  Timer.periodic(const Duration(milliseconds: 80), (_) {
    burnCpu(const Duration(milliseconds: 35));
    replies.send('done');
  });
}

@pragma('vm:never-inline')
void burnCpu(Duration duration) {
  final watch = Stopwatch()..start();
  var value = 7;
  while (watch.elapsed < duration) {
    for (var i = 0; i < 20_000; i++) {
      value = (value * 1_664_525 + i) & 0x7fffffff;
    }
  }
  if (value == -1) throw StateError('unreachable');
}
