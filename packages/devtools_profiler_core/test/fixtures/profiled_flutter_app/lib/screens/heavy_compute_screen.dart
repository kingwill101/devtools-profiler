import 'package:flutter/material.dart';
import 'package:devtools_region_profiler/devtools_region_profiler.dart';

class HeavyComputeScreen extends StatefulWidget {
  const HeavyComputeScreen({super.key});

  @override
  State<HeavyComputeScreen> createState() => _HeavyComputeScreenState();
}

class _HeavyComputeScreenState extends State<HeavyComputeScreen> {
  String _result = 'Press the button to start';
  bool _running = false;

  Future<void> _runHeavyComputation() async {
    setState(() => _running = true);

    await profileRegion(
      'heavy-compute',
      attributes: {'kind': 'cpu-burn'},
      () async {
        // Nested inner region — matrix multiplication simulation
        await profileRegion(
          'matrix-multiply',
          attributes: {'size': '200x200'},
          () async {
            _burnCpu(const Duration(milliseconds: 500));
          },
        );

        // Prime number search
        await profileRegion(
          'prime-search',
          attributes: {'limit': '50000'},
          () async {
            _findPrimes(50000);
          },
        );

        // JSON-like string processing
        await profileRegion(
          'string-processing',
          attributes: {'kind': 'concatenation'},
          () async {
            _processStrings();
          },
        );
      },
    );

    if (mounted) {
      setState(() {
        _result = 'Computation completed';
        _running = false;
      });
    }
  }

  void _burnCpu(Duration duration) {
    final stopwatch = Stopwatch()..start();
    var state = 1;
    while (stopwatch.elapsed < duration) {
      for (var i = 0; i < 50000; i++) {
        state = ((state * 1664525) + i) & 0x7fffffff;
      }
    }
    if (state == -1) throw StateError('unreachable');
  }

  List<int> _findPrimes(int limit) {
    final sieve = List<bool>.filled(limit + 1, true);
    sieve[0] = false;
    sieve[1] = false;
    for (var i = 2; i * i <= limit; i++) {
      if (sieve[i]) {
        for (var j = i * i; j <= limit; j += i) {
          sieve[j] = false;
        }
      }
    }
    final primes = <int>[];
    for (var i = 2; i <= limit; i++) {
      if (sieve[i]) primes.add(i);
    }
    return primes;
  }

  void _processStrings() {
    var buffer = StringBuffer();
    for (var i = 0; i < 10000; i++) {
      buffer.write('item-$i');
      if (i % 100 == 0) {
        buffer = StringBuffer(buffer.toString().substring(0, buffer.length));
      }
    }
    // Force retention
    if (buffer.length < 100) throw StateError('unreachable');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Heavy Compute')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'This screen runs CPU-intensive operations\n'
                'inside profiler regions.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_running) const CircularProgressIndicator(),
              if (!_running)
                FilledButton.icon(
                  onPressed: _runHeavyComputation,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run Computation'),
                ),
              const SizedBox(height: 16),
              Text(_result, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
