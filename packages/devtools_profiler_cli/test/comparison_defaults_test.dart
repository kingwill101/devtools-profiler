import 'dart:convert';
import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:devtools_profiler_cli/src/cli/commands/analysis_commands.dart';
import 'package:devtools_profiler_cli/src/cli/commands/profile_session_resolution.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'default comparison uses previous baseline and newest current',
    () async {
      final output = <String>[];
      final backend = _Runner();
      final runner = CommandRunner<int>('profiler', 'test', out: output.add)
        ..addCommand(_CompareCommand(backend));
      expect(await runner.run(['compare', '--json']), 0);
      expect(backend.paths, ['/previous', '/latest']);
      final json = jsonDecode(output.join('\n')) as Map;
      expect((json['baseline'] as Map)['path'], '/previous');
      expect((json['current'] as Map)['path'], '/latest');
    },
  );
}

class _CompareCommand extends CompareCommand {
  _CompareCommand(super.profileRunner);

  @override
  Future<List<StoredSession>> discoverSessions([Directory? directory]) async =>
      [
        for (final id in ['latest', 'previous'])
          StoredSession(
            directory: Directory('/$id'),
            modifiedTime: DateTime.utc(2026, 1, id == 'latest' ? 2 : 1),
            result: ProfileRunResult.fromJson({'sessionId': id}),
          ),
      ];
}

class _Runner extends ProfileRunner {
  final paths = <String>[];

  @override
  Future<Map<String, Object?>> summarizeArtifact(String path) async {
    paths.add(path);
    return ProfileRegionResult.fromJson({
      'regionId': 'overall',
      'name': 'whole-session',
    }).toJson();
  }
}
