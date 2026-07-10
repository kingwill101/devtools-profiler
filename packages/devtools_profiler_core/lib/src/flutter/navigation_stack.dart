import 'dart:async';
import 'package:vm_service/vm_service.dart';

/// Represents a single route in the Flutter navigation stack.
final class RouteEntry {
  /// Creates a route entry.
  const RouteEntry({
    required this.name,
    required this.path,
    required this.settingsName,
    required this.isCurrent,
    required this.isFirst,
  });

  /// The route's Dart type name.
  final String name;

  /// The route's path or description.
  final String path;

  /// The RouteSettings name, if set.
  final String? settingsName;

  /// Whether this is the currently displayed route.
  final bool isCurrent;

  /// Whether this is the first/persistent route.
  final bool isFirst;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'name': name,
    'path': path,
    'settingsName': settingsName,
    'isCurrent': isCurrent,
    'isFirst': isFirst,
  };
}

/// Captured navigation stack from a running Flutter app.
final class NavigationStack {
  /// Creates a navigation stack.
  const NavigationStack({required this.routes, required this.currentRoute});

  /// All routes in the stack (first to last).
  final List<RouteEntry> routes;

  /// The currently visible route.
  final RouteEntry? currentRoute;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'routes': [for (final route in routes) route.toJson()],
    'currentRoute': currentRoute?.toJson(),
  };
}

/// Inspects the Flutter navigation stack via VM service extensions.
class NavigationStackService {
  /// Creates a navigation stack service.
  NavigationStackService({required VmService vmService})
    : _vmService = vmService;

  final VmService _vmService;

  /// Fetches the current route stack from [isolateId].
  Future<NavigationStack> getNavigationStack({
    required String isolateId,
  }) async {
    final response = await _vmService.callServiceExtension(
      'ext.flutter.inspector.getRouteStack',
      isolateId: isolateId,
      args: {'objectGroup': 'inspector'},
    );

    final routesJson =
        response.json?['result'] as List<Object?>? ??
        response.json?['routes'] as List<Object?>? ??
        [];

    final routes = <RouteEntry>[];
    RouteEntry? currentRoute;

    for (final entry in routesJson) {
      if (entry is! Map<String, Object?>) continue;

      final name =
          entry['name'] as String? ??
          entry['routeName'] as String? ??
          'unknown';
      final path =
          entry['path'] as String? ?? entry['description'] as String? ?? '';
      final settingsName = entry['settingsName'] as String?;
      final isCurrent =
          (entry['isCurrent'] as bool?) ?? (entry['current'] as bool?) ?? false;
      final isFirst =
          (entry['isFirst'] as bool?) ?? (entry['first'] as bool?) ?? false;

      final route = RouteEntry(
        name: name,
        path: path,
        settingsName: settingsName,
        isCurrent: isCurrent,
        isFirst: isFirst,
      );
      routes.add(route);
      if (isCurrent) currentRoute = route;
    }

    return NavigationStack(routes: routes, currentRoute: currentRoute);
  }
}
