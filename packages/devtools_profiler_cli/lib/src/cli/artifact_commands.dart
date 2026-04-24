
part of '../cli.dart';

class _SummarizeCommand extends _ProfilerCommand {
  _SummarizeCommand(super.profileRunner);

  @override
  String get name => 'summarize';

  @override
  String get description => 'Summarize a session directory or artifact.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('A session directory or artifact path is required.');
    }

    final targetPath = argResults!.rest.first;
    final options = _presentationOptions;
    final summary = await profileRunner.summarizeArtifact(targetPath);

    if (summary case {'regions': final Object? _}) {
      final prepared = await prepareSessionPresentation(
        profileRunner,
        ProfileRunResult.fromJson(summary),
        options: options,
      );
      if (_printJson) {
        _writeJson(
          sessionPresentationJson(
            prepared.session,
            prepared.overallTree,
            prepared.overallBottomUpTree,
            prepared.overallMethodTable,
            prepared.regionTrees,
            prepared.regionBottomUpTrees,
            prepared.regionMethodTables,
          ),
        );
      } else {
        _writeSessionSummary(
          io,
          prepared.session,
          overallTree: prepared.overallTree,
          overallBottomUpTree: prepared.overallBottomUpTree,
          overallMethodTable: prepared.overallMethodTable,
          regionTrees: prepared.regionTrees,
          regionBottomUpTrees: prepared.regionBottomUpTrees,
          regionMethodTables: prepared.regionMethodTables,
          options: options,
        );
      }
      return _successExitCode;
    }

    if (summary case {'topSelfFrames': final Object? _}) {
      final prepared = await prepareRegionPresentation(
        profileRunner,
        ProfileRegionResult.fromJson(summary),
        options: options,
      );
      if (_printJson) {
        _writeJson(
          regionPresentationJson(
            prepared.region,
            prepared.callTree,
            prepared.bottomUpTree,
            prepared.methodTable,
          ),
        );
      } else {
        _writeRegionSummary(
          io,
          prepared.region,
          callTree: prepared.callTree,
          bottomUpTree: prepared.bottomUpTree,
          methodTable: prepared.methodTable,
          workingDirectory: _workingDirectoryFromRegionPath(prepared.region),
          options: options,
        );
      }
      return _successExitCode;
    }

    line(_jsonEncoder.convert(summary));
    return _successExitCode;
  }
}

class _ExplainCommand extends _ProfilerCommand {
  _ExplainCommand(super.profileRunner) {
    argParser.addOption(
      'profile-id',
      help: 'Profile id to select from a session directory.',
    );
  }

  @override
  String get name => 'explain';

  @override
  String get description =>
      'Explain the hotspots in a session/profile artifact.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      usageException(
        'Explain requires exactly one session directory or profile artifact path.',
      );
    }

    final options = _presentationOptions;
    final explanation = await prepareProfileExplanation(
      profileRunner,
      targetPath: argResults!.rest.single,
      profileId: argResults!['profile-id'] as String?,
      options: options,
    );

    if (_printJson) {
      _writeJson(hotspotExplanationJson(explanation));
    } else {
      _writeHotspotExplanation(io, explanation, options: options);
    }

    return _successExitCode;
  }
}
