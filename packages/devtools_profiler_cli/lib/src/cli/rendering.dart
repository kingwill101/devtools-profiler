
part of '../cli.dart';

void _writeSessionSummary(
  Console console,
  ProfileRunResult session, {
  ProfileCallTree? overallTree,
  ProfileCallTree? overallBottomUpTree,
  ProfileMethodTable? overallMethodTable,
  Map<String, ProfileCallTree> regionTrees = const {},
  Map<String, ProfileCallTree> regionBottomUpTrees = const {},
  Map<String, ProfileMethodTable> regionMethodTables = const {},
  required ProfilePresentationOptions options,
}) {
  console.title('Profiler Session');
  console.components.definitionList({
    'Session': session.sessionId,
    'Exit code': session.exitCode,
    'Command': session.command.join(' '),
    'Working directory': session.workingDirectory,
    'Artifacts': session.artifactDirectory,
    'Capture kinds': _formatCaptureKinds(session.supportedCaptureKinds),
    'Isolate scopes': _formatIsolateScopes(session.supportedIsolateScopes),
    'Whole session': switch (session.overallProfile) {
      final ProfileRegionResult profile when profile.error == null =>
        'captured',
      final ProfileRegionResult _ => 'error',
      _ => 'unavailable',
    },
    if (session.vmServiceUri != null) 'VM service': session.vmServiceUri,
  });

  final overallProfile = session.overallProfile;
  if (overallProfile == null && session.regions.isEmpty) {
    console.warn('No profile data was captured.');
  }
  if (overallProfile == null && session.regions.isNotEmpty) {
    console.warn('Whole-session profiling was unavailable for this run.');
  }

  if (overallProfile != null) {
    _writeRegionDetails(
      console,
      overallProfile,
      callTree: overallTree,
      bottomUpTree: overallBottomUpTree,
      methodTable: overallMethodTable,
      heading: 'Whole Session',
      includeNameField: false,
      workingDirectory: session.workingDirectory,
      options: options,
    );
  }

  if (session.regions.isNotEmpty) {
    console.section('Regions');
    console.table(
      headers: const [
        'Region',
        'Parent',
        'Duration',
        'Samples',
        'Top Self',
        'Status',
      ],
      rows: [
        for (final region in session.regions)
          [
            region.name,
            region.parentRegionId ?? '-',
            _formatMicros(region.durationMicros),
            region.sampleCount,
            _topFrameName(region.topSelfFrames),
            region.error == null ? 'captured' : 'error',
          ],
      ],
    );

    for (final region
        in session.regions.where((region) => region.error != null)) {
      console.error('${region.name}: ${region.error}');
    }
  } else if (overallProfile != null) {
    console.warn('No explicit profile regions were captured.');
  }

  if (session.warnings.isNotEmpty) {
    console.section('Warnings');
    console.components.bulletList(session.warnings);
  }

  if (session.regions.isNotEmpty) {
    console.section('Region Details');
    for (final region in session.regions) {
      _writeRegionDetails(
        console,
        region,
        callTree: regionTrees[region.regionId],
        bottomUpTree: regionBottomUpTrees[region.regionId],
        methodTable: regionMethodTables[region.regionId],
        heading: 'Region: ${region.name}',
        includeNameField: false,
        workingDirectory: session.workingDirectory,
        options: options,
      );
    }
  }
}

void _writeRegionSummary(
  Console console,
  ProfileRegionResult region, {
  ProfileCallTree? callTree,
  ProfileCallTree? bottomUpTree,
  ProfileMethodTable? methodTable,
  String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  console.title('Region Summary');
  _writeRegionDetails(
    console,
    region,
    callTree: callTree,
    bottomUpTree: bottomUpTree,
    methodTable: methodTable,
    workingDirectory: workingDirectory,
    options: options,
  );
}

void _writeComparisonSummary(
  Console console,
  PreparedProfileComparison comparison, {
  required ProfilePresentationOptions options,
}) {
  final baseline = comparison.baseline.presentation.region;
  final current = comparison.current.presentation.region;
  final delta = comparison.comparison;
  console.title('Profile Comparison');
  console.components.definitionList({
    'Baseline path': comparison.baseline.path,
    'Current path': comparison.current.path,
    'Baseline target':
        '${comparison.baseline.selectedProfileId} (${baseline.name})',
    'Current target':
        '${comparison.current.selectedProfileId} (${current.name})',
    'Baseline kind': comparison.baseline.inputKind,
    'Current kind': comparison.current.inputKind,
    if (comparison.baseline.sessionId != null)
      'Baseline session': comparison.baseline.sessionId,
    if (comparison.current.sessionId != null)
      'Current session': comparison.current.sessionId,
  });

  console.section('Delta Summary');
  console.table(
    headers: const ['Metric', 'Baseline', 'Current', 'Delta', 'Change'],
    rows: [
      [
        'Duration',
        _formatMicros(delta.durationMicros.baseline.toInt()),
        _formatMicros(delta.durationMicros.current.toInt()),
        _formatSignedMicros(delta.durationMicros.delta.toInt()),
        _formatPercentChange(delta.durationMicros),
      ],
      [
        'Samples',
        _formatCount(delta.sampleCount.baseline),
        _formatCount(delta.sampleCount.current),
        _formatSignedCount(delta.sampleCount.delta.toInt()),
        _formatPercentChange(delta.sampleCount),
      ],
      [
        'Sample period',
        _formatMicros(delta.samplePeriodMicros.baseline.toInt()),
        _formatMicros(delta.samplePeriodMicros.current.toInt()),
        _formatSignedMicros(delta.samplePeriodMicros.delta.toInt()),
        _formatPercentChange(delta.samplePeriodMicros),
      ],
    ],
  );

  _writeRegressionInsights(console, comparison.regressions);

  if (delta.warnings.isNotEmpty) {
    console.section('Warnings');
    console.components.bulletList(delta.warnings);
  }

  _writeFrameDeltaTable(
    console,
    title: 'Top Self Frame Deltas',
    frames: delta.topSelfFrames,
    workingDirectory: _workingDirectoryFromRegionPath(baseline),
    options: options,
  );
  _writeFrameDeltaTable(
    console,
    title: 'Top Total Frame Deltas',
    frames: delta.topTotalFrames,
    workingDirectory: _workingDirectoryFromRegionPath(baseline),
    options: options,
  );
  _writeMethodDeltaTable(
    console,
    methods: delta.methods,
    workingDirectory: _workingDirectoryFromRegionPath(baseline),
    options: options,
  );
  _writeMemoryDeltaSummary(
    console,
    delta.memory,
    workingDirectory: _workingDirectoryFromRegionPath(baseline),
    options: options,
  );

  if (options.includeCallTree ||
      options.includeBottomUpTree ||
      options.includeMethodTable) {
    _writeRegionDetails(
      console,
      baseline,
      callTree: comparison.baseline.presentation.callTree,
      bottomUpTree: comparison.baseline.presentation.bottomUpTree,
      methodTable: comparison.baseline.presentation.methodTable,
      heading: 'Baseline Profile',
      workingDirectory: _workingDirectoryFromRegionPath(baseline),
      options: options,
    );
    _writeRegionDetails(
      console,
      current,
      callTree: comparison.current.presentation.callTree,
      bottomUpTree: comparison.current.presentation.bottomUpTree,
      methodTable: comparison.current.presentation.methodTable,
      heading: 'Current Profile',
      workingDirectory: _workingDirectoryFromRegionPath(current),
      options: options,
    );
  }
}

void _writeHotspotExplanation(
  Console console,
  PreparedProfileExplanation explanation, {
  required ProfilePresentationOptions options,
}) {
  final region = explanation.target.presentation.region;
  console.title('Hotspot Explanation');
  console.components.definitionList({
    'Path': explanation.target.path,
    'Target': '${explanation.target.selectedProfileId} (${region.name})',
    'Kind': explanation.target.inputKind,
    if (explanation.target.sessionId != null)
      'Session': explanation.target.sessionId,
    'Status': explanation.hotspots.status,
  });

  console.section('Hotspot Insights');
  if (explanation.hotspots.insights.isEmpty) {
    console
        .warn('No strong hotspots were detected from the current heuristics.');
  } else {
    console.components.bulletList([
      for (final insight in explanation.hotspots.insights)
        _hotspotInsightLine(
          insight,
          workingDirectory: _workingDirectoryFromRegionPath(region),
          options: options,
        ),
    ]);
  }

  if (explanation.hotspots.warnings.isNotEmpty) {
    console.section('Warnings');
    console.components.bulletList(explanation.hotspots.warnings);
  }

  _writeRegionDetails(
    console,
    region,
    callTree: explanation.target.presentation.callTree,
    bottomUpTree: explanation.target.presentation.bottomUpTree,
    methodTable: explanation.target.presentation.methodTable,
    heading: 'Profile Summary',
    workingDirectory: _workingDirectoryFromRegionPath(region),
    options: options.copyWith(includeMethodTable: true),
  );
}

void _writeMethodInspection(
  Console console,
  PreparedProfileMethodInspection inspection, {
  required ProfilePresentationOptions options,
}) {
  final region = inspection.target.presentation.region;
  final result = inspection.inspection;
  console.title('Method Inspection');
  console.components.definitionList({
    'Path': inspection.target.path,
    'Target': '${inspection.target.selectedProfileId} (${region.name})',
    'Kind': inspection.target.inputKind,
    if (inspection.target.sessionId != null)
      'Session': inspection.target.sessionId,
    'Query': result.query,
    'Query kind': result.queryKind,
    'Status': result.status.name,
  });

  if (result.message != null && result.message!.isNotEmpty) {
    console.section('Details');
    console.warn(result.message!);
  }

  final method = result.method;
  if (method != null) {
    final workingDirectory = _workingDirectoryFromRegionPath(region);
    console.section('Method Summary');
    console.components.definitionList({
      'Method ID': method.methodId,
      'Name': method.name,
      'Kind': method.kind,
      'Self': _formatPercent(method.selfPercent),
      'Total': _formatPercent(method.totalPercent),
      'Source': _displayLocation(
        method.location,
        fullLocations: _fullLocationsEnabled(options),
        workingDirectory: workingDirectory,
      ),
    });

    if (method.callers.isNotEmpty) {
      console.section('Callers');
      console.table(
        headers: const ['Method', 'Samples', 'Percent', 'Source'],
        rows: [
          for (final caller in method.callers)
            [
              caller.name,
              caller.sampleCount,
              _formatPercent(caller.percent),
              _displayLocation(
                caller.location,
                fullLocations: _fullLocationsEnabled(options),
                workingDirectory: workingDirectory,
              ),
            ],
        ],
      );
    }

    if (method.callees.isNotEmpty) {
      console.section('Callees');
      console.table(
        headers: const ['Method', 'Samples', 'Percent', 'Source'],
        rows: [
          for (final callee in method.callees)
            [
              callee.name,
              callee.sampleCount,
              _formatPercent(callee.percent),
              _displayLocation(
                callee.location,
                fullLocations: _fullLocationsEnabled(options),
                workingDirectory: workingDirectory,
              ),
            ],
        ],
      );
    }

    _writeMethodPaths(
      console,
      title: 'Top Down Paths',
      paths: result.topDownPaths,
      workingDirectory: workingDirectory,
      options: options,
    );
    _writeMethodPaths(
      console,
      title: 'Bottom Up Paths',
      paths: result.bottomUpPaths,
      workingDirectory: workingDirectory,
      options: options,
    );
  }

  if (result.candidates.isNotEmpty) {
    final workingDirectory = _workingDirectoryFromRegionPath(region);
    console.section('Candidates');
    console.table(
      headers: const ['Method', 'Method ID', 'Self', 'Total', 'Source'],
      rows: [
        for (final candidate in result.candidates)
          [
            candidate.name,
            candidate.methodId,
            _formatPercent(candidate.selfPercent),
            _formatPercent(candidate.totalPercent),
            _displayLocation(
              candidate.location,
              fullLocations: _fullLocationsEnabled(options),
              workingDirectory: workingDirectory,
            ),
          ],
      ],
    );
  }
}

void _writeMethodSearch(
  Console console,
  PreparedProfileMethodSearch search, {
  required ProfilePresentationOptions options,
}) {
  final region = search.target.presentation.region;
  final result = search.search;
  final workingDirectory = _workingDirectoryFromRegionPath(region);
  console.title('Method Search');
  console.components.definitionList({
    'Path': search.target.path,
    'Target': '${search.target.selectedProfileId} (${region.name})',
    'Kind': search.target.inputKind,
    if (search.target.sessionId != null) 'Session': search.target.sessionId,
    'Query': result.query?.isNotEmpty == true ? result.query : '(all methods)',
    'Sort': result.sortBy.name,
    'Status': result.status.name,
    'Matches': '${result.methods.length} of ${result.totalMatches}',
    'Truncated': result.truncated ? 'yes' : 'no',
  });

  if (result.message != null && result.message!.isNotEmpty) {
    console.section('Details');
    console.warn(result.message!);
  }

  if (result.methods.isEmpty) {
    console.section('Matches');
    console.warn('No methods matched the current query.');
    return;
  }

  console.section('Matches');
  console.table(
    headers: const ['Method', 'Method ID', 'Self', 'Total', 'Source'],
    rows: [
      for (final method in result.methods)
        [
          method.name,
          method.methodId,
          _formatPercent(method.selfPercent),
          _formatPercent(method.totalPercent),
          _displayLocation(
            method.location,
            fullLocations: _fullLocationsEnabled(options),
            workingDirectory: workingDirectory,
          ),
        ],
    ],
  );

  if (result.truncated) {
    console.warn(
      'Results were truncated. Increase --limit to inspect more matches.',
    );
  }
}

void _writeMethodComparison(
  Console console,
  PreparedProfileMethodComparison comparison, {
  required ProfilePresentationOptions options,
}) {
  console.title('Method Comparison');
  console.components.definitionList({
    'Baseline path': comparison.baseline.path,
    'Current path': comparison.current.path,
    'Query': comparison.comparison.query,
    'Query kind': comparison.comparison.queryKind,
    'Status': comparison.comparison.status.name,
  });

  _writeMethodComparisonInspectionSummary(
    console,
    title: 'Baseline',
    target: comparison.baseline,
    inspection: comparison.comparison.baseline,
    options: options,
  );
  _writeMethodComparisonInspectionSummary(
    console,
    title: 'Current',
    target: comparison.current,
    inspection: comparison.comparison.current,
    options: options,
  );

  final methodDelta = comparison.comparison.methodDelta;
  if (methodDelta != null) {
    console.section('Method Delta');
    console.components.definitionList({
      'Method': methodDelta.name,
      'Method ID': methodDelta.methodId,
      'Source': _displayLocation(
        methodDelta.location,
        fullLocations: _fullLocationsEnabled(options),
        workingDirectory: null,
      ),
      'Self delta':
          '${_formatSignedCount(methodDelta.selfSamples.delta.toInt())} samples',
      'Total delta':
          '${_formatSignedCount(methodDelta.totalSamples.delta.toInt())} samples',
      'Self percent delta':
          _formatSignedPercent(methodDelta.selfPercent.delta.toDouble()),
      'Total percent delta':
          _formatSignedPercent(methodDelta.totalPercent.delta.toDouble()),
    });
  }

  _writeMethodRelationDeltas(
    console,
    title: 'Caller Deltas',
    deltas: comparison.comparison.callerDeltas,
    options: options,
  );
  _writeMethodRelationDeltas(
    console,
    title: 'Callee Deltas',
    deltas: comparison.comparison.calleeDeltas,
    options: options,
  );

  if (comparison.comparison.warnings.isNotEmpty) {
    console.section('Warnings');
    console.components.bulletList(comparison.comparison.warnings);
  }
}

void _writeTrendSummary(
  Console console,
  PreparedProfileTrends trends, {
  required ProfilePresentationOptions options,
}) {
  final summary = trends.trends;
  final firstTarget = trends.targets.first;
  final lastTarget = trends.targets.last;
  console.title('Profile Trends');
  console.components.definitionList({
    'Status': summary.status,
    'Targets': trends.targets.length,
    'First': _trendTargetLabelForDisplay(firstTarget),
    'Last': _trendTargetLabelForDisplay(lastTarget),
    'Profile': firstTarget.selectedProfileId,
  });

  console.section('Series');
  console.table(
    headers: const [
      'Target',
      'Duration',
      'Samples',
      'Heap Delta',
      'Top Self',
      'Top Method',
    ],
    rows: [
      for (final point in summary.points)
        [
          point.id,
          _formatMicros(point.durationMicros),
          point.sampleCount,
          switch (point.deltaHeapBytes) {
            final int delta => _formatSignedBytes(delta),
            _ => '-',
          },
          point.topSelfFrame ?? '-',
          point.topMethod ?? '-',
        ],
    ],
  );

  final overallComparison = summary.overallComparison;
  final overallRegressions = summary.overallRegressions;
  if (overallComparison != null) {
    console.section('Overall');
    console.components.definitionList({
      'Duration delta':
          '${_formatSignedCount(overallComparison.durationMicros.delta.toInt())} us',
      'Sample delta':
          _formatSignedCount(overallComparison.sampleCount.delta.toInt()),
      if (overallComparison.memory != null)
        'Heap delta': _formatSignedBytes(
            overallComparison.memory!.heapBytes.delta.toInt()),
    });
  }
  if (overallRegressions != null) {
    _writeRegressionInsights(console, overallRegressions);
  }

  if (summary.recurringRegressions.isNotEmpty) {
    console.section('Recurring Regressions');
    console.table(
      headers: const [
        'Kind',
        'Subject',
        'Count',
        'Total Delta',
        'Latest Delta',
      ],
      rows: [
        for (final item in summary.recurringRegressions)
          [
            item.kind,
            item.subject,
            item.occurrences,
            _formatSignedNumber(item.totalDelta),
            _formatSignedNumber(item.latestDelta),
          ],
      ],
    );
  }

  if (summary.steps.isNotEmpty) {
    console.section('Step Changes');
    console.table(
      headers: const [
        'Baseline',
        'Current',
        'Duration Delta',
        'Status',
        'Top Insight',
      ],
      rows: [
        for (final step in summary.steps)
          [
            step.baselineId,
            step.currentId,
            '${_formatSignedCount(step.comparison.durationMicros.delta.toInt())} us',
            step.regressions.status,
            step.regressions.insights.isEmpty
                ? '-'
                : step.regressions.insights.first.title,
          ],
      ],
    );
  }

  if (summary.warnings.isNotEmpty) {
    console.section('Warnings');
    console.components.bulletList(summary.warnings);
  }
}

void _writeMethodComparisonInspectionSummary(
  Console console, {
  required String title,
  required PreparedComparisonTarget target,
  required ProfileMethodInspection inspection,
  required ProfilePresentationOptions options,
}) {
  final region = target.presentation.region;
  final workingDirectory = _workingDirectoryFromRegionPath(region);
  console.section(title);
  console.components.definitionList({
    'Target': '${target.selectedProfileId} (${region.name})',
    'Kind': target.inputKind,
    if (target.sessionId != null) 'Session': target.sessionId,
    'Status': inspection.status.name,
  });

  if (inspection.message != null && inspection.message!.isNotEmpty) {
    console.warn(inspection.message!);
  }

  final method = inspection.method;
  if (method != null) {
    console.components.definitionList({
      'Method ID': method.methodId,
      'Method': method.name,
      'Self': _formatPercent(method.selfPercent),
      'Total': _formatPercent(method.totalPercent),
      'Source': _displayLocation(
        method.location,
        fullLocations: _fullLocationsEnabled(options),
        workingDirectory: workingDirectory,
      ),
    });
  }

  if (inspection.candidates.isNotEmpty) {
    console.table(
      headers: const ['Method', 'Method ID', 'Self', 'Total', 'Source'],
      rows: [
        for (final candidate in inspection.candidates)
          [
            candidate.name,
            candidate.methodId,
            _formatPercent(candidate.selfPercent),
            _formatPercent(candidate.totalPercent),
            _displayLocation(
              candidate.location,
              fullLocations: _fullLocationsEnabled(options),
              workingDirectory: workingDirectory,
            ),
          ],
      ],
    );
  }

  _writeMethodPaths(
    console,
    title: '$title Top Down Paths',
    paths: inspection.topDownPaths,
    workingDirectory: workingDirectory,
    options: options,
  );
  _writeMethodPaths(
    console,
    title: '$title Bottom Up Paths',
    paths: inspection.bottomUpPaths,
    workingDirectory: workingDirectory,
    options: options,
  );
}

void _writeMethodRelationDeltas(
  Console console, {
  required String title,
  required List<ProfileMethodRelationDelta> deltas,
  required ProfilePresentationOptions options,
}) {
  if (deltas.isEmpty) {
    return;
  }

  console.section(title);
  console.table(
    headers: const ['Method', 'Sample Delta', 'Percent Delta', 'Source'],
    rows: [
      for (final delta in deltas)
        [
          delta.name,
          _formatSignedCount(delta.sampleCount.delta.toInt()),
          _formatSignedPercent(delta.percent.delta.toDouble()),
          _displayLocation(
            delta.location,
            fullLocations: _fullLocationsEnabled(options),
            workingDirectory: null,
          ),
        ],
    ],
  );
}

void _writeMethodPaths(
  Console console, {
  required String title,
  required List<ProfileMethodPath> paths,
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  if (paths.isEmpty) {
    return;
  }

  console.section(title);
  console.components.bulletList([
    for (final path in paths)
      '${path.frames.map((frame) => _displayNameWithLocation(frame.name, frame.location, fullLocations: _fullLocationsEnabled(options), workingDirectory: workingDirectory)).join(' -> ')} '
          '[self ${path.selfSamples}, total ${path.totalSamples}, '
          '${_formatPercent(path.selfPercent)} self, ${_formatPercent(path.totalPercent)} total]',
  ]);
}

String _hotspotInsightLine(
  ProfileHotspotInsight insight, {
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  final buffer = StringBuffer(
      '[${insight.severity.name}] ${insight.title}: ${insight.summary}');
  void writePath(ProfileHotspotPath? path, String label) {
    if (path == null || path.frames.isEmpty) {
      return;
    }
    buffer.write(' $label ');
    buffer.write(
      path.frames
          .map(
            (frame) => _displayNameWithLocation(
              frame.name,
              frame.location,
              fullLocations: _fullLocationsEnabled(options),
              workingDirectory: workingDirectory,
            ),
          )
          .join(' -> '),
    );
  }

  writePath(insight.path, 'Path:');
  writePath(insight.bottomUpPath, 'Bottom up:');

  final focusMethod = insight.focusMethod;
  if (focusMethod != null) {
    buffer.write(' Inspect: ');
    buffer.write(
      _displayNameWithLocation(
        focusMethod.name,
        focusMethod.location,
        fullLocations: _fullLocationsEnabled(options),
        workingDirectory: workingDirectory,
      ),
    );
    if (focusMethod.callers.isNotEmpty) {
      buffer.write(' callers [');
      buffer.write(focusMethod.callers.map((caller) => caller.name).join(', '));
      buffer.write(']');
    }
    if (focusMethod.callees.isNotEmpty) {
      buffer.write(' callees [');
      buffer.write(focusMethod.callees.map((callee) => callee.name).join(', '));
      buffer.write(']');
    }
  }
  return buffer.toString();
}

String _trendTargetLabelForDisplay(PreparedComparisonTarget target) {
  return target.sessionId ?? target.path;
}

String _formatSignedNumber(num value) {
  final sign = value > 0 ? '+' : '';
  if (value is int) {
    return '$sign$value';
  }
  return '$sign${value.toStringAsFixed(1)}';
}

void _writeRegressionInsights(
  Console console,
  ProfileRegressionSummary regressions,
) {
  console.section('Regression Insights');
  console.components.definitionList({
    'Status': regressions.status,
    'Count': regressions.insights.length,
  });
  if (regressions.insights.isEmpty) {
    console.warn(
        'No strong regressions were detected from the current heuristics.');
    return;
  }
  console.components.bulletList([
    for (final insight in regressions.insights)
      '[${insight.severity.name}] ${insight.title}: ${insight.summary}',
  ]);
}

void _writeRegionDetails(
  Console console,
  ProfileRegionResult region, {
  ProfileCallTree? callTree,
  ProfileCallTree? bottomUpTree,
  ProfileMethodTable? methodTable,
  String? heading,
  bool includeNameField = true,
  String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  if (heading != null) {
    console.section(heading);
  }

  console.components.definitionList({
    if (includeNameField) 'Region': region.name,
    'Region ID': region.regionId,
    'Capture kinds': _formatCaptureKinds(region.captureKinds),
    'Isolate scope': region.isolateScope.name,
    'Origin isolate': region.isolateId,
    'Captured isolates': _formatIsolateIds(region.isolateIds),
    'Parent region': region.parentRegionId ?? '-',
    'Duration': _formatMicros(region.durationMicros),
    'Samples': region.sampleCount,
    'Sample period': _formatMicros(region.samplePeriodMicros),
    'Started': region.startTimestampMicros,
    'Ended': region.endTimestampMicros,
    'Summary': region.summaryPath,
    if (region.rawProfilePath != null) 'Raw profile': region.rawProfilePath,
    if (region.memory?.rawProfilePath != null)
      'Raw memory profile': region.memory!.rawProfilePath,
  });

  if (region.attributes.isNotEmpty) {
    console.section('Attributes');
    console.table(
      headers: const ['Key', 'Value'],
      rows: [
        for (final entry in region.attributes.entries) [entry.key, entry.value],
      ],
    );
  }

  _writeMemorySummary(
    console,
    region.memory,
    workingDirectory: workingDirectory,
    options: options,
  );
  _writeMethodTable(
    console,
    methodTable,
    workingDirectory: workingDirectory,
    options: options,
  );

  _writeFrameTable(
    console,
    title: 'Top Self Frames',
    frames: region.topSelfFrames,
    sampleSelector: (frame) => frame.selfSamples,
    percentSelector: (frame) => frame.selfPercent,
    workingDirectory: workingDirectory,
    options: options,
  );
  _writeFrameTable(
    console,
    title: 'Top Total Frames',
    frames: region.topTotalFrames,
    sampleSelector: (frame) => frame.totalSamples,
    percentSelector: (frame) => frame.totalPercent,
    workingDirectory: workingDirectory,
    options: options,
  );

  if (region.error != null) {
    console.section('Errors');
    console.error(region.error!);
    return;
  }

  if (options.includeCallTree) {
    console.section(_treeHeading(ProfileCallTreeView.topDown, options));
    if (callTree == null) {
      console.warn(
        'Call tree unavailable because no raw CPU profile artifact was available for this region.',
      );
    } else {
      console.tree(
        _callTreeChildrenData(
          callTree.root,
          workingDirectory: workingDirectory,
          options: options,
        ),
        root: _callTreeLabel(
          callTree.root,
          isRoot: true,
          workingDirectory: workingDirectory,
          options: options,
        ),
        style: TreeStyle.rounded,
      );
    }
  }

  if (!options.includeBottomUpTree) {
    return;
  }

  console.section(_treeHeading(ProfileCallTreeView.bottomUp, options));
  if (bottomUpTree == null) {
    console.warn(
      'Bottom-up tree unavailable because no raw CPU profile artifact was available for this region.',
    );
    return;
  }

  console.tree(
    _callTreeChildrenData(
      bottomUpTree.root,
      workingDirectory: workingDirectory,
      options: options,
    ),
    root: _callTreeLabel(
      bottomUpTree.root,
      isRoot: true,
      workingDirectory: workingDirectory,
      options: options,
    ),
    style: TreeStyle.rounded,
  );
}

void _writeMemorySummary(
  Console console,
  ProfileMemoryResult? memory, {
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  if (memory == null) {
    return;
  }

  console.section('Memory Summary');
  console.components.definitionList({
    'Heap start': _formatBytes(memory.start.used),
    'Heap end': _formatBytes(memory.end.used),
    'Heap delta': _formatSignedBytes(memory.deltaHeapBytes),
    'External delta': _formatSignedBytes(memory.deltaExternalBytes),
    'Capacity delta': _formatSignedBytes(memory.deltaCapacityBytes),
    'Class count': memory.classCount,
  });

  if (memory.topClasses.isEmpty) {
    return;
  }

  console.section('Top Allocation Classes');
  console.table(
    headers: const [
      'Class',
      'Allocated',
      'Live Delta',
      'Live',
      'Instances',
      'Source',
    ],
    rows: [
      for (final item in memory.topClasses)
        [
          item.className,
          _formatSignedBytes(item.allocationBytesDelta),
          _formatSignedBytes(item.liveBytesDelta),
          _formatBytes(item.liveBytes),
          _formatSignedCount(item.allocationInstancesDelta),
          _displayLocation(
            item.libraryUri,
            fullLocations: _fullLocationsEnabled(options),
            workingDirectory: workingDirectory,
          ),
        ],
    ],
  );
}

void _writeMethodTable(
  Console console,
  ProfileMethodTable? methodTable, {
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  if (!options.includeMethodTable || methodTable == null) {
    return;
  }

  console.section('Method Table');
  console.table(
    headers: const ['Method', 'Self', 'Total', 'Kind', 'Source'],
    rows: [
      for (final method in methodTable.methods)
        [
          method.name,
          _formatPercent(method.selfPercent),
          _formatPercent(method.totalPercent),
          method.kind,
          _displayLocation(
            method.location,
            fullLocations: _fullLocationsEnabled(options),
            workingDirectory: workingDirectory,
          ),
        ],
    ],
  );

  final detailedMethods = methodTable.methods.take(5);
  for (final method in detailedMethods) {
    if (method.callers.isEmpty && method.callees.isEmpty) {
      continue;
    }

    console.section('Method Graph: ${method.name}');
    console.components.definitionList({
      'Self': _formatPercent(method.selfPercent),
      'Total': _formatPercent(method.totalPercent),
      'Source': _displayLocation(
        method.location,
        fullLocations: _fullLocationsEnabled(options),
        workingDirectory: workingDirectory,
      ),
    });

    if (method.callers.isNotEmpty) {
      console.section('Callers');
      console.table(
        headers: const ['Method', 'Samples', 'Percent', 'Source'],
        rows: [
          for (final caller in method.callers)
            [
              caller.name,
              caller.sampleCount,
              _formatPercent(caller.percent),
              _displayLocation(
                caller.location,
                fullLocations: _fullLocationsEnabled(options),
                workingDirectory: workingDirectory,
              ),
            ],
        ],
      );
    }

    if (method.callees.isNotEmpty) {
      console.section('Callees');
      console.table(
        headers: const ['Method', 'Samples', 'Percent', 'Source'],
        rows: [
          for (final callee in method.callees)
            [
              callee.name,
              callee.sampleCount,
              _formatPercent(callee.percent),
              _displayLocation(
                callee.location,
                fullLocations: _fullLocationsEnabled(options),
                workingDirectory: workingDirectory,
              ),
            ],
        ],
      );
    }
  }
}

void _writeFrameTable(
  Console console, {
  required String title,
  required List<ProfileFrameSummary> frames,
  required int Function(ProfileFrameSummary frame) sampleSelector,
  required double Function(ProfileFrameSummary frame) percentSelector,
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  if (frames.isEmpty) {
    return;
  }

  console.section(title);
  console.table(
    headers: const ['Method', 'Samples', 'Percent', 'Kind', 'Source'],
    rows: [
      for (final frame in frames)
        [
          frame.name,
          sampleSelector(frame),
          _formatPercent(percentSelector(frame)),
          frame.kind,
          _displayLocation(
            frame.location,
            fullLocations: _fullLocationsEnabled(options),
            workingDirectory: workingDirectory,
          ),
        ],
    ],
  );
}

void _writeFrameDeltaTable(
  Console console, {
  required String title,
  required List<ProfileFrameDelta> frames,
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  if (frames.isEmpty) {
    return;
  }

  console.section(title);
  console.table(
    headers: const [
      'Method',
      'Base Self',
      'Current Self',
      'Self Delta',
      'Base Total',
      'Current Total',
      'Total Delta',
      'Source',
    ],
    rows: [
      for (final frame in frames)
        [
          frame.name,
          _formatCount(frame.selfSamples.baseline),
          _formatCount(frame.selfSamples.current),
          _formatSignedCount(frame.selfSamples.delta.toInt()),
          _formatCount(frame.totalSamples.baseline),
          _formatCount(frame.totalSamples.current),
          _formatSignedCount(frame.totalSamples.delta.toInt()),
          _displayLocation(
            frame.location,
            fullLocations: _fullLocationsEnabled(options),
            workingDirectory: workingDirectory,
          ),
        ],
    ],
  );
}

void _writeMethodDeltaTable(
  Console console, {
  required List<ProfileMethodDelta> methods,
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  if (methods.isEmpty) {
    return;
  }

  console.section('Method Deltas');
  console.table(
    headers: const [
      'Method',
      'Base Self',
      'Current Self',
      'Self Delta',
      'Base Total',
      'Current Total',
      'Total Delta',
      'Source',
    ],
    rows: [
      for (final method in methods)
        [
          method.name,
          _formatCount(method.selfSamples.baseline),
          _formatCount(method.selfSamples.current),
          _formatSignedCount(method.selfSamples.delta.toInt()),
          _formatCount(method.totalSamples.baseline),
          _formatCount(method.totalSamples.current),
          _formatSignedCount(method.totalSamples.delta.toInt()),
          _displayLocation(
            method.location,
            fullLocations: _fullLocationsEnabled(options),
            workingDirectory: workingDirectory,
          ),
        ],
    ],
  );
}

void _writeMemoryDeltaSummary(
  Console console,
  ProfileMemoryComparison? memory, {
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  if (memory == null) {
    return;
  }

  console.section('Memory Deltas');
  console.components.definitionList({
    'Heap delta': _formatDeltaBytes(memory.heapBytes),
    'External delta': _formatDeltaBytes(memory.externalBytes),
    'Capacity delta': _formatDeltaBytes(memory.capacityBytes),
    'Class count': _formatDeltaCount(memory.classCount),
  });

  if (memory.topClasses.isEmpty) {
    return;
  }

  console.section('Memory Class Deltas');
  console.table(
    headers: const [
      'Class',
      'Base Alloc',
      'Current Alloc',
      'Alloc Delta',
      'Base Live Delta',
      'Current Live Delta',
      'Live Delta',
      'Source',
    ],
    rows: [
      for (final item in memory.topClasses)
        [
          item.className,
          _formatBytes(item.allocationBytesDelta.baseline.toInt()),
          _formatBytes(item.allocationBytesDelta.current.toInt()),
          _formatSignedBytes(item.allocationBytesDelta.delta.toInt()),
          _formatSignedBytes(item.liveBytesDelta.baseline.toInt()),
          _formatSignedBytes(item.liveBytesDelta.current.toInt()),
          _formatSignedBytes(item.liveBytesDelta.delta.toInt()),
          _displayLocation(
            item.libraryUri,
            fullLocations: _fullLocationsEnabled(options),
            workingDirectory: workingDirectory,
          ),
        ],
    ],
  );
}

String _treeHeading(
  ProfileCallTreeView view,
  ProfilePresentationOptions options,
) {
  final details = <String>[
    switch (view) {
      ProfileCallTreeView.topDown => 'top-down',
      ProfileCallTreeView.bottomUp => 'bottom-up',
    },
  ];
  details.add(
    options.maxDepth == null ? 'full depth' : 'depth ${options.maxDepth}',
  );
  details.add(
    options.maxChildren == null
        ? 'all children'
        : 'max ${options.maxChildren} children',
  );
  if (options.hideSdk) {
    details.add('sdk hidden');
  }
  return switch (view) {
    ProfileCallTreeView.topDown => 'Call Tree (${details.join(', ')})',
    ProfileCallTreeView.bottomUp => 'Bottom Up Tree (${details.join(', ')})',
  };
}

Map<String, dynamic> _callTreeChildrenData(
  ProfileCallTreeNode node, {
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  return {
    for (final child in node.children)
      _callTreeLabel(
        child,
        workingDirectory: workingDirectory,
        options: options,
      ): child.children.isEmpty
          ? null
          : _callTreeChildrenData(
              child,
              workingDirectory: workingDirectory,
              options: options,
            ),
  };
}

String _callTreeLabel(
  ProfileCallTreeNode node, {
  bool isRoot = false,
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  final displayName = _displayNameWithLocation(
    node.name,
    node.location,
    fullLocations: _fullLocationsEnabled(options),
    workingDirectory: workingDirectory,
  );
  if (isRoot) {
    return '$displayName [samples ${node.totalSamples}]';
  }
  return '$displayName [self ${node.selfSamples}, total ${node.totalSamples}, '
      '${_formatPercent(node.selfPercent)} self, '
      '${_formatPercent(node.totalPercent)} total]';
}

String _formatMicros(int micros) {
  if (micros >= Duration.microsecondsPerSecond) {
    return '${(micros / Duration.microsecondsPerSecond).toStringAsFixed(2)}s';
  }
  if (micros >= Duration.microsecondsPerMillisecond) {
    return '${(micros / Duration.microsecondsPerMillisecond).toStringAsFixed(2)}ms';
  }
  return '${micros}us';
}

String _formatPercent(double percent) =>
    '${(percent * 100).toStringAsFixed(1)}%';

String _formatSignedPercent(double percent) {
  final formatted = _formatPercent(percent.abs());
  if (percent > 0) {
    return '+$formatted';
  }
  if (percent < 0) {
    return '-$formatted';
  }
  return formatted;
}

String _formatBytes(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value.abs() >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final precision = unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}

String _formatSignedBytes(int bytes) {
  if (bytes == 0) {
    return _formatBytes(0);
  }
  final prefix = bytes > 0 ? '+' : '-';
  return '$prefix${_formatBytes(bytes.abs())}';
}

String _formatSignedCount(int count) {
  if (count > 0) {
    return '+$count';
  }
  return '$count';
}

String _formatCount(num count) {
  if (count is int) {
    return '$count';
  }
  if (count == count.roundToDouble()) {
    return '${count.toInt()}';
  }
  return count.toStringAsFixed(2);
}

String _formatSignedMicros(int micros) {
  if (micros == 0) {
    return _formatMicros(0);
  }
  final prefix = micros > 0 ? '+' : '-';
  return '$prefix${_formatMicros(micros.abs())}';
}

String _formatPercentChange(ProfileNumericDelta delta) {
  final percentChange = delta.percentChange;
  if (percentChange == null) {
    return '-';
  }
  final prefix = percentChange > 0 ? '+' : '';
  return '$prefix${percentChange.toStringAsFixed(1)}%';
}

String _formatDeltaBytes(ProfileNumericDelta delta) {
  return '${_formatSignedBytes(delta.delta.toInt())} '
      '(${_formatBytes(delta.baseline.toInt())} -> '
      '${_formatBytes(delta.current.toInt())})';
}

String _formatDeltaCount(ProfileNumericDelta delta) {
  return '${_formatSignedCount(delta.delta.toInt())} '
      '(${_formatCount(delta.baseline)} -> ${_formatCount(delta.current)})';
}

String _topFrameName(List<ProfileFrameSummary> frames) {
  if (frames.isEmpty) {
    return '-';
  }
  return frames.first.name;
}

String _formatCaptureKinds(List<ProfileCaptureKind> captureKinds) {
  return captureKinds.map((kind) => kind.name).join(', ');
}

String _formatIsolateScopes(List<ProfileIsolateScope> isolateScopes) {
  return isolateScopes.map((scope) => scope.name).join(', ');
}

String _formatIsolateIds(List<String> isolateIds) {
  if (isolateIds.isEmpty) {
    return '-';
  }
  if (isolateIds.length <= 3) {
    return isolateIds.join(', ');
  }
  return '${isolateIds.length} isolates (${isolateIds.take(3).join(', ')}, ...)';
}

String _displayNameWithLocation(
  String name,
  String? location, {
  required bool fullLocations,
  required String? workingDirectory,
}) {
  final displayLocation = _displayLocation(
    location,
    fullLocations: fullLocations,
    workingDirectory: workingDirectory,
  );
  if (displayLocation == '-') {
    return name;
  }
  return '$name - ($displayLocation)';
}

String _displayLocation(
  String? location, {
  required bool fullLocations,
  required String? workingDirectory,
}) {
  if (location == null || location.isEmpty) {
    return '-';
  }
  if (fullLocations) {
    return location;
  }
  if (location.startsWith(_dartSdkUriPrefix)) {
    return 'sdk:${location.substring(_dartSdkUriPrefix.length)}';
  }
  if (location.startsWith('dart:') || location.startsWith('package:')) {
    return location;
  }

  final parsedUri = Uri.tryParse(location);
  if (parsedUri != null && parsedUri.scheme == 'file') {
    return _shortFilePath(parsedUri.toFilePath(), workingDirectory);
  }

  return location;
}

String _shortFilePath(String filePath, String? workingDirectory) {
  final normalized = path.normalize(filePath);
  if (workingDirectory != null && path.isWithin(workingDirectory, normalized)) {
    return path.relative(normalized, from: workingDirectory);
  }

  final segments = path.split(normalized);
  final pubCacheIndex = segments.lastIndexOf('.pub-cache');
  if (pubCacheIndex != -1) {
    final libIndex = segments.indexOf('lib', pubCacheIndex);
    if (libIndex != -1 &&
        libIndex > pubCacheIndex + 1 &&
        libIndex < segments.length) {
      final packageFolder = segments[libIndex - 1];
      final packageName = _packageNameFromFolder(packageFolder);
      final rest = segments.skip(libIndex + 1).join('/');
      return rest.isEmpty
          ? 'package:$packageName'
          : 'package:$packageName/$rest';
    }
  }

  if (segments.length <= 4) {
    return normalized;
  }
  return '.../${segments.skip(segments.length - 4).join('/')}';
}

String _packageNameFromFolder(String folder) {
  final versionMatch =
      RegExp(r'^(.+)-(\d+\.\d+\.\d+(?:[-+].*)?)$').firstMatch(folder);
  return versionMatch?.group(1) ?? folder;
}

String? _workingDirectoryFromRegionPath(ProfileRegionResult region) {
  final rawProfilePath = region.rawProfilePath;
  if (rawProfilePath == null || rawProfilePath.isEmpty) {
    return null;
  }
  final segments = path.split(path.normalize(rawProfilePath));
  final dartToolIndex = segments.lastIndexOf('.dart_tool');
  if (dartToolIndex <= 0) {
    return null;
  }
  return path.joinAll(segments.take(dartToolIndex));
}

bool _fullLocationsEnabled(ProfilePresentationOptions options) =>
    options.fullLocations;
