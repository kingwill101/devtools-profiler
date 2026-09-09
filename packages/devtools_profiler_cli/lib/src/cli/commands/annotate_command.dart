import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';

import '../constants.dart';
import '../options.dart';
import 'profile_target_command.dart';

/// Command that annotates function definition lines with self sample counts.
///
/// Uses the function's [lineForFunction] location, not the sampled statement.
/// This does not provide statement-level execution counts.
class AnnotateCommand extends ProfileTargetCommand {
  /// Creates an annotate command.
  AnnotateCommand(super.profileRunner) {
    argParser
      ..addOption(
        'file',
        help: 'Only annotate this specific source file. Matches file name.',
      )
      ..addOption(
        'top',
        defaultsTo: '30',
        help: 'Maximum source lines to show. Use 0 for unlimited.',
      )
      ..addOption(
        'min-samples',
        defaultsTo: '1',
        help: 'Minimum sample count to show a line.',
      )
      ..addOption(
        'context',
        defaultsTo: '2',
        help: 'Number of non-annotated context lines to show around each hit.',
      );
  }

  @override
  String get name => 'annotate';

  @override
  String get description =>
      'Annotate function definition lines with self sample counts.';

  @override
  String get invocation => '${runner!.executableName} annotate [path]';

  @override
  String formatUsage({bool includeDescription = true}) => usageWithExamples(
    super.formatUsage(includeDescription: includeDescription),
    const [
      'devtools-profiler annotate /path/to/session',
      'devtools-profiler annotate --file vm.dart 0712060003-8c410',
      'devtools-profiler annotate --top 50 --min-samples 5 --context 3 /path/to/session',
    ],
  );

  @override
  Future<int> run() async {
    final targetPath = await resolveTargetPath();
    final fileFilter = argResults!['file'] as String?;
    final topLimit = parseLimit(
      argResults!['top'] as String?,
      optionName: 'top',
    );
    final minSamples = parseNonNegativeInt(
      argResults!['min-samples'] as String?,
      optionName: 'min-samples',
    );
    final context = parseNonNegativeInt(
      argResults!['context'] as String?,
      optionName: 'context',
    );

    // Read the artifact and extract topSelfFrames + raw CPU samples.
    final summary = await profileRunner.summarizeArtifact(targetPath);

    final List<ProfileFrameSummary> topSelfFrames;
    final int totalSampleCount;
    CpuSamples? cpuSamples;

    if (summary case {'regions': final Object? _}) {
      final session = ProfileRunResult.fromJson(summary);
      final profile =
          session.overallProfile ??
          (session.regions.isNotEmpty ? session.regions.first : null);
      if (profile == null) {
        throw ArgumentError('No profile data found at "$targetPath".');
      }
      topSelfFrames = profile.topSelfFrames;
      totalSampleCount = profile.sampleCount;
      if (profile.rawProfilePath != null) {
        cpuSamples = await profileRunner.readCpuSamples(
          profile.rawProfilePath!,
        );
      }
    } else if (summary case {'topSelfFrames': final Object? _}) {
      final region = ProfileRegionResult.fromJson(summary);
      topSelfFrames = region.topSelfFrames;
      totalSampleCount = region.sampleCount;
      if (region.rawProfilePath != null) {
        cpuSamples = await profileRunner.readCpuSamples(region.rawProfilePath!);
      }
    } else {
      throw ArgumentError(
        'Unsupported target at "$targetPath". '
        'Use a session directory or a profile summary artifact.',
      );
    }

    if (topSelfFrames.isEmpty) {
      warn('No profile samples available for annotation.');
      return successExitCode;
    }

    // Build line-level and function-level counts from raw CPU samples.
    // lineCounts: file -> line -> sample count
    final lineCounts = <String, Map<int, int>>{};
    // functionCounts: file -> function name -> sample count (fallback)
    final functionCounts = <String, Map<String, int>>{};

    if (cpuSamples != null &&
        cpuSamples.functions != null &&
        cpuSamples.samples != null) {
      final functions = cpuSamples.functions!;
      for (final sample in cpuSamples.samples!) {
        final stack = sample.stack ?? const <int>[];
        if (stack.isEmpty) continue;
        final funcIdx = stack.first;
        if (funcIdx < 0 || funcIdx >= functions.length) continue;
        final func = functions[funcIdx];
        final loc = locationForFunction(func);
        if (loc == null || loc.isEmpty) continue;
        if (loc.startsWith('dart:') || loc.startsWith('org-dartlang-sdk://')) {
          continue;
        }
        final resolved = _resolveSourceFile(loc);
        if (resolved == null) continue;

        final funcName = displayNameForFunction(func);
        functionCounts.putIfAbsent(resolved, () => {});
        functionCounts[resolved]![funcName] =
            (functionCounts[resolved]![funcName] ?? 0) + 1;

        // Line-level: use the function's definition line.
        final line = lineForFunction(func);
        if (line != null) {
          lineCounts.putIfAbsent(resolved, () => {});
          lineCounts[resolved]![line] = (lineCounts[resolved]![line] ?? 0) + 1;
        }
      }
    } else {
      // Fallback: use topSelfFrames (function-level only).
      for (final frame in topSelfFrames) {
        final loc = frame.location;
        if (loc == null || loc.isEmpty) continue;
        if (loc.startsWith('dart:') || loc.startsWith('org-dartlang-sdk://')) {
          continue;
        }
        final resolved = _resolveSourceFile(loc);
        if (resolved == null) continue;
        functionCounts.putIfAbsent(resolved, () => {});
        functionCounts[resolved]![frame.name] =
            (functionCounts[resolved]![frame.name] ?? 0) + frame.selfSamples;
      }
    }

    if (functionCounts.isEmpty) {
      warn('No source files could be resolved from profile data.');
      return successExitCode;
    }

    // Sort files by total sample count.
    final sortedFiles = functionCounts.entries.toList()
      ..sort(
        (a, b) => b.value.values
            .fold(0, (s, v) => s + v)
            .compareTo(a.value.values.fold(0, (s, v) => s + v)),
      );

    // Apply file filter.
    final filesToShow = fileFilter != null
        ? sortedFiles.where((e) => path.basename(e.key).contains(fileFilter))
        : sortedFiles.take(5);

    final filesList = filesToShow.toList();
    if (fileFilter == null && sortedFiles.length > filesList.length) {
      line(
        'Showing ${filesList.length} of ${sortedFiles.length} files. '
        'Use --file to select omitted files.',
      );
    }
    if (filesList.isEmpty) {
      warn('No files matched filter "$fileFilter".');
      return successExitCode;
    }

    final divisor = totalSampleCount == 0 ? 1 : totalSampleCount;

    for (final fileEntry in filesList) {
      final filePath = fileEntry.key;
      if (!File(filePath).existsSync()) {
        warn('Source file not found: $filePath');
        continue;
      }

      final sourceLines = File(filePath).readAsLinesSync();
      final fileLineCounts = lineCounts[filePath] ?? {};
      final fileFuncCounts = functionCounts[filePath] ?? {};

      line('');
      line(
        '╔══ ${path.basename(filePath)} '
        '(${fileFuncCounts.values.fold<int>(0, (s, v) => s + v)} total samples)',
      );
      line('');

      if (fileLineCounts.isNotEmpty) {
        // Line-level annotation.
        final sortedLines = fileLineCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        final eligibleLines = sortedLines.where(
          (e) => e.value >= (minSamples ?? 1),
        );
        final shownLines =
            (topLimit == null ? eligibleLines : eligibleLines.take(topLimit))
                .toList();

        if (shownLines.isEmpty) {
          line('  (no lines meet minimum sample threshold)');
        } else {
          final maxCount = shownLines.first.value;

          // Collect hit line numbers for context window.
          final hitLines = shownLines.map((e) => e.key).toSet();

          // Print each hit line with surrounding context.
          for (final (entryIndex, entry) in shownLines.indexed) {
            final lineNum = entry.key;
            final count = entry.value;
            final pct = (count / divisor) * 100;
            final barLen = ((count / maxCount) * 20).round().clamp(1, 20);
            final bar = '█' * barLen;
            final srcLine = lineNum > 0 && lineNum <= sourceLines.length
                ? sourceLines[lineNum - 1]
                : '';

            line(
              '${count.toString().padLeft(5)} (${pct.toStringAsFixed(1)}%) '
              '$bar │ ${lineNum.toString().padRight(5)} $srcLine',
            );

            // Show context lines after (if not the last hit).
            if (entryIndex < shownLines.length - 1) {
              final nextLine = shownLines[entryIndex + 1].key;
              for (
                var ctx = lineNum + 1;
                ctx < nextLine && ctx <= sourceLines.length;
                ctx++
              ) {
                if (hitLines.contains(ctx)) break;
                if (ctx - lineNum > (context ?? 2)) break;
                line(
                  '${' '.padLeft(5)} ${' '.padLeft(7)} │ '
                  '${ctx.toString().padRight(5)} ${sourceLines[ctx - 1]}',
                );
              }
            }
          }
        }
      } else {
        // Function-level fallback annotation.
        final sorted = fileFuncCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final maxCount = sorted.isEmpty ? 1 : sorted.first.value;
        final eligible = sorted.where((e) => e.value >= (minSamples ?? 1));
        final shown = topLimit == null ? eligible : eligible.take(topLimit);

        for (final entry in shown) {
          final pct = (entry.value / divisor) * 100;
          final barLen = ((entry.value / maxCount) * 20).round().clamp(1, 20);
          final bar = '█' * barLen;
          line(
            '${entry.value.toString().padLeft(5)} (${pct.toStringAsFixed(1)}%) '
            '$bar │ ${entry.key}',
          );
        }
        if (shown.isEmpty) {
          line('  (no functions meet minimum sample threshold)');
        }
      }
      line('');
    }

    return successExitCode;
  }

  /// Resolves package/file URIs or existing local paths; otherwise returns null.
  String? _resolveSourceFile(String location) {
    if (location.startsWith('package:')) {
      return _resolvePackageUri(location);
    }
    if (location.startsWith('file://')) {
      final filePath = Uri.parse(location).toFilePath();
      if (File(filePath).existsSync()) return filePath;
      return null;
    }
    if (File(location).existsSync()) return location;
    return null;
  }

  /// Searches at most eight ancestors for the first package configuration.
  ///
  /// Returns null when no configuration or matching source file is found.
  String? _resolvePackageUri(String packageUri) {
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
      final configFile = File(
        path.join(dir.path, '.dart_tool', 'package_config.json'),
      );
      if (configFile.existsSync()) {
        return _resolveFromPackageConfig(configFile, packageUri);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  /// Resolves a package root using rootUri, trying lib/ then root-relative paths.
  ///
  /// Custom packageUri mappings are not supported. Missing files or invalid
  /// configurations return null.
  String? _resolveFromPackageConfig(File configFile, String packageUri) {
    try {
      final configDir = configFile.parent;
      final config =
          jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
      final packages = config['packages'] as List<Object?>? ?? [];
      for (final pkg in packages) {
        final pkgMap = pkg as Map<String, Object?>;
        final name = pkgMap['name'] as String?;
        final rootUri = pkgMap['rootUri'] as String?;
        if (name == null || rootUri == null) continue;

        final prefix = 'package:$name/';
        if (packageUri.startsWith(prefix)) {
          final relativePath = packageUri.substring(prefix.length);
          final pkgRoot = rootUri.startsWith('file://')
              ? Uri.parse(rootUri).toFilePath()
              : path.normalize(path.join(configDir.path, rootUri));
          var resolved = path.normalize(
            path.join(pkgRoot, 'lib', relativePath),
          );
          if (File(resolved).existsSync()) return resolved;
          resolved = path.normalize(path.join(pkgRoot, relativePath));
          if (File(resolved).existsSync()) return resolved;
        }
      }
    } catch (_) {}
    return null;
  }
}
