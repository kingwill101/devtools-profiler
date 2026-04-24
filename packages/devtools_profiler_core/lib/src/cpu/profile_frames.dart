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

  /// The package name for `package:` or pub-cache sourced frames.
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

    final filePath = parsedUri.toFilePath();
    final segments = path.split(path.normalize(filePath));
    final pubCacheIndex = segments.lastIndexOf('.pub-cache');
    if (pubCacheIndex == -1) {
      return null;
    }
    final libIndex = segments.indexOf('lib', pubCacheIndex);
    if (libIndex == -1 || libIndex <= pubCacheIndex + 1) {
      return null;
    }
    return _packageNameFromPubCacheFolder(segments[libIndex - 1]);
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

String _packageNameFromPubCacheFolder(String folder) {
  final versionMatch =
      RegExp(r'^(.+)-(\d+\.\d+\.\d+(?:[-+].*)?)$').firstMatch(folder);
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
}) {
  if (stack.isEmpty) {
    return const [];
  }

  final frames = <ProfileFrame>[];
  final resolvedFrames = <int, ProfileFrame>{};
  for (final functionIndex in stack) {
    final frame = resolvedFrames.putIfAbsent(
      functionIndex,
      () => profileFrameFromFunction(functions, functionIndex),
    );
    if (includeFrame == null || includeFrame(frame)) {
      frames.add(frame);
    }
  }
  return frames;
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
  final resolvedUrl = function.resolvedUrl;
  if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
    return resolvedUrl;
  }

  final object = function.function;
  if (object case FuncRef(location: final location?)) {
    return location.script?.uri;
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
