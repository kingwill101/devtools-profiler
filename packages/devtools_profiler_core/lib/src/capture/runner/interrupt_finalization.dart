import 'dart:async';

/// Waits for interrupted-session finalization without abandoning its result.
///
/// [warningTimeout] is intentionally only a diagnostic threshold. A profile
/// capture may need longer than that threshold to serialize a large CPU or
/// memory response, so the returned future still waits for [finalization]
/// before the caller tears down the VM-service connection.
Future<void> awaitInterruptedFinalization({
  required Future<void> finalization,
  required Duration warningTimeout,
  required void Function() onTimeout,
}) async {
  try {
    await finalization.timeout(warningTimeout);
  } on TimeoutException {
    onTimeout();
    await finalization;
  }
}
