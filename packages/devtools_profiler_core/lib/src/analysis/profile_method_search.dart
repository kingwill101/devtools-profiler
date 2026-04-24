import '../cpu/method_table.dart';
import 'profile_method_inspector.dart';

/// Ordering modes for method search results.
enum ProfileMethodSearchSort {
  /// Order by inclusive samples / time first.
  total,

  /// Order by top-of-stack samples / time first.
  self;

  /// Parses a wire value.
  static ProfileMethodSearchSort parse(String value) {
    for (final sort in values) {
      if (sort.name == value) {
        return sort;
      }
    }
    throw ArgumentError.value(
      value,
      'value',
      'Unsupported method search sort.',
    );
  }
}

/// Availability state for method search against a profile target.
enum ProfileMethodSearchStatus {
  /// Method-table data was available and the search ran.
  available,

  /// Method-table data was unavailable for the selected profile.
  unavailable;

  /// Parses a wire value.
  static ProfileMethodSearchStatus parse(String value) {
    for (final status in values) {
      if (status.name == value) {
        return status;
      }
    }
    throw ArgumentError.value(
      value,
      'value',
      'Unsupported method search status.',
    );
  }
}

/// A structured result for searching methods within one prepared profile.
class ProfileMethodSearchResult {
  /// Creates a method search result.
  ProfileMethodSearchResult({
    required this.query,
    required this.sortBy,
    required this.status,
    required this.totalMatches,
    required this.truncated,
    required List<ProfileMethodCandidate> methods,
    this.message,
  }) : methods = List.unmodifiable(methods);

  /// Deserializes a method search result from JSON.
  factory ProfileMethodSearchResult.fromJson(Map<String, Object?> json) {
    return ProfileMethodSearchResult(
      query: json['query'] as String?,
      sortBy: switch (json['sortBy']) {
        final String value => ProfileMethodSearchSort.parse(value),
        _ => ProfileMethodSearchSort.total,
      },
      status: switch (json['status']) {
        final String value => ProfileMethodSearchStatus.parse(value),
        _ => ProfileMethodSearchStatus.available,
      },
      totalMatches: json['totalMatches'] as int? ?? 0,
      truncated: json['truncated'] as bool? ?? false,
      message: json['message'] as String?,
      methods: (json['methods'] as List<Object?>? ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (item) => ProfileMethodCandidate.fromJson(
              item.cast<String, Object?>(),
            ),
          )
          .toList(),
    );
  }

  /// Optional query applied to the method table.
  final String? query;

  /// The ordering mode used for the returned methods.
  final ProfileMethodSearchSort sortBy;

  /// Whether method-table data was available.
  final ProfileMethodSearchStatus status;

  /// Optional human-readable status detail.
  final String? message;

  /// The total number of matches before truncation.
  final int totalMatches;

  /// Whether the results were truncated by a limit.
  final bool truncated;

  /// The returned methods.
  final List<ProfileMethodCandidate> methods;

  /// Converts this result to JSON.
  Map<String, Object?> toJson() => {
        'query': query,
        'sortBy': sortBy.name,
        'status': status.name,
        'message': message,
        'totalMatches': totalMatches,
        'truncated': truncated,
        'methods': [for (final method in methods) method.toJson()],
      };
}

/// Searches a DevTools-style method table for candidate methods.
ProfileMethodSearchResult searchProfileMethods({
  required ProfileMethodTable? methodTable,
  String? query,
  ProfileMethodSearchSort sortBy = ProfileMethodSearchSort.total,
  int? limit,
}) {
  if (methodTable == null) {
    return ProfileMethodSearchResult(
      query: query,
      sortBy: sortBy,
      status: ProfileMethodSearchStatus.unavailable,
      message:
          'Method search requires a raw CPU profile artifact, but no method table was available.',
      totalMatches: 0,
      truncated: false,
      methods: const [],
    );
  }

  final normalizedQuery = query?.trim();
  final lowerQuery = normalizedQuery?.toLowerCase();
  final matches = [
    for (final method in methodTable.methods)
      if (_matchesMethodQuery(method, lowerQuery)) method,
  ];
  matches.sort((left, right) => _compareMethodSearch(left, right, sortBy));

  final normalizedLimit = limit == null || limit <= 0 ? null : limit;
  final totalMatches = matches.length;
  final limitedMatches = normalizedLimit == null
      ? matches
      : matches.take(normalizedLimit).toList(growable: false);

  return ProfileMethodSearchResult(
    query: normalizedQuery,
    sortBy: sortBy,
    status: ProfileMethodSearchStatus.available,
    totalMatches: totalMatches,
    truncated: normalizedLimit != null && totalMatches > limitedMatches.length,
    methods: [
      for (final method in limitedMatches)
        ProfileMethodCandidate.fromSummary(method),
    ],
  );
}

bool _matchesMethodQuery(ProfileMethodSummary method, String? query) {
  if (query == null || query.isEmpty) {
    return true;
  }
  return method.name.toLowerCase().contains(query) ||
      method.methodId.toLowerCase().contains(query) ||
      (method.location?.toLowerCase().contains(query) ?? false);
}

int _compareMethodSearch(
  ProfileMethodSummary left,
  ProfileMethodSummary right,
  ProfileMethodSearchSort sortBy,
) {
  final primaryCompare = switch (sortBy) {
    ProfileMethodSearchSort.total =>
      right.totalSamples.compareTo(left.totalSamples),
    ProfileMethodSearchSort.self =>
      right.selfSamples.compareTo(left.selfSamples),
  };
  if (primaryCompare != 0) {
    return primaryCompare;
  }

  final secondaryCompare = switch (sortBy) {
    ProfileMethodSearchSort.total =>
      right.selfSamples.compareTo(left.selfSamples),
    ProfileMethodSearchSort.self =>
      right.totalSamples.compareTo(left.totalSamples),
  };
  if (secondaryCompare != 0) {
    return secondaryCompare;
  }

  return left.name.compareTo(right.name);
}
