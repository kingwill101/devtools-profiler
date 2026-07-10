import 'dart:io';

void main() {
  print(DateTime.now());
  for (var i = 0; i < 1_000_000; i++) {
    for (var j = 1_000; j > 0; j--) {}
  }
  print("done");
}
