import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;

import 'profiler_command.dart';

/// Provides stored-session discovery helpers for profiler commands that
/// need to resolve profiling sessions without requiring explicit paths.
///
/// Classes that mix in this type gain access to:
///
/// - [defaultSessionsDirectory] — locates `.dart_tool/devtools_profiler/sessions`
///   under the current working directory.
/// - [discoverSessions] — lists all stored sessions, sorted newest first.
/// - [selectSession] — picks a session by id, "latest", or "previous".
///
/// These methods are shared between CLI commands (via [ProfilerCommand]) and
/// the MCP tool handlers to avoid duplicating session discovery logic.
mixin ProfileSessionResolution on ProfilerCommand {
  /// Locates the default sessions directory under the current working
  /// directory.
  ///
  /// Returns `.dart_tool/devtools_profiler/sessions` if it exists under
  /// [Directory.current]; falls back to [Directory.current] itself so that
  /// callers can discover sessions even from a sessions-directory path.
  Directory defaultSessionsDirectory() {
    final candidate = Directory(
      path.join(
        Directory.current.path,
        '.dart_tool',
        'devtools_profiler',
        'sessions',
      ),
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    return Directory.current;
  }

  /// Lists all stored profiling sessions, sorted newest first.
  ///
  /// Reads each subdirectory of [directory] that contains a `session.json`
  /// file, parses it with [ProfileArtifacts.readSession], and returns the
  /// results as [StoredSession] instances ordered by modification time.
  ///
  /// If [directory] is omitted, the return from [defaultSessionsDirectory]
  /// is used.
  Future<List<StoredSession>> discoverSessions([Directory? directory]) async {
    final dir = directory ?? defaultSessionsDirectory();
    final sessions = <StoredSession>[];
    const sessionFileName = 'session.json';
    for (final entity in dir.listSync()) {
      if (entity is! Directory) continue;
      final sessionFile = File('${entity.path}/$sessionFileName');
      if (!sessionFile.existsSync()) continue;
      final stat = await sessionFile.stat();
      final result = await ProfileArtifacts.readSession(entity.path);
      sessions.add(
        StoredSession(
          directory: Directory(path.normalize(path.absolute(entity.path))),
          result: result,
          modifiedTime: stat.modified.toUtc(),
        ),
      );
    }
    sessions.sort(
      (left, right) => right.modifiedTime.compareTo(left.modifiedTime),
    );
    return sessions;
  }

  /// Returns the single stored session identified by [sessionId].
  ///
  /// When [sessionId] is `null` or empty, returns the first (newest) session.
  /// The strings `"latest"` and `"previous"` select the newest and
  /// second-newest session, respectively. Any other value is treated as an
  /// exact session id match.
  ///
  /// Throws [ArgumentError] when:
  /// - `"previous"` is requested but fewer than two sessions are available.
  /// - An explicit id does not match any stored session.
  StoredSession selectSession(
    List<StoredSession> sessions, {
    String? sessionId,
  }) {
    final normalized = sessionId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return sessions.first;
    }

    switch (normalized) {
      case 'latest':
        return sessions.first;
      case 'previous':
        if (sessions.length < 2) {
          throw ArgumentError(
            'Unable to resolve the previous session because fewer than '
            'two stored sessions are available.',
          );
        }
        return sessions[1];
    }

    return sessions.firstWhere(
      (session) => session.result.sessionId == normalized,
      orElse: () => throw ArgumentError(
        'Session "$normalized" was not found in the stored session list.',
      ),
    );
  }
}

/// A profiling session discovered from a stored sessions directory.
///
/// Contains the parsed [result] from `session.json`, the on-disk [directory],
/// and the file [modifiedTime] used for time-ordered sorting.
class StoredSession {
  const StoredSession({
    required this.directory,
    required this.result,
    required this.modifiedTime,
  });

  final Directory directory;
  final ProfileRunResult result;
  final DateTime modifiedTime;
}
