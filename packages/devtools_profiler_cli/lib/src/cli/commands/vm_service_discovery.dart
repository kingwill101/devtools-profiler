import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:vm_service/vm_service.dart';

import 'profiler_command.dart';

/// Discovers running apps for CLI commands that can auto-select a VM service.
Future<List<DiscoveredApp>> Function() discoverVmServiceApps =
    discoverActiveApps;

/// Mixin for flutter commands that can auto-discover a VM service URI
/// when none is explicitly provided.
mixin VmServiceDiscovery on ProfilerCommand {
  /// Returns the VM service URI from [argResults] if provided, otherwise
  /// attempts to auto-discover a running Flutter/Dart application.
  ///
  /// When exactly one app is discovered, its URI is used automatically.
  /// When multiple apps are found, a descriptive error lists them.
  Future<String> resolveVmServiceUri() async {
    if (argResults!.rest.isNotEmpty) {
      return argResults!.rest.single;
    }

    final apps = await discoverVmServiceApps();

    if (apps.isEmpty) {
      throw usageException(
        'No VM service URI provided and no running Flutter or Dart '
        'applications were discovered on this machine.\n'
        'Start your app in debug mode and provide the VM service URI:\n'
        '  ${runner!.executableName} $commandName <vm-service-uri>',
      );
    }

    if (apps.length == 1) {
      final app = apps.single;
      warn('Auto-discovered: ${app.projectName} at ${app.vmServiceUri}');
      return app.vmServiceUri;
    }

    throw usageException(
      'No VM service URI provided and ${apps.length} running applications '
      'were found:\n'
      '${apps.map((a) => '  ${a.projectName}: ${a.vmServiceUri}').join('\n')}\n'
      'Use ${runner!.executableName} $commandName <uri> to select one.',
    );
  }

  /// Normalizes an HTTP/HTTPS VM service URI to a WebSocket URI suitable
  /// for [vmServiceConnectUri]. Replaces `http://` with `ws://` and
  /// `https://` with `wss://`, then ensures the result ends with `/ws`.
  String normalizeWsUri(String uri) {
    final wsUri = uri
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    return wsUri.endsWith('/ws') ? wsUri : '$wsUri/ws';
  }

  /// Returns the ID of the first non-system isolate in [vm].
  ///
  /// Throws [StateError] when no isolates are found.
  String resolveMainIsolate(VM vm) {
    final isolates = vm.isolates ?? [];
    final active = isolates.where((i) => i.isSystemIsolate != true).toList();
    if (active.isEmpty && isolates.isEmpty) {
      throw StateError('No isolates found in the target VM.');
    }
    return (active.isNotEmpty ? active.first : isolates.first).id!;
  }

  /// The full command name including namespace prefix.
  String get commandName {
    final p = parent;
    return p != null ? '${p.name}:${name}' : name;
  }
}
