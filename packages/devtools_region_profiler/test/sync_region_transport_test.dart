import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final mode in ['success', 'start-error', 'stale-session']) {
    test('sync region orders and closes DTD requests: $mode', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final sockets = <WebSocket>[];
      addTearDown(() async {
        for (final socket in sockets) {
          await socket.close();
        }
      });
      final methods = <String>[];
      var startAcknowledged = false;
      var prematureStop = false;
      final closed = Completer<void>();
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen(
          (message) async {
            final rpc = jsonDecode(message as String) as Map;
            final method = rpc['method'] as String;
            methods.add(method);
            if (method.endsWith('.startRegion')) {
              // Stop is requested immediately by the child. Keep reading while
              // the start response is delayed to detect an unordered channel.
              await Future<void>.delayed(const Duration(milliseconds: 100));
              startAcknowledged = true;
            }
            if (method.endsWith('.stopRegion') && !startAcknowledged) {
              prematureStop = true;
            }
            socket.add(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': rpc['id'],
                if (mode == 'start-error' && method.endsWith('.startRegion'))
                  'error': {'code': -32602, 'message': 'Rejected start'}
                else
                  'result': {
                    'type': 'Success',
                    'sessionId': mode == 'stale-session' ? 'stale' : 'session',
                  },
              }),
            );
          },
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
        );
      });
      final packageRoot =
          Directory.current.path.endsWith('devtools_region_profiler')
          ? Directory.current
          : Directory('packages/devtools_region_profiler');
      final child = await Process.start(
        Platform.resolvedExecutable,
        ['${packageRoot.absolute.path}/test/fixtures/sync_region.dart'],
        environment: {
          'DEVTOOLS_PROFILER_DTD_URI': 'ws://127.0.0.1:${server.port}',
          'DEVTOOLS_PROFILER_SESSION_ID': 'session',
        },
      );
      addTearDown(child.kill);
      final output = child.stdout.transform(utf8.decoder).join();
      final errors = child.stderr.transform(utf8.decoder).join();
      expect(await child.exitCode.timeout(const Duration(seconds: 20)), 0);
      expect(await errors, isEmpty);
      expect(
        await output,
        contains(mode == 'success' ? 'stopped' : 'rejected'),
      );
      await closed.future.timeout(const Duration(seconds: 2));
      expect(sockets, hasLength(1));
      expect(prematureStop, isFalse);
      expect(methods, [
        'DevToolsProfiler.getSessionInfo',
        if (mode != 'stale-session') 'DevToolsProfiler.startRegion',
        if (mode == 'success') 'DevToolsProfiler.stopRegion',
      ]);
    });
  }
}
