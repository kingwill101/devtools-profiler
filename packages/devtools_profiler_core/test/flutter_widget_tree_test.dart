import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('WidgetTreeCapture', () {
    test('parses fixture widget tree data', () {
      final fixturePath = path.join(
        _fixtureDirectory().path,
        'data',
        'widget_tree_response.json',
      );
      final json =
          jsonDecode(File(fixturePath).readAsStringSync())
              as Map<String, dynamic>;

      expect(json['name'], 'MyApp');

      final children = json['children'] as List<dynamic>;
      expect(children, hasLength(1));

      final materialApp = children.first as Map<String, dynamic>;
      expect(materialApp['name'], 'MaterialApp');

      final scaffold =
          (materialApp['children'] as List<dynamic>).first
              as Map<String, dynamic>;
      expect(scaffold['name'], 'Scaffold');
    });
  });

  group('WidgetTreeNode', () {
    test('builds recursive tree structure', () {
      final tree = WidgetTreeNode(
        name: 'Root',
        details: 'root widget',
        children: [
          WidgetTreeNode(
            name: 'Child1',
            details: 'first child',
            children: [WidgetTreeNode(name: 'Grandchild', details: 'leaf')],
          ),
          WidgetTreeNode(name: 'Child2', details: 'second child'),
        ],
      );

      expect(tree.name, 'Root');
      expect(tree.children, hasLength(2));
      expect(tree.children.first.children, hasLength(1));
      expect(tree.children.last.children, isEmpty);

      final json = tree.toJson();
      expect(json['name'], 'Root');
      expect((json['children'] as List<dynamic>), hasLength(2));
    });
  });
}

Directory _fixtureDirectory() {
  final candidates = [
    path.join(Directory.current.path, 'test', 'fixtures'),
    path.join(
      Directory.current.path,
      'packages',
      'devtools_profiler_core',
      'test',
      'fixtures',
    ),
  ];

  for (final candidate in candidates) {
    final directory = Directory(candidate);
    if (directory.existsSync()) {
      return directory;
    }
  }

  throw StateError(
    'Could not find fixtures directory. Searched: ${candidates.join(", ")}',
  );
}
