import 'package:artisanal/artisanal.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../presentation.dart';
import 'helpers.dart';

void writeSessionSummary(
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
    'Capture kinds': formatCaptureKinds(session.supportedCaptureKinds),
    'Isolate scopes': formatIsolateScopes(session.supportedIsolateScopes),
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
            formatMicros(region.durationMicros),
            region.sampleCount,
            topFrameName(region.topSelfFrames),
            region.error == null ? 'captured' : 'error',
          ],
      ],
    );

    for (final region in session.regions.where(
      (region) => region.error != null,
    )) {
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

void writeRegionSummary(
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

void writeComparisonSummary(
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
        formatMicros(delta.durationMicros.baseline.toInt()),
        formatMicros(delta.durationMicros.current.toInt()),
        formatSignedMicros(delta.durationMicros.delta.toInt()),
        formatPercentChange(delta.durationMicros),
      ],
      [
        'Samples',
        formatCount(delta.sampleCount.baseline),
        formatCount(delta.sampleCount.current),
        formatSignedCount(delta.sampleCount.delta.toInt()),
        formatPercentChange(delta.sampleCount),
      ],
      [
        'Sample period',
        formatMicros(delta.samplePeriodMicros.baseline.toInt()),
        formatMicros(delta.samplePeriodMicros.current.toInt()),
        formatSignedMicros(delta.samplePeriodMicros.delta.toInt()),
        formatPercentChange(delta.samplePeriodMicros),
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
    workingDirectory: workingDirectoryFromRegionPath(baseline),
    options: options,
  );
  _writeFrameDeltaTable(
    console,
    title: 'Top Total Frame Deltas',
    frames: delta.topTotalFrames,
    workingDirectory: workingDirectoryFromRegionPath(baseline),
    options: options,
  );
  _writeMethodDeltaTable(
    console,
    methods: delta.methods,
    workingDirectory: workingDirectoryFromRegionPath(baseline),
    options: options,
  );
  _writeMemoryDeltaSummary(
    console,
    delta.memory,
    workingDirectory: workingDirectoryFromRegionPath(baseline),
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
      workingDirectory: workingDirectoryFromRegionPath(baseline),
      options: options,
    );
    _writeRegionDetails(
      console,
      current,
      callTree: comparison.current.presentation.callTree,
      bottomUpTree: comparison.current.presentation.bottomUpTree,
      methodTable: comparison.current.presentation.methodTable,
      heading: 'Current Profile',
      workingDirectory: workingDirectoryFromRegionPath(current),
      options: options,
    );
  }
}

void writeHotspotExplanation(
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
    console.warn(
      'No strong hotspots were detected from the current heuristics.',
    );
  } else {
    console.components.bulletList([
      for (final insight in explanation.hotspots.insights)
        _hotspotInsightLine(
          insight,
          workingDirectory: workingDirectoryFromRegionPath(region),
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
    workingDirectory: workingDirectoryFromRegionPath(region),
    options: options.copyWith(includeMethodTable: true),
  );
}

void writeTrendSummary(
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
          formatMicros(point.durationMicros),
          point.sampleCount,
          switch (point.deltaHeapBytes) {
            final int delta => formatSignedBytes(delta),
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
          '${formatSignedCount(overallComparison.durationMicros.delta.toInt())} us',
      'Sample delta': formatSignedCount(
        overallComparison.sampleCount.delta.toInt(),
      ),
      if (overallComparison.memory != null)
        'Heap delta': formatSignedBytes(
          overallComparison.memory!.heapBytes.delta.toInt(),
        ),
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
            '${formatSignedCount(step.comparison.durationMicros.delta.toInt())} us',
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

String _hotspotInsightLine(
  ProfileHotspotInsight insight, {
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  final buffer = StringBuffer(
    '[${insight.severity.name}] ${insight.title}: ${insight.summary}',
  );
  void writePath(ProfileHotspotPath? path, String label) {
    if (path == null || path.frames.isEmpty) {
      return;
    }
    buffer.write(' $label ');
    buffer.write(
      path.frames
          .map(
            (frame) => displayNameWithLocation(
              frame.name,
              frame.location,
              fullLocations: fullLocationsEnabled(options),
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
      displayNameWithLocation(
        focusMethod.name,
        focusMethod.location,
        fullLocations: fullLocationsEnabled(options),
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
      'No strong regressions were detected from the current heuristics.',
    );
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
    'Capture kinds': formatCaptureKinds(region.captureKinds),
    'Isolate scope': region.isolateScope.name,
    'Origin isolate': region.isolateId,
    'Captured isolates': formatIsolateIds(region.isolateIds),
    'Parent region': region.parentRegionId ?? '-',
    'Duration': formatMicros(region.durationMicros),
    'Samples': region.sampleCount,
    'Sample period': formatMicros(region.samplePeriodMicros),
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
    console.section(treeHeading(ProfileCallTreeView.topDown, options));
    if (callTree == null) {
      console.warn(
        'Call tree unavailable because no raw CPU profile artifact was available for this region.',
      );
    } else {
      console.tree(
        callTreeChildrenData(
          callTree.root,
          workingDirectory: workingDirectory,
          options: options,
        ),
        root: callTreeLabel(
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

  console.section(treeHeading(ProfileCallTreeView.bottomUp, options));
  if (bottomUpTree == null) {
    console.warn(
      'Bottom-up tree unavailable because no raw CPU profile artifact was available for this region.',
    );
    return;
  }

  console.tree(
    callTreeChildrenData(
      bottomUpTree.root,
      workingDirectory: workingDirectory,
      options: options,
    ),
    root: callTreeLabel(
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
    'Heap start': formatBytes(memory.start.used),
    'Heap end': formatBytes(memory.end.used),
    'Heap delta': formatSignedBytes(memory.deltaHeapBytes),
    'External delta': formatSignedBytes(memory.deltaExternalBytes),
    'Capacity delta': formatSignedBytes(memory.deltaCapacityBytes),
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
          formatSignedBytes(item.allocationBytesDelta),
          formatSignedBytes(item.liveBytesDelta),
          formatBytes(item.liveBytes),
          formatSignedCount(item.allocationInstancesDelta),
          displayLocation(
            item.libraryUri,
            fullLocations: fullLocationsEnabled(options),
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
          formatPercent(method.selfPercent),
          formatPercent(method.totalPercent),
          method.kind,
          displayLocation(
            method.location,
            fullLocations: fullLocationsEnabled(options),
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
      'Self': formatPercent(method.selfPercent),
      'Total': formatPercent(method.totalPercent),
      'Source': displayLocation(
        method.location,
        fullLocations: fullLocationsEnabled(options),
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
              formatPercent(caller.percent),
              displayLocation(
                caller.location,
                fullLocations: fullLocationsEnabled(options),
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
              formatPercent(callee.percent),
              displayLocation(
                callee.location,
                fullLocations: fullLocationsEnabled(options),
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
          formatPercent(percentSelector(frame)),
          frame.kind,
          displayLocation(
            frame.location,
            fullLocations: fullLocationsEnabled(options),
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
          formatCount(frame.selfSamples.baseline),
          formatCount(frame.selfSamples.current),
          formatSignedCount(frame.selfSamples.delta.toInt()),
          formatCount(frame.totalSamples.baseline),
          formatCount(frame.totalSamples.current),
          formatSignedCount(frame.totalSamples.delta.toInt()),
          displayLocation(
            frame.location,
            fullLocations: fullLocationsEnabled(options),
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
          formatCount(method.selfSamples.baseline),
          formatCount(method.selfSamples.current),
          formatSignedCount(method.selfSamples.delta.toInt()),
          formatCount(method.totalSamples.baseline),
          formatCount(method.totalSamples.current),
          formatSignedCount(method.totalSamples.delta.toInt()),
          displayLocation(
            method.location,
            fullLocations: fullLocationsEnabled(options),
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
    'Heap delta': formatDeltaBytes(memory.heapBytes),
    'External delta': formatDeltaBytes(memory.externalBytes),
    'Capacity delta': formatDeltaBytes(memory.capacityBytes),
    'Class count': formatDeltaCount(memory.classCount),
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
          formatBytes(item.allocationBytesDelta.baseline.toInt()),
          formatBytes(item.allocationBytesDelta.current.toInt()),
          formatSignedBytes(item.allocationBytesDelta.delta.toInt()),
          formatSignedBytes(item.liveBytesDelta.baseline.toInt()),
          formatSignedBytes(item.liveBytesDelta.current.toInt()),
          formatSignedBytes(item.liveBytesDelta.delta.toInt()),
          displayLocation(
            item.libraryUri,
            fullLocations: fullLocationsEnabled(options),
            workingDirectory: workingDirectory,
          ),
        ],
    ],
  );
}
