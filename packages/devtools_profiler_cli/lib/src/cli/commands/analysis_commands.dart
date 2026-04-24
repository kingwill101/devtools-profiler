import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../../presentation.dart';
import '../../rendering.dart';
import '../constants.dart';
import '../options.dart';
import 'profiler_command.dart';

/// Command that compares two session or profile artifacts.
class CompareCommand extends ProfilerCommand {
  /// Creates a compare command.
  CompareCommand(super.profileRunner) {
    argParser
      ..addOption(
        'baseline-profile-id',
        help: 'Profile id to select from the baseline session directory.',
      )
      ..addOption(
        'current-profile-id',
        help: 'Profile id to select from the current session directory.',
      );
  }

  @override
  String get name => 'compare';

  @override
  String get description => 'Compare two session/profile artifacts.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 2) {
      usageException(
        'Compare requires exactly two targets: a baseline path and a current path.',
      );
    }

    final options = presentationOptions;
    final comparison = await prepareProfileComparison(
      profileRunner,
      baselinePath: argResults!.rest.first,
      currentPath: argResults!.rest.last,
      baselineProfileId: argResults!['baseline-profile-id'] as String?,
      currentProfileId: argResults!['current-profile-id'] as String?,
      options: options,
    );

    if (printJson) {
      writeJson(comparisonPresentationJson(comparison));
    } else {
      writeComparisonSummary(io, comparison, options: options);
    }

    return successExitCode;
  }
}

/// Command that analyzes profile trends across multiple artifacts.
class TrendsCommand extends ProfilerCommand {
  /// Creates a trends command.
  TrendsCommand(super.profileRunner) {
    argParser.addOption(
      'profile-id',
      help: 'Profile id to select from each session directory.',
    );
  }

  @override
  String get name => 'trends';

  @override
  String get description =>
      'Analyze trends across multiple session/profile artifacts.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length < 2) {
      usageException(
        'Trends requires at least two session directories or profile artifact paths.',
      );
    }

    final options = presentationOptions;
    final trends = await prepareProfileTrends(
      profileRunner,
      targetPaths: argResults!.rest,
      profileId: argResults!['profile-id'] as String?,
      options: options,
    );

    if (printJson) {
      writeJson(trendPresentationJson(trends));
    } else {
      writeTrendSummary(io, trends, options: options);
    }

    return successExitCode;
  }
}

/// Command that inspects one method in a profile.
class InspectCommand extends ProfilerCommand {
  /// Creates an inspect command.
  InspectCommand(super.profileRunner) {
    argParser
      ..addOption(
        'profile-id',
        help: 'Profile id to select from a session directory.',
      )
      ..addOption('method-id', help: 'Exact method id to inspect.')
      ..addOption('method', help: 'Method name query to inspect.')
      ..addOption(
        'path-limit',
        defaultsTo: '$defaultMethodPathLimit',
        help:
            'Maximum representative top-down and bottom-up paths to include. Use 0 for unlimited.',
      );
  }

  @override
  String get name => 'inspect';

  @override
  String get description => 'Inspect one method in a session/profile artifact.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      usageException(
        'Inspect requires exactly one session directory or profile artifact path.',
      );
    }

    final options = presentationOptions;
    final inspection = await prepareProfileMethodInspection(
      profileRunner,
      targetPath: argResults!.rest.single,
      profileId: argResults!['profile-id'] as String?,
      methodId: argResults!['method-id'] as String?,
      methodName: argResults!['method'] as String?,
      pathLimit: parseLimit(
        argResults!['path-limit'] as String,
        optionName: 'path-limit',
      ),
      options: options,
    );

    if (printJson) {
      writeJson(methodInspectionJson(inspection));
    } else {
      writeMethodInspection(io, inspection, options: options);
    }

    return successExitCode;
  }
}

/// Command that compares one method across two profiles.
class CompareMethodCommand extends ProfilerCommand {
  /// Creates a compare-method command.
  CompareMethodCommand(super.profileRunner) {
    argParser
      ..addOption(
        'baseline-profile-id',
        help: 'Profile id to select from the baseline session directory.',
      )
      ..addOption(
        'current-profile-id',
        help: 'Profile id to select from the current session directory.',
      )
      ..addOption('method-id', help: 'Exact method id to compare.')
      ..addOption('method', help: 'Method name query to compare.')
      ..addOption(
        'path-limit',
        defaultsTo: '$defaultMethodPathLimit',
        help:
            'Maximum representative top-down and bottom-up paths to include. Use 0 for unlimited.',
      );
  }

  @override
  String get name => 'compare-method';

  @override
  String get description =>
      'Compare one method across two session/profile artifacts.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 2) {
      usageException(
        'Compare-method requires exactly two targets: a baseline path and a current path.',
      );
    }

    final options = presentationOptions;
    final comparison = await prepareProfileMethodComparison(
      profileRunner,
      baselinePath: argResults!.rest.first,
      currentPath: argResults!.rest.last,
      baselineProfileId: argResults!['baseline-profile-id'] as String?,
      currentProfileId: argResults!['current-profile-id'] as String?,
      methodId: argResults!['method-id'] as String?,
      methodName: argResults!['method'] as String?,
      pathLimit: parseLimit(
        argResults!['path-limit'] as String,
        optionName: 'path-limit',
      ),
      relationLimit: options.methodLimit,
      options: options,
    );

    if (printJson) {
      writeJson(methodComparisonJson(comparison));
    } else {
      writeMethodComparison(io, comparison, options: options);
    }

    return successExitCode;
  }
}

/// Command that searches methods in one profile.
class SearchMethodsCommand extends ProfilerCommand {
  /// Creates a search-methods command.
  SearchMethodsCommand(super.profileRunner) {
    argParser
      ..addOption(
        'profile-id',
        help: 'Profile id to select from a session directory.',
      )
      ..addOption(
        'query',
        help: 'Optional method query matched against name, id, and location.',
      )
      ..addOption(
        'sort',
        defaultsTo: ProfileMethodSearchSort.total.name,
        allowed: [for (final sort in ProfileMethodSearchSort.values) sort.name],
        help: 'Order the results by total or self cost.',
      )
      ..addOption(
        'limit',
        defaultsTo: '$defaultFrameLimit',
        help: 'Maximum methods to return. Use 0 for unlimited.',
      );
  }

  @override
  String get name => 'search-methods';

  @override
  String get description => 'Search methods in a session/profile artifact.';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      usageException(
        'Search-methods requires exactly one session directory or profile artifact path.',
      );
    }

    final options = presentationOptions;
    final search = await prepareProfileMethodSearch(
      profileRunner,
      targetPath: argResults!.rest.single,
      profileId: argResults!['profile-id'] as String?,
      query: argResults!['query'] as String?,
      sortBy: ProfileMethodSearchSort.parse(argResults!['sort'] as String),
      limit: parseLimit(argResults!['limit'] as String, optionName: 'limit'),
      options: options,
    );

    if (printJson) {
      writeJson(methodSearchJson(search));
    } else {
      writeMethodSearch(io, search, options: options);
    }

    return successExitCode;
  }
}
