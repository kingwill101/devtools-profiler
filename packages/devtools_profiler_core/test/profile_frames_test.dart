import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test('resolver reuses metadata across stacks without caching predicates', () {
    final resolver = ProfileFrameResolver([
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(id: 'functions/work', name: 'work'),
      ),
    ]);
    var predicateCalls = 0;
    bool includeFrame(ProfileFrame frame) => ++predicateCalls != 2;

    final first = resolver.filterStack([0, 0], includeFrame: includeFrame);
    final second = resolver.filterStack([0], includeFrame: includeFrame);

    expect(predicateCalls, 3);
    expect(first, hasLength(1));
    expect(identical(first.single, second.single), isTrue);
    expect(resolver.filterStack([0, 0]), hasLength(2));
    expect(resolver.filterStack([]), isEmpty);
    expect(identical(resolver.resolve(-10), resolver.resolve(100)), isTrue);
    expect(resolver.resolve(100).name, 'unknown');
  });

  test('resolvers isolate metadata from different profile function tables', () {
    ProfileFrameResolver resolverFor(String name) => ProfileFrameResolver([
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(id: 'functions/0', name: name),
      ),
    ]);

    expect(resolverFor('first').resolve(0).name, 'first');
    expect(resolverFor('second').resolve(0).name, 'second');
  });

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
        path.posix.join(
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
        windows: false,
      ).toString(),
    );

    expect(frame.packageName, 'lualike');
  });

  test('packageName resolves local package file URIs', () {
    final frame = ProfileFrame(
      name: 'Value.toString',
      kind: 'Dart',
      location: Uri.file(
        path.posix.join(
          '/',
          'repo',
          'pkgs',
          'lualike',
          'lib',
          'src',
          'value.dart',
        ),
        windows: false,
      ).toString(),
    );

    expect(frame.packageName, 'lualike');
  });

  test('packageName resolves local packages before nested lib folders', () {
    final frame = ProfileFrame(
      name: 'Value.toString',
      kind: 'Dart',
      location: Uri.file(
        path.posix.join(
          '/',
          'repo',
          'pkgs',
          'lualike',
          'lib',
          'src',
          'generated',
          'lib',
          'value.dart',
        ),
        windows: false,
      ).toString(),
    );

    expect(frame.packageName, 'lualike');
  });

  test('packageName strips version suffixes from file package folders', () {
    final frame = ProfileFrame(
      name: 'Value.toString',
      kind: 'Dart',
      location: Uri.file(
        path.posix.join(
          '/',
          'workspace',
          'cache',
          'lualike-1.2.3',
          'lib',
          'src',
          'value.dart',
        ),
        windows: false,
      ).toString(),
    );

    expect(frame.packageName, 'lualike');
  });

  test('packageName ignores file URIs outside package layouts', () {
    final frame = ProfileFrame(
      name: 'main',
      kind: 'Dart',
      location: Uri.file(
        path.posix.join('/', 'repo', 'tool', 'main.dart'),
        windows: false,
      ).toString(),
    );

    expect(frame.packageName, isNull);
  });
}
