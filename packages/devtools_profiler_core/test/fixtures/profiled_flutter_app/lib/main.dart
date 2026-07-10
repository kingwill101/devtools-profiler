import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/heavy_compute_screen.dart';
import 'screens/animation_screen.dart';
import 'screens/memory_allocation_screen.dart';
import 'screens/list_scroll_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProfilerDemoApp());
}


class ProfilerDemoApp extends StatelessWidget {
  const ProfilerDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Profiler Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/compute': (context) => const HeavyComputeScreen(),
        '/animation': (context) => const AnimationScreen(),
        '/memory': (context) => const MemoryAllocationScreen(),
        '/scroll': (context) => const ListScrollScreen(),
      },
    );
  }
}
