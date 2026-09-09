import 'package:artisanal/args.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../../presentation.dart';
import '../constants.dart';
import '../options.dart';

/// Base class for profiler commands that expose common presentation options.
abstract class ProfilerCommand extends Command<int> {
  /// Creates a profiler command backed by [profileRunner].
  ///
  /// When [includePresentationOptions] is false, presentation arguments are
  /// omitted. Subclasses must not read [presentationOptions], [printJson],
  /// or [printCsv].
  ProfilerCommand(
    this.profileRunner, {
    bool includePresentationOptions = true,
  }) {
    if (includePresentationOptions) addPresentationOptions(argParser);
  }

  /// The profiler backend used by this command.
  final ProfileRunner profileRunner;

  /// Rejects ambiguous formats and formats without an implemented renderer.
  void validateOutputFormat(ArgResults arguments) {
    if (!argParser.options.containsKey('json')) return;
    final json = arguments['json'] as bool;
    final csv = arguments['csv'] as bool;
    if (json && csv) usageException('Pass either --json or --csv, not both.');
    if (csv &&
        !const {'summarize', 'compare', 'regress', 'trends'}.contains(name)) {
      usageException('$name does not support --csv.');
    }
    if (json && const {'replay', 'annotate', 'mcp'}.contains(name)) {
      usageException('$name does not support --json.');
    }
  }

  /// Returns presentation options parsed from the current [argResults].
  ProfilePresentationOptions get presentationOptions =>
      presentationOptionsFrom(argResults!);

  /// Whether to print output as JSON.
  bool get printJson => argResults!['json'] as bool? ?? false;

  /// Whether to print output as compact CSV.
  bool get printCsv => argResults!['csv'] as bool? ?? false;

  /// Writes [value] as indented JSON to the command output.
  void writeJson(Object? value) {
    line(jsonEncoder.convert(value));
  }
}
