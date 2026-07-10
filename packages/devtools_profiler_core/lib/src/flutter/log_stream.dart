import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';

/// A single log entry captured from a VM service stream.
final class LogEntry {
  /// Creates a log entry.
  const LogEntry({
    required this.timestamp,
    required this.kind,
    required this.message,
  });

  /// Timestamp in microseconds since epoch.
  final int timestamp;

  /// Stream kind: 'log', 'stdout', 'stderr'.
  final String kind;

  /// The log message.
  final String message;

  /// JSON-compatible representation.
  Map<String, Object?> toJson() => {
    'timestamp': timestamp,
    'kind': kind,
    'message': message,
  };
}

/// Captures log and output streams from a running Dart VM service.
///
/// Listens to the `Logging`, `Stdout`, and `Stderr` VM service streams and
/// buffers entries for retrieval.
class LogStreamCapture {
  /// Creates a log stream capture.
  LogStreamCapture({required VmService vmService}) : _vmService = vmService;

  final VmService _vmService;
  final List<LogEntry> _entries = [];
  StreamSubscription<Event>? _loggingSub;
  StreamSubscription<Event>? _stdoutSub;
  StreamSubscription<Event>? _stderrSub;
  bool _capturing = false;

  /// Whether capture is currently active.
  bool get isCapturing => _capturing;

  /// Starts capturing logs from VM service streams.
  Future<void> start() async {
    if (_capturing) return;
    _capturing = true;

    _loggingSub = _vmService.onEvent('Logging').listen(_onLogEvent);
    _stdoutSub = _vmService.onEvent('Stdout').listen(_onStdoutEvent);
    _stderrSub = _vmService.onEvent('Stderr').listen(_onStderrEvent);

    await Future.wait([
      _vmService.streamListen('Logging'),
      _vmService.streamListen('Stdout'),
      _vmService.streamListen('Stderr'),
    ]);
  }

  /// Stops capturing. Returns all captured entries.
  Future<List<LogEntry>> stop() async {
    if (!_capturing) return _entries;
    _capturing = false;

    for (final stream in ['Logging', 'Stdout', 'Stderr']) {
      try {
        await _vmService.streamCancel(stream);
      } catch (_) {}
    }

    await _loggingSub?.cancel();
    _loggingSub = null;
    await _stdoutSub?.cancel();
    _stdoutSub = null;
    await _stderrSub?.cancel();
    _stderrSub = null;

    return _entries;
  }

  /// Returns all entries captured so far without stopping.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Writes captured entries as JSON-lines to [file].
  Future<void> writeToFile(File file) async {
    final sink = file.openWrite();
    for (final entry in _entries) {
      sink.writeln(jsonEncode(entry.toJson()));
    }
    await sink.flush();
    await sink.close();
  }

  void _onLogEvent(Event event) {
    final logRecord = event.logRecord;
    if (logRecord == null) return;

    final logMessage = logRecord.message?.valueAsString ?? '';
    if (logMessage.trim().isEmpty) return;

    _entries.add(
      LogEntry(
        timestamp: (logRecord.time ?? event.timestamp ?? 0) * 1000,
        kind: 'log',
        message: logMessage,
      ),
    );
  }

  void _onStdoutEvent(Event event) {
    _addWriteEvent(event, 'stdout');
  }

  void _onStderrEvent(Event event) {
    _addWriteEvent(event, 'stderr');
  }

  void _addWriteEvent(Event event, String kind) {
    final bytesBase64 = event.bytes;
    if (bytesBase64 == null || bytesBase64.isEmpty) return;

    try {
      final decoded = base64Decode(bytesBase64);
      final message = utf8.decode(decoded);
      if (message.trim().isEmpty) return;
      _entries.add(
        LogEntry(
          timestamp: (event.timestamp ?? 0) * 1000,
          kind: kind,
          message: message,
        ),
      );
    } catch (_) {
      // Skip unparseable write events
    }
  }
}
