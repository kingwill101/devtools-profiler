@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

void main() {
  for (final failedOperation in ['start', 'stop']) {
    test(
      'logs only the failing synchronous $failedOperation operation',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final sockets = <WebSocket>[];
        addTearDown(() async {
          for (final socket in sockets) {
            await socket.close();
          }
        });
        final methods = <String>[];
        server.listen((request) async {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          socket.listen((message) {
            final rpc = jsonDecode(message as String) as Map;
            final method = rpc['method'] as String;
            methods.add(method);
            socket.add(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': rpc['id'],
                if (method == 'DevToolsProfiler.${failedOperation}Region')
                  'error': {
                    'code': -32602,
                    'message': 'Rejected $failedOperation',
                  }
                else
                  'result': {'type': 'Success', 'sessionId': 'session'},
              }),
            );
          });
        });
        final root = Directory.current.path.endsWith('devtools_profiler_core')
            ? Directory.current
            : Directory('packages/devtools_profiler_core');
        final child = await Process.start(
          Platform.resolvedExecutable,
          [
            '--enable-vm-service=0',
            '--disable-service-auth-codes',
            '${root.absolute.path}/test/fixtures/sync_region_diagnostics.dart',
          ],
          environment: {
            'DEVTOOLS_PROFILER_DTD_URI': 'ws://127.0.0.1:${server.port}',
            'DEVTOOLS_PROFILER_SESSION_ID': 'session',
          },
        );
        addTearDown(child.kill);
        final uriReady = Completer<String>();
        final stdoutDone = child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) {
              final uri = RegExp(r'http://127\.0\.0\.1:\d+/').firstMatch(line);
              if (uri != null && !uriReady.isCompleted) {
                uriReady.complete(uri.group(0));
              }
            });
        final stderrText = child.stderr.transform(utf8.decoder).join();
        final uri = await uriReady.future.timeout(const Duration(seconds: 45));
        final service = await vmServiceConnectUri(
          '${uri.replaceFirst('http:', 'ws:')}ws',
        );
        addTearDown(service.dispose);
        final logs = <String>[];
        final firstLog = Completer<void>();
        final subscription = service.onLoggingEvent.listen((event) {
          if (event.logRecord?.loggerName?.valueAsString !=
              'devtools_region_profiler') {
            return;
          }
          logs.add(event.logRecord!.message!.valueAsString!);
          if (!firstLog.isCompleted) firstLog.complete();
        });
        addTearDown(subscription.cancel);
        await service.streamListen(EventStreams.kLogging);
        child.stdin.writeln('run');
        await firstLog.future.timeout(const Duration(seconds: 45));
        child.stdin.writeln('finish');
        expect(await child.exitCode.timeout(const Duration(seconds: 10)), 0);
        await stdoutDone;
        expect(await stderrText, isEmpty);
        expect(logs, hasLength(1), reason: logs.join('\n'));
        expect(
          logs.single,
          startsWith('Failed to $failedOperation profiling region'),
        );
        expect(methods, [
          'DevToolsProfiler.getSessionInfo',
          'DevToolsProfiler.startRegion',
          if (failedOperation == 'stop') 'DevToolsProfiler.stopRegion',
        ]);
      },
    );
  }
}
