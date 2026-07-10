import 'package:flutter/material.dart';
import 'package:devtools_region_profiler/devtools_region_profiler.dart';

class MemoryAllocationScreen extends StatefulWidget {
  const MemoryAllocationScreen({super.key});

  @override
  State<MemoryAllocationScreen> createState() => _MemoryAllocationScreenState();
}

class _MemoryAllocationScreenState extends State<MemoryAllocationScreen> {
  final List<Object> _retained = [];
  String _status = 'Press a button to allocate';
  bool _running = false;

  Future<void> _allocateMany() async {
    setState(() => _running = true);

    final items = <List<int>>[];

    await profileRegion(
      'bulk-allocations',
      attributes: {'kind': 'memory', 'count': '192'},
      () async {
        for (var index = 0; index < 192; index++) {
          items.add(List<int>.filled(1024, index));
        }
        _retained.addAll(items);
      },
      options: const ProfileRegionOptions(
        captureKinds: [ProfileCaptureKind.memory],
      ),
    );

    if (mounted) {
      setState(() {
        _status = 'Allocated ${items.length} lists (${_retained.length} total)';
        _running = false;
      });
    }
  }

  Future<void> _allocateAndRelease() async {
    setState(() => _running = true);

    await profileRegion(
      'allocate-and-release',
      attributes: {'kind': 'memory', 'pattern': 'allocate-release'},
      () async {
        // Allocate many temporary objects
        for (var cycle = 0; cycle < 10; cycle++) {
          final temp = <String>[];
          for (var i = 0; i < 1000; i++) {
            temp.add('item-${i.toString().padLeft(8, '0')}');
          }
          // Sort to trigger additional operations
          temp.sort((a, b) => b.compareTo(a));
          // Let temp fall out of scope
        }
      },
      options: const ProfileRegionOptions(
        captureKinds: [ProfileCaptureKind.memory],
      ),
    );

    if (mounted) {
      setState(() {
        _status = 'Allocation and release cycle completed';
        _running = false;
      });
    }
  }

  void _releaseAll() {
    _retained.clear();
    setState(() {
      _status = 'Released all retained objects';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory Allocation')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Test memory allocation patterns.\n'
                'Use memory-snapshot to observe heap changes.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_running) const CircularProgressIndicator(),
              if (!_running) ...[
                FilledButton.icon(
                  onPressed: _allocateMany,
                  icon: const Icon(Icons.add_circle),
                  label: const Text('Allocate & Retain'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _allocateAndRelease,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Allocate & Release'),
                ),
                if (_retained.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _releaseAll,
                    icon: const Icon(Icons.clear_all),
                    label: Text('Release All (${_retained.length} items)'),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Text(_status, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
