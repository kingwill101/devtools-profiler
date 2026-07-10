import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../constants.dart';
import 'profiler_command.dart';

/// Command that discovers running Flutter/Dart apps on the local machine.
class DiscoverCommand extends ProfilerCommand {
  /// Creates a discover command.
  DiscoverCommand(super.profileRunner);

  @override
  String get name => 'discover';

  @override
  String get description =>
      'Discover running Flutter/Dart apps with VM service URIs.';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const ['devtools-profiler discover', 'devtools-profiler discover --json'],
  );

  @override
  Future<int> run() async {
    final apps = await discoverActiveApps();

    if (apps.isEmpty) {
      warn(
        'No running Flutter or Dart applications were discovered on this '
        'machine. Make sure your app is running in debug or profile mode.',
      );
      return successExitCode;
    }

    if (printJson) {
      line(jsonEncoder.convert([for (final app in apps) app.toJson()]));
      return successExitCode;
    }

    io.title('Discovered Applications');
    io.table(
      headers: const ['Project', 'VM Service URI'],
      rows: [
        for (final app in apps) [app.projectName, app.vmServiceUri],
      ],
    );

    comment(
      'Use `devtools-profiler attach --duration <s> <uri>` to profile one of '
      'these apps, or `devtools-profiler attach --duration <s>` when only one '
      'app is running.',
    );

    return successExitCode;
  }
}
