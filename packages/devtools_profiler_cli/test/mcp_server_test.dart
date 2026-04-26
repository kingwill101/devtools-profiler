import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:devtools_profiler_cli/devtools_profiler_cli.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  test('lists tools and forwards summarize calls to the runner', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);

    final initializeResult = await _initializeServer(environment);
    expect(initializeResult.capabilities.tools, isNotNull);

    final tools = await environment.serverConnection.listTools();
    expect(
      tools.tools.map((tool) => tool.name),
      containsAll([
        'profile_run',
        'profile_attach',
        'profile_summarize',
        'profile_read_artifact',
        'profile_list_sessions',
        'profile_latest_session',
        'profile_get_session',
        'profile_list_regions',
        'profile_get_region',
        'profile_explain_hotspots',
        'profile_inspect_method',
        'profile_search_methods',
        'profile_compare_method',
        'profile_compare',
        'profile_analyze_trends',
        'profile_find_regressions',
        'profile_inspect_classes',
      ]),
    );

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_summarize',
        arguments: {'path': '/tmp/summary.json'},
      ),
    );

    expect(result.isError, isNot(true));
    expect(environment.runner.lastSummarizePath, '/tmp/summary.json');
    expect(result.structuredContent, containsPair('kind', 'summary'));
  });

  test('returns a tool error when required arguments are missing', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(name: 'profile_run', arguments: const {}),
    );

    expect(result.isError, isTrue);
    expect(
      (result.content.single as TextContent).text,
      contains('Required property "command" is missing'),
    );
  });

  test('includes a call tree when summarize requests expansion', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_summarize',
        arguments: {
          'path': '/tmp/profile.json',
          'includeCallTree': true,
          'treeDepth': 4,
          'treeChildren': 4,
        },
      ),
    );

    expect(result.isError, isNot(true));
    final summary = result.structuredContent!;
    final callTree = summary['callTree'] as Map<String, Object?>;
    final root = callTree['root'] as Map<String, Object?>;
    expect(root['name'], 'all');
    expect(
      ((root['children'] as List<Object?>).single
          as Map<String, Object?>)['name'],
      'Worker.run',
    );
  });

  test('includes a bottom-up tree when summarize requests it', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_summarize',
        arguments: {
          'path': '/tmp/profile.json',
          'includeBottomUpTree': true,
          'hideSdk': true,
        },
      ),
    );

    expect(result.isError, isNot(true));
    final summary = result.structuredContent!;
    final bottomUpTree = summary['bottomUpTree'] as Map<String, Object?>;
    final root = bottomUpTree['root'] as Map<String, Object?>;
    expect(root['name'], 'all');
    final children = root['children'] as List<Object?>;
    expect((children.first as Map<String, Object?>)['name'], 'Worker.run');
    expect((children[1] as Map<String, Object?>)['name'], 'Worker.hotLeaf');
  });

  test('includes a method table when summarize requests it', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_summarize',
        arguments: {
          'path': '/tmp/profile.json',
          'includeMethodTable': true,
          'hideSdk': true,
        },
      ),
    );

    expect(result.isError, isNot(true));
    final summary = result.structuredContent!;
    final methodTable = summary['methodTable'] as Map<String, Object?>;
    final methods = methodTable['methods'] as List<Object?>;
    expect((methods.first as Map<String, Object?>)['name'], 'Worker.run');
    final callees =
        (methods.first as Map<String, Object?>)['callees'] as List<Object?>;
    expect((callees.single as Map<String, Object?>)['name'], 'Worker.hotLeaf');
  });

  test('profile_run returns the whole-session profile for agents', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_run',
        arguments: {
          'command': ['dart', 'run', 'bin/main.dart'],
        },
      ),
    );

    expect(result.isError, isNot(true));
    final session = result.structuredContent!;
    expect(session['overallProfile'], isA<Map<String, Object?>>());
  });

  test('profile_run accepts flutter commands for agents', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_run',
        arguments: {
          'command': ['flutter', 'test', 'test/widget_test.dart'],
          'durationSeconds': 5,
          'vmServiceTimeoutSeconds': 120,
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(environment.runner.lastRunRequest?.command, [
      'flutter',
      'test',
      'test/widget_test.dart',
    ]);
    expect(
      environment.runner.lastRunRequest?.runDuration,
      const Duration(seconds: 5),
    );
    expect(
      environment.runner.lastRunRequest?.vmServiceTimeout,
      const Duration(seconds: 120),
    );
  });

  test('profile_attach profiles an existing VM service for agents', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_attach',
        arguments: {
          'vmServiceUri': 'http://127.0.0.1:8181/abcd/',
          'durationSeconds': 3,
          'workingDirectory': '/tmp/app',
          'includeCallTree': true,
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(
      environment.runner.lastAttachRequest?.vmServiceUri,
      Uri.parse('http://127.0.0.1:8181/abcd/'),
    );
    expect(
      environment.runner.lastAttachRequest?.duration,
      const Duration(seconds: 3),
    );
    expect(environment.runner.lastAttachRequest?.workingDirectory, '/tmp/app');
    final session = result.structuredContent!;
    expect(session['sessionId'], 'session-attach');
    expect(session['overallProfile'], isA<Map<String, Object?>>());
    expect(
      (session['overallProfile'] as Map<String, Object?>)['callTree'],
      isA<Map<String, Object?>>(),
    );
  });

  test('emits progress notifications for long-running tool calls', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final request = CallToolRequest(
      name: 'profile_run',
      arguments: {
        'command': ['dart', 'run', 'bin/main.dart'],
      },
      meta: MetaWithProgressToken(
        progressToken: ProgressToken('profile-run-progress'),
      ),
    );
    final progressEventsFuture = environment.serverConnection
        .onProgress(request)
        .toList();
    final result = await environment.serverConnection.callTool(request);
    final progressEvents = await progressEventsFuture;

    expect(result.isError, isNot(true));
    expect(progressEvents, isNotEmpty);
    expect(progressEvents.first.message, 'Starting profile run.');
    expect(progressEvents.last.message, 'Profile run completed.');
    expect(progressEvents.last.progress, 3);
    expect(progressEvents.last.total, 3);
  });

  test('supports hiding sdk frames for agent-facing summaries', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_summarize',
        arguments: {
          'path': '/tmp/profile.json',
          'includeCallTree': true,
          'hideSdk': true,
        },
      ),
    );

    expect(result.isError, isNot(true));
    final summary = result.structuredContent!;
    final topTotalFrames = summary['topTotalFrames'] as List<Object?>;
    expect(
      topTotalFrames.any(
        (frame) =>
            (frame as Map<String, Object?>)['name'] ==
            '_Future._completeWithValue',
      ),
      isFalse,
    );
  });

  test('lists stored sessions by newest modification time', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final rootDirectory = await Directory.systemTemp.createTemp(
      'profiler_mcp_',
    );
    addTearDown(() => rootDirectory.delete(recursive: true));

    final olderSession = await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-old',
      regionId: 'region-old',
      modifiedTime: DateTime.utc(2026, 4, 23, 18),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );
    final newerSession = await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-new',
      regionId: 'region-new',
      modifiedTime: DateTime.utc(2026, 4, 23, 19),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_list_sessions',
        arguments: {'rootDirectory': rootDirectory.path},
      ),
    );

    expect(result.isError, isNot(true));
    final listing = result.structuredContent!;
    final sessions = listing['sessions'] as List<Object?>;
    expect(
      listing['sessionsDirectory'],
      endsWith('.dart_tool/devtools_profiler/sessions'),
    );
    expect(listing['totalSessions'], 2);
    expect(
      (sessions.first as Map<String, Object?>)['sessionId'],
      'session-new',
    );
    expect(
      (sessions.first as Map<String, Object?>)['sessionPath'],
      newerSession.path,
    );
    expect(
      (sessions.last as Map<String, Object?>)['sessionPath'],
      olderSession.path,
    );
  });

  test('lists overall and explicit regions for a stored session', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final rootDirectory = await Directory.systemTemp.createTemp(
      'profiler_mcp_',
    );
    addTearDown(() => rootDirectory.delete(recursive: true));

    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-regions',
      regionId: 'region-lookup',
      modifiedTime: DateTime.utc(2026, 4, 23, 19, 30),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_list_regions',
        arguments: {
          'rootDirectory': rootDirectory.path,
          'sessionId': 'session-regions',
        },
      ),
    );

    expect(result.isError, isNot(true));
    final listing = result.structuredContent!;
    expect(listing['availableProfileIds'], ['overall', 'region-lookup']);
    final overallProfile = listing['overallProfile'] as Map<String, Object?>;
    final regions = listing['regions'] as List<Object?>;
    expect(overallProfile['scope'], 'session');
    expect(
      (regions.single as Map<String, Object?>)['regionId'],
      'region-lookup',
    );
  });

  test('loads the latest stored session directly', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final rootDirectory = await Directory.systemTemp.createTemp(
      'profiler_mcp_',
    );
    addTearDown(() => rootDirectory.delete(recursive: true));

    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-old',
      regionId: 'region-old',
      modifiedTime: DateTime.utc(2026, 4, 23, 18),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );
    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-newest',
      regionId: 'region-new',
      modifiedTime: DateTime.utc(2026, 4, 23, 20),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_latest_session',
        arguments: {'rootDirectory': rootDirectory.path},
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'latestSession');
    final session = payload['session'] as Map<String, Object?>;
    expect(session['sessionId'], 'session-newest');
    final summary = payload['summary'] as Map<String, Object?>;
    expect(summary['sessionId'], 'session-newest');
  });

  test('loads a stored session directly by selector', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final rootDirectory = await Directory.systemTemp.createTemp(
      'profiler_mcp_',
    );
    addTearDown(() => rootDirectory.delete(recursive: true));

    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-old',
      regionId: 'region-old',
      modifiedTime: DateTime.utc(2026, 4, 23, 18),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );
    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-newest',
      regionId: 'region-new',
      modifiedTime: DateTime.utc(2026, 4, 23, 20),
      cpuSamples: _FakeProfileRunner._cpuSamplesCurrent,
    );

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_get_session',
        arguments: {
          'rootDirectory': rootDirectory.path,
          'sessionId': 'previous',
        },
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'session');
    final session = payload['session'] as Map<String, Object?>;
    expect(session['sessionId'], 'session-old');
    final summary = payload['summary'] as Map<String, Object?>;
    expect(summary['sessionId'], 'session-old');
  });

  test('explains hotspots for a direct profile artifact', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_explain_hotspots',
        arguments: {'path': '/tmp/profile.json'},
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'hotspotExplanation');
    final hotspots = payload['hotspots'] as Map<String, Object?>;
    expect(hotspots['status'], 'analyzed');
    final insights = hotspots['insights'] as List<Object?>;
    final selfInsight = insights.cast<Map<String, Object?>>().firstWhere(
      (insight) => insight['kind'] == 'selfFrame',
    );
    final path = selfInsight['path'] as Map<String, Object?>;
    final frames = path['frames'] as List<Object?>;
    expect((frames.first as Map<String, Object?>)['name'], 'all');
    expect((frames[1] as Map<String, Object?>)['name'], 'Worker.run');
    expect((frames.last as Map<String, Object?>)['name'], 'Worker.hotLeaf');
    final bottomUpPath = selfInsight['bottomUpPath'] as Map<String, Object?>;
    final bottomUpFrames = bottomUpPath['frames'] as List<Object?>;
    expect(
      (bottomUpFrames[1] as Map<String, Object?>)['name'],
      'Worker.hotLeaf',
    );
    final focusMethod = selfInsight['focusMethod'] as Map<String, Object?>;
    expect(focusMethod['name'], 'Worker.hotLeaf');
    expect(focusMethod['methodId'], contains('Worker.hotLeaf'));
  });

  test('inspects a method for a direct profile artifact', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_inspect_method',
        arguments: {
          'path': '/tmp/profile.json',
          'methodName': 'Worker.hotLeaf',
        },
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'methodInspection');
    final inspection = payload['inspection'] as Map<String, Object?>;
    expect(inspection['status'], 'found');
    final method = inspection['method'] as Map<String, Object?>;
    expect(method['name'], 'Worker.hotLeaf');
    final topDownPaths = inspection['topDownPaths'] as List<Object?>;
    final frames =
        (topDownPaths.single as Map<String, Object?>)['frames']
            as List<Object?>;
    expect((frames.first as Map<String, Object?>)['name'], 'all');
    expect((frames.last as Map<String, Object?>)['name'], 'Worker.hotLeaf');
  });

  test('searches methods for a direct profile artifact', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_search_methods',
        arguments: {'path': '/tmp/profile.json', 'query': 'Worker'},
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'methodSearch');
    final search = payload['search'] as Map<String, Object?>;
    expect(search['status'], 'available');
    expect(search['totalMatches'], 2);
    final methods = search['methods'] as List<Object?>;
    expect(
      methods
          .cast<Map<String, Object?>>()
          .map((method) => method['name'])
          .toList(),
      ['Worker.run', 'Worker.hotLeaf'],
    );
  });

  test('compares one method across two profiles for agents', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_compare_method',
        arguments: {
          'baselinePath': '/tmp/artifacts/session-1',
          'currentPath': '/tmp/artifacts/session-2',
          'methodName': 'Worker.hotLeaf',
        },
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'methodComparison');
    final comparison = payload['comparison'] as Map<String, Object?>;
    expect(comparison['status'], 'compared');
    final methodDelta = comparison['methodDelta'] as Map<String, Object?>;
    expect(methodDelta['name'], 'Worker.hotLeaf');
    expect((methodDelta['selfSamples'] as Map<String, Object?>)['delta'], 6);
  });

  test('loads an explicit region by id with a call tree', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final rootDirectory = await Directory.systemTemp.createTemp(
      'profiler_mcp_',
    );
    addTearDown(() => rootDirectory.delete(recursive: true));

    final sessionDirectory = await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-region-fetch',
      regionId: 'region-fetch',
      modifiedTime: DateTime.utc(2026, 4, 23, 19, 45),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_get_region',
        arguments: {
          'sessionPath': sessionDirectory.path,
          'regionId': 'region-fetch',
          'includeCallTree': true,
          'hideSdk': true,
        },
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['scope'], 'region');
    final profile = payload['profile'] as Map<String, Object?>;
    expect(profile['regionId'], 'region-fetch');
    final callTree = profile['callTree'] as Map<String, Object?>;
    final root = callTree['root'] as Map<String, Object?>;
    expect(root['name'], 'all');
    expect(
      ((root['children'] as List<Object?>).single
          as Map<String, Object?>)['name'],
      'Worker.run',
    );
  });

  test('loads the whole-session profile by the special overall id', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final rootDirectory = await Directory.systemTemp.createTemp(
      'profiler_mcp_',
    );
    addTearDown(() => rootDirectory.delete(recursive: true));

    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-overall',
      regionId: 'region-fetch',
      modifiedTime: DateTime.utc(2026, 4, 23, 20),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_get_region',
        arguments: {
          'rootDirectory': rootDirectory.path,
          'sessionId': 'session-overall',
          'regionId': 'overall',
        },
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['scope'], 'session');
    final profile = payload['profile'] as Map<String, Object?>;
    expect(profile['regionId'], 'overall');
  });

  test('compares two session profiles for agents', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_compare',
        arguments: {
          'baselinePath': '/tmp/artifacts/session-1',
          'currentPath': '/tmp/artifacts/session-2',
          'includeMethodTable': true,
        },
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'profileComparison');
    final comparison = payload['comparison'] as Map<String, Object?>;
    final durationMicros = comparison['durationMicros'] as Map<String, Object?>;
    expect(durationMicros['delta'], 90);
    final regressions = payload['regressions'] as Map<String, Object?>;
    expect(regressions['status'], 'regressed');
    final insights = regressions['insights'] as List<Object?>;
    expect((insights.first as Map<String, Object?>)['kind'], 'duration');
    final methods = comparison['methods'] as List<Object?>;
    expect((methods.first as Map<String, Object?>)['name'], 'Worker.hotLeaf');
  });

  test('compares memory classes with an unlimited MCP limit', () async {
    final runner = _FakeMemoryProfileRunner();
    final environment = _McpTestEnvironment(runner);
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_compare',
        arguments: {
          'baselinePath': '/tmp/memory/session-1',
          'currentPath': '/tmp/memory/session-2',
          'memoryClassLimit': 0,
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(runner.readMemoryTopClassCounts, [0, 0]);
    final payload = result.structuredContent!;
    final comparison = payload['comparison'] as Map<String, Object?>;
    final memory = comparison['memory'] as Map<String, Object?>;
    final topClasses = memory['topClasses'] as List<Object?>;
    expect(topClasses, hasLength(3));
  });

  test('rejects negative MCP memory comparison limits', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_compare',
        arguments: {
          'baselinePath': '/tmp/artifacts/session-1',
          'currentPath': '/tmp/artifacts/session-2',
          'memoryClassLimit': -1,
        },
      ),
    );

    expect(result.isError, isTrue);
    expect(
      (result.content.single as TextContent).text,
      contains('"memoryClassLimit" argument must be a non-negative integer'),
    );
  });

  test('inspects memory classes for agents', () async {
    final runner = _FakeMemoryProfileRunner();
    final environment = _McpTestEnvironment(runner);
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_inspect_classes',
        arguments: {
          'path': '/tmp/memory/session-1',
          'classQuery': 'Love',
          'minLiveBytes': 512,
          'limit': 1,
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(runner.lastReadMemoryPath, '/tmp/memory/session-1');
    expect(runner.lastMemoryClassQuery, 'Love');
    expect(runner.lastMinLiveBytes, 512);
    expect(runner.readMemoryTopClassCounts, [1]);
    final payload = result.structuredContent!;
    expect(payload['kind'], 'memoryClassInspection');
    final classes = payload['classes'] as List<Object?>;
    expect(classes, hasLength(1));
    expect((classes.single as Map<String, Object?>)['className'], 'LoveImage');
  });

  test('inspects memory classes with MCP default class limit', () async {
    final runner = _FakeMemoryProfileRunner();
    final environment = _McpTestEnvironment(runner);
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_inspect_classes',
        arguments: {'path': '/tmp/memory/session-1'},
      ),
    );

    expect(result.isError, isNot(true));
    expect(runner.readMemoryTopClassCounts, [50]);
    expect(result.structuredContent!['topClassCount'], 50);
  });

  test('rejects negative MCP inspect-classes minLiveBytes', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_inspect_classes',
        arguments: {'path': '/tmp/memory/session-1', 'minLiveBytes': -1},
      ),
    );

    expect(result.isError, isTrue);
    expect(
      (result.content.single as TextContent).text,
      contains('"minLiveBytes" argument must be a non-negative integer'),
    );
  });

  test('analyzes trends across explicit session paths for agents', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_analyze_trends',
        arguments: {
          'paths': [
            '/tmp/artifacts/session-1',
            '/tmp/artifacts/session-2',
            '/tmp/artifacts/session-3',
          ],
        },
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'profileTrends');
    final trends = payload['trends'] as Map<String, Object?>;
    expect(trends['status'], 'regressing');
    final points = trends['points'] as List<Object?>;
    expect(points, hasLength(3));
    final recurring = trends['recurringRegressions'] as List<Object?>;
    expect(
      recurring.cast<Map<String, Object?>>().any(
        (item) => item['subject'] == 'Worker.hotLeaf',
      ),
      isTrue,
    );
  });

  test('compares stored sessions directly by selector', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final rootDirectory = await Directory.systemTemp.createTemp(
      'profiler_mcp_',
    );
    addTearDown(() => rootDirectory.delete(recursive: true));

    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-old',
      regionId: 'region-old',
      modifiedTime: DateTime.utc(2026, 4, 23, 18),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );
    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-new',
      regionId: 'region-new',
      modifiedTime: DateTime.utc(2026, 4, 23, 19),
      cpuSamples: _FakeProfileRunner._cpuSamplesCurrent,
    );

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_compare',
        arguments: {
          'rootDirectory': rootDirectory.path,
          'baselineSessionId': 'previous',
          'currentSessionId': 'latest',
          'includeMethodTable': true,
        },
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'profileComparison');
    final baseline = payload['baseline'] as Map<String, Object?>;
    final current = payload['current'] as Map<String, Object?>;
    expect(baseline['sessionId'], 'session-old');
    expect(current['sessionId'], 'session-new');
    final comparison = payload['comparison'] as Map<String, Object?>;
    final durationMicros = comparison['durationMicros'] as Map<String, Object?>;
    expect(durationMicros['delta'], 90);
  });

  test('analyzes trends across newest stored sessions', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final rootDirectory = await Directory.systemTemp.createTemp(
      'profiler_mcp_',
    );
    addTearDown(() => rootDirectory.delete(recursive: true));

    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-old',
      regionId: 'region-old',
      modifiedTime: DateTime.utc(2026, 4, 23, 18),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );
    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-new',
      regionId: 'region-new',
      modifiedTime: DateTime.utc(2026, 4, 23, 19),
      cpuSamples: _FakeProfileRunner._cpuSamplesCurrent,
    );
    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-latest',
      regionId: 'region-latest',
      modifiedTime: DateTime.utc(2026, 4, 23, 20),
      cpuSamples: _FakeProfileRunner._cpuSamplesTrend,
    );

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_analyze_trends',
        arguments: {'rootDirectory': rootDirectory.path, 'limit': 3},
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'profileTrends');
    expect(
      payload['sessionsDirectory'],
      contains('.dart_tool/devtools_profiler/sessions'),
    );
    final trends = payload['trends'] as Map<String, Object?>;
    expect(trends['status'], 'regressing');
    final points = trends['points'] as List<Object?>;
    expect(
      points.cast<Map<String, Object?>>().map((point) => point['id']).toList(),
      ['session-old', 'session-new', 'session-latest'],
    );
  });

  test('finds regressions between the newest stored sessions', () async {
    final environment = _McpTestEnvironment(_FakeProfileRunner());
    addTearDown(environment.shutdown);
    await _initializeServer(environment);

    final rootDirectory = await Directory.systemTemp.createTemp(
      'profiler_mcp_',
    );
    addTearDown(() => rootDirectory.delete(recursive: true));

    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-old',
      regionId: 'region-old',
      modifiedTime: DateTime.utc(2026, 4, 23, 18),
      cpuSamples: _FakeProfileRunner._cpuSamples,
    );
    await _writeStoredSession(
      rootDirectory: rootDirectory,
      sessionId: 'session-new',
      regionId: 'region-new',
      modifiedTime: DateTime.utc(2026, 4, 23, 19),
      cpuSamples: _FakeProfileRunner._cpuSamplesCurrent,
    );

    final result = await environment.serverConnection.callTool(
      CallToolRequest(
        name: 'profile_find_regressions',
        arguments: {
          'rootDirectory': rootDirectory.path,
          'includeMethodTable': true,
        },
      ),
    );

    expect(result.isError, isNot(true));
    final payload = result.structuredContent!;
    expect(payload['kind'], 'regressionSearch');
    final baselineSession = payload['baselineSession'] as Map<String, Object?>;
    final currentSession = payload['currentSession'] as Map<String, Object?>;
    expect(baselineSession['sessionId'], 'session-old');
    expect(currentSession['sessionId'], 'session-new');
    final regressions = payload['regressions'] as Map<String, Object?>;
    expect(regressions['status'], 'regressed');
    final insights = regressions['insights'] as List<Object?>;
    expect((insights.first as Map<String, Object?>)['kind'], 'duration');
  });

  test(
    'supports hiding runtime helper packages for agent-facing summaries',
    () async {
      final environment = _McpTestEnvironment(_FakeProfileRunner());
      addTearDown(environment.shutdown);
      await _initializeServer(environment);

      final result = await environment.serverConnection.callTool(
        CallToolRequest(
          name: 'profile_summarize',
          arguments: {
            'path': '/tmp/helper_profile.json',
            'hideRuntimeHelpers': true,
          },
        ),
      );

      expect(result.isError, isNot(true));
      final summary = result.structuredContent!;
      final topTotalFrames = summary['topTotalFrames'] as List<Object?>;
      expect(
        topTotalFrames.any(
          (frame) =>
              (frame as Map<String, Object?>)['name'] == 'JsonRpcClient.send',
        ),
        isFalse,
      );
    },
  );
}

Future<InitializeResult> _initializeServer(
  _McpTestEnvironment environment,
) async {
  final initializeResult = await environment.serverConnection.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: environment.client.capabilities,
      clientInfo: environment.client.implementation,
    ),
  );
  environment.serverConnection.notifyInitialized(InitializedNotification());
  await environment.server.initialized;
  return initializeResult;
}

Future<Directory> _writeStoredSession({
  required Directory rootDirectory,
  required String sessionId,
  required String regionId,
  required DateTime modifiedTime,
  required CpuSamples cpuSamples,
}) async {
  final sessionsDirectory = Directory(
    path.join(
      rootDirectory.path,
      '.dart_tool',
      'devtools_profiler',
      'sessions',
    ),
  );
  final sessionDirectory = Directory(
    path.join(sessionsDirectory.path, sessionId),
  );
  await sessionDirectory.create(recursive: true);

  final overallSummaryPath = path.join(
    sessionDirectory.path,
    'overall',
    'summary.json',
  );
  final overallRawPath = path.join(
    sessionDirectory.path,
    'overall',
    'cpu_profile.json',
  );
  final regionSummaryPath = path.join(
    sessionDirectory.path,
    'regions',
    regionId,
    'summary.json',
  );
  final regionRawPath = path.join(
    sessionDirectory.path,
    'regions',
    regionId,
    'cpu_profile.json',
  );

  final result = ProfileRunResult(
    sessionId: sessionId,
    command: const ['dart', 'run', 'bin/main.dart'],
    workingDirectory: rootDirectory.path,
    exitCode: 0,
    artifactDirectory: sessionDirectory.path,
    vmServiceUri: 'http://127.0.0.1:8181/$sessionId/',
    overallProfile: ProfileRegionResult(
      regionId: 'overall',
      name: 'whole-session',
      attributes: const {'scope': 'session'},
      isolateId: 'isolates/1',
      captureKinds: const [ProfileCaptureKind.cpu],
      startTimestampMicros: 0,
      endTimestampMicros: cpuSamples.timeExtentMicros ?? 0,
      durationMicros: cpuSamples.timeExtentMicros ?? 0,
      sampleCount: cpuSamples.sampleCount ?? 0,
      samplePeriodMicros: cpuSamples.samplePeriod ?? 0,
      topSelfFrames: const [],
      topTotalFrames: const [],
      summaryPath: overallSummaryPath,
      rawProfilePath: overallRawPath,
    ),
    regions: [
      ProfileRegionResult(
        regionId: regionId,
        name: 'cpu-burn',
        attributes: const {'phase': 'fixture'},
        isolateId: 'isolates/1',
        captureKinds: const [ProfileCaptureKind.cpu],
        startTimestampMicros: 10,
        endTimestampMicros: 10 + (cpuSamples.timeExtentMicros ?? 0),
        durationMicros: cpuSamples.timeExtentMicros ?? 0,
        sampleCount: cpuSamples.sampleCount ?? 0,
        samplePeriodMicros: cpuSamples.samplePeriod ?? 0,
        topSelfFrames: const [],
        topTotalFrames: const [],
        summaryPath: regionSummaryPath,
        rawProfilePath: regionRawPath,
      ),
    ],
    warnings: const [],
  );

  final sessionFile = File(path.join(sessionDirectory.path, 'session.json'));
  await sessionFile.writeAsString(result.toPrettyJson());
  await sessionFile.setLastModified(modifiedTime);

  await _writeCpuArtifact(overallRawPath, cpuSamples);
  await _writeCpuArtifact(regionRawPath, cpuSamples);
  await File(overallSummaryPath).create(recursive: true);
  await File(regionSummaryPath).create(recursive: true);

  return sessionDirectory;
}

Future<void> _writeCpuArtifact(
  String artifactPath,
  CpuSamples cpuSamples,
) async {
  final file = File(artifactPath);
  await file.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(cpuSamples.toJson()),
  );
}

class _McpTestEnvironment {
  _McpTestEnvironment(this.runner) {
    server = ProfilerMcpServer(runner: runner, channel: serverChannel);
    serverConnection = client.connectServer(clientChannel);
  }

  final _FakeProfileRunner runner;
  final client = MCPClient(
    Implementation(name: 'test client', version: '0.1.0'),
  );
  final clientController = StreamController<String>();
  final serverController = StreamController<String>();

  late final StreamChannel<String> clientChannel =
      StreamChannel<String>.withCloseGuarantee(
        serverController.stream,
        clientController.sink,
      );
  late final StreamChannel<String> serverChannel =
      StreamChannel<String>.withCloseGuarantee(
        clientController.stream,
        serverController.sink,
      );

  late final ProfilerMcpServer server;
  late final ServerConnection serverConnection;

  Future<void> shutdown() async {
    await client.shutdown();
    await server.shutdown();
    await clientController.close();
    await serverController.close();
  }
}

class _FakeProfileRunner extends ProfileRunner {
  ProfileRunRequest? lastRunRequest;
  ProfileAttachRequest? lastAttachRequest;
  String? lastSummarizePath;
  String? lastReadArtifactPath;

  static final _workerClass = ClassRef(id: 'classes/worker', name: 'Worker');

  static final _cpuSamples = CpuSamples(
    sampleCount: 10,
    samplePeriod: 50,
    timeOriginMicros: 0,
    timeExtentMicros: 100,
    functions: [
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/hot_leaf',
          name: 'hotLeaf',
          owner: _workerClass,
        ),
        resolvedUrl: 'package:fixture/hot_leaf.dart',
      ),
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/run',
          name: 'run',
          owner: _workerClass,
        ),
        resolvedUrl: 'package:fixture/run.dart',
      ),
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/complete',
          name: '_completeWithValue',
          owner: ClassRef(id: 'classes/future', name: '_Future'),
        ),
        resolvedUrl: 'org-dartlang-sdk:///sdk/lib/async/future_impl.dart',
      ),
    ],
    samples: [
      for (var i = 0; i < 8; i++) CpuSample(timestamp: i, stack: [0, 2, 1]),
      CpuSample(timestamp: 8, stack: const [1]),
      CpuSample(timestamp: 9, stack: const [1]),
    ],
  );

  static final _cpuSamplesCurrent = CpuSamples(
    sampleCount: 14,
    samplePeriod: 50,
    timeOriginMicros: 0,
    timeExtentMicros: 190,
    functions: _cpuSamples.functions,
    samples: [
      for (var i = 0; i < 9; i++) CpuSample(timestamp: i, stack: [0, 2, 1]),
      for (var i = 0; i < 5; i++) CpuSample(timestamp: 9 + i, stack: [0, 1]),
    ],
  );

  static final _cpuSamplesTrend = CpuSamples(
    sampleCount: 18,
    samplePeriod: 50,
    timeOriginMicros: 0,
    timeExtentMicros: 280,
    functions: _cpuSamples.functions,
    samples: [
      for (var i = 0; i < 11; i++) CpuSample(timestamp: i, stack: [0, 2, 1]),
      for (var i = 0; i < 7; i++) CpuSample(timestamp: 11 + i, stack: [0, 1]),
    ],
  );

  static final _cpuSamplesWithHelper = CpuSamples(
    sampleCount: 11,
    samplePeriod: 50,
    timeOriginMicros: 0,
    timeExtentMicros: 110,
    functions: [
      ..._cpuSamples.functions!,
      ProfileFunction(
        kind: 'Dart',
        function: FuncRef(
          id: 'functions/json_rpc',
          name: 'send',
          owner: ClassRef(id: 'classes/json_rpc', name: 'JsonRpcClient'),
        ),
        resolvedUrl: 'package:json_rpc_2/json_rpc_2.dart',
      ),
    ],
    samples: [
      for (var i = 0; i < 8; i++) CpuSample(timestamp: i, stack: [0, 2, 1]),
      CpuSample(timestamp: 8, stack: const [1]),
      CpuSample(timestamp: 9, stack: const [1]),
      CpuSample(timestamp: 10, stack: const [3, 1]),
    ],
  );

  static final _region = ProfileRegionResult(
    regionId: 'region-1',
    name: 'cpu-burn',
    attributes: const {},
    isolateId: 'isolates/1',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 0,
    endTimestampMicros: 100,
    durationMicros: 100,
    sampleCount: 1,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/profile.json',
    rawProfilePath: '/tmp/profile.cpu.json',
  );

  static final _overallProfile = ProfileRegionResult(
    regionId: 'overall',
    name: 'whole-session',
    attributes: const {'scope': 'session'},
    isolateId: 'isolates/1',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 0,
    endTimestampMicros: 100,
    durationMicros: 100,
    sampleCount: 1,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/overall/summary.json',
    rawProfilePath: '/tmp/overall/cpu_profile.json',
  );

  static final _regionCurrent = ProfileRegionResult(
    regionId: 'region-2',
    name: 'cpu-burn',
    attributes: const {},
    isolateId: 'isolates/1',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 0,
    endTimestampMicros: 190,
    durationMicros: 190,
    sampleCount: 14,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/artifacts/session-2/regions/region-2/summary.json',
    rawProfilePath:
        '/tmp/artifacts/session-2/regions/region-2/cpu_profile.json',
  );

  static final _overallProfileCurrent = ProfileRegionResult(
    regionId: 'overall',
    name: 'whole-session',
    attributes: const {'scope': 'session'},
    isolateId: 'isolates/1',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 0,
    endTimestampMicros: 190,
    durationMicros: 190,
    sampleCount: 14,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/artifacts/session-2/overall/summary.json',
    rawProfilePath: '/tmp/artifacts/session-2/overall/cpu_profile.json',
  );

  static final _helperRegion = ProfileRegionResult(
    regionId: 'region-helper',
    name: 'cpu-burn',
    attributes: const {},
    isolateId: 'isolates/1',
    captureKinds: const [ProfileCaptureKind.cpu],
    startTimestampMicros: 0,
    endTimestampMicros: 110,
    durationMicros: 110,
    sampleCount: 11,
    samplePeriodMicros: 50,
    topSelfFrames: const [],
    topTotalFrames: const [],
    summaryPath: '/tmp/helper_profile.json',
    rawProfilePath: '/tmp/helper_profile.cpu.json',
  );

  @override
  Future<ProfileRunResult> run(ProfileRunRequest request) async {
    lastRunRequest = request;
    return ProfileRunResult(
      sessionId: 'session-1',
      command: request.command,
      workingDirectory: request.workingDirectory ?? '/workspace',
      exitCode: 0,
      artifactDirectory: '/tmp/artifacts/session-1',
      vmServiceUri: 'http://127.0.0.1:8181/abcd/',
      overallProfile: _overallProfile,
      regions: const [],
      warnings: const [],
    );
  }

  @override
  Future<ProfileRunResult> attach(ProfileAttachRequest request) async {
    lastAttachRequest = request;
    return ProfileRunResult(
      sessionId: 'session-attach',
      command: ['attach', request.vmServiceUri.toString()],
      workingDirectory: request.workingDirectory ?? '/workspace',
      exitCode: 0,
      artifactDirectory: '/tmp/artifacts/session-attach',
      vmServiceUri: request.vmServiceUri.toString(),
      overallProfile: _overallProfile,
      regions: const [],
      warnings: const [],
    );
  }

  @override
  Future<Map<String, Object?>> readArtifact(String targetPath) async {
    lastReadArtifactPath = targetPath;
    return {'kind': 'artifact', 'path': targetPath};
  }

  @override
  Future<Map<String, Object?>> summarizeArtifact(String targetPath) async {
    lastSummarizePath = targetPath;
    if (targetPath == '/tmp/profile.json') {
      return _region.toJson();
    }
    if (targetPath == '/tmp/helper_profile.json') {
      return _helperRegion.toJson();
    }
    if (targetPath == '/tmp/artifacts/session-1') {
      return ProfileRunResult(
        sessionId: 'session-1',
        command: const ['dart', 'run', 'bin/main.dart'],
        workingDirectory: '/workspace',
        exitCode: 0,
        artifactDirectory: '/tmp/artifacts/session-1',
        vmServiceUri: 'http://127.0.0.1:8181/abcd/',
        overallProfile: _overallProfile,
        regions: [_region],
        warnings: const [],
      ).toJson();
    }
    if (targetPath == '/tmp/artifacts/session-2') {
      return ProfileRunResult(
        sessionId: 'session-2',
        command: const ['dart', 'run', 'bin/main.dart'],
        workingDirectory: '/workspace',
        exitCode: 0,
        artifactDirectory: '/tmp/artifacts/session-2',
        vmServiceUri: 'http://127.0.0.1:8181/efgh/',
        overallProfile: _overallProfileCurrent,
        regions: [_regionCurrent],
        warnings: const [],
      ).toJson();
    }
    if (targetPath == '/tmp/artifacts/session-3') {
      return ProfileRunResult(
        sessionId: 'session-3',
        command: const ['dart', 'run', 'bin/main.dart'],
        workingDirectory: '/workspace',
        exitCode: 0,
        artifactDirectory: '/tmp/artifacts/session-3',
        vmServiceUri: 'http://127.0.0.1:8181/ijkl/',
        overallProfile: ProfileRegionResult(
          regionId: 'overall',
          name: 'whole-session',
          attributes: const {'scope': 'session'},
          isolateId: 'isolates/1',
          captureKinds: const [ProfileCaptureKind.cpu],
          startTimestampMicros: 0,
          endTimestampMicros: 280,
          durationMicros: 280,
          sampleCount: 18,
          samplePeriodMicros: 50,
          topSelfFrames: const [],
          topTotalFrames: const [],
          summaryPath: '/tmp/artifacts/session-3/overall/summary.json',
          rawProfilePath: '/tmp/artifacts/session-3/overall/cpu_profile.json',
        ),
        regions: [
          ProfileRegionResult(
            regionId: 'region-3',
            name: 'cpu-burn',
            attributes: {},
            isolateId: 'isolates/1',
            captureKinds: const [ProfileCaptureKind.cpu],
            startTimestampMicros: 0,
            endTimestampMicros: 280,
            durationMicros: 280,
            sampleCount: 18,
            samplePeriodMicros: 50,
            topSelfFrames: const [],
            topTotalFrames: const [],
            summaryPath:
                '/tmp/artifacts/session-3/regions/region-3/summary.json',
            rawProfilePath:
                '/tmp/artifacts/session-3/regions/region-3/cpu_profile.json',
          ),
        ],
        warnings: const [],
      ).toJson();
    }
    final entityType = FileSystemEntity.typeSync(targetPath);
    if (entityType != FileSystemEntityType.notFound) {
      return ProfileArtifacts.summarizeArtifact(targetPath);
    }
    return {'kind': 'summary', 'path': targetPath};
  }

  @override
  Future<CpuSamples> readCpuSamples(String targetPath) async {
    if (targetPath == '/tmp/helper_profile.cpu.json') {
      return _cpuSamplesWithHelper;
    }
    if (File(targetPath).existsSync()) {
      return ProfileArtifacts.readCpuSamples(targetPath);
    }
    if (targetPath.contains('session-3')) {
      return _cpuSamplesTrend;
    }
    if (targetPath.contains('session-2')) {
      return _cpuSamplesCurrent;
    }
    return _cpuSamples;
  }
}

class _FakeMemoryProfileRunner extends _FakeProfileRunner {
  String? lastReadMemoryPath;
  String? lastMemoryClassQuery;
  int? lastMinLiveBytes;
  final List<int> readMemoryTopClassCounts = [];

  static const _baselineRawMemoryPath =
      '/tmp/memory/session-1/overall/memory_profile.json';
  static const _currentRawMemoryPath =
      '/tmp/memory/session-2/overall/memory_profile.json';

  static final _memoryClasses = [
    const ProfileMemoryClassSummary(
      className: 'LoveImage',
      libraryUri: 'package:love2d/image.dart',
      liveBytes: 2048,
      liveBytesDelta: 512,
      liveInstances: 2,
      liveInstancesDelta: 1,
      allocationBytesDelta: 4096,
      allocationInstancesDelta: 4,
    ),
    const ProfileMemoryClassSummary(
      className: 'LoveCanvas',
      libraryUri: 'package:love2d/canvas.dart',
      liveBytes: 1024,
      liveBytesDelta: 256,
      liveInstances: 1,
      liveInstancesDelta: 1,
      allocationBytesDelta: 2048,
      allocationInstancesDelta: 2,
    ),
    const ProfileMemoryClassSummary(
      className: 'WorkerBuffer',
      libraryUri: 'package:fixture/buffer.dart',
      liveBytes: 256,
      liveBytesDelta: 128,
      liveInstances: 1,
      liveInstancesDelta: 0,
      allocationBytesDelta: 512,
      allocationInstancesDelta: 1,
    ),
  ];

  @override
  Future<Map<String, Object?>> summarizeArtifact(String targetPath) async {
    return switch (targetPath) {
      '/tmp/memory/session-1' => _sessionWithMemory(
        sessionId: 'session-1',
        artifactDirectory: '/tmp/memory/session-1',
        vmServiceUri: 'http://127.0.0.1:8181/abcd/',
        region: _FakeProfileRunner._overallProfile,
        rawMemoryPath: _baselineRawMemoryPath,
      ).toJson(),
      '/tmp/memory/session-2' => _sessionWithMemory(
        sessionId: 'session-2',
        artifactDirectory: '/tmp/memory/session-2',
        vmServiceUri: 'http://127.0.0.1:8181/efgh/',
        region: _FakeProfileRunner._overallProfileCurrent,
        rawMemoryPath: _currentRawMemoryPath,
      ).toJson(),
      _ => super.summarizeArtifact(targetPath),
    };
  }

  @override
  Future<ProfileMemoryResult> readMemoryClasses(
    String targetPath, {
    String? classQuery,
    int? minLiveBytes,
    int topClassCount = 50,
  }) async {
    lastReadMemoryPath = targetPath;
    lastMemoryClassQuery = classQuery;
    lastMinLiveBytes = minLiveBytes;
    readMemoryTopClassCounts.add(topClassCount);

    var classes = _memoryClasses
        .where((item) {
          if (classQuery != null &&
              !item.className.toLowerCase().contains(
                classQuery.toLowerCase(),
              )) {
            return false;
          }
          if (minLiveBytes != null && item.liveBytes < minLiveBytes) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    if (topClassCount > 0 && classes.length > topClassCount) {
      classes = classes.take(topClassCount).toList(growable: false);
    }
    return _memoryResult(rawProfilePath: targetPath, classes: classes);
  }

  static ProfileRunResult _sessionWithMemory({
    required String sessionId,
    required String artifactDirectory,
    required String vmServiceUri,
    required ProfileRegionResult region,
    required String rawMemoryPath,
  }) {
    return ProfileRunResult(
      sessionId: sessionId,
      command: const ['dart', 'run', 'bin/main.dart'],
      workingDirectory: '/workspace',
      exitCode: 0,
      artifactDirectory: artifactDirectory,
      vmServiceUri: vmServiceUri,
      overallProfile: _regionWithMemory(region, rawMemoryPath),
      regions: const [],
      warnings: const [],
    );
  }

  static ProfileRegionResult _regionWithMemory(
    ProfileRegionResult region,
    String rawMemoryPath,
  ) {
    return ProfileRegionResult(
      regionId: region.regionId,
      name: region.name,
      attributes: region.attributes,
      isolateId: region.isolateId,
      isolateIds: region.isolateIds,
      captureKinds: region.captureKinds,
      isolateScope: region.isolateScope,
      parentRegionId: region.parentRegionId,
      memory: _memoryResult(rawProfilePath: rawMemoryPath),
      startTimestampMicros: region.startTimestampMicros,
      endTimestampMicros: region.endTimestampMicros,
      durationMicros: region.durationMicros,
      sampleCount: region.sampleCount,
      samplePeriodMicros: region.samplePeriodMicros,
      topSelfFrames: region.topSelfFrames,
      topTotalFrames: region.topTotalFrames,
      summaryPath: region.summaryPath,
      rawProfilePath: region.rawProfilePath,
      error: region.error,
    );
  }

  static ProfileMemoryResult _memoryResult({
    required String rawProfilePath,
    List<ProfileMemoryClassSummary>? classes,
  }) {
    final topClasses = classes ?? _memoryClasses;
    return ProfileMemoryResult.fromJson({
      'start': _heapSampleJson(timestamp: 1, used: 1024),
      'end': _heapSampleJson(timestamp: 2, used: 4096),
      'deltaHeapBytes': 3072,
      'deltaExternalBytes': 128,
      'deltaCapacityBytes': 4096,
      'classCount': _memoryClasses.length,
      'topClasses': [for (final item in topClasses) item.toJson()],
      'rawProfilePath': rawProfilePath,
    });
  }

  static Map<String, Object?> _heapSampleJson({
    required int timestamp,
    required int used,
  }) {
    return {
      'timestamp': timestamp,
      'rss': 0,
      'capacity': 8192,
      'used': used,
      'external': 0,
      'gc': false,
      'adb_memoryInfo': {
        'Realtime': 0,
        'Java Heap': 0,
        'Native Heap': 0,
        'Code': 0,
        'Stack': 0,
        'Graphics': 0,
        'Private Other': 0,
        'System': 0,
        'Total': 0,
      },
      'memory_eventInfo': {
        'timestamp': -1,
        'gcEvent': false,
        'snapshotEvent': false,
        'snapshotAutoEvent': false,
        'allocationAccumulatorEvent': {
          'start': false,
          'continues': false,
          'reset': false,
        },
        'extensionEvents': null,
      },
      'rasterCache': {'layerBytes': 0, 'pictureBytes': 0},
    };
  }
}
