import 'dart:io';

import 'profiler_command.dart';
import 'profile_session_resolution.dart';

/// Base class for profiler commands that can resolve their target path
/// from an explicit argument or from the latest stored session.
///
/// When no positional path is given, [resolveTargetPath] automatically
/// discovers the sessions directory under `.dart_tool/devtools_profiler/sessions`
/// and picks the newest session. Use `--session-id` to override which
/// session is selected (supports `"latest"`, `"previous"`, or an exact id).
///
/// Subclasses call [resolveTargetPath] in their [run] method instead of
/// checking [argResults!.rest] directly.
abstract class ProfileTargetCommand extends ProfilerCommand
    with ProfileSessionResolution {
  /// Creates a profile target command backed by [profileRunner].
  ProfileTargetCommand(super.profileRunner) {
    argParser
      ..addOption(
        'session-id',
        help:
            'Stored session id to use when no explicit path is provided. '
            'Accepts "latest" or "previous".',
      )
      ..addOption(
        'cwd',
        help:
            'The working directory containing '
            '.dart_tool/devtools_profiler/sessions. '
            'Defaults to the current directory.',
      );
  }

  /// Returns the explicit profile path from the positional rest args, if any.
  String? get explicitTargetPath {
    if (argResults!.rest.isEmpty) return null;
    return argResults!.rest.single;
  }

  /// Resolves the profile target path to use for this command.
  ///
  /// Returns the explicit path if provided as a positional argument;
  /// otherwise discovers stored sessions under the default sessions directory
  /// and returns the path to the selected session (newest by default, or
  /// whatever `--session-id` specifies).
  ///
  /// When an explicit positional argument is given, [resolveSessionOrPath]
  /// first tries to match it against stored session ids using the
  /// `--cwd`-aware sessions directory. Only when no stored session matches
  /// does it normalize the input as a file path.
  ///
  /// Throws [ArgumentError] when no stored sessions are found and no
  /// explicit path was provided.
  Future<String> resolveTargetPath() async {
    final explicit = explicitTargetPath;
    if (explicit != null) {
      final sessionsDirectory = _resolveSessionsDirectory();
      return resolveSessionOrPath(
        explicit,
        sessionsDirectory: sessionsDirectory,
      );
    }

    final sessionsDirectory = _resolveSessionsDirectory();
    final sessions = await discoverSessions(sessionsDirectory);
    if (sessions.isEmpty) {
      throw ArgumentError(
        'No explicit profile path was provided and no stored profiling '
        'sessions were found under "${sessionsDirectory.path}".',
      );
    }

    final sessionId = argResults!['session-id'] as String?;
    final selected = selectSession(sessions, sessionId: sessionId);
    return selected.directory.path;
  }

  /// Resolves the sessions directory, checking --cwd first.
  Directory _resolveSessionsDirectory() {
    return resolveSessionsDirectory(cwd: argResults!['cwd'] as String?);
  }
}
