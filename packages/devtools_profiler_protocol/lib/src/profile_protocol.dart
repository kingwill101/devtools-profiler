
/// Supported profiler capture kinds.
enum ProfileCaptureKind {
  /// CPU sampling via the VM service profiler.
  cpu,

  /// Memory and allocation sampling.
  memory,

  /// Timeline and trace event capture.
  timeline;

  /// Parses a wire value.
  static ProfileCaptureKind parse(String value) {
    for (final kind in values) {
      if (kind.name == value) {
        return kind;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unsupported capture kind.');
  }
}

/// Supported isolate scopes for a profiling region.
enum ProfileIsolateScope {
  /// Profile only the isolate that started the region.
  current,

  /// Profile all non-system isolates in the target VM.
  all;

  /// Parses a wire value.
  static ProfileIsolateScope parse(String value) {
    for (final scope in values) {
      if (scope.name == value) {
        return scope;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unsupported isolate scope.');
  }
}

/// The default capture kinds for a region request.
const defaultProfileCaptureKinds = <ProfileCaptureKind>[
  ProfileCaptureKind.cpu,
  ProfileCaptureKind.memory,
];

/// Shared region options passed between the helper and backend.
class ProfileRegionOptions {
  /// Creates region options.
  const ProfileRegionOptions({
    this.captureKinds = defaultProfileCaptureKinds,
    this.isolateScope = ProfileIsolateScope.current,
    this.parentRegionId,
  });

  /// Deserializes options from JSON-compatible data.
  factory ProfileRegionOptions.fromJson(Map<String, Object?> json) {
    final captureKinds = switch (json['captureKinds']) {
      final List<Object?> values => [
          for (final value in values)
            ProfileCaptureKind.parse(value.toString()),
        ],
      _ => defaultProfileCaptureKinds,
    };
    final isolateScope = switch (json['isolateScope']) {
      final String value => ProfileIsolateScope.parse(value),
      _ => ProfileIsolateScope.current,
    };
    return ProfileRegionOptions(
      captureKinds: normalizeProfileCaptureKinds(captureKinds),
      isolateScope: isolateScope,
      parentRegionId: json['parentRegionId'] as String?,
    );
  }

  /// Capture kinds requested for the region.
  final List<ProfileCaptureKind> captureKinds;

  /// The isolate scope requested for the region.
  final ProfileIsolateScope isolateScope;

  /// The parent region id when this region is nested under another.
  final String? parentRegionId;

  /// Whether CPU capture is requested.
  bool get capturesCpu => captureKinds.contains(ProfileCaptureKind.cpu);

  /// Whether memory capture is requested.
  bool get capturesMemory => captureKinds.contains(ProfileCaptureKind.memory);

  /// Returns a copy with selected fields replaced.
  ProfileRegionOptions copyWith({
    List<ProfileCaptureKind>? captureKinds,
    ProfileIsolateScope? isolateScope,
    String? parentRegionId,
    bool clearParentRegionId = false,
  }) {
    return ProfileRegionOptions(
      captureKinds: captureKinds ?? this.captureKinds,
      isolateScope: isolateScope ?? this.isolateScope,
      parentRegionId:
          clearParentRegionId ? null : parentRegionId ?? this.parentRegionId,
    );
  }

  /// Converts options to JSON-compatible data.
  Map<String, Object?> toJson() => {
        'captureKinds': [for (final kind in captureKinds) kind.name],
        'isolateScope': isolateScope.name,
        'parentRegionId': parentRegionId,
      };
}

/// Normalizes capture kinds by removing duplicates while preserving order.
List<ProfileCaptureKind> normalizeProfileCaptureKinds(
  Iterable<ProfileCaptureKind> captureKinds,
) {
  final normalized = <ProfileCaptureKind>[];
  for (final kind in captureKinds) {
    if (!normalized.contains(kind)) {
      normalized.add(kind);
    }
  }
  return normalized.isEmpty ? [...defaultProfileCaptureKinds] : normalized;
}

/// Normalizes isolate scopes by removing duplicates while preserving order.
List<ProfileIsolateScope> normalizeProfileIsolateScopes(
  Iterable<ProfileIsolateScope> isolateScopes,
) {
  final normalized = <ProfileIsolateScope>[];
  for (final scope in isolateScopes) {
    if (!normalized.contains(scope)) {
      normalized.add(scope);
    }
  }
  return normalized;
}
