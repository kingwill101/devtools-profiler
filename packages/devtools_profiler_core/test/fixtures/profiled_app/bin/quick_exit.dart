void main() {
  final stopwatch = Stopwatch()..start();
  var state = 1;
  while (stopwatch.elapsed < const Duration(milliseconds: 200)) {
    for (var i = 0; i < 10000; i++) {
      state = ((state * 1664525) + i) & 0x7fffffff;
    }
  }
  if (state == -1) {
    throw StateError('unreachable');
  }
}
