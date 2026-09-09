import 'dart:async';
import 'dart:io';

import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> main() async {
  final input = StreamIterator(stdin);
  try {
    // The parent subscribes to VM Logging before allowing the region to run.
    await input.moveNext();
    profileRegionSync('diagnostic-test', () => 42);
    // Keep the VM alive until the parent has received the expected diagnostic.
    await input.moveNext();
    // Allow any duplicate fire-and-forget diagnostics to reach the VM stream.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  } finally {
    await input.cancel();
  }
}
