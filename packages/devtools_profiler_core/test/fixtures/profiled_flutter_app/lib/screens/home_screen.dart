import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profiler Fixture'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Select a scenario to profile:',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _ScenarioCard(
            icon: Icons.calculate,
            title: 'Heavy Compute',
            subtitle: 'CPU-bound work, nested regions, tight loops',
            route: '/compute',
          ),
          _ScenarioCard(
            icon: Icons.animation,
            title: 'Animation',
            subtitle: 'Widget rebuilds, frame timing, Tween animations',
            route: '/animation',
          ),
          _ScenarioCard(
            icon: Icons.memory,
            title: 'Memory Allocation',
            subtitle: 'List allocations, retained objects, GC pressure',
            route: '/memory',
          ),
          _ScenarioCard(
            icon: Icons.list,
            title: 'List Scrolling',
            subtitle: 'Long list, lazy rendering, paint complexity',
            route: '/scroll',
          ),
        ],
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 36),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, route),
      ),
    );
  }
}
