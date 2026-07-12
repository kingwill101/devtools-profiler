import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import 'terminal.dart';

/// Writes top self and total frame tables from [region] as CSV.
///
/// Each section starts with a `#` comment header, followed by a header row,
/// then one data row per frame. Uses [writeLine] for each output line.
void writeCsvRegionFrames(
  void Function(String line) writeLine,
  ProfileRegionResult region,
) {
  if (region.topSelfFrames.isNotEmpty) {
    _writeCsvFrameTable(writeLine, 'Top Self Frames', region.topSelfFrames);
  }

  if (region.topTotalFrames.isNotEmpty) {
    _writeCsvFrameTable(writeLine, 'Top Total Frames', region.topTotalFrames);
  }
}

/// Writes top self and total frame delta tables from [comparison] as CSV.
void writeCsvComparisonFrames(
  void Function(String line) writeLine,
  ProfileRegionComparison comparison,
) {
  if (comparison.topSelfFrames.isNotEmpty) {
    writeLine('# Top Self Frame Deltas');
    writeLine(
      'method,base_self,current_self,self_delta,'
      'base_total,current_total,total_delta',
    );
    for (final frame in comparison.topSelfFrames) {
      writeLine(
        '${_csvEscape(frame.name)},'
        '${frame.selfSamples.baseline},'
        '${frame.selfSamples.current},'
        '${frame.selfSamples.delta},'
        '${frame.totalSamples.baseline},'
        '${frame.totalSamples.current},'
        '${frame.totalSamples.delta}',
      );
    }
  }

  if (comparison.topTotalFrames.isNotEmpty) {
    writeLine('# Top Total Frame Deltas');
    writeLine(
      'method,base_self,current_self,self_delta,'
      'base_total,current_total,total_delta',
    );
    for (final frame in comparison.topTotalFrames) {
      writeLine(
        '${_csvEscape(frame.name)},'
        '${frame.selfSamples.baseline},'
        '${frame.selfSamples.current},'
        '${frame.selfSamples.delta},'
        '${frame.totalSamples.baseline},'
        '${frame.totalSamples.current},'
        '${frame.totalSamples.delta}',
      );
    }
  }
}

/// Writes the trends series table as CSV.
void writeCsvTrendSeries(
  void Function(String line) writeLine,
  ProfileTrendSummary summary,
) {
  if (summary.points.isEmpty) {
    return;
  }

  writeLine('# Series');
  writeLine(
    'target,duration_micros,samples,heap_delta_bytes,top_self,top_method',
  );
  for (final point in summary.points) {
    writeLine(
      '${_csvEscape(point.id)},'
      '${point.durationMicros},'
      '${point.sampleCount},'
      '${point.deltaHeapBytes ?? ''},'
      '${_csvEscape(point.topSelfFrame ?? '')},'
      '${_csvEscape(point.topMethod ?? '')}',
    );
  }
}

void _writeCsvFrameTable(
  void Function(String line) writeLine,
  String title,
  List<ProfileFrameSummary> frames,
) {
  writeLine('# $title');
  writeLine('method,self_samples,self_percent,total_samples,total_percent');
  for (final frame in frames) {
    writeLine(
      '${_csvEscape(frame.name)},'
      '${frame.selfSamples},'
      '${_formatPercentCsv(frame.selfPercent)},'
      '${frame.totalSamples},'
      '${_formatPercentCsv(frame.totalPercent)}',
    );
  }
}

String _csvEscape(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// Writes a multi-compare column table as CSV.
void writeCsvMultiCompare(
  void Function(String line) writeLine,
  List<MultiCompareColumn> columns,
) {
  if (columns.isEmpty) return;

  // Collect union of method names.
  final allNames = <String>{};
  final nameOrder = <String>[];
  for (final column in columns) {
    for (final frame in column.frames) {
      if (allNames.add(frame.name)) {
        nameOrder.add(frame.name);
      }
    }
  }

  // Build lookups.
  final lookups = <int, Map<String, ProfileFrameSummary>>{};
  for (var i = 0; i < columns.length; i++) {
    final map = <String, ProfileFrameSummary>{};
    for (final frame in columns[i].frames) {
      map[frame.name] = frame;
    }
    lookups[i] = map;
  }

  // Sort by first column.
  nameOrder.sort((a, b) {
    final aFrame = lookups[0]![a];
    final bFrame = lookups[0]![b];
    final aPercent = aFrame?.selfPercent ?? -1.0;
    final bPercent = bFrame?.selfPercent ?? -1.0;
    return bPercent.compareTo(aPercent);
  });

  // Header
  final header = StringBuffer('method');
  for (final column in columns) {
    header.write(',${_csvEscape(column.label)}');
  }
  writeLine(header.toString());

  // Rows
  for (final name in nameOrder) {
    final row = StringBuffer(_csvEscape(name));
    for (var i = 0; i < columns.length; i++) {
      final frame = lookups[i]![name];
      row.write(',');
      row.write(
        frame != null ? frame.selfPercent.toStringAsFixed(4) : 'eliminated',
      );
    }
    writeLine(row.toString());
  }
}

String _formatPercentCsv(double percent) {
  // Output as a raw decimal so it's easy to consume programmatically.
  // E.g. 0.42 instead of 42.0%.
  return percent.toStringAsFixed(4);
}
