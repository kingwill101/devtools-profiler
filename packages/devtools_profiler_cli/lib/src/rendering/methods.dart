import 'package:artisanal/artisanal.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../presentation.dart';
import 'helpers.dart';

void writeMethodInspection(
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
    final workingDirectory = workingDirectoryFromRegionPath(region);
    console.section('Method Summary');
    console.components.definitionList({
      'Method ID': method.methodId,
      'Name': method.name,
      'Kind': method.kind,
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
    final workingDirectory = workingDirectoryFromRegionPath(region);
    console.section('Candidates');
    console.table(
      headers: const ['Method', 'Method ID', 'Self', 'Total', 'Source'],
      rows: [
        for (final candidate in result.candidates)
          [
            candidate.name,
            candidate.methodId,
            formatPercent(candidate.selfPercent),
            formatPercent(candidate.totalPercent),
            displayLocation(
              candidate.location,
              fullLocations: fullLocationsEnabled(options),
              workingDirectory: workingDirectory,
            ),
          ],
      ],
    );
  }
}

void writeMethodSearch(
  Console console,
  PreparedProfileMethodSearch search, {
  required ProfilePresentationOptions options,
}) {
  final region = search.target.presentation.region;
  final result = search.search;
  final workingDirectory = workingDirectoryFromRegionPath(region);
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
          formatPercent(method.selfPercent),
          formatPercent(method.totalPercent),
          displayLocation(
            method.location,
            fullLocations: fullLocationsEnabled(options),
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

void writeMethodComparison(
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
      'Source': displayLocation(
        methodDelta.location,
        fullLocations: fullLocationsEnabled(options),
        workingDirectory: null,
      ),
      'Self delta':
          '${formatSignedCount(methodDelta.selfSamples.delta.toInt())} samples',
      'Total delta':
          '${formatSignedCount(methodDelta.totalSamples.delta.toInt())} samples',
      'Self percent delta': formatSignedPercent(
        methodDelta.selfPercent.delta.toDouble(),
      ),
      'Total percent delta': formatSignedPercent(
        methodDelta.totalPercent.delta.toDouble(),
      ),
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

void _writeMethodComparisonInspectionSummary(
  Console console, {
  required String title,
  required PreparedComparisonTarget target,
  required ProfileMethodInspection inspection,
  required ProfilePresentationOptions options,
}) {
  final region = target.presentation.region;
  final workingDirectory = workingDirectoryFromRegionPath(region);
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
      'Self': formatPercent(method.selfPercent),
      'Total': formatPercent(method.totalPercent),
      'Source': displayLocation(
        method.location,
        fullLocations: fullLocationsEnabled(options),
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
            formatPercent(candidate.selfPercent),
            formatPercent(candidate.totalPercent),
            displayLocation(
              candidate.location,
              fullLocations: fullLocationsEnabled(options),
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
          formatSignedCount(delta.sampleCount.delta.toInt()),
          formatSignedPercent(delta.percent.delta.toDouble()),
          displayLocation(
            delta.location,
            fullLocations: fullLocationsEnabled(options),
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
      '${path.frames.map((frame) => displayNameWithLocation(frame.name, frame.location, fullLocations: fullLocationsEnabled(options), workingDirectory: workingDirectory)).join(' -> ')} '
          '[self ${path.selfSamples}, total ${path.totalSamples}, '
          '${formatPercent(path.selfPercent)} self, ${formatPercent(path.totalPercent)} total]',
  ]);
}
