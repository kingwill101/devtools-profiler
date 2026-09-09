import 'dart:io';

import 'package:artisanal/runtime.dart' as tui;
import 'package:path/path.dart' as path;

import '../../browser/session_browser.dart';
import '../constants.dart';
import 'profile_session_resolution.dart';
import 'profiler_command.dart';

/// Opens an explicit, read-only browser of stored session summaries.
final class BrowseCommand extends ProfilerCommand
    with ProfileSessionResolution {
  /// Creates a browser; redirected hosts must disable terminal access.
  BrowseCommand(super.profileRunner, {required this.terminalAllowed})
    : super(includePresentationOptions: false) {
    argParser.addOption('cwd', help: 'Project root or sessions directory.');
  }

  /// Whether the host permits exclusive ownership of terminal I/O.
  final bool terminalAllowed;

  @override
  String get name => 'browse';

  @override
  String get description =>
      'Select stored baseline/current profiles in a read-only terminal browser.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty ||
        !terminalAllowed ||
        !stdin.hasTerminal ||
        !stdout.hasTerminal) {
      throw const FormatException(
        'browse requires an interactive terminal and no positional arguments. '
        'Use profiles --extended or compare <baseline> <current> instead.',
      );
    }
    final cwd = argResults!['cwd'] as String?;
    var directory = cwd == null ? defaultSessionsDirectory() : Directory(cwd);
    final nested = Directory(
      path.join(directory.path, '.dart_tool', 'devtools_profiler', 'sessions'),
    );
    if (nested.existsSync()) directory = nested;
    final sessions = await discoverSessions(directory);
    final browser = SessionBrowser(sessions);
    if (browser.entries.isEmpty) {
      warn('No stored profiles found under "${directory.path}".');
      return successExitCode;
    }
    final result = await tui.runProgramWithResult(
      browser,
      options: const tui.ProgramOptions(altScreen: true),
    );
    if (result.exportedCommand case final command?) line(command);
    return successExitCode;
  }
}
