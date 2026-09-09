import 'dart:convert';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:vm_service/vm_service.dart';

/// Compares independent view builds with one shared complete call tree.
///
/// Run from the workspace root:
/// `dart run packages/devtools_profiler_core/benchmark/cpu_views_benchmark.dart`
/// Use `--independent` to measure only the independent-build path.
void main(List<String> arguments) {
  for (final depth in [8, 32]) {
    final samples = CpuSamples(
      samplePeriod: 1000,
      functions: [
        for (var i = 0; i < 128; i++)
          ProfileFunction(
            kind: 'Dart',
            function: FuncRef(id: 'functions/$i', name: 'method$i'),
            resolvedUrl: 'package:benchmark/method$i.dart',
          ),
      ],
      samples: [
        for (var i = 0; i < 20_000; i++)
          CpuSample(
            timestamp: i * 1000,
            stack: [for (var j = 0; j < depth; j++) (i + j) % 128],
          ),
      ],
    );
    for (final shared in [
      false,
      if (!arguments.contains('--independent')) true,
    ]) {
      final times = <int>[];
      var checksum = 0;
      for (var iteration = 0; iteration < 10; iteration++) {
        final stopwatch = Stopwatch()..start();
        final tree = buildCallTree(cpuSamples: samples);
        final bottomUp = shared
            ? buildBottomUpTreeFromCallTree(tree)
            : buildBottomUpTree(cpuSamples: samples);
        final table = shared
            ? buildMethodTableFromCallTree(tree)
            : buildMethodTable(cpuSamples: samples);
        stopwatch.stop();
        // Consume the complete output outside the timed section, not only roots.
        checksum = _checksum(
          jsonEncode([tree.toJson(), bottomUp.toJson(), table.toJson()]),
        );
        if (iteration >= 3) times.add(stopwatch.elapsedMicroseconds);
      }
      times.sort();
      print(
        jsonEncode({
          'mode': shared ? 'shared' : 'independent',
          'samples': samples.samples!.length,
          'depth': depth,
          'medianMicros': times[times.length ~/ 2],
          'checksum': checksum,
        }),
      );
    }
  }
}

int _checksum(String text) {
  var hash = 0x811c9dc5;
  for (final value in text.codeUnits) {
    hash = ((hash ^ value) * 0x01000193) & 0xffffffff;
  }
  return hash;
}
