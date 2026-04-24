/// Supported profiler capture kinds.
enum ProfileCaptureKind {
  /// CPU sampling via the VM service profiler.
  cpu,

  /// Memory and allocation sampling.
  memory,

  /// Timeline and trace event capture.
  ///
  /// This value is part of the shared protocol so callers can express timeline
  /// intent consistently even when the current backend does not yet implement
  /// timeline capture.
  timeline;

  /// Parses the wire-format [value] into a capture kind.
  ///
  /// Throws an [ArgumentError] when [value] does not match one of the known
  /// enum names.
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

  /// Parses the wire-format [value] into an isolate scope.
  ///
  /// Throws an [ArgumentError] when [value] does not match one of the known
  /// enum names.
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
///
/// Regions capture both CPU and memory data unless the caller requests a more
/// specific subset.
const defaultProfileCaptureKinds = <ProfileCaptureKind>[
  ProfileCaptureKind.cpu,
  ProfileCaptureKind.memory,
];

/// Shared region options passed between the helper and backend.
///
/// This object is the protocol contract for explicit profiling regions. It is
/// intentionally JSON-friendly so app-side helpers, the CLI, and backend
/// components can exchange it without additional adapters.
///
/// ```dart
/// const options = ProfileRegionOptions(
///   captureKinds: [ProfileCaptureKind.cpu],
///   isolateScope: ProfileIsolateScope.current,
///   parentRegionId: 'request-1',
/// );
/// ```
class ProfileRegionOptions {
  /// Creates region options.
  ///
  /// When [captureKinds] is omitted, regions default to CPU and memory
  /// capture. When [isolateScope] is omitted, regions default to the current
  /// isolate only.
  const ProfileRegionOptions({
    this.captureKinds = defaultProfileCaptureKinds,
    this.isolateScope = ProfileIsolateScope.current,
    this.parentRegionId,
  });

  /// Deserializes options from JSON-compatible data.
  ///
  /// Missing `captureKinds` values default to [defaultProfileCaptureKinds], and
  /// missing `isolateScope` values default to [ProfileIsolateScope.current].
  /// Duplicate capture kinds are normalized away while preserving order.
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

  /// Capture kinds requested for this region.
  final List<ProfileCaptureKind> captureKinds;

  /// The isolate scope requested for this region.
  final ProfileIsolateScope isolateScope;

  /// The parent region identifier when this region is nested under another.
  ///
  /// `null` means the region is top-level unless a higher-level helper fills in
  /// an inherited parent automatically.
  final String? parentRegionId;

  /// Whether CPU capture is requested.
  bool get capturesCpu => captureKinds.contains(ProfileCaptureKind.cpu);

  /// Whether memory capture is requested.
  bool get capturesMemory => captureKinds.contains(ProfileCaptureKind.memory);

  /// Returns a copy with selected fields replaced.
  ///
  /// Set [clearParentRegionId] to `true` to remove the current parent even
  /// when [parentRegionId] is omitted.
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

  /// Converts these options to JSON-compatible data.
  Map<String, Object?> toJson() => {
        'captureKinds': [for (final kind in captureKinds) kind.name],
        'isolateScope': isolateScope.name,
        'parentRegionId': parentRegionId,
      };
}

/// Normalizes capture kinds by removing duplicates while preserving order.
///
/// Returns [defaultProfileCaptureKinds] when [captureKinds] is empty after
/// normalization so callers can treat an empty request as "use defaults".
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
///
/// Unlike [normalizeProfileCaptureKinds], this does not inject defaults because
/// isolate scope is represented by one scalar value in [ProfileRegionOptions].
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
