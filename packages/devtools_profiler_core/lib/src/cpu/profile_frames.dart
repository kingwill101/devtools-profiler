import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';

const _closureName = '<closure>';
const _anonymousClosureName = '<anonymous closure>';
const _dartScheme = 'dart:';
const _dartSdkUriPrefix = 'org-dartlang-sdk:///';
const _flutterPackagePrefix = 'package:flutter/';
const _dartUiLibrary = 'dart:ui';
const _flutterEnginePrefix = 'flutter::';

/// A predicate that determines whether a [ProfileFrame] should be included.
typedef ProfileFramePredicate = bool Function(ProfileFrame frame);

/// Metadata for a resolved CPU profile frame.
class ProfileFrame {
  /// Creates a resolved CPU profile frame.
  const ProfileFrame({
    required this.name,
    required this.kind,
    required this.location,
  });

  /// The display name for the frame.
  final String name;

  /// The VM-reported frame kind.
  final String kind;

  /// The resolved source location, when available.
  final String? location;

  /// A stable key used to merge matching frames.
  String get key => '$name|$kind|${location ?? ''}';

  /// Whether the frame belongs to the Dart SDK.
  bool get isDartCore {
    final source = location;
    return source != null &&
        (source.startsWith(_dartScheme) ||
            source.startsWith(_dartSdkUriPrefix));
  }

  /// Whether the frame belongs to Flutter framework or engine code.
  bool get isFlutterCore {
    final source = location;
    return name.startsWith(_flutterEnginePrefix) ||
        (source != null &&
            (source.startsWith(_flutterPackagePrefix) ||
                source.startsWith(_dartUiLibrary)));
  }

  /// Whether the frame belongs to SDK-managed libraries.
  bool get isSdk => isDartCore || isFlutterCore;

  /// The package name for `package:`, pub-cache, or local package frames.
  String? get packageName {
    final source = location;
    if (source == null || source.isEmpty) {
      return null;
    }
    if (source.startsWith('package:')) {
      final suffix = source.substring('package:'.length);
      final slashIndex = suffix.indexOf('/');
      return slashIndex == -1 ? suffix : suffix.substring(0, slashIndex);
    }

    final parsedUri = Uri.tryParse(source);
    if (parsedUri == null || parsedUri.scheme != 'file') {
      return null;
    }

    return _packageNameFromFilePath(parsedUri.toFilePath());
  }

  /// Whether the frame belongs to `dart:async` and should be collapsed into
  /// an "async overhead" entry when [ProfilePresentationOptions.collapseAsync]
  /// is enabled.
  bool get isAsyncOverhead {
    final source = location;
    if (source == null || source.isEmpty) return false;
    if (source.startsWith('dart:async')) return true;
    // org-dartlang-sdk:///sdk/lib/async/...
    if (source.startsWith('org-dartlang-sdk:///sdk/lib/async/')) return true;
    if (packageName == 'dart:async') return true;
    return false;
  }

  /// Whether the frame represents native code.
  bool get isNative {
    final source = location;
    if (kind.toLowerCase() == 'native') {
      return true;
    }
    return (source == null || source.isEmpty) &&
        !name.startsWith(_flutterEnginePrefix);
  }
}

String? _packageNameFromFilePath(String filePath) {
  final segments = path.split(path.normalize(filePath));

  final pubCacheIndex = segments.lastIndexOf('.pub-cache');
  if (pubCacheIndex != -1) {
    final libIndex = segments.indexOf('lib', pubCacheIndex);
    if (libIndex == -1 || libIndex <= pubCacheIndex + 1) {
      return null;
    }
    return _packageNameFromPubCacheFolder(segments[libIndex - 1]);
  }

  final libIndex = segments.indexOf('lib');
  if (libIndex <= 0) {
    return null;
  }
  final packageDirectoryName = segments[libIndex - 1];
  if (packageDirectoryName.isEmpty || packageDirectoryName == path.separator) {
    return null;
  }
  return _packageNameFromPubCacheFolder(packageDirectoryName);
}

String _packageNameFromPubCacheFolder(String folder) {
  final versionMatch = RegExp(r'^(.+)-(\d+\.\d+\.\d+(?:[-+].*)?)$')
      .firstMatch(folder);
  return versionMatch?.group(1) ?? folder;
}

ProfileFrame profileFrameFromFunction(
  List<ProfileFunction> functions,
  int functionIndex,
) {
  if (functionIndex < 0 || functionIndex >= functions.length) {
    return const ProfileFrame(name: 'unknown', kind: 'unknown', location: null);
  }

  final function = functions[functionIndex];
  return ProfileFrame(
    name: displayNameForFunction(function),
    kind: function.kind ?? 'unknown',
    location: locationForFunction(function),
  );
}

List<ProfileFrame> filterStackFrames(
  List<int> stack,
  List<ProfileFunction> functions, {
  ProfileFramePredicate? includeFrame,
}) =>
    ProfileFrameResolver(functions)
        .filterStack(stack, includeFrame: includeFrame);

/// Resolves function metadata once per index within one CPU profile.
///
/// Create a new resolver for each profile or changed function table. The
/// function table must not be mutated while this resolver is in use.
/// Stack lists and predicate results are not cached, so memory is bounded by
/// the number of referenced functions, not by the number of samples.
final class ProfileFrameResolver {
  /// Creates a resolver for [functions].
  ProfileFrameResolver(List<ProfileFunction> functions)
    : _functions = functions;

  final List<ProfileFunction> _functions;
  final Map<int, ProfileFrame> _frames = {};

  /// Returns the cached metadata for [functionIndex].
  ProfileFrame resolve(int functionIndex) {
    // Invalid indices share one unknown entry rather than growing the cache.
    final index = functionIndex < 0 || functionIndex >= _functions.length
        ? -1
        : functionIndex;
    return _frames.putIfAbsent(
      index,
      () => profileFrameFromFunction(_functions, index),
    );
  }

  /// Returns included frames in stack order, preserving recursive occurrences.
  ///
  /// [includeFrame] is evaluated for each occurrence, including cached frames.
  List<ProfileFrame> filterStack(
    List<int> stack, {
    ProfileFramePredicate? includeFrame,
  }) {
    if (stack.isEmpty) return const [];
    final frames = <ProfileFrame>[];
    for (final index in stack) {
      final frame = resolve(index);
      if (includeFrame == null || includeFrame(frame)) {
        frames.add(frame);
      }
    }
    return frames;
  }
}

/// Returns a human-readable name for a VM profile function.
String displayNameForFunction(ProfileFunction function) {
  final object = function.function;
  if (object case FuncRef(name: final functionName?)) {
    final owner = object.owner;
    String? name;
    if (owner case ClassRef(name: final className?)) {
      name = '$className.$functionName';
    } else if (functionName == _anonymousClosureName) {
      name = _closureDisplayName(object);
    } else {
      name = functionName;
    }
    return _simplifyStackFrameName(name);
  }
  if (object case NativeFunction(name: final nativeName?)) {
    return _simplifyStackFrameName(nativeName);
  }
  return 'unknown';
}

/// Returns the best source location available for a VM profile function.
String? locationForFunction(ProfileFunction function) {
  // Prefer package: URIs from script location over resolved file paths.
  // This gives us stable package-relative paths instead of machine-specific
  // absolute file paths, making profile output portable across machines.
  final object = function.function;
  if (object case FuncRef(location: final location?)) {
    final scriptUri = location.script?.uri;
    if (scriptUri != null && scriptUri.isNotEmpty) {
      return scriptUri;
    }
  }

  // Fall back to resolved file path when no package URI is available.
  final resolvedUrl = function.resolvedUrl;
  if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
    return resolvedUrl;
  }

  return null;
}

String? _closureDisplayName(FuncRef function) {
  final nameParts = <String?>[_anonymousClosureName];
  final owner = function.owner;
  if (owner case FuncRef(name: final ownerFunctionName?)) {
    String? className;
    final ownerOwner = owner.owner;
    if (ownerOwner case ClassRef(name: final classOwnerName?)) {
      className = classOwnerName;
    }
    nameParts.insertAll(0, [className, ownerFunctionName]);
  } else if (owner case ClassRef(name: final className?)) {
    nameParts.insert(0, className);
  }
  return nameParts.nonNulls.join('.');
}

String _simplifyStackFrameName(String? name) {
  final normalized = (name ?? '').replaceAll(
    _anonymousClosureName,
    _closureName,
  );
  if (normalized.contains(' ')) {
    return normalized;
  }
  return normalized.split('&').last;
}

/// Returns the approximate source line number for [function], or `null` if
/// the line number is unavailable.
int? lineForFunction(ProfileFunction function) {
  final object = function.function;
  if (object case FuncRef(location: final SourceLocation location?)) {
    return location.line;
  }
  return null;
}
