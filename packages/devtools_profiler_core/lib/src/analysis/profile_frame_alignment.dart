import '../capture/models.dart';

/// One source in a cross-run top-frame comparison.
final class ProfileFrameColumn {
  /// Creates a labeled source.
  const ProfileFrameColumn({required this.label, required this.frames});

  /// The source label.
  final String label;

  /// Available frames, which may be a limited stored summary.
  final List<ProfileFrameSummary> frames;
}

/// One aligned function across multiple sources.
final class ProfileFrameRow {
  /// Creates a row with nullable observations.
  const ProfileFrameRow({
    required this.name,
    required this.kind,
    required this.location,
    required this.frames,
  });

  /// The function display name.
  final String name;

  /// The VM function kind.
  final String kind;

  /// The exact source location used for matching.
  final String? location;

  /// Observations in source order; null means absent from the supplied list.
  ///
  /// Absence is not evidence of elimination or zero execution cost.
  final List<ProfileFrameSummary?> frames;

  /// Converts this row to structured output, retaining missing observations.
  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind,
    'location': location,
    'frames': [for (final frame in frames) frame?.toJson()],
  };
}

/// Aligns top-frame lists by name, kind, and exact source location.
///
/// Does not guess equivalence between different checkout roots or package
/// versions. Package URIs already match portably; unresolved locations remain
/// unresolved. Sorts by first-source self percentage with deterministic ties.
/// Input lists must contain at most one entry per identity.
List<ProfileFrameRow> alignProfileFrames(
  List<ProfileFrameColumn> columns, {
  int? limit,
}) {
  final identities = <(String, String, String?)>{};
  final lookups = [
    for (final _ in columns) <(String, String, String?), ProfileFrameSummary>{},
  ];
  for (var i = 0; i < columns.length; i++) {
    for (final frame in columns[i].frames) {
      final key = (frame.name, frame.kind, frame.location);
      if (lookups[i].containsKey(key)) {
        throw ArgumentError('Duplicate frame identity in ${columns[i].label}');
      }
      identities.add(key);
      lookups[i][key] = frame;
    }
  }
  final keys = identities.toList()
    ..sort((a, b) {
      final byPercent = (lookups.first[b]?.selfPercent ?? -1).compareTo(
        lookups.first[a]?.selfPercent ?? -1,
      );
      if (byPercent != 0) return byPercent;
      final byName = a.$1.compareTo(b.$1);
      if (byName != 0) return byName;
      final byKind = a.$2.compareTo(b.$2);
      if (byKind != 0) return byKind;
      return (a.$3 ?? '').compareTo(b.$3 ?? '');
    });
  return [
    for (final key in limit != null && limit > 0 ? keys.take(limit) : keys)
      ProfileFrameRow(
        name: key.$1,
        kind: key.$2,
        location: key.$3,
        frames: List.unmodifiable([for (final lookup in lookups) lookup[key]]),
      ),
  ];
}
