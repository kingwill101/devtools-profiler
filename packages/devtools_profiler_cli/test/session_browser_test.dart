import 'dart:io';

import 'package:artisanal/runtime.dart' as tui;
import 'package:artisanal/style.dart';
import 'package:devtools_profiler_cli/src/browser/session_browser.dart';
import 'package:devtools_profiler_cli/src/cli/commands/profile_session_resolution.dart';
import 'package:devtools_profiler_cli/src/rendering/csv.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';

void main() {
  test('handles Artisanal signal interrupts even while searching', () {
    final browser = SessionBrowser([_session('base')]);
    browser.update(_key('/'));
    final (_, command) = browser.update(const tui.InterruptMsg());
    expect(command, isNotNull);
    expect(browser.exportedCommand, isNull);
  });

  test(
    'selects explicit region IDs and preserves baseline through filtering',
    () {
      final browser = SessionBrowser([_session('base'), _session('current')]);
      browser.update(_key('b'));
      browser.update(_key('/'));
      browser.update(_key('current'));
      browser.update(tui.KeyMsg(tui.Key(tui.KeyType.enter)));
      browser.update(_key('c'));
      expect(browser.baseline!.session.result.sessionId, 'base');
      expect(browser.current!.session.result.sessionId, 'current');
      expect(
        browser.comparisonCommand,
        contains('--baseline-profile-id overall --current-profile-id overall'),
      );
      browser.update(_key('e'));
      expect(browser.exportedCommand, browser.comparisonCommand);
    },
  );

  test(
    'search input cannot trigger export/quit or move beyond empty results',
    () {
      final browser = SessionBrowser([_session('base')]);
      browser.update(_key('/'));
      browser.update(_key('qeb'));
      expect(browser.query, 'qeb');
      expect(browser.visible, isEmpty);
      expect(browser.exportedCommand, isNull);
      browser.update(tui.KeyMsg(tui.Key(tui.KeyType.enter)));
      browser.update(_key('j'));
      browser.update(_key('b'));
      expect(browser.cursor, 0);
      expect(browser.baseline, isNull);
    },
  );

  test('narrow view is bounded and artifact controls cannot escape', () {
    final browser = SessionBrowser([_session('base\x1b[2J')]);
    browser.update(const tui.WindowSizeMsg(32, 12));
    final view = browser.view();
    expect(view, isNot(contains('\x1b[2J')));
    final lines = view.split('\n');
    expect(lines.length, lessThanOrEqualTo(12));
    for (final line in lines) {
      expect(Style.visibleLength(line), lessThanOrEqualTo(32));
    }
  });

  test('details preserve unknown observations and percentage-point units', () {
    final browser = SessionBrowser([_session('base'), _session('current')]);
    browser.update(const tui.WindowSizeMsg(160, 50));
    browser.update(_key('b'));
    browser.update(_key('j'));
    browser.update(_key('c'));
    browser.update(_key('d'));
    expect(browser.view(), contains('NOT eliminated'));
    expect(browser.view(), contains('+0.00 pp'));
    expect(browser.view(), contains('unavailable'));
  });

  test('CSV retains locations and leaves missing observations blank', () {
    final output = <String>[];
    writeCsvMultiCompare(output.add, [
      ProfileFrameColumn(label: 'base', frames: [_frame('package:a/a.dart')]),
      ProfileFrameColumn(label: 'next', frames: [_frame('package:b/b.dart')]),
    ]);
    expect(output, hasLength(3));
    expect(output.first, 'method,kind,location,base,next');
    expect(output[1], 'work,Dart,package:a/a.dart,0.1000,');
    expect(output[2], 'work,Dart,package:b/b.dart,,0.1000');
  });
}

tui.KeyMsg _key(String text) =>
    tui.KeyMsg(tui.Key(tui.KeyType.runes, runes: text.runes.toList()));

StoredSession _session(String id) => StoredSession(
  directory: Directory('/tmp/$id with spaces'),
  modifiedTime: DateTime.utc(2026),
  result: ProfileRunResult.fromJson({
    'sessionId': id,
    'command': ['dart', 'run', 'main.dart'],
    'workingDirectory': '/project',
    'overallProfile': {
      'regionId': 'overall',
      'name': 'overall',
      'sampleCount': 100,
      'topSelfFrames': [_frame('package:a/a.dart').toJson()],
    },
  }),
);

ProfileFrameSummary _frame(String location) => ProfileFrameSummary(
  name: 'work',
  kind: 'Dart',
  location: location,
  selfSamples: 10,
  totalSamples: 10,
  selfPercent: 0.1,
  totalPercent: 0.1,
);
