import 'package:flutter/material.dart';

class ListScrollScreen extends StatelessWidget {
  const ListScrollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = List<String>.generate(1000, (i) => 'Item $i');

    return Scaffold(
      appBar: AppBar(title: const Text('Scroll List')),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.indigo.withValues(alpha: 0.2),
              child: Text(
                '${index % 100}',
                style: const TextStyle(color: Colors.indigo),
              ),
            ),
            title: Text(item),
            subtitle: Text(
              'Description for $item with some extra text to increase '
              'paint complexity and trigger layout passes.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Tapped $item')));
            },
          );
        },
      ),
    );
  }
}
