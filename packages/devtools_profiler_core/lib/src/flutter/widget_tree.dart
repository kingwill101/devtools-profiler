import 'dart:async';

import 'package:vm_service/vm_service.dart';

/// A node in the captured Flutter widget tree.
final class WidgetTreeNode {
  /// Creates a widget tree node.
  const WidgetTreeNode({
    required this.name,
    required this.details,
    this.children = const [],
  });

  /// The widget type name.
  final String name;

  /// A details string from the inspector (may be truncated).
  final String details;

  /// Child widgets.
  final List<WidgetTreeNode> children;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'name': name,
    'details': details,
    'children': [for (final child in children) child.toJson()],
  };
}

/// Captured Flutter widget tree with metadata.
final class WidgetTreeCapture {
  /// Creates a widget tree capture.
  const WidgetTreeCapture({
    required this.root,
    required this.timestamp,
    required this.nodeCount,
    required this.maxDepth,
  });

  /// Root node of the widget tree.
  final WidgetTreeNode root;

  /// When the tree was captured.
  final DateTime timestamp;

  /// Total number of nodes in the tree.
  final int nodeCount;

  /// Maximum depth of the tree.
  final int maxDepth;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'root': root.toJson(),
    'timestamp': timestamp.toIso8601String(),
    'nodeCount': nodeCount,
    'maxDepth': maxDepth,
  };
}

/// Captures Flutter widget trees from a running application via VM service
/// extension calls.
class WidgetTreeCaptureService {
  /// Creates a widget tree capture service.
  WidgetTreeCaptureService({required VmService vmService})
    : _vmService = vmService;

  final VmService _vmService;

  /// Captures the widget tree from [isolateId].
  ///
  /// When [projectOnly] is true, only widgets belonging to the project package
  /// are returned. [maxDepth] limits tree depth.
  Future<WidgetTreeCapture> captureWidgetTree({
    required String isolateId,
    int maxDepth = 15,
    bool projectOnly = false,
  }) async {
    final response = await _vmService.callServiceExtension(
      'ext.flutter.inspector.getRootWidgetTree',
      isolateId: isolateId,
      args: {
        'maxDepth': maxDepth.toString(),
        'objectGroup': 'inspector',
        'isSummaryTree': 'false',
        'groupName': 'root',
      },
    );

    final treeJson =
        response.json?['result'] as Map<String, Object?>? ??
        response.json as Map<String, Object?>;

    final root = _parseNode(treeJson, projectOnly: projectOnly);
    final nodeCount = _countNodes(root);
    final treeDepth = _maxDepth(root);

    return WidgetTreeCapture(
      root: root,
      timestamp: DateTime.now(),
      nodeCount: nodeCount,
      maxDepth: treeDepth,
    );
  }

  /// Captures the widget tree as a summary (Flutter-only widgets, no children
  /// details).
  Future<WidgetTreeCapture> captureSummaryWidgetTree({
    required String isolateId,
    int maxDepth = 15,
    bool projectOnly = false,
  }) async {
    final response = await _vmService.callServiceExtension(
      'ext.flutter.inspector.getRootWidgetSummaryTree',
      isolateId: isolateId,
      args: {'maxDepth': maxDepth.toString(), 'objectGroup': 'inspector'},
    );

    final treeJson =
        response.json?['result'] as Map<String, Object?>? ??
        response.json as Map<String, Object?>;

    final root = _parseNode(treeJson, projectOnly: projectOnly);
    final nodeCount = _countNodes(root);
    final treeDepth = _maxDepth(root);

    return WidgetTreeCapture(
      root: root,
      timestamp: DateTime.now(),
      nodeCount: nodeCount,
      maxDepth: treeDepth,
    );
  }

  WidgetTreeNode _parseNode(
    Map<String, Object?> node, {
    bool projectOnly = false,
  }) {
    final name =
        node['name'] as String? ??
        node['widgetRuntimeType'] as String? ??
        node['description'] as String? ??
        'unknown';

    final description =
        node['description'] as String? ?? node['value'] as String? ?? '';

    final childrenJson = node['children'] as List<Object?>?;
    final children = <WidgetTreeNode>[];

    if (childrenJson != null) {
      for (final child in childrenJson) {
        if (child is Map<String, Object?>) {
          final childNode = _parseNode(child, projectOnly: projectOnly);
          if (projectOnly && _isFrameworkWidget(childNode.name)) {
            children.addAll(childNode.children);
          } else {
            children.add(childNode);
          }
        }
      }
    }

    // Also handle 'child' (single child case)
    final singleChild = node['child'] as Map<String, Object?>?;
    if (singleChild != null) {
      final childNode = _parseNode(singleChild, projectOnly: projectOnly);
      if (projectOnly && _isFrameworkWidget(childNode.name)) {
        children.addAll(childNode.children);
      } else {
        children.add(childNode);
      }
    }

    return WidgetTreeNode(name: name, details: description, children: children);
  }

  bool _isFrameworkWidget(String name) =>
      name.startsWith('Render') ||
      name == 'SizedBox' ||
      name == 'ConstrainedBox' ||
      name == 'Padding' ||
      name == 'Column' ||
      name == 'Row' ||
      name == 'Center' ||
      name == 'Align' ||
      name == 'Stack' ||
      name == 'Positioned' ||
      name == 'Flex' ||
      name == 'Expanded' ||
      name == 'MediaQuery' ||
      name == 'Directionality' ||
      name == 'MaterialApp' ||
      name == 'CupertinoApp' ||
      name == 'Scaffold' ||
      name == 'AppBar' ||
      name == 'Navigator' ||
      name == 'SafeArea' ||
      name == 'Theme' ||
      name == 'ScaffoldMessenger' ||
      name == 'DefaultTabController' ||
      name == 'TabBar' ||
      name == 'TabBarView' ||
      name == 'GestureDetector' ||
      name == 'Listener' ||
      name == 'Builder' ||
      name == 'RepaintBoundary' ||
      name == 'KeyedSubtree' ||
      name == 'OverflowBar' ||
      name == 'DefaultTextStyle' ||
      name == 'IconTheme' ||
      name == 'Banner' ||
      name == 'Semantics';

  int _countNodes(WidgetTreeNode node) {
    var count = 1;
    for (final child in node.children) {
      count += _countNodes(child);
    }
    return count;
  }

  int _maxDepth(WidgetTreeNode node) {
    var maxChildDepth = 0;
    for (final child in node.children) {
      final childDepth = _maxDepth(child);
      if (childDepth > maxChildDepth) maxChildDepth = childDepth;
    }
    return 1 + maxChildDepth;
  }
}
