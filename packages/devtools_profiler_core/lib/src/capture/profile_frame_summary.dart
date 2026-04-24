/// A summary of a single frame observed during CPU sampling.
///
/// These summaries appear in top-self and top-total frame lists for region and
/// whole-session results.
class ProfileFrameSummary {
  /// Creates a frame summary.
  const ProfileFrameSummary({
    required this.name,
    required this.kind,
    required this.selfSamples,
    required this.totalSamples,
    required this.selfPercent,
    required this.totalPercent,
    this.location,
  });

  /// Deserializes a frame summary from JSON.
  factory ProfileFrameSummary.fromJson(Map<String, Object?> json) {
    return ProfileFrameSummary(
      name: json['name'] as String? ?? 'unknown',
      kind: json['kind'] as String? ?? 'unknown',
      location: json['location'] as String?,
      selfSamples: json['selfSamples'] as int? ?? 0,
      totalSamples: json['totalSamples'] as int? ?? 0,
      selfPercent: (json['selfPercent'] as num?)?.toDouble() ?? 0.0,
      totalPercent: (json['totalPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// The display name of the frame.
  final String name;

  /// The VM-reported frame kind.
  final String kind;

  /// The resolved source location, when available.
  final String? location;

  /// The number of times the frame was observed at the top of the stack.
  final int selfSamples;

  /// The number of times the frame was observed anywhere in the stack.
  final int totalSamples;

  /// The percentage of samples attributed to [selfSamples].
  final double selfPercent;

  /// The percentage of samples attributed to [totalSamples].
  final double totalPercent;

  /// Converts this frame summary to JSON.
  Map<String, Object?> toJson() => {
        'name': name,
        'kind': kind,
        'location': location,
        'selfSamples': selfSamples,
        'totalSamples': totalSamples,
        'selfPercent': selfPercent,
        'totalPercent': totalPercent,
      };
}
