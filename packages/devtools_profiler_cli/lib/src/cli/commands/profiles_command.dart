import 'dart:io';

import 'package:path/path.dart' as path;

import '../constants.dart';
import '../options.dart';
import 'profiler_command.dart';
import 'profile_session_resolution.dart';

/// Command that lists available profiling sessions.
///
/// Prints a compact one-line-per-session listing by default showing the
/// session id, modified time, and command name. Pass `--extended` to show
/// a full table with working directory, exit code, region count, and
/// warnings. Use `--limit` to control how many sessions are shown.
///
/// Sessions are discovered from `.dart_tool/devtools_profiler/sessions`
/// under the current working directory and sorted newest-first.
class ProfilesCommand extends ProfilerCommand with ProfileSessionResolution {
  /// Creates a profiles command.
  ProfilesCommand(super.profileRunner) {
    argParser.addOption(
      'cwd',
      help:
          'The working directory containing .dart_tool/devtools_profiler/sessions. Defaults to the current directory.',
    );
    argParser.addFlag(
      'extended',
      negatable: false,
      help:
          'Show full session details including working directory, '
          'exit code, regions, and warnings.',
    );
    argParser.addOption(
      'limit',
      defaultsTo: '$defaultProfileLimit',
      help: 'Maximum sessions to show. Use 0 for unlimited.',
    );
  }

  @override
  String get name => 'profiles';

  @override
  String get description =>
      'List available profiling sessions. Use --extended for full details.';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler profiles',
      'devtools-profiler profiles --extended',
      'devtools-profiler profiles --limit 0 --json',
    ],
  );

  @override
  Future<int> run() async {
    final sessionsDirectory = _resolveSessionsDirectory();
    final sessions = await discoverSessions(sessionsDirectory);

    if (sessions.isEmpty) {
      warn(
        'No profiling sessions were found under "${sessionsDirectory.path}".',
      );
      return successExitCode;
    }

    final limit = parseLimit(
      argResults!['limit'] as String?,
      optionName: 'limit',
    );
    final listed = limit == null
        ? sessions
        : sessions.take(limit).toList(growable: false);
    final truncated = limit != null && sessions.length > limit;

    line('Profiling Sessions (${listed.length} of ${sessions.length}):');

    if (argResults!['extended'] as bool? ?? false) {
      io.table(
        headers: const [
          'Session',
          'Modified',
          'Working Directory',
          'Command',
          'Exit Code',
          'Regions',
          'Warnings',
        ],
        rows: [
          for (final session in listed)
            [
              session.result.sessionId,
              _formatTime(session.modifiedTime),
              session.result.workingDirectory,
              session.result.command.join(' '),
              '${session.result.exitCode}',
              '${session.result.regions.length}',
              '${session.result.warnings.length}',
            ],
        ],
      );
    } else {
      for (final session in listed) {
        comment(
          '${session.result.sessionId}  '
          '${_formatTime(session.modifiedTime)}  '
          '${session.result.command.join(' ')}',
        );
      }
    }

    if (truncated) {
      info(
        '${sessions.length - listed.length} more session(s) available. '
        'Use --limit 0 to show all.',
      );
    }

    return successExitCode;
  }

  /// Locates the sessions directory, using --cwd when provided.
  Directory _resolveSessionsDirectory() {
    final cwd = argResults!['cwd'] as String?;
    if (cwd != null) {
      // Check for .dart_tool/devtools_profiler/sessions under the given path
      final dartToolDir = Directory(
        path.join(cwd, '.dart_tool', 'devtools_profiler', 'sessions'),
      );
      if (dartToolDir.existsSync()) return dartToolDir;
      // Fall back to the raw path
      final dir = Directory(cwd);
      if (dir.existsSync()) return dir;
      throw ArgumentError('Directory not found: $cwd');
    }
    return defaultSessionsDirectory();
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return 'today ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    if (local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day) {
      return 'yesterday ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }

    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
