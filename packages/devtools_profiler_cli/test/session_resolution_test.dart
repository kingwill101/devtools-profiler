import 'dart:io';

import 'package:devtools_profiler_cli/src/cli/commands/profile_session_resolution.dart';
import 'package:devtools_profiler_cli/src/cli/commands/profiles_command.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late _Command command;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('session_resolution.');
    command = _Command();
  });
  tearDown(() => root.delete(recursive: true));

  test('normalizes direct directories and prefers nested sessions', () async {
    final relative = path.relative(root.path);
    expect(command.resolveSessionsDirectory(cwd: relative).path, root.path);
    final nested = await Directory(
      path.join(root.path, '.dart_tool', 'devtools_profiler', 'sessions'),
    ).create(recursive: true);
    expect(command.resolveSessionsDirectory(cwd: relative).path, nested.path);
  });

  test('rejects missing directories', () {
    expect(
      () => command.resolveSessionsDirectory(
        cwd: path.join(root.path, 'missing'),
      ),
      throwsArgumentError,
    );
  });

  test('existing paths never trigger session parsing', () async {
    final file = await File(path.join(root.path, 'latest')).create();
    expect(await command.resolveSessionOrPath(file.path), file.path);
    expect(await command.resolveSessionOrPath(root.path), root.path);
  });
}

class _Command extends ProfilesCommand {
  _Command() : super(ProfileRunner());

  @override
  Future<List<StoredSession>> discoverSessions([Directory? directory]) {
    throw StateError('Explicit paths must not discover sessions.');
  }
}
