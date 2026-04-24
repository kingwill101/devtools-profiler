import 'package:artisanal/args.dart';

import '../presentation.dart';

/// Adds shared presentation flags to [parser].
void addPresentationOptions(ArgParser parser) {
  parser
    ..addFlag(
      'json',
      negatable: false,
      help: 'Print the result as JSON.',
    )
    ..addFlag(
      'call-tree',
      negatable: false,
      help: 'Include a top-down call tree for each captured region.',
    )
    ..addFlag(
      'bottom-up',
      negatable: false,
      help: 'Include a DevTools-style bottom-up tree for each captured region.',
    )
    ..addFlag(
      'method-table',
      negatable: false,
      help: 'Include a DevTools-style method table with callers and callees.',
    )
    ..addFlag(
      'expand',
      negatable: false,
      help: 'Alias for --call-tree.',
    )
    ..addFlag(
      'hide-sdk',
      negatable: false,
      help: 'Hide Dart and Flutter SDK frames from summaries and call trees.',
    )
    ..addFlag(
      'hide-runtime-helpers',
      negatable: false,
      help: 'Hide common profiler/runtime helper packages from summaries.',
    )
    ..addMultiOption(
      'include-package',
      help:
          'Only include package prefixes that match these values. May be repeated.',
    )
    ..addMultiOption(
      'exclude-package',
      help:
          'Exclude package prefixes that match these values. May be repeated.',
    )
    ..addFlag(
      'full-locations',
      negatable: false,
      help: 'Show full source locations instead of shortened display labels.',
    )
    ..addOption(
      'frame-limit',
      defaultsTo: '$defaultFrameLimit',
      help:
          'Maximum rows per self / total table. Use 0 to show every matching frame.',
    )
    ..addOption(
      'tree-depth',
      defaultsTo: '$defaultTreeDepth',
      help:
          'Maximum call tree depth when --call-tree is used. Use 0 for unlimited.',
    )
    ..addOption(
      'tree-children',
      defaultsTo: '$defaultTreeChildren',
      help:
          'Maximum children per call tree node when --call-tree is used. Use 0 for unlimited.',
    )
    ..addOption(
      'method-limit',
      defaultsTo: '$defaultFrameLimit',
      help:
          'Maximum methods to include when --method-table is used. Use 0 for unlimited.',
    );
}

/// Returns presentation options parsed from [results].
ProfilePresentationOptions presentationOptionsFrom(ArgResults results) {
  final includeCallTree = (results['call-tree'] as bool? ?? false) ||
      (results['expand'] as bool? ?? false);
  return ProfilePresentationOptions(
    includeCallTree: includeCallTree,
    includeBottomUpTree: results['bottom-up'] as bool? ?? false,
    includeMethodTable: results['method-table'] as bool? ?? false,
    hideSdk: results['hide-sdk'] as bool? ?? false,
    hideRuntimeHelpers: results['hide-runtime-helpers'] as bool? ?? false,
    fullLocations: results['full-locations'] as bool? ?? false,
    includePackages: (results['include-package'] as List<String>? ?? const [])
        .where((value) => value.isNotEmpty)
        .toList(growable: false),
    excludePackages: (results['exclude-package'] as List<String>? ?? const [])
        .where((value) => value.isNotEmpty)
        .toList(growable: false),
    frameLimit: parseLimit(
      results['frame-limit'] as String?,
      optionName: 'frame-limit',
    ),
    methodLimit: parseLimit(
      results['method-limit'] as String?,
      optionName: 'method-limit',
    ),
    maxDepth: parseLimit(
      results['tree-depth'] as String?,
      optionName: 'tree-depth',
    ),
    maxChildren: parseLimit(
      results['tree-children'] as String?,
      optionName: 'tree-children',
    ),
  );
}

/// Parses a CLI duration option.
Duration? parseDuration(String? value, {required String optionName}) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final match = RegExp(r'^(\d+)(ms|s|m|h)?$').firstMatch(value);
  if (match == null) {
    throw FormatException(
      'The "$optionName" option must be a duration like 30, 30s, 2m, or 500ms.',
    );
  }
  final amount = int.parse(match.group(1)!);
  if (amount <= 0) {
    throw FormatException('The "$optionName" option must be positive.');
  }
  return switch (match.group(2)) {
    'ms' => Duration(milliseconds: amount),
    's' => Duration(seconds: amount),
    'm' => Duration(minutes: amount),
    'h' => Duration(hours: amount),
    null => Duration(seconds: amount),
    _ => throw FormatException(
        'The "$optionName" option must be a duration like 30, 30s, 2m, or 500ms.',
      ),
  };
}

/// Parses a VM service URI argument.
Uri parseVmServiceUriArgument(String value) {
  final uri = Uri.parse(value);
  if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw const FormatException(
      'The VM service URI must start with http:// or https://.',
    );
  }
  return uri;
}

/// Parses a non-negative row or tree limit.
int? parseLimit(String? value, {required String optionName}) {
  if (value == null || value.isEmpty) {
    return null;
  }

  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) {
    throw FormatException(
      'The "$optionName" option must be a non-negative integer.',
    );
  }
  return parsed == 0 ? null : parsed;
}
