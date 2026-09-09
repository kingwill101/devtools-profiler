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
    _writeCsvDeltaTable(
      writeLine,
      'Top Self Frame Deltas',
      comparison.topSelfFrames,
    );
  }

  if (comparison.topTotalFrames.isNotEmpty) {
    _writeCsvDeltaTable(
      writeLine,
      'Top Total Frame Deltas',
      comparison.topTotalFrames,
    );
  }
}

void _writeCsvDeltaTable(
  void Function(String line) writeLine,
  String title,
  List<ProfileFrameDelta> frames,
) {
  writeLine('# $title');
  writeLine(
    'method,base_self,current_self,self_delta,'
    'base_total,current_total,total_delta',
  );
  for (final frame in frames) {
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
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// Writes a multi-compare column table as CSV.
void writeCsvMultiCompare(
  void Function(String line) writeLine,
  List<MultiCompareColumn> columns, {
  int? frameLimit,
}) {
  if (columns.isEmpty) return;

  // Header
  final header = StringBuffer('method,kind,location');
  for (final column in columns) {
    header.write(',${_csvEscape(column.label)}');
  }
  writeLine(header.toString());

  // Rows
  for (final aligned in alignProfileFrames(columns, limit: frameLimit)) {
    final row = StringBuffer(
      '${_csvEscape(aligned.name)},${_csvEscape(aligned.kind)},'
      '${_csvEscape(aligned.location ?? '')}',
    );
    for (final frame in aligned.frames) {
      row.write(',');
      row.write(frame != null ? frame.selfPercent.toStringAsFixed(4) : '');
    }
    writeLine(row.toString());
  }
}

String _formatPercentCsv(double percent) {
  // Output as a raw decimal so it's easy to consume programmatically.
  // E.g. 0.42 instead of 42.0%.
  return percent.toStringAsFixed(4);
}
