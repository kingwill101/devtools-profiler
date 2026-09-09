import 'dart:math' as math;

import 'package:artisanal/runtime.dart' as tui;
import 'package:artisanal/style.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';

import '../cli/commands/profile_session_resolution.dart';
import '../presentation/cli_command.dart';

/// A selectable whole-session or explicit region summary.
final class BrowserProfile {
  /// Creates an entry without loading raw artifacts.
  const BrowserProfile(this.session, this.profile);

  /// The owning stored session.
  final StoredSession session;

  /// The selected profile, including its run-local region ID.
  final ProfileRegionResult profile;

  /// A searchable, unambiguous label.
  String get label =>
      '${session.result.sessionId} / ${profile.name} [${profile.regionId}] '
      '${session.result.command.join(' ')} ${session.result.workingDirectory}';
}

/// Read-only, summary-backed session selection and comparison.
///
/// Holds no CPU sample artifacts, performs no rendering-time I/O, and never
/// guesses region equivalence. Each region is selected explicitly.
final class SessionBrowser implements tui.Model {
  /// Creates a browser from stored summary metadata.
  SessionBrowser(List<StoredSession> sessions)
    : entries = [
        for (final session in sessions) ...[
          if (session.result.overallProfile case final profile?)
            BrowserProfile(session, profile),
          for (final profile in session.result.regions)
            BrowserProfile(session, profile),
        ],
      ];

  /// Available summary entries.
  final List<BrowserProfile> entries;

  /// The selected baseline, independent of the active search.
  BrowserProfile? baseline;

  /// The selected current run, independent of the active search.
  BrowserProfile? current;

  /// Search text.
  String query = '';

  /// Whether keyboard input is editing the search.
  bool searching = false;

  /// The cursor within the filtered list.
  int cursor = 0;

  int _width = 80;
  int _height = 24;
  bool _details = false;
  int _detailOffset = 0;

  /// The command to print after restoring the terminal, if requested.
  String? exportedCommand;

  /// Returns entries matching the current query.
  List<BrowserProfile> get visible => [
    for (final entry in entries)
      if (entry.label.toLowerCase().contains(query.toLowerCase())) entry,
  ];

  /// Returns a reproducible POSIX-shell comparison command.
  String? get comparisonCommand {
    final base = baseline;
    final next = current;
    if (base == null || next == null) return null;
    return shellJoin([
      'devtools-profiler',
      'compare',
      '--baseline-profile-id',
      base.profile.regionId,
      '--current-profile-id',
      next.profile.regionId,
      '--',
      base.session.directory.path,
      next.session.directory.path,
    ]);
  }

  @override
  tui.Cmd? init() => null;

  @override
  (tui.Model, tui.Cmd?) update(tui.Msg msg) {
    if (msg is tui.InterruptMsg) return (this, tui.Cmd.quit());
    if (msg case tui.WindowSizeMsg(:final width, :final height)) {
      _width = math.max(1, width);
      _height = math.max(1, height);
    }
    if (msg is! tui.KeyMsg) return (this, null);
    final key = msg.key;
    final text = String.fromCharCodes(key.runes);
    if (key.ctrl && text == 'c') return (this, tui.Cmd.quit());
    if (searching) {
      if (key.type == tui.KeyType.escape || key.type == tui.KeyType.enter) {
        searching = false;
      } else if (key.type == tui.KeyType.backspace) {
        query = String.fromCharCodes(
          query.runes.take(math.max(0, query.runes.length - 1)),
        );
      } else if (key.type == tui.KeyType.runes && !key.ctrl && !key.alt) {
        query += _safe(text);
      }
      cursor = 0;
      return (this, null);
    }
    if (text == 'q' || key.type == tui.KeyType.escape) {
      if (_details) {
        _details = false;
        return (this, null);
      }
      return (this, tui.Cmd.quit());
    }
    if (text == '/') {
      searching = true;
      _details = false;
    } else if (text == 'd') {
      _details = !_details;
      _detailOffset = 0;
    } else if (text == 'e' && comparisonCommand != null) {
      exportedCommand = comparisonCommand;
      return (this, tui.Cmd.quit());
    } else if (key.type == tui.KeyType.down || text == 'j') {
      if (_details) {
        _detailOffset = math.min(
          math.max(0, _preview().length - 1),
          _detailOffset + 1,
        );
      } else {
        cursor = math.min(math.max(0, visible.length - 1), cursor + 1);
      }
    } else if (key.type == tui.KeyType.up || text == 'k') {
      if (_details) {
        _detailOffset = math.max(0, _detailOffset - 1);
      } else {
        cursor = math.max(0, cursor - 1);
      }
    } else if (visible.isNotEmpty) {
      if (text == 'b') baseline = visible[cursor];
      if (text == 'c' || key.type == tui.KeyType.enter) {
        current = visible[cursor];
      }
    }
    return (this, null);
  }

  @override
  String view() {
    final lines = <String>[
      'PROFILE BROWSER | stored summaries',
      'B: ${_selectionLabel(baseline)}',
      'C: ${_selectionLabel(current)}',
      '/ search | b baseline | c current | d details | e export | q quit',
    ];
    if (_details) {
      lines.addAll(_preview().skip(_detailOffset));
    } else {
      lines.add('${searching ? 'Search>' : 'Filter:'} $query');
      final filtered = visible;
      final count = math.max(1, (_height - 8) ~/ 2);
      final start = (cursor ~/ count) * count;
      if (filtered.isEmpty) lines.add('No matching profiles.');
      for (var i = start; i < math.min(filtered.length, start + count); i++) {
        lines.add('${i == cursor ? '>' : ' '} ${filtered[i].label}');
      }
      lines.add('--- Preview (d for scrollable details) ---');
      lines.addAll(_preview());
    }
    return Style()
        .maxWidth(_width)
        .maxHeight(_height)
        .render(
          [
            for (var i = 0; i < lines.length; i++)
              if (i == 0 || lines[i].startsWith('> '))
                Style().bold().render(_safe(lines[i]))
              else
                _safe(lines[i]),
          ].join('\n'),
        );
  }

  List<String> _preview() {
    final base = baseline;
    final next = current;
    if (base == null || next == null) {
      return [
        'Select baseline and current profiles; regions have explicit IDs.',
      ];
    }
    final a = base.profile;
    final b = next.profile;
    final rows = alignProfileFrames([
      ProfileFrameColumn(label: 'baseline', frames: a.topSelfFrames),
      ProfileFrameColumn(label: 'current', frames: b.topSelfFrames),
    ]);
    return [
      'Duration: ${(a.durationMicros / 1000).toStringAsFixed(1)} -> '
          '${(b.durationMicros / 1000).toStringAsFixed(1)} ms (capture window)',
      'Samples: ${a.sampleCount} -> ${b.sampleCount}; '
          'period: ${a.samplePeriodMicros} -> ${b.samplePeriodMicros} us',
      'Heap delta: ${a.memory?.deltaHeapBytes ?? 'unavailable'} -> '
          '${b.memory?.deltaHeapBytes ?? 'unavailable'} bytes',
      if (a.samplePeriodMicros != b.samplePeriodMicros)
        'WARNING: Different sample periods.',
      if (a.name != b.name)
        'WARNING: Different profile names; verify matching workloads.',
      if (a.isolateScope != b.isolateScope)
        'WARNING: Different isolate scopes.',
      if (a.durationMicros != b.durationMicros)
        'WARNING: Different capture durations.',
      if (a.error case final error?) 'WARNING: Baseline capture: $error',
      if (b.error case final error?) 'WARNING: Current capture: $error',
      'Comparability is not guaranteed: verify build mode, workload and coverage.',
      for (final warning in {
        ...base.session.result.warnings,
        ...next.session.result.warnings,
      })
        'WARNING: $warning',
      'Self share: baseline -> current (delta in percentage points).',
      'Not listed is NOT eliminated. Stored top lists may be incomplete.',
      for (final row in rows)
        '${row.name} [${row.kind}] ${row.location ?? '(unknown location)'}: '
            '${_percent(row.frames[0])} -> ${_percent(row.frames[1])}'
            '${_delta(row.frames[0], row.frames[1])}',
      'POSIX command (e prints the complete command after exit):',
      comparisonCommand!,
    ];
  }
}

String _selectionLabel(BrowserProfile? entry) => entry == null
    ? '(not selected)'
    : '${entry.session.result.sessionId} / '
          '${entry.profile.name} [${entry.profile.regionId}]';

String _percent(ProfileFrameSummary? frame) => frame == null
    ? 'not listed'
    : '${(frame.selfPercent * 100).toStringAsFixed(2)}%';

String _delta(ProfileFrameSummary? a, ProfileFrameSummary? b) {
  if (a == null || b == null) return '';
  final delta = (b.selfPercent - a.selfPercent) * 100;
  return ' (${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)} pp)';
}

// Artifacts are data, not terminal commands. Never render embedded controls.
String _safe(String text) =>
    text.replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), ' ');
