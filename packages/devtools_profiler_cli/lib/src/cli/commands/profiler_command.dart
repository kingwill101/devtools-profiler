import 'package:artisanal/args.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../../presentation.dart';
import '../constants.dart';
import '../options.dart';

/// Base class for profiler commands that expose common presentation options.
abstract class ProfilerCommand extends Command<int> {
  /// Creates a profiler command backed by [profileRunner].
  ProfilerCommand(this.profileRunner) {
    addPresentationOptions(argParser);
  }

  /// The profiler backend used by this command.
  final ProfileRunner profileRunner;

  /// Returns presentation options parsed from the current [argResults].
  ProfilePresentationOptions get presentationOptions =>
      presentationOptionsFrom(argResults!);

  /// Whether to print output as JSON.
  bool get printJson => argResults!['json'] as bool? ?? false;

  /// Writes [value] as indented JSON to the command output.
  void writeJson(Object? value) {
    line(jsonEncoder.convert(value));
  }
}
