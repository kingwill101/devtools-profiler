import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../../presentation.dart';
import '../../rendering.dart';
import '../constants.dart';
import 'profile_target_command.dart';

/// Command that summarizes a session directory or profile artifact.
class SummarizeCommand extends ProfileTargetCommand {
  /// Creates a summarize command.
  SummarizeCommand(super.profileRunner);

  @override
  String get name => 'summarize';

  @override
  String get description => 'Summarize a session directory or artifact.';

  @override
  String get invocation => '${runner!.executableName} summarize [path]';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler summarize',
      'devtools-profiler summarize --call-tree --method-table',
      'devtools-profiler summarize --hide-sdk --hide-runtime-helpers path/to/session',
    ],
  );

  @override
  Future<int> run() async {
    final targetPath = await resolveTargetPath();
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
            prepared.overallAllocAttribution,
          ),
        );
      } else if (printCsv) {
        final overall = prepared.session.overallProfile;
        if (overall != null) {
          writeCsvRegionFrames(line, overall);
        }
        for (final region in prepared.session.regions) {
          writeCsvRegionFrames(line, region);
        }
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
          allocAttribution: prepared.overallAllocAttribution,
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
            warnings: prepared.warnings,
            allocAttribution: prepared.allocAttribution,
          ),
        );
      } else if (printCsv) {
        writeCsvRegionFrames(line, prepared.region);
      } else {
        writeRegionSummary(
          io,
          prepared.region,
          callTree: prepared.callTree,
          bottomUpTree: prepared.bottomUpTree,
          methodTable: prepared.methodTable,
          workingDirectory: workingDirectoryFromRegionPath(prepared.region),
          warnings: prepared.warnings,
          allocAttribution: prepared.allocAttribution,
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
class ExplainCommand extends ProfileTargetCommand {
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
  String get invocation => '${runner!.executableName} explain [path]';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler explain --profile-id overall',
      'devtools-profiler explain --hide-sdk',
    ],
  );

  @override
  Future<int> run() async {
    final targetPath = await resolveTargetPath();
    final options = presentationOptions;
    final explanation = await prepareProfileExplanation(
      profileRunner,
      targetPath: targetPath,
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
