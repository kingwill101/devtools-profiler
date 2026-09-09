import 'dart:async';

import 'package:devtools_profiler_core/src/capture/runner/interrupt_finalization.dart';
import 'package:test/test.dart';

void main() {
  test('waits for slow finalization after the warning threshold', () async {
    final finalization = Completer<void>();
    var timedOut = false;
    var completed = false;

    final waiting = awaitInterruptedFinalization(
      finalization: finalization.future,
      warningTimeout: const Duration(milliseconds: 1),
      onTimeout: () => timedOut = true,
    ).then((_) => completed = true);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(timedOut, isTrue);
    expect(completed, isFalse);

    finalization.complete();
    await waiting;
    expect(completed, isTrue);
  });

  test('propagates finalization errors', () async {
    final error = StateError('capture failed');

    await expectLater(
      awaitInterruptedFinalization(
        finalization: Future<void>.error(error),
        warningTimeout: const Duration(seconds: 1),
        onTimeout: () {},
      ),
      throwsA(same(error)),
    );
  });
}
