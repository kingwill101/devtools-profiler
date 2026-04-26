import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;

import '../presentation.dart';

const _dartSdkUriPrefix = 'org-dartlang-sdk:///sdk/lib/';

String treeHeading(
  ProfileCallTreeView view,
  ProfilePresentationOptions options,
) {
  final details = <String>[
    switch (view) {
      ProfileCallTreeView.topDown => 'top-down',
      ProfileCallTreeView.bottomUp => 'bottom-up',
    },
  ];
  details.add(
    options.maxDepth == null ? 'full depth' : 'depth ${options.maxDepth}',
  );
  details.add(
    options.maxChildren == null
        ? 'all children'
        : 'max ${options.maxChildren} children',
  );
  if (options.hideSdk) {
    details.add('sdk hidden');
  }
  return switch (view) {
    ProfileCallTreeView.topDown => 'Call Tree (${details.join(', ')})',
    ProfileCallTreeView.bottomUp => 'Bottom Up Tree (${details.join(', ')})',
  };
}

Map<String, dynamic> callTreeChildrenData(
  ProfileCallTreeNode node, {
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  return {
    for (final child in node.children)
      callTreeLabel(
        child,
        workingDirectory: workingDirectory,
        options: options,
      ): child.children.isEmpty
          ? null
          : callTreeChildrenData(
              child,
              workingDirectory: workingDirectory,
              options: options,
            ),
  };
}

String callTreeLabel(
  ProfileCallTreeNode node, {
  bool isRoot = false,
  required String? workingDirectory,
  required ProfilePresentationOptions options,
}) {
  final displayName = displayNameWithLocation(
    node.name,
    node.location,
    fullLocations: fullLocationsEnabled(options),
    workingDirectory: workingDirectory,
  );
  if (isRoot) {
    return '$displayName [samples ${node.totalSamples}]';
  }
  return '$displayName [self ${node.selfSamples}, total ${node.totalSamples}, '
      '${formatPercent(node.selfPercent)} self, '
      '${formatPercent(node.totalPercent)} total]';
}

String formatMicros(int micros) {
  if (micros >= Duration.microsecondsPerSecond) {
    return '${(micros / Duration.microsecondsPerSecond).toStringAsFixed(2)}s';
  }
  if (micros >= Duration.microsecondsPerMillisecond) {
    return '${(micros / Duration.microsecondsPerMillisecond).toStringAsFixed(2)}ms';
  }
  return '${micros}us';
}

String formatPercent(double percent) =>
    '${(percent * 100).toStringAsFixed(1)}%';

String formatSignedPercent(double percent) {
  final formatted = formatPercent(percent.abs());
  if (percent > 0) {
    return '+$formatted';
  }
  if (percent < 0) {
    return '-$formatted';
  }
  return formatted;
}

String formatBytes(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value.abs() >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final precision = unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}

String formatSignedBytes(int bytes) {
  if (bytes == 0) {
    return formatBytes(0);
  }
  final prefix = bytes > 0 ? '+' : '-';
  return '$prefix${formatBytes(bytes.abs())}';
}

String formatSignedCount(int count) {
  if (count > 0) {
    return '+$count';
  }
  return '$count';
}

String formatCount(num count) {
  if (count is int) {
    return '$count';
  }
  if (count == count.roundToDouble()) {
    return '${count.toInt()}';
  }
  return count.toStringAsFixed(2);
}

String formatSignedMicros(int micros) {
  if (micros == 0) {
    return formatMicros(0);
  }
  final prefix = micros > 0 ? '+' : '-';
  return '$prefix${formatMicros(micros.abs())}';
}

String formatPercentChange(ProfileNumericDelta delta) {
  final percentChange = delta.percentChange;
  if (percentChange == null) {
    return '-';
  }
  final prefix = percentChange > 0 ? '+' : '';
  return '$prefix${percentChange.toStringAsFixed(1)}%';
}

String formatDeltaBytes(ProfileNumericDelta delta) {
  return '${formatSignedBytes(delta.delta.toInt())} '
      '(${formatBytes(delta.baseline.toInt())} -> '
      '${formatBytes(delta.current.toInt())})';
}

String formatDeltaCount(ProfileNumericDelta delta) {
  return '${formatSignedCount(delta.delta.toInt())} '
      '(${formatCount(delta.baseline)} -> ${formatCount(delta.current)})';
}

String shellJoin(Iterable<String> arguments) {
  return arguments.map(shellQuote).join(' ');
}

String shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  const specialCharacters = "'\"\\\$`!|&;<>(){}[]*?";
  final needsQuoting = value.runes.any(
    (rune) =>
        String.fromCharCode(rune).trim().isEmpty ||
        specialCharacters.contains(String.fromCharCode(rune)),
  );
  if (!needsQuoting) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}

String topFrameName(List<ProfileFrameSummary> frames) {
  if (frames.isEmpty) {
    return '-';
  }
  return frames.first.name;
}

String formatCaptureKinds(List<ProfileCaptureKind> captureKinds) {
  return captureKinds.map((kind) => kind.name).join(', ');
}

String formatIsolateScopes(List<ProfileIsolateScope> isolateScopes) {
  return isolateScopes.map((scope) => scope.name).join(', ');
}

String formatIsolateIds(List<String> isolateIds) {
  if (isolateIds.isEmpty) {
    return '-';
  }
  if (isolateIds.length <= 3) {
    return isolateIds.join(', ');
  }
  return '${isolateIds.length} isolates (${isolateIds.take(3).join(', ')}, ...)';
}

String displayNameWithLocation(
  String name,
  String? location, {
  required bool fullLocations,
  required String? workingDirectory,
}) {
  final locationLabel = displayLocation(
    location,
    fullLocations: fullLocations,
    workingDirectory: workingDirectory,
  );
  if (locationLabel == '-') {
    return name;
  }
  return '$name - ($locationLabel)';
}

String displayLocation(
  String? location, {
  required bool fullLocations,
  required String? workingDirectory,
}) {
  if (location == null || location.isEmpty) {
    return '-';
  }
  if (fullLocations) {
    return location;
  }
  if (location.startsWith(_dartSdkUriPrefix)) {
    return 'sdk:${location.substring(_dartSdkUriPrefix.length)}';
  }
  if (location.startsWith('dart:') || location.startsWith('package:')) {
    return location;
  }

  final parsedUri = Uri.tryParse(location);
  if (parsedUri != null && parsedUri.scheme == 'file') {
    return shortFilePath(parsedUri.toFilePath(), workingDirectory);
  }

  return location;
}

String shortFilePath(String filePath, String? workingDirectory) {
  final normalized = path.normalize(filePath);
  if (workingDirectory != null && path.isWithin(workingDirectory, normalized)) {
    return path.relative(normalized, from: workingDirectory);
  }

  final segments = path.split(normalized);
  final pubCacheIndex = segments.lastIndexOf('.pub-cache');
  if (pubCacheIndex != -1) {
    final libIndex = segments.indexOf('lib', pubCacheIndex);
    if (libIndex != -1 &&
        libIndex > pubCacheIndex + 1 &&
        libIndex < segments.length) {
      final packageFolder = segments[libIndex - 1];
      final packageName = packageNameFromFolder(packageFolder);
      final rest = segments.skip(libIndex + 1).join('/');
      return rest.isEmpty
          ? 'package:$packageName'
          : 'package:$packageName/$rest';
    }
  }

  if (segments.length <= 4) {
    return normalized;
  }
  return '.../${segments.skip(segments.length - 4).join('/')}';
}

String packageNameFromFolder(String folder) {
  final versionMatch = RegExp(
    r'^(.+)-(\d+\.\d+\.\d+(?:[-+].*)?)$',
  ).firstMatch(folder);
  return versionMatch?.group(1) ?? folder;
}

String? workingDirectoryFromRegionPath(ProfileRegionResult region) {
  final rawProfilePath = region.rawProfilePath;
  if (rawProfilePath == null || rawProfilePath.isEmpty) {
    return null;
  }
  final segments = path.split(path.normalize(rawProfilePath));
  final dartToolIndex = segments.lastIndexOf('.dart_tool');
  if (dartToolIndex <= 0) {
    return null;
  }
  return path.joinAll(segments.take(dartToolIndex));
}

bool fullLocationsEnabled(ProfilePresentationOptions options) =>
    options.fullLocations;
