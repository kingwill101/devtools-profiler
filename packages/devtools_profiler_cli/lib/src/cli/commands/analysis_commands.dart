import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../../presentation.dart';
import '../../rendering.dart';
import '../constants.dart';
import '../options.dart';
import 'profiler_command.dart';
import 'profile_session_resolution.dart';
import 'profile_target_command.dart';

/// Command that compares two session or profile artifacts.
class CompareCommand extends ProfilerCommand with ProfileSessionResolution {
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
      )
      ..addOption(
        'min-live-bytes',
        help:
            'Re-read raw memory artifacts and include only classes with at '
            'least this many live bytes at the end of each capture window. '
            'Useful for surfacing large retained classes missed by the stored '
            'top-class list.',
      )
      ..addOption(
        'memory-class-limit',
        help:
            'Maximum memory classes to compare. Use 0 for unlimited. '
            'When set, re-reads raw memory artifacts to expand beyond the '
            'stored top-class list.',
      );
  }

  @override
  String get name => 'compare';

  @override
  String get description => 'Compare two session/profile artifacts.';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler compare path/to/baseline path/to/current',
      'devtools-profiler compare --method-table path/to/baseline path/to/current',
      'devtools-profiler compare --min-live-bytes 524288 path/to/baseline path/to/current',
    ],
  );

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      final baselinePath = await _resolveDefaultTarget('baseline');
      final currentPath = await _resolveDefaultTarget('current');
      final options = presentationOptions;
      final memoryClassLimitStr = argResults!['memory-class-limit'] as String?;
      final memoryClassLimitSpecified = memoryClassLimitStr != null;
      final comparison = await prepareProfileComparison(
        profileRunner,
        baselinePath: baselinePath,
        currentPath: currentPath,
        baselineProfileId: argResults!['baseline-profile-id'] as String?,
        currentProfileId: argResults!['current-profile-id'] as String?,
        minLiveBytes: parseNonNegativeInt(
          argResults!['min-live-bytes'] as String?,
          optionName: 'min-live-bytes',
        ),
        memoryClassLimit: parseLimit(
          memoryClassLimitStr,
          optionName: 'memory-class-limit',
        ),
        memoryClassLimitSpecified: memoryClassLimitSpecified,
        options: options,
      );
      if (printJson) {
        writeJson(comparisonPresentationJson(comparison));
      } else {
        writeComparisonSummary(io, comparison, options: options);
      }
      return successExitCode;
    }

    if (argResults!.rest.length != 2) {
      usageException(
        'Compare requires exactly two targets or no targets to compare the two latest stored sessions.',
      );
    }

    final options = presentationOptions;

    final memoryClassLimitStr = argResults!['memory-class-limit'] as String?;
    final memoryClassLimitSpecified = memoryClassLimitStr != null;

    final comparison = await prepareProfileComparison(
      profileRunner,
      baselinePath: argResults!.rest.first,
      currentPath: argResults!.rest.last,
      baselineProfileId: argResults!['baseline-profile-id'] as String?,
      currentProfileId: argResults!['current-profile-id'] as String?,
      minLiveBytes: parseNonNegativeInt(
        argResults!['min-live-bytes'] as String?,
        optionName: 'min-live-bytes',
      ),
      memoryClassLimit: parseLimit(
        memoryClassLimitStr,
        optionName: 'memory-class-limit',
      ),
      memoryClassLimitSpecified: memoryClassLimitSpecified,
      options: options,
    );

    if (printJson) {
      writeJson(comparisonPresentationJson(comparison));
    } else {
      writeComparisonSummary(io, comparison, options: options);
    }

    return successExitCode;
  }

  Future<String> _resolveDefaultTarget(String label) async {
    final sessionsDirectory = defaultSessionsDirectory();
    final sessions = await discoverSessions(sessionsDirectory);
    if (sessions.isEmpty) {
      throw ArgumentError(
        'No explicit profile paths were provided and no stored profiling '
        'sessions were found under "${sessionsDirectory.path}" for $label.',
      );
    }
    if (label == 'baseline') return sessions.first.directory.path;
    if (sessions.length >= 2) return sessions[1].directory.path;
    throw ArgumentError(
      'A second profile target is required and only one stored session is available.',
    );
  }
}

/// Command that analyzes profile trends across multiple artifacts.
class TrendsCommand extends ProfilerCommand with ProfileSessionResolution {
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
  String get invocation => '${runner!.executableName} trends [paths...]';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler trends session-a session-b session-c',
      'devtools-profiler trends --json --profile-id overall',
    ],
  );

  @override
  Future<int> run() async {
    final targetPaths = await _resolveTrendTargetPaths();
    if (targetPaths.length < 2) {
      usageException('Trends requires at least two profile targets.');
    }

    final options = presentationOptions;
    final trends = await prepareProfileTrends(
      profileRunner,
      targetPaths: targetPaths,
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

  Future<List<String>> _resolveTrendTargetPaths() async {
    if (argResults!.rest.isNotEmpty) {
      return argResults!.rest.toList();
    }

    final sessionsDirectory = defaultSessionsDirectory();
    final sessions = await discoverSessions(sessionsDirectory);
    if (sessions.length < 2) {
      throw ArgumentError(
        'No explicit profile paths were provided and fewer than two stored '
        'sessions were found under "${sessionsDirectory.path}".',
      );
    }
    return sessions.take(2).map((session) => session.directory.path).toList();
  }
}

/// Command that inspects one method in a profile.
class InspectCommand extends ProfileTargetCommand {
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
  String get invocation => '${runner!.executableName} inspect [path]';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler inspect --method Parser.parseFile',
      'devtools-profiler inspect --method Parser.parseFile --session-id latest',
      'devtools-profiler inspect --method-id isolate/12345.function.678',
    ],
  );

  @override
  Future<int> run() async {
    final methodId = argResults!['method-id'] as String?;
    final methodName = argResults!['method'] as String?;
    if ((methodId == null || methodId.trim().isEmpty) ==
        (methodName == null || methodName.trim().isEmpty)) {
      usageException(
        'The inspect command requires exactly one of --method or --method-id.\n'
        'Examples:\n'
        '  ${runner!.executableName} inspect --method Parser.parseFile\n'
        '  ${runner!.executableName} inspect --method-id some.function.123',
      );
    }

    final targetPath = await resolveTargetPath();
    final options = presentationOptions;
    final inspection = await prepareProfileMethodInspection(
      profileRunner,
      targetPath: targetPath,
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
class CompareMethodCommand extends ProfilerCommand
    with ProfileSessionResolution {
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
  String get invocation =>
      '${runner!.executableName} compare-method [options] [baseline] [current]';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler compare-method --method Parser.parseFile path/to/baseline path/to/current',
      'devtools-profiler compare-method --method Parser.parseFile',
    ],
  );

  @override
  Future<int> run() async {
    final baselinePath = await _resolveComparisonTarget('baseline');
    final currentPath = await _resolveComparisonTarget('current');
    final options = presentationOptions;
    final comparison = await prepareProfileMethodComparison(
      profileRunner,
      baselinePath: baselinePath,
      currentPath: currentPath,
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

  Future<String> _resolveComparisonTarget(String label) async {
    if (argResults!.rest.length == 2) {
      return label == 'baseline'
          ? argResults!.rest.first
          : argResults!.rest.last;
    }

    if (argResults!.rest.isNotEmpty) {
      usageException(
        'Compare-method requires exactly two targets or no targets to compare the two latest stored sessions.',
      );
    }

    final sessionsDirectory = defaultSessionsDirectory();
    final sessions = await discoverSessions(sessionsDirectory);
    if (sessions.isEmpty) {
      throw ArgumentError(
        'No explicit profile paths were provided and no stored profiling sessions were found for $label.',
      );
    }
    if (label == 'baseline') return sessions.first.directory.path;
    if (sessions.length >= 2) return sessions[1].directory.path;
    throw ArgumentError(
      'A second profile target is required and only one stored session is available.',
    );
  }
}

/// Command that searches methods in one profile.
class SearchMethodsCommand extends ProfileTargetCommand {
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
  String get invocation => '${runner!.executableName} search-methods [path]';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler search-methods --query Parser --sort total',
      'devtools-profiler search-methods --query Parser --json',
    ],
  );

  @override
  Future<int> run() async {
    final targetPath = await resolveTargetPath();
    final options = presentationOptions;
    final search = await prepareProfileMethodSearch(
      profileRunner,
      targetPath: targetPath,
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

/// Command that inspects memory class data in a stored profile artifact.
class InspectClassesCommand extends ProfileTargetCommand {
  /// Creates an inspect-classes command.
  InspectClassesCommand(super.profileRunner) {
    argParser
      ..addOption(
        'class',
        help:
            'Filter to classes whose name contains this query (case-insensitive).',
      )
      ..addOption(
        'min-live-bytes',
        help:
            'Only include classes with at least this many live bytes at the '
            'end of the capture window.',
      )
      ..addOption(
        'limit',
        defaultsTo: '$defaultMemoryClassLimit',
        help: 'Maximum classes to show. Use 0 for unlimited.',
      );
  }

  @override
  String get name => 'inspect-classes';

  @override
  String get description =>
      'Inspect memory class data in a stored session or region artifact.';

  @override
  String get invocation => '${runner!.executableName} inspect-classes [path]';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler inspect-classes path/to/session',
      'devtools-profiler inspect-classes --class LoveColor path/to/session',
      'devtools-profiler inspect-classes --min-live-bytes 1048576 path/to/session',
    ],
  );

  @override
  Future<int> run() async {
    final targetPath = await resolveTargetPath();
    final limitStr = argResults!['limit'] as String;
    final limit = parseLimit(limitStr, optionName: 'limit');

    final inspection = await prepareMemoryClassInspection(
      profileRunner,
      targetPath,
      classQuery: argResults!['class'] as String?,
      minLiveBytes: parseNonNegativeInt(
        argResults!['min-live-bytes'] as String?,
        optionName: 'min-live-bytes',
      ),
      topClassCount: limit ?? 0,
    );

    if (printJson) {
      writeJson(memoryClassInspectionJson(inspection));
    } else {
      writeMemoryClassInspection(io, inspection);
    }

    return successExitCode;
  }
}
