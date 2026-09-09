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
  String get description =>
      'Compare session/profile artifacts pairwise or across multiple sessions.';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler compare path/to/baseline path/to/current',
      'devtools-profiler compare --method-table path/to/baseline path/to/current',
      'devtools-profiler compare --min-live-bytes 524288 path/to/baseline path/to/current',
      'devtools-profiler compare session-a session-b session-c',
    ],
  );

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      final baselinePath = await _resolveDefaultTarget('baseline');
      final currentPath = await _resolveDefaultTarget('current');
      return _comparePair(baselinePath, currentPath);
    }

    if (argResults!.rest.length == 2) {
      final baselinePath = await resolveSessionOrPath(argResults!.rest.first);
      final currentPath = await resolveSessionOrPath(argResults!.rest.last);
      return _comparePair(baselinePath, currentPath);
    }

    // 3+ args: multi-compare mode
    final prepared = await prepareProfileFrameColumns(
      profileRunner,
      paths: [
        for (final arg in argResults!.rest) await resolveSessionOrPath(arg),
      ],
      options: presentationOptions,
    );
    final columns = prepared.columns;

    if (printJson) {
      writeJson(
        frameColumnsJson(
          columns,
          warnings: prepared.warnings,
          frameLimit: presentationOptions.frameLimit,
        ),
      );
    } else if (printCsv) {
      writeCsvMultiCompare(
        line,
        columns,
        frameLimit: presentationOptions.frameLimit,
      );
    } else {
      for (final warning in prepared.warnings) warn(warning);
      writeMultiCompareSummary(io, columns, options: presentationOptions);
    }

    return successExitCode;
  }

  Future<int> _comparePair(String baselinePath, String currentPath) async {
    final options = presentationOptions;
    final memoryClassLimit = argResults!['memory-class-limit'] as String?;
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
        memoryClassLimit,
        optionName: 'memory-class-limit',
      ),
      memoryClassLimitSpecified: memoryClassLimit != null,
      options: options,
    );
    if (printJson) {
      writeJson(comparisonPresentationJson(comparison));
    } else if (printCsv) {
      writeCsvComparisonFrames(line, comparison.comparison);
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
    return selectComparisonSession(
      sessions,
      baseline: label == 'baseline',
    ).directory.path;
  }
}

/// Exit code returned when regressions are detected by the regress command.
///
/// This allows the command to be used in CI pipelines: a non-zero exit
/// signals that the current profile regressed against the baseline.
const regressionExitCode = 1;

/// Command that compares the current profile against a known-good baseline
/// and reports regressions.
///
/// Use this in CI or after profiling workflow to quickly check whether a
/// change slowed down the target. Exits with code [regressionExitCode] when
/// regressions are found, unless `--warn-only` is set.
class RegressCommand extends ProfilerCommand with ProfileSessionResolution {
  /// Creates a regress command.
  RegressCommand(super.profileRunner) {
    argParser
      ..addOption(
        'baseline-profile-id',
        help: 'Profile id to select from the baseline session directory.',
      )
      ..addOption(
        'current-profile-id',
        help: 'Profile id to select from the current session directory.',
      )
      ..addFlag(
        'warn-only',
        negatable: false,
        help:
            'Print regressions as warnings but always exit with code 0. '
            'Useful for development workflows where regressions are expected.',
      )
      ..addOption(
        'min-live-bytes',
        help:
            'Re-read raw memory artifacts and include only classes with at '
            'least this many live bytes at the end of each capture window.',
      )
      ..addOption(
        'memory-class-limit',
        help: 'Maximum memory classes to compare. Use 0 for unlimited.',
      );
  }

  @override
  String get name => 'regress';

  @override
  String get description =>
      'Compare the current profile against a baseline and report regressions. '
      'Useful for CI and post-change verification.';

  @override
  String get invocation =>
      '${runner!.executableName} regress [options] <baseline> [current]';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler regress path/to/baseline',
      'devtools-profiler regress --warn-only path/to/baseline',
      'devtools-profiler regress 0712060003-8c410 0711235455-ebfb3',
      'devtools-profiler regress --min-live-bytes 524288 path/to/baseline',
    ],
  );

  @override
  Future<int> run() async {
    final options = presentationOptions;
    final warnOnly = argResults!['warn-only'] as bool? ?? false;

    // Resolve baseline (first positional arg).
    if (argResults!.rest.isEmpty) {
      usageException(
        'The regress command requires at least a baseline target.\n'
        'Examples:\n'
        '  ${runner!.executableName} regress path/to/baseline-session\n'
        '  ${runner!.executableName} regress 0712060003-8c410',
      );
    }

    final baselinePath = await resolveSessionOrPath(argResults!.rest.first);

    // Resolve current path: second positional arg or latest stored session.
    String currentPath;
    if (argResults!.rest.length >= 2) {
      currentPath = await resolveSessionOrPath(argResults!.rest[1]);
    } else {
      final sessionsDir = defaultSessionsDirectory();
      final sessions = await discoverSessions(sessionsDir);
      if (sessions.isEmpty) {
        throw ArgumentError(
          'No stored profiling sessions found and no current target was '
          'provided. Pass a current target path or session id.',
        );
      }
      currentPath = sessions.first.directory.path;
    }

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

    final hasRegressions = comparison.regressions.insights.isNotEmpty;

    if (printJson) {
      final json = comparisonPresentationJson(comparison);
      if (!warnOnly) {
        json['regressionExitCode'] = regressionExitCode;
      }
      writeJson(json);
    } else if (printCsv) {
      writeCsvComparisonFrames(line, comparison.comparison);
    } else {
      if (hasRegressions) {
        line('Regression check: REGRESSIONS DETECTED');
      } else {
        line('Regression check: PASSED');
      }
      writeComparisonSummary(io, comparison, options: options);
    }

    if (hasRegressions && !warnOnly) {
      return regressionExitCode;
    }
    return successExitCode;
  }
}

/// Command that analyzes profile trends across multiple artifacts.
class TrendsCommand extends ProfilerCommand with ProfileSessionResolution {
  /// Creates a trends command.
  TrendsCommand(super.profileRunner) {
    argParser
      ..addOption(
        'profile-id',
        help: 'Profile id to select from each session directory.',
      )
      ..addOption(
        'last',
        help:
            'Use the N most recent stored sessions. '
            'Ignored when explicit paths are provided.',
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
      'devtools-profiler trends --last 5',
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
    } else if (printCsv) {
      writeCsvTrendSeries(line, trends.trends);
    } else {
      writeTrendSummary(io, trends, options: options);
    }

    return successExitCode;
  }

  Future<List<String>> _resolveTrendTargetPaths() async {
    final last = argResults!['last'] as String?;
    final requestedCount = last == null ? null : int.tryParse(last);
    if (last != null && (requestedCount == null || requestedCount <= 0)) {
      usageException('The --last option must be a positive integer.');
    }
    if (argResults!.rest.isNotEmpty) {
      return [
        for (final arg in argResults!.rest) await resolveSessionOrPath(arg),
      ];
    }

    final sessionsDirectory = defaultSessionsDirectory();
    final sessions = await discoverSessions(sessionsDirectory);
    if (sessions.length < 2) {
      throw ArgumentError(
        'No explicit profile paths were provided and fewer than two stored '
        'sessions were found under "${sessionsDirectory.path}".',
      );
    }

    if (requestedCount != null) {
      final count = requestedCount < sessions.length
          ? requestedCount
          : sessions.length;
      return sessions.take(count).map((s) => s.directory.path).toList();
    }

    return sessions.take(2).map((s) => s.directory.path).toList();
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
            'Maximum representative top-down and bottom-up paths to include. '
            'Use 0 for unlimited.',
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
            'Maximum representative top-down and bottom-up paths to include. '
            'Use 0 for unlimited.',
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
      final input = label == 'baseline'
          ? argResults!.rest.first
          : argResults!.rest.last;
      return resolveSessionOrPath(input);
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
    return selectComparisonSession(
      sessions,
      baseline: label == 'baseline',
    ).directory.path;
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
            'Filter to classes whose name contains this query '
            '(case-insensitive).',
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
