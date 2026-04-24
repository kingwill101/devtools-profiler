
part of '../cli.dart';

class _CompareCommand extends _ProfilerCommand {
  _CompareCommand(super.profileRunner) {
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

    final options = _presentationOptions;
    final comparison = await prepareProfileComparison(
      profileRunner,
      baselinePath: argResults!.rest.first,
      currentPath: argResults!.rest.last,
      baselineProfileId: argResults!['baseline-profile-id'] as String?,
      currentProfileId: argResults!['current-profile-id'] as String?,
      options: options,
    );

    if (_printJson) {
      _writeJson(comparisonPresentationJson(comparison));
    } else {
      _writeComparisonSummary(io, comparison, options: options);
    }

    return _successExitCode;
  }
}

class _TrendsCommand extends _ProfilerCommand {
  _TrendsCommand(super.profileRunner) {
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

    final options = _presentationOptions;
    final trends = await prepareProfileTrends(
      profileRunner,
      targetPaths: argResults!.rest,
      profileId: argResults!['profile-id'] as String?,
      options: options,
    );

    if (_printJson) {
      _writeJson(trendPresentationJson(trends));
    } else {
      _writeTrendSummary(io, trends, options: options);
    }

    return _successExitCode;
  }
}

class _InspectCommand extends _ProfilerCommand {
  _InspectCommand(super.profileRunner) {
    argParser
      ..addOption(
        'profile-id',
        help: 'Profile id to select from a session directory.',
      )
      ..addOption(
        'method-id',
        help: 'Exact method id to inspect.',
      )
      ..addOption(
        'method',
        help: 'Method name query to inspect.',
      )
      ..addOption(
        'path-limit',
        defaultsTo: '$_defaultMethodPathLimit',
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

    final options = _presentationOptions;
    final inspection = await prepareProfileMethodInspection(
      profileRunner,
      targetPath: argResults!.rest.single,
      profileId: argResults!['profile-id'] as String?,
      methodId: argResults!['method-id'] as String?,
      methodName: argResults!['method'] as String?,
      pathLimit: _parseLimit(
        argResults!['path-limit'] as String,
        optionName: 'path-limit',
      ),
      options: options,
    );

    if (_printJson) {
      _writeJson(methodInspectionJson(inspection));
    } else {
      _writeMethodInspection(io, inspection, options: options);
    }

    return _successExitCode;
  }
}

class _CompareMethodCommand extends _ProfilerCommand {
  _CompareMethodCommand(super.profileRunner) {
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
        'method-id',
        help: 'Exact method id to compare.',
      )
      ..addOption(
        'method',
        help: 'Method name query to compare.',
      )
      ..addOption(
        'path-limit',
        defaultsTo: '$_defaultMethodPathLimit',
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

    final options = _presentationOptions;
    final comparison = await prepareProfileMethodComparison(
      profileRunner,
      baselinePath: argResults!.rest.first,
      currentPath: argResults!.rest.last,
      baselineProfileId: argResults!['baseline-profile-id'] as String?,
      currentProfileId: argResults!['current-profile-id'] as String?,
      methodId: argResults!['method-id'] as String?,
      methodName: argResults!['method'] as String?,
      pathLimit: _parseLimit(
        argResults!['path-limit'] as String,
        optionName: 'path-limit',
      ),
      relationLimit: options.methodLimit,
      options: options,
    );

    if (_printJson) {
      _writeJson(methodComparisonJson(comparison));
    } else {
      _writeMethodComparison(io, comparison, options: options);
    }

    return _successExitCode;
  }
}

class _SearchMethodsCommand extends _ProfilerCommand {
  _SearchMethodsCommand(super.profileRunner) {
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

    final options = _presentationOptions;
    final search = await prepareProfileMethodSearch(
      profileRunner,
      targetPath: argResults!.rest.single,
      profileId: argResults!['profile-id'] as String?,
      query: argResults!['query'] as String?,
      sortBy: ProfileMethodSearchSort.parse(argResults!['sort'] as String),
      limit: _parseLimit(
        argResults!['limit'] as String,
        optionName: 'limit',
      ),
      options: options,
    );

    if (_printJson) {
      _writeJson(methodSearchJson(search));
    } else {
      _writeMethodSearch(io, search, options: options);
    }

    return _successExitCode;
  }
}
