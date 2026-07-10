import 'package:flutter/material.dart';
import 'package:devtools_region_profiler/devtools_region_profiler.dart';

class AnimationScreen extends StatefulWidget {
  const AnimationScreen({super.key});

  @override
  State<AnimationScreen> createState() => _AnimationScreenState();
}

class _AnimationScreenState extends State<AnimationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;
  late final Animation<double> _scale;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _rotation = Tween<double>(
      begin: 0,
      end: 2 * 3.14159,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _scale = Tween<double>(
      begin: 0.5,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startAnimation() {
    setState(() => _running = true);
    profileRegion(
      'pulsing-animation',
      attributes: {'kind': 'animation'},
      () async {
        _controller.repeat(reverse: true);
        // Let the animation run for 10 seconds
        await Future<void>.delayed(const Duration(seconds: 10));
        _controller.stop();
        _controller.reset();
      },
    ).then((_) {
      if (mounted) setState(() => _running = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Animation')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Animated widget that triggers frame rebuilds.\n'
              'Profile frame timing while this runs.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scale.value,
                  child: Transform.rotate(
                    angle: _rotation.value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.indigo.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'Pulse',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            if (!_running)
              FilledButton.icon(
                onPressed: _startAnimation,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start 10s Animation'),
              ),
            if (_running)
              const Text(
                'Animating... profile frame timing now.',
                style: TextStyle(color: Colors.green),
              ),
          ],
        ),
      ),
    );
  }
}
