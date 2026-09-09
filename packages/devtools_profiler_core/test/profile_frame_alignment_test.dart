import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:test/test.dart';

void main() {
  test('limits aligned rows and treats zero as unlimited', () {
    final columns = [
      ProfileFrameColumn(
        label: 'a',
        frames: [_frame('package:a/a.dart'), _frame('package:b/b.dart')],
      ),
      ProfileFrameColumn(label: 'b', frames: [_frame('package:b/b.dart')]),
    ];
    final all = alignProfileFrames(columns);
    expect(alignProfileFrames(columns, limit: 0), hasLength(2));
    final limited = alignProfileFrames(columns, limit: 1);
    expect(limited, hasLength(1));
    expect(limited.single.toJson(), all.first.toJson());
  });

  test('separates same-name functions by kind and exact location', () {
    final rows = alignProfileFrames([
      ProfileFrameColumn(
        label: 'a',
        frames: [
          _frame('package:a/a.dart'),
          _frame('package:b/b.dart'),
          _frame('package:a/a.dart', kind: 'Native'),
        ],
      ),
      ProfileFrameColumn(label: 'b', frames: [_frame('package:b/b.dart')]),
    ]);
    expect(rows, hasLength(3));
    expect(
      rows.where((row) => row.frames[1] != null).single.location,
      'package:b/b.dart',
    );
    expect(rows.where((row) => row.frames[1] == null), hasLength(2));
    expect(rows.first.toJson()['frames'], contains(null));
  });

  test('does not guess checkout equivalence or absence as zero', () {
    final rows = alignProfileFrames([
      ProfileFrameColumn(label: 'a', frames: [_frame('file:///a/lib/a.dart')]),
      ProfileFrameColumn(label: 'b', frames: [_frame('file:///b/lib/a.dart')]),
    ]);
    expect(rows, hasLength(2));
    expect(rows[0].frames[1], isNull);
    expect(rows[1].frames[0], isNull);
  });

  test('empty and duplicate inputs have explicit semantics', () {
    expect(alignProfileFrames([]), isEmpty);
    expect(
      alignProfileFrames([
        const ProfileFrameColumn(label: 'empty', frames: []),
      ]),
      isEmpty,
    );
    expect(
      () => alignProfileFrames([
        ProfileFrameColumn(
          label: 'duplicate',
          frames: [_frame(null), _frame(null)],
        ),
      ]),
      throwsArgumentError,
    );
  });
}

ProfileFrameSummary _frame(String? location, {String kind = 'Dart'}) =>
    ProfileFrameSummary(
      name: 'work',
      kind: kind,
      location: location,
      selfSamples: 10,
      totalSamples: 10,
      selfPercent: 0.1,
      totalPercent: 0.1,
    );
