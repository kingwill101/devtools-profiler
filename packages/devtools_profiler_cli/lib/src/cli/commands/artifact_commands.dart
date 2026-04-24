import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../../presentation.dart';
import '../../rendering.dart';
import '../constants.dart';
import 'profiler_command.dart';

/// Command that summarizes a session directory or profile artifact.
class SummarizeCommand extends ProfilerCommand {
  /// Creates a summarize command.
  SummarizeCommand(super.profileRunner);

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
    final options = presentationOptions;
    final summary = await profileRunner.summarizeArtifact(targetPath);

    if (summary case {'regions': final Object? _}) {
      final prepared = await prepareSessionPresentation(
        profileRunner,
        ProfileRunResult.fromJson(summary),
        options: options,
      );
      if (printJson) {
        writeJson(
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
        writeSessionSummary(
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
      return successExitCode;
    }

    if (summary case {'topSelfFrames': final Object? _}) {
      final prepared = await prepareRegionPresentation(
        profileRunner,
        ProfileRegionResult.fromJson(summary),
        options: options,
      );
      if (printJson) {
        writeJson(
          regionPresentationJson(
            prepared.region,
            prepared.callTree,
            prepared.bottomUpTree,
            prepared.methodTable,
          ),
        );
      } else {
        writeRegionSummary(
          io,
          prepared.region,
          callTree: prepared.callTree,
          bottomUpTree: prepared.bottomUpTree,
          methodTable: prepared.methodTable,
          workingDirectory: workingDirectoryFromRegionPath(prepared.region),
          options: options,
        );
      }
      return successExitCode;
    }

    line(jsonEncoder.convert(summary));
    return successExitCode;
  }
}

/// Command that explains likely hotspots in a stored profile.
class ExplainCommand extends ProfilerCommand {
  /// Creates an explain command.
  ExplainCommand(super.profileRunner) {
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

    final options = presentationOptions;
    final explanation = await prepareProfileExplanation(
      profileRunner,
      targetPath: argResults!.rest.single,
      profileId: argResults!['profile-id'] as String?,
      options: options,
    );

    if (printJson) {
      writeJson(hotspotExplanationJson(explanation));
    } else {
      writeHotspotExplanation(io, explanation, options: options);
    }

    return successExitCode;
  }
}
