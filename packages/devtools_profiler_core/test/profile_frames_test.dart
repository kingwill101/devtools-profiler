import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('packageName resolves package URIs', () {
    const frame = ProfileFrame(
      name: 'Value.toString',
      kind: 'Dart',
      location: 'package:lualike/src/value.dart',
    );

    expect(frame.packageName, 'lualike');
  });

  test('packageName resolves pub-cache file URIs', () {
    final frame = ProfileFrame(
      name: 'Value.toString',
      kind: 'Dart',
      location: Uri.file(
        path.join(
          '/',
          'home',
          'user',
          '.pub-cache',
          'hosted',
          'pub.dev',
          'lualike-1.2.3',
          'lib',
          'src',
          'value.dart',
        ),
      ).toString(),
    );

    expect(frame.packageName, 'lualike');
  });

  test('packageName resolves local package file URIs', () {
    final frame = ProfileFrame(
      name: 'Value.toString',
      kind: 'Dart',
      location: Uri.file(
        path.join('/', 'repo', 'pkgs', 'lualike', 'lib', 'src', 'value.dart'),
      ).toString(),
    );

    expect(frame.packageName, 'lualike');
  });

  test('packageName strips version suffixes from file package folders', () {
    final frame = ProfileFrame(
      name: 'Value.toString',
      kind: 'Dart',
      location: Uri.file(
        path.join(
          '/',
          'workspace',
          'cache',
          'lualike-1.2.3',
          'lib',
          'src',
          'value.dart',
        ),
      ).toString(),
    );

    expect(frame.packageName, 'lualike');
  });

  test('packageName ignores file URIs outside package layouts', () {
    final frame = ProfileFrame(
      name: 'main',
      kind: 'Dart',
      location: Uri.file(
        path.join('/', 'repo', 'tool', 'main.dart'),
      ).toString(),
    );

    expect(frame.packageName, isNull);
  });
}
