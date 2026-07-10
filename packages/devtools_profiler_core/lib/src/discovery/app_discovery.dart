import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A running Dart or Flutter application discovered on the local machine.
final class DiscoveredApp {
  /// Creates a new discovered application.
  const DiscoveredApp({required this.vmServiceUri, required this.projectName});

  /// The WebSocket VM Service URI of the application.
  final String vmServiceUri;

  /// A human-readable label for the application.
  final String projectName;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'vmServiceUri': vmServiceUri,
    'projectName': projectName,
  };
}

/// Discovers running Dart and Flutter applications by scanning OS processes.
///
/// On Linux and macOS, this runs `ps aux` and looks for DDS/Dart processes
/// with `--vm-service-uri=` arguments. On Windows, it uses PowerShell.
///
/// Returns a list of [DiscoveredApp] instances, one for each unique VM
/// service URI found.
Future<List<DiscoveredApp>> discoverActiveApps() async {
  final apps = <DiscoveredApp>[];
  final seenUris = <String>{};
  final uriPattern = RegExp(r'--vm-service-uri=(http://\S+)');

  try {
    if (Platform.isWindows) {
      final result = await Process.run('powershell', [
        '-Command',
        r'Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*development-service*" } | Select-Object CommandLine, ProcessId, WorkingDirectory | ConvertTo-Json',
      ]).timeout(const Duration(seconds: 5));

      if (result.exitCode != 0) return apps;

      final rawJson = (result.stdout as String).trim();
      if (rawJson.isEmpty) return apps;

      final decoded = jsonDecode(rawJson);
      final processes = decoded is List ? decoded : [decoded];

      for (final proc in processes) {
        if (proc is! Map) continue;
        final cmdLine = proc['CommandLine'] as String? ?? '';
        final pid = (proc['ProcessId'] ?? '').toString();
        final workingDir = proc['WorkingDirectory'] as String? ?? '';

        final uriMatch = uriPattern.firstMatch(cmdLine);
        if (uriMatch == null) continue;

        final rawVmUri = uriMatch.group(1)!;
        final projectName = workingDir.isNotEmpty
            ? workingDir.split(Platform.pathSeparator).last
            : 'Flutter App (pid $pid)';

        _addUniqueApp(rawVmUri, projectName, apps, seenUris);
      }
    } else {
      final result = await Process.run('ps', [
        'aux',
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) return apps;

      final lines = (result.stdout as String).split('\n');
      final pidPattern = RegExp(r'^\S+\s+(\d+)');

      for (final line in lines) {
        if (!line.contains('development-service')) continue;

        final uriMatch = uriPattern.firstMatch(line);
        final pidMatch = pidPattern.firstMatch(line);
        if (uriMatch == null || pidMatch == null) continue;

        final rawVmUri = uriMatch.group(1)!;
        final pid = pidMatch.group(1)!;

        // Try to get the project name from the process's working directory.
        String projectName = 'Flutter App (pid $pid)';
        try {
          final cwdResult = await Process.run('lsof', [
            '-p',
            pid,
            '-Fn',
            '-d',
            'cwd',
          ]).timeout(const Duration(seconds: 3));
          if (cwdResult.exitCode == 0) {
            final cwdLines = (cwdResult.stdout as String).split('\n');
            for (final cwdLine in cwdLines) {
              if (cwdLine.startsWith('n/')) {
                projectName = cwdLine.substring(1).split('/').last;
                break;
              }
            }
          }
        } catch (_) {}

        _addUniqueApp(rawVmUri, projectName, apps, seenUris);
      }
    }
  } catch (_) {}

  return apps;
}

/// Normalizes an HTTP VM service URI to a WebSocket URI and adds it to [apps]
/// if it hasn't been seen before.
void _addUniqueApp(
  String rawVmUri,
  String projectName,
  List<DiscoveredApp> apps,
  Set<String> seenUris,
) {
  var wsUri = rawVmUri
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://');
  if (!wsUri.endsWith('/ws')) {
    wsUri = '${wsUri.replaceAll(RegExp(r'/?$'), '')}/ws';
  }

  if (seenUris.add(wsUri)) {
    apps.add(DiscoveredApp(vmServiceUri: wsUri, projectName: projectName));
  }
}
