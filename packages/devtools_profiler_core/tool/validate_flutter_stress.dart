import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service_io.dart';

/// Drives the stress fixture through VM RPCs and validates repeatable attaches.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: validate_flutter_stress.dart <vm-uri> <artifact-dir>',
    );
    exitCode = 64;
    return;
  }
  final uri = Uri.parse(arguments[0]);
  final service = await vmServiceConnectUri(
    convertToWebSocketUrl(serviceProtocolUrl: uri).toString(),
  );
  String? mainId;
  Timer? retirementTimer;
  try {
    for (final isolate in (await service.getVM()).isolates!) {
      final details = await service.getIsolate(isolate.id!);
      if (details.extensionRPCs?.contains('ext.profilerFixture.start') ??
          false) {
        mainId = isolate.id;
        break;
      }
    }
    if (mainId == null) throw StateError('Stress fixture RPCs not available.');
    for (var window = 0; window < 2; window++) {
      await service.callServiceExtension(
        'ext.profilerFixture.start',
        isolateId: mainId,
      );
      // An observed worker exits during capture; its samples must survive.
      final retired = Completer<void>();
      Object? retirementError;
      retirementTimer = Timer(const Duration(seconds: 4), () async {
        try {
          await service.callServiceExtension(
            'ext.profilerFixture.retireWorker',
            isolateId: mainId,
          );
        } catch (error) {
          retirementError = error;
        } finally {
          retired.complete();
        }
      });
      final result = await ProfileRunner().attach(
        ProfileAttachRequest(
          vmServiceUri: uri,
          duration: const Duration(seconds: 8),
          artifactDirectory: '${arguments[1]}/window-$window',
        ),
      );
      await retired.future;
      if (retirementError != null) {
        throw StateError('Worker retirement failed: $retirementError');
      }
      final profile = result.overallProfile;
      if (profile == null || !profile.succeeded || profile.sampleCount == 0) {
        throw StateError('Attach failed: ${result.warnings}');
      }
      final samples = await ProfileRunner().readCpuSamples(
        profile.rawProfilePath!,
      );
      final functions = samples.functions!;
      final resolver = ProfileFrameResolver(functions);
      final unknownFunctions = <Map<String, Object?>>[];
      var unknownSelf = 0;
      var unresolvedNativeSelf = 0;
      var truncated = 0;
      final byIsolate = <String, Map<int, int>>{};
      for (var index = 0; index < functions.length; index++) {
        final frame = profileFrameFromFunction(functions, index);
        if (isUnknown(frame.name)) {
          unknownFunctions.add({
            'index': index,
            'runtimeType': functions[index].function.runtimeType.toString(),
            'function': functions[index].toJson(),
          });
        }
      }
      for (final sample in samples.samples!) {
        if (sample.truncated ?? false) truncated++;
        if (sample is ProfileCpuSample && sample.isolateId != null) {
          final threads = byIsolate.putIfAbsent(sample.isolateId!, () => {});
          threads.update(
            sample.tid ?? -1,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        final stack = sample.stack;
        if (stack == null || stack.isEmpty) continue;
        final frame = resolver.resolve(stack.first);
        if (isUnknown(frame.name)) {
          unknownSelf++;
        }
        if (frame.name.startsWith('[Native] ') && frame.name.contains('+0x')) {
          unresolvedNativeSelf++;
        }
      }
      final status = await service.callServiceExtension(
        'ext.profilerFixture.status',
        isolateId: mainId,
      );
      final report = {
        'window': window,
        'sampleCount': profile.sampleCount,
        'isolateIds': profile.isolateIds,
        'threadIds': samples.samples!
            .map((sample) => sample.tid)
            .toSet()
            .toList(),
        'unknownSelfSamples': unknownSelf,
        'unresolvedNativeSelfSamples': unresolvedNativeSelf,
        'truncatedSamples': truncated,
        'isolateThreads': {
          for (final entry in byIsolate.entries)
            entry.key: {
              for (final thread in entry.value.entries)
                thread.key.toString(): thread.value,
            },
        },
        'unknownFunctions': unknownFunctions,
        'topSelf': profile.topSelfFrames
            .map((frame) => frame.toJson())
            .toList(),
        'warnings': result.warnings,
        'status': status.json,
      };
      await File('${arguments[1]}/window-$window/validation.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      stdout.writeln(
        jsonEncode({
          ...report,
          'unknownFunctions': unknownFunctions.length,
          'topSelf': profile.topSelfFrames
              .take(3)
              .map(
                (frame) => {
                  'name': frame.name,
                  'selfSamples': frame.selfSamples,
                },
              )
              .toList(),
        }),
      );
      if (profile.isolateIds.length < 3) {
        throw StateError('Expected main and both persistent workers.');
      }
      if (byIsolate.length < 3 ||
          byIsolate.values.any((threads) => threads.containsKey(-1))) {
        throw StateError(
          'Missing isolate/thread provenance in captured samples.',
        );
      }
      if (status.json?['workers'] != 1) {
        throw StateError('Worker retirement did not execute during capture.');
      }
      await service.callServiceExtension(
        'ext.profilerFixture.stop',
        isolateId: mainId,
      );
    }
  } finally {
    retirementTimer?.cancel();
    try {
      if (mainId != null) {
        await service.callServiceExtension(
          'ext.profilerFixture.stop',
          isolateId: mainId,
        );
      }
    } finally {
      await service.dispose();
    }
  }
}

bool isUnknown(String name) =>
    name.isEmpty || name == 'unknown' || name.startsWith('<unknown');
