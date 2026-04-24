import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dtd/dtd.dart';

/// A launched Dart Tooling Daemon process plus its active connection.
final class DtdProcessSession {
  DtdProcessSession({
    required this.daemon,
    required this.info,
    required this.process,
    required this.stdoutSubscription,
  });

  final DartToolingDaemon daemon;
  final DtdConnectionInfo info;
  final Process process;
  final StreamSubscription<List<int>> stdoutSubscription;

  /// Starts a local tooling-daemon process and connects to it.
  static Future<DtdProcessSession> start() async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      const ['tooling-daemon', '--machine'],
    );
    final completer = Completer<DtdConnectionInfo>();

    final stdoutBuffer = StringBuffer();
    late final StreamSubscription<List<int>> stdoutSubscription;
    stdoutSubscription = process.stdout.listen((data) {
      if (completer.isCompleted) return;
      stdoutBuffer.write(utf8.decode(data));
      final decoded = stdoutBuffer.toString().trim();
      if (decoded.isEmpty) return;

      try {
        final json = jsonDecode(decoded) as Map<String, Object?>;
        final toolingDetails =
            json['tooling_daemon_details'] as Map<String, Object?>?;
        final uri = toolingDetails?['uri'] as String?;
        final secret = toolingDetails?['trusted_client_secret'] as String?;
        if (uri == null || secret == null) {
          completer.completeError(
            StateError('Unexpected tooling-daemon machine output: $decoded'),
          );
          return;
        }
        completer.complete(
          DtdConnectionInfo(
            localUri: Uri.parse(uri),
            trustedClientSecret: secret,
          ),
        );
      } on FormatException {
        // Wait for more data if the tooling-daemon JSON arrived in chunks.
      }
    });

    final info = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw StateError('Timed out starting the tooling-daemon process.');
      },
    );
    final daemon = await DartToolingDaemon.connect(info.localUri);
    return DtdProcessSession(
      daemon: daemon,
      info: info,
      process: process,
      stdoutSubscription: stdoutSubscription,
    );
  }

  /// Closes this daemon connection and terminates the child process.
  Future<void> dispose() async {
    await daemon.close();
    await stdoutSubscription.cancel();
    process.kill();
    await process.exitCode;
  }
}

/// Machine-readable connection details emitted by the tooling daemon.
final class DtdConnectionInfo {
  const DtdConnectionInfo({
    required this.localUri,
    required this.trustedClientSecret,
  });

  final Uri localUri;
  final String trustedClientSecret;
}
