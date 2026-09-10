import 'dart:isolate';
import 'dart:math';

import 'package:devtools_region_profiler/devtools_region_profiler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  final scenario = SearchScenario();
  if (kDebugMode) {
    registerMarionetteExtension(
      name: 'profilerDemo.search',
      description: 'Runs seeded searches in a worker and awaits completion.',
      inputSchema: ExtensionInputSchema(
        properties: {
          'seed': ExtensionParam.integer(defaultValue: 42),
          'items': ExtensionParam.integer(defaultValue: 20_000),
          'passes': ExtensionParam.integer(defaultValue: 100),
        },
      ),
      callback: (params) async {
        final seed = int.tryParse(params['seed'] ?? '');
        final items = int.tryParse(params['items'] ?? '');
        final passes = int.tryParse(params['passes'] ?? '');
        if (seed == null ||
            items == null ||
            passes == null ||
            items < 1 ||
            items > 100_000 ||
            passes < 1 ||
            passes > 500) {
          return MarionetteExtensionResult.invalidParams(
            'Expected integer seed, items in 1..100000, passes in 1..500.',
          );
        }
        if (scenario.running) {
          return MarionetteExtensionResult.invalidParams('Scenario is busy.');
        }
        final result = await scenario.run(
          seed: seed,
          items: items,
          passes: passes,
        );
        return MarionetteExtensionResult.success(result);
      },
    );
  }
  runApp(DemoApp(scenario: scenario));
}

/// Runs one bounded, reproducible workload at a time.
final class SearchScenario extends ChangeNotifier {
  bool running = false;
  String status = 'Ready';

  /// Whether this Flutter build received profiler session configuration.
  static const regionsEnabled =
      String.fromEnvironment('DEVTOOLS_PROFILER_DTD_URI') != '' &&
      String.fromEnvironment('DEVTOOLS_PROFILER_SESSION_ID') != '';

  Future<Map<String, Object>> run({
    int seed = 42,
    int items = 20_000,
    int passes = 100,
  }) async {
    if (running) throw StateError('Scenario is busy.');
    if (items < 1 || items > 100_000 || passes < 1 || passes > 500) {
      throw ArgumentError('Workload exceeds demo limits.');
    }
    running = true;
    status = 'Running: seed=$seed, items=$items, passes=$passes';
    notifyListeners();
    // Keep the worker alive until region capture finishes, so it remains
    // available to the VM service's final all-isolate sample request.
    final replies = ReceivePort();
    Isolate? worker;
    ProfileRegionHandle? region;
    try {
      if (regionsEnabled) {
        region = await startProfileRegion(
          'marionette-search',
          attributes: {
            'scenarioVersion': '1',
            'seed': '$seed',
            'items': '$items',
            'passes': '$passes',
          },
          options: const ProfileRegionOptions(
            isolateScope: ProfileIsolateScope.all,
          ),
        );
      }
      worker = await Isolate.spawn(
        searchWorker,
        (replies.sendPort, seed, items, passes),
        debugName: 'marionette-search-worker',
        onError: replies.sendPort,
        errorsAreFatal: true,
      );
      final reply = await replies.first.timeout(const Duration(seconds: 45));
      if (reply is! int) throw StateError('Worker failed: $reply');
      await region?.stop();
      region = null;
      final result = <String, Object>{
        'completed': true,
        'seed': seed,
        'items': items,
        'passes': passes,
        'checksum': reply,
        'regionCaptured': regionsEnabled,
      };
      status =
          'Completed: checksum=$reply, seed=$seed, '
          'items=$items, passes=$passes';
      return result;
    } catch (error) {
      status = 'Failed: $error';
      rethrow;
    } finally {
      try {
        await region?.stop();
      } finally {
        worker?.kill(priority: Isolate.immediate);
        replies.close();
        running = false;
        notifyListeners();
      }
    }
  }
}

/// Keeps its isolate available for region capture after returning the checksum.
void searchWorker((SendPort, int, int, int) request) {
  final (reply, seed, items, passes) = request;
  final keepAlive = ReceivePort();
  keepAlive.listen((_) {});
  reply.send(searchChecksum(seed: seed, items: items, passes: passes));
}

/// Returns a deterministic checksum for a seeded allocation/search workload.
int searchChecksum({
  required int seed,
  required int items,
  required int passes,
}) {
  final random = Random(seed);
  final words = List.generate(
    items,
    (_) => 'entry-${random.nextInt(1_000_000)}',
  );
  var checksum = 0;
  for (var pass = 0; pass < passes; pass++) {
    final query = '${pass % 100}';
    final matches = words.where((word) => word.contains(query)).toList()
      ..sort();
    for (final word in matches) {
      checksum = (checksum + word.length) & 0x7fffffff;
    }
  }
  return checksum;
}

/// Minimal UI for driving the same action manually or through Marionette.
class DemoApp extends StatelessWidget {
  const DemoApp({required this.scenario, super.key});

  final SearchScenario scenario;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Marionette + Profiler')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListenableBuilder(
          listenable: scenario,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                SearchScenario.regionsEnabled
                    ? 'Region capture configured'
                    : 'Standalone: no region capture',
              ),
              const SizedBox(height: 16),
              SelectableText(scenario.status),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: scenario.running
                    ? null
                    : () async {
                        try {
                          await scenario.run();
                        } catch (_) {
                          // The scenario exposes errors in its status.
                        }
                      },
                child: const Text('Run seeded search'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
