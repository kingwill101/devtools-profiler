
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:path/path.dart' as path;
import 'package:stream_channel/stream_channel.dart';

import 'presentation.dart';

const _serverName = 'devtools-profiler';
const _serverVersion = '0.1.0';
const _jsonEncoder = JsonEncoder.withIndent('  ');
const _sessionFileName = 'session.json';
const _sessionsDirectoryName = 'sessions';
const _defaultSessionListLimit = 20;

typedef _ProgressReporter = void Function(
  num progress,
  num total,
  String message,
);

/// Serves the profiler backend over the MCP stdio transport.
Future<void> serveMcp({
  required ProfileRunner runner,
  Stream<List<int>>? input,
  StreamSink<List<int>>? output,
  Sink<String>? protocolLogSink,
}) async {
  final server = ProfilerMcpServer(
    runner: runner,
    channel: stdioChannel(input: input ?? stdin, output: output ?? stdout),
    protocolLogSink: protocolLogSink,
  );
  await server.done;
}

/// An MCP server that exposes the profiler backend as tools.
base class ProfilerMcpServer extends MCPServer with ToolsSupport {
  /// Creates an MCP server backed by [runner].
  ProfilerMcpServer({
    required this.runner,
    required StreamChannel<String> channel,
    Sink<String>? protocolLogSink,
  }) : super.fromStreamChannel(
          channel,
          implementation: Implementation(
            name: _serverName,
            version: _serverVersion,
          ),
          instructions:
              'Launch profiled Dart or Flutter commands, summarize artifacts, '
              'and read stored CPU profiling results.',
          protocolLogSink: protocolLogSink,
        ) {
    registerTool(_profileRunTool, _profileRun);
    registerTool(_profileAttachTool, _profileAttach);
    registerTool(_profileSummarizeTool, _profileSummarize);
    registerTool(_profileReadArtifactTool, _profileReadArtifact);
    registerTool(_profileListSessionsTool, _profileListSessions);
    registerTool(_profileLatestSessionTool, _profileLatestSession);
    registerTool(_profileGetSessionTool, _profileGetSession);
    registerTool(_profileListRegionsTool, _profileListRegions);
    registerTool(_profileGetRegionTool, _profileGetRegion);
    registerTool(_profileExplainHotspotsTool, _profileExplainHotspots);
    registerTool(_profileInspectMethodTool, _profileInspectMethod);
    registerTool(_profileSearchMethodsTool, _profileSearchMethods);
    registerTool(_profileCompareMethodTool, _profileCompareMethod);
    registerTool(_profileCompareTool, _profileCompare);
    registerTool(_profileAnalyzeTrendsTool, _profileAnalyzeTrends);
    registerTool(_profileFindRegressionsTool, _profileFindRegressions);
  }

  /// The profiler backend used by all tool calls.
  final ProfileRunner runner;

  final Tool _profileRunTool = Tool(
    name: 'profile_run',
    title: 'Profile Run',
    description:
        'Launch a Dart or Flutter command and return structured CPU summaries '
        'for marked regions.',
    inputSchema: Schema.object(
      properties: {
        'command': Schema.list(
          description:
              'A command such as ["dart", "run", "bin/main.dart"] or ["flutter", "test"].',
          items: Schema.string(),
        ),
        'workingDirectory': Schema.string(
          description: 'The working directory to use for the launched process.',
        ),
        'artifactDirectory': Schema.string(
          description: 'Where session artifacts should be written.',
        ),
        'durationSeconds': Schema.int(
          description:
              'Optional duration in seconds to profile before terminating the launched process.',
        ),
        'vmServiceTimeoutSeconds': Schema.int(
          description:
              'Optional timeout in seconds for waiting for the launched process to expose a Dart VM service URI.',
        ),
        'forwardOutput': Schema.bool(
          description: 'Whether child stdout and stderr should be echoed.',
        ),
        'includeCallTree': Schema.bool(
          description: 'Whether to attach top-down region call trees.',
        ),
        'includeBottomUpTree': Schema.bool(
          description: 'Whether to attach DevTools-style bottom-up trees.',
        ),
        'includeMethodTable': Schema.bool(
          description: 'Whether to attach a DevTools-style method table.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method table. Use 0 for unlimited.',
        ),
        'treeDepth': Schema.int(
          description:
              'Maximum call tree depth when includeCallTree is true. Use 0 for unlimited.',
        ),
        'treeChildren': Schema.int(
          description:
              'Maximum children per call tree node when includeCallTree is true. Use 0 for unlimited.',
        ),
      },
      required: ['command'],
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Structured profiling session result.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false,
      readOnlyHint: false,
      title: 'Profile Run',
    ),
  );

  final Tool _profileAttachTool = Tool(
    name: 'profile_attach',
    title: 'Profile Attach',
    description:
        'Attach to an existing Dart or Flutter VM service URI and return structured CPU summaries for a fixed profiling window.',
    inputSchema: Schema.object(
      properties: {
        'vmServiceUri': Schema.string(
          description:
              'The HTTP VM service URI printed by dart or flutter, for example "http://127.0.0.1:8181/abcd/".',
        ),
        'durationSeconds': Schema.int(
          description:
              'Required duration in seconds to profile the already-running VM service.',
        ),
        'workingDirectory': Schema.string(
          description:
              'The working directory associated with the profiled target.',
        ),
        'artifactDirectory': Schema.string(
          description: 'Where session artifacts should be written.',
        ),
        'includeCallTree': Schema.bool(
          description: 'Whether to attach top-down region call trees.',
        ),
        'includeBottomUpTree': Schema.bool(
          description: 'Whether to attach DevTools-style bottom-up trees.',
        ),
        'includeMethodTable': Schema.bool(
          description: 'Whether to attach a DevTools-style method table.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method table. Use 0 for unlimited.',
        ),
        'treeDepth': Schema.int(
          description:
              'Maximum call tree depth when includeCallTree is true. Use 0 for unlimited.',
        ),
        'treeChildren': Schema.int(
          description:
              'Maximum children per call tree node when includeCallTree is true. Use 0 for unlimited.',
        ),
      },
      required: ['vmServiceUri', 'durationSeconds'],
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Structured attached profiling session result.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false,
      readOnlyHint: false,
      title: 'Profile Attach',
    ),
  );

  final Tool _profileSummarizeTool = Tool(
    name: 'profile_summarize',
    title: 'Profile Summarize',
    description: 'Summarize a session directory or raw CPU profile artifact.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'A session directory or artifact JSON path.',
        ),
        'includeCallTree': Schema.bool(
          description: 'Whether to attach top-down region call trees.',
        ),
        'includeBottomUpTree': Schema.bool(
          description: 'Whether to attach DevTools-style bottom-up trees.',
        ),
        'includeMethodTable': Schema.bool(
          description: 'Whether to attach a DevTools-style method table.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method table. Use 0 for unlimited.',
        ),
        'treeDepth': Schema.int(
          description:
              'Maximum call tree depth when includeCallTree is true. Use 0 for unlimited.',
        ),
        'treeChildren': Schema.int(
          description:
              'Maximum children per call tree node when includeCallTree is true. Use 0 for unlimited.',
        ),
      },
      required: ['path'],
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Structured artifact summary.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Summarize',
    ),
  );

  final Tool _profileReadArtifactTool = Tool(
    name: 'profile_read_artifact',
    title: 'Profile Read Artifact',
    description: 'Read an artifact file or session directory directly.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'The artifact file or directory to read.',
        ),
      },
      required: ['path'],
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Structured artifact payload.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Read Artifact',
    ),
  );

  final Tool _profileListSessionsTool = Tool(
    name: 'profile_list_sessions',
    title: 'Profile List Sessions',
    description:
        'List stored profiling sessions under a project root or sessions directory.',
    inputSchema: Schema.object(
      properties: {
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'limit': Schema.int(
          description: 'Maximum sessions to return. Use 0 for all sessions.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Stored profiling session metadata.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile List Sessions',
    ),
  );

  final Tool _profileListRegionsTool = Tool(
    name: 'profile_list_regions',
    title: 'Profile List Regions',
    description:
        'List the whole-session profile and explicit regions stored in a session.',
    inputSchema: Schema.object(
      properties: {
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'sessionId': Schema.string(
          description: 'Session id to resolve under the sessions directory.',
        ),
        'sessionPath': Schema.string(
          description: 'Direct path to a session directory.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Stored region metadata for a profiling session.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile List Regions',
    ),
  );

  final Tool _profileLatestSessionTool = Tool(
    name: 'profile_latest_session',
    title: 'Profile Latest Session',
    description:
        'Resolve the newest stored profiling session and return its prepared summary.',
    inputSchema: Schema.object(
      properties: {
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'includeCallTree': Schema.bool(
          description: 'Whether to attach top-down region call trees.',
        ),
        'includeBottomUpTree': Schema.bool(
          description: 'Whether to attach DevTools-style bottom-up trees.',
        ),
        'includeMethodTable': Schema.bool(
          description: 'Whether to attach a DevTools-style method table.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method table. Use 0 for unlimited.',
        ),
        'treeDepth': Schema.int(
          description:
              'Maximum call tree depth when includeCallTree is true. Use 0 for unlimited.',
        ),
        'treeChildren': Schema.int(
          description:
              'Maximum children per call tree node when includeCallTree is true. Use 0 for unlimited.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'The newest stored profiling session.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Latest Session',
    ),
  );

  final Tool _profileGetSessionTool = Tool(
    name: 'profile_get_session',
    title: 'Profile Get Session',
    description:
        'Resolve a stored profiling session by id or path and return its prepared summary.',
    inputSchema: Schema.object(
      properties: {
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'sessionId': Schema.string(
          description:
              'Session id to resolve under the sessions directory. Also accepts "latest" or "previous".',
        ),
        'sessionPath': Schema.string(
          description: 'Direct path to a session directory.',
        ),
        'includeCallTree': Schema.bool(
          description: 'Whether to attach top-down region call trees.',
        ),
        'includeBottomUpTree': Schema.bool(
          description: 'Whether to attach DevTools-style bottom-up trees.',
        ),
        'includeMethodTable': Schema.bool(
          description: 'Whether to attach a DevTools-style method table.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method table. Use 0 for unlimited.',
        ),
        'treeDepth': Schema.int(
          description:
              'Maximum call tree depth when includeCallTree is true. Use 0 for unlimited.',
        ),
        'treeChildren': Schema.int(
          description:
              'Maximum children per call tree node when includeCallTree is true. Use 0 for unlimited.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Prepared stored profiling session.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Get Session',
    ),
  );

  final Tool _profileGetRegionTool = Tool(
    name: 'profile_get_region',
    title: 'Profile Get Region',
    description:
        'Read a stored whole-session profile or explicit region by id and return the prepared summary.',
    inputSchema: Schema.object(
      properties: {
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'sessionId': Schema.string(
          description: 'Session id to resolve under the sessions directory.',
        ),
        'sessionPath': Schema.string(
          description: 'Direct path to a session directory.',
        ),
        'regionId': Schema.string(
          description:
              'The explicit region id to load, or "overall" for the whole-session profile.',
        ),
        'includeCallTree': Schema.bool(
          description: 'Whether to attach a top-down call tree.',
        ),
        'includeBottomUpTree': Schema.bool(
          description: 'Whether to attach a DevTools-style bottom-up tree.',
        ),
        'includeMethodTable': Schema.bool(
          description: 'Whether to attach a DevTools-style method table.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method table. Use 0 for unlimited.',
        ),
        'treeDepth': Schema.int(
          description:
              'Maximum call tree depth when includeCallTree is true. Use 0 for unlimited.',
        ),
        'treeChildren': Schema.int(
          description:
              'Maximum children per call tree node when includeCallTree is true. Use 0 for unlimited.',
        ),
      },
      required: ['regionId'],
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Prepared profile region result.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Get Region',
    ),
  );

  final Tool _profileExplainHotspotsTool = Tool(
    name: 'profile_explain_hotspots',
    title: 'Profile Explain Hotspots',
    description:
        'Explain the main hotspots in a stored session profile or a direct profile artifact.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description:
              'A session directory or a direct profile artifact path. When omitted, use session selectors instead.',
        ),
        'profileId': Schema.string(
          description:
              'Optional profile id to select from a session directory path. Use "overall" for the whole-session profile.',
        ),
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'sessionId': Schema.string(
          description:
              'Session id to resolve under the sessions directory. Also accepts "latest".',
        ),
        'sessionPath': Schema.string(
          description: 'Direct path to a session directory.',
        ),
        'regionId': Schema.string(
          description:
              'Optional explicit region id to explain. Defaults to "overall" when available.',
        ),
        'includeCallTree': Schema.bool(
          description: 'Whether to attach a top-down call tree.',
        ),
        'includeBottomUpTree': Schema.bool(
          description: 'Whether to attach a DevTools-style bottom-up tree.',
        ),
        'includeMethodTable': Schema.bool(
          description:
              'Whether to include the DevTools-style method table in the returned profile.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method table. Use 0 for unlimited.',
        ),
        'treeDepth': Schema.int(
          description:
              'Maximum call tree depth when includeCallTree is true. Use 0 for unlimited.',
        ),
        'treeChildren': Schema.int(
          description:
              'Maximum children per call tree node when includeCallTree is true. Use 0 for unlimited.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Prepared profile plus prioritized hotspot insights.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Explain Hotspots',
    ),
  );

  final Tool _profileInspectMethodTool = Tool(
    name: 'profile_inspect_method',
    title: 'Profile Inspect Method',
    description:
        'Inspect one method in a stored session profile or direct profile artifact and return callers, callees, and representative paths.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description:
              'A session directory or a direct profile artifact path. When omitted, use session selectors instead.',
        ),
        'profileId': Schema.string(
          description:
              'Optional profile id to select from a session directory path. Use "overall" for the whole-session profile.',
        ),
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'sessionId': Schema.string(
          description:
              'Session id to resolve under the sessions directory. Also accepts "latest".',
        ),
        'sessionPath': Schema.string(
          description: 'Direct path to a session directory.',
        ),
        'regionId': Schema.string(
          description:
              'Optional explicit region id to inspect. Defaults to "overall" when available.',
        ),
        'methodId': Schema.string(
          description: 'Exact method id to inspect.',
        ),
        'methodName': Schema.string(
          description: 'Method name query to inspect.',
        ),
        'pathLimit': Schema.int(
          description:
              'Maximum representative top-down and bottom-up paths to include. Use 0 for unlimited.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method table. Use 0 for unlimited.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Prepared method inspection result.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Inspect Method',
    ),
  );

  final Tool _profileSearchMethodsTool = Tool(
    name: 'profile_search_methods',
    title: 'Profile Search Methods',
    description:
        'Search a stored session profile or direct profile artifact for matching methods and return ranked candidates.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description:
              'A session directory or a direct profile artifact path. When omitted, use session selectors instead.',
        ),
        'profileId': Schema.string(
          description:
              'Optional profile id to select from a session directory path. Use "overall" for the whole-session profile.',
        ),
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'sessionId': Schema.string(
          description:
              'Session id to resolve under the sessions directory. Also accepts "latest".',
        ),
        'sessionPath': Schema.string(
          description: 'Direct path to a session directory.',
        ),
        'regionId': Schema.string(
          description:
              'Optional explicit region id to search. Defaults to "overall" when available.',
        ),
        'query': Schema.string(
          description:
              'Optional method query matched against method name, id, and source location.',
        ),
        'sortBy': Schema.string(
          description: 'Sort mode for matches: "total" or "self".',
        ),
        'limit': Schema.int(
          description: 'Maximum methods to return. Use 0 for unlimited.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method table. Use 0 for unlimited.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Prepared method search result.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Search Methods',
    ),
  );

  final Tool _profileCompareMethodTool = Tool(
    name: 'profile_compare_method',
    title: 'Profile Compare Method',
    description:
        'Compare one method across two session/profile targets and return method, caller, and callee deltas.',
    inputSchema: Schema.object(
      properties: {
        'baselinePath': Schema.string(
          description: 'Baseline session directory or profile artifact path.',
        ),
        'currentPath': Schema.string(
          description: 'Current session directory or profile artifact path.',
        ),
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'baselineSessionId': Schema.string(
          description:
              'Optional baseline session id. Also accepts "latest" or "previous".',
        ),
        'currentSessionId': Schema.string(
          description:
              'Optional current session id. Also accepts "latest" or "previous".',
        ),
        'baselineSessionPath': Schema.string(
          description:
              'Optional direct path to the baseline session directory.',
        ),
        'currentSessionPath': Schema.string(
          description: 'Optional direct path to the current session directory.',
        ),
        'baselineProfileId': Schema.string(
          description:
              'Optional profile id to select from the baseline session. Use "overall" for the whole-session profile.',
        ),
        'currentProfileId': Schema.string(
          description:
              'Optional profile id to select from the current session. Use "overall" for the whole-session profile.',
        ),
        'methodId': Schema.string(
          description: 'Exact method id to compare.',
        ),
        'methodName': Schema.string(
          description: 'Method name query to compare.',
        ),
        'pathLimit': Schema.int(
          description:
              'Maximum representative top-down and bottom-up paths to include. Use 0 for unlimited.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum method relations to include in the comparison. Use 0 for unlimited.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Prepared method comparison result.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Compare Method',
    ),
  );

  final Tool _profileCompareTool = Tool(
    name: 'profile_compare',
    title: 'Profile Compare',
    description:
        'Compare two session/profile targets and return structured deltas plus the prepared baseline/current views.',
    inputSchema: Schema.object(
      properties: {
        'baselinePath': Schema.string(
          description: 'Baseline session directory or profile artifact path.',
        ),
        'currentPath': Schema.string(
          description: 'Current session directory or profile artifact path.',
        ),
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'baselineSessionId': Schema.string(
          description:
              'Optional baseline session id. Also accepts "latest" or "previous".',
        ),
        'currentSessionId': Schema.string(
          description:
              'Optional current session id. Also accepts "latest" or "previous".',
        ),
        'baselineSessionPath': Schema.string(
          description:
              'Optional direct path to the baseline session directory.',
        ),
        'currentSessionPath': Schema.string(
          description: 'Optional direct path to the current session directory.',
        ),
        'baselineProfileId': Schema.string(
          description:
              'Optional profile id to select from the baseline session. Use "overall" for the whole-session profile.',
        ),
        'currentProfileId': Schema.string(
          description:
              'Optional profile id to select from the current session. Use "overall" for the whole-session profile.',
        ),
        'includeCallTree': Schema.bool(
          description: 'Whether to attach top-down trees for both sides.',
        ),
        'includeBottomUpTree': Schema.bool(
          description: 'Whether to attach bottom-up trees for both sides.',
        ),
        'includeMethodTable': Schema.bool(
          description:
              'Whether to attach method tables and include method deltas.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total comparison table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method comparison. Use 0 for unlimited.',
        ),
        'treeDepth': Schema.int(
          description:
              'Maximum call tree depth when trees are included. Use 0 for unlimited.',
        ),
        'treeChildren': Schema.int(
          description:
              'Maximum children per call tree node when trees are included. Use 0 for unlimited.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Prepared baseline/current profiles plus structured deltas.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Compare',
    ),
  );

  final Tool _profileAnalyzeTrendsTool = Tool(
    name: 'profile_analyze_trends',
    title: 'Profile Analyze Trends',
    description:
        'Analyze a sequence of stored profiling sessions and return first-to-last deltas plus recurring regressions.',
    inputSchema: Schema.object(
      properties: {
        'paths': Schema.list(
          description:
              'Explicit session directories or profile artifact paths in chronological order.',
          items: Schema.string(),
        ),
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'sessionIds': Schema.list(
          description:
              'Optional explicit session ids to analyze in order. When omitted, the newest sessions are used.',
          items: Schema.string(),
        ),
        'profileId': Schema.string(
          description:
              'Optional profile id to select from each session. Use "overall" for the whole-session profile.',
        ),
        'limit': Schema.int(
          description:
              'Maximum newest stored sessions to analyze when paths/sessionIds are omitted. Use 0 for all.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total comparison table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in trend comparisons. Use 0 for unlimited.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description: 'Structured cross-session profile trend analysis.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Analyze Trends',
    ),
  );

  final Tool _profileFindRegressionsTool = Tool(
    name: 'profile_find_regressions',
    title: 'Profile Find Regressions',
    description:
        'Compare stored profiling sessions, defaulting to the newest run versus the previous run, and return prioritized regression insights.',
    inputSchema: Schema.object(
      properties: {
        'rootDirectory': Schema.string(
          description:
              'Project root containing .dart_tool/devtools_profiler/sessions.',
        ),
        'sessionsDirectory': Schema.string(
          description:
              'A direct path to a devtools_profiler sessions directory.',
        ),
        'baselineSessionId': Schema.string(
          description:
              'Optional baseline session id. Defaults to "previous". Also accepts "latest" or "previous".',
        ),
        'currentSessionId': Schema.string(
          description:
              'Optional current session id. Defaults to "latest". Also accepts "latest" or "previous".',
        ),
        'baselineProfileId': Schema.string(
          description:
              'Optional baseline profile id within the session. Use "overall" for the whole-session profile.',
        ),
        'currentProfileId': Schema.string(
          description:
              'Optional current profile id within the session. Use "overall" for the whole-session profile.',
        ),
        'includeCallTree': Schema.bool(
          description: 'Whether to attach top-down trees for both sides.',
        ),
        'includeBottomUpTree': Schema.bool(
          description: 'Whether to attach bottom-up trees for both sides.',
        ),
        'includeMethodTable': Schema.bool(
          description:
              'Whether to attach method tables and include method deltas.',
        ),
        'hideSdk': Schema.bool(
          description: 'Whether to hide Dart and Flutter SDK frames.',
        ),
        'hideRuntimeHelpers': Schema.bool(
          description:
              'Whether to hide common profiler/runtime helper packages.',
        ),
        'includePackages': Schema.list(
          description:
              'Optional package prefixes to keep. Frames outside these packages are hidden.',
          items: Schema.string(),
        ),
        'excludePackages': Schema.list(
          description: 'Optional package prefixes to exclude.',
          items: Schema.string(),
        ),
        'frameLimit': Schema.int(
          description:
              'Maximum rows per self / total comparison table. Use 0 for unlimited.',
        ),
        'methodLimit': Schema.int(
          description:
              'Maximum methods to include in the method comparison. Use 0 for unlimited.',
        ),
        'treeDepth': Schema.int(
          description:
              'Maximum call tree depth when trees are included. Use 0 for unlimited.',
        ),
        'treeChildren': Schema.int(
          description:
              'Maximum children per call tree node when trees are included. Use 0 for unlimited.',
        ),
      },
      additionalProperties: false,
    ),
    outputSchema: Schema.object(
      description:
          'Structured comparison and prioritized regression summary for stored sessions.',
      additionalProperties: true,
    ),
    annotations: ToolAnnotations(
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
      readOnlyHint: true,
      title: 'Profile Find Regressions',
    ),
  );

  Future<CallToolResult> _profileRun(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Profiling completed.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        final command = _stringListArgument(arguments, key: 'command');
        final treeOptions = _treeOptionsFromArguments(arguments);
        progress(0, 3, 'Starting profile run.');
        final result = await runner.run(
          ProfileRunRequest(
            artifactDirectory: _optionalStringArgument(
              arguments,
              key: 'artifactDirectory',
            ),
            command: command,
            forwardOutput: arguments['forwardOutput'] as bool? ?? false,
            runDuration: _optionalDurationSecondsArgument(arguments),
            vmServiceTimeout: _optionalDurationSecondsArgument(
              arguments,
              key: 'vmServiceTimeoutSeconds',
            ),
            workingDirectory: _optionalStringArgument(
              arguments,
              key: 'workingDirectory',
            ),
          ),
        );
        progress(1, 3, 'Run finished. Preparing session presentation.');
        final prepared = await prepareSessionPresentation(
          runner,
          result,
          options: treeOptions,
        );
        progress(2, 3, 'Building structured session response.');
        final response = sessionPresentationJson(
          prepared.session,
          prepared.overallTree,
          prepared.overallBottomUpTree,
          prepared.overallMethodTable,
          prepared.regionTrees,
          prepared.regionBottomUpTrees,
          prepared.regionMethodTables,
        );
        progress(3, 3, 'Profile run completed.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileAttach(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Attach profiling completed.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        final treeOptions = _treeOptionsFromArguments(arguments);
        progress(0, 3, 'Attaching to VM service.');
        final result = await runner.attach(
          ProfileAttachRequest(
            artifactDirectory: _optionalStringArgument(
              arguments,
              key: 'artifactDirectory',
            ),
            duration: _requiredDurationSecondsArgument(arguments),
            vmServiceUri: _requiredUriArgument(
              arguments,
              key: 'vmServiceUri',
            ),
            workingDirectory: _optionalStringArgument(
              arguments,
              key: 'workingDirectory',
            ),
          ),
        );
        progress(
            1, 3, 'Attach window finished. Preparing session presentation.');
        final prepared = await prepareSessionPresentation(
          runner,
          result,
          options: treeOptions,
        );
        progress(2, 3, 'Building structured session response.');
        final response = sessionPresentationJson(
          prepared.session,
          prepared.overallTree,
          prepared.overallBottomUpTree,
          prepared.overallMethodTable,
          prepared.regionTrees,
          prepared.regionBottomUpTrees,
          prepared.regionMethodTables,
        );
        progress(3, 3, 'Attach profiling completed.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileSummarize(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Artifact summarized.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        final targetPath = _requiredStringArgument(arguments, key: 'path');
        final treeOptions = _treeOptionsFromArguments(arguments);
        progress(0, 2, 'Loading artifact summary.');
        final response = await _summarizeWithCallTrees(targetPath, treeOptions);
        progress(2, 2, 'Artifact summary prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileReadArtifact(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Artifact read.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        final targetPath = _requiredStringArgument(arguments, key: 'path');
        progress(0, 2, 'Reading artifact.');
        final response = await runner.readArtifact(targetPath);
        progress(2, 2, 'Artifact read completed.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileListSessions(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Sessions listed.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        progress(0, 2, 'Discovering stored sessions.');
        final sessionsDirectory = _resolveSessionsDirectory(arguments);
        final sessions = await _discoverSessions(sessionsDirectory);
        final limit = _listLimitFromArguments(arguments);
        final listedSessions = limit == null
            ? sessions
            : sessions.take(limit).toList(growable: false);
        final response = {
          'kind': 'sessionList',
          'sessionsDirectory': sessionsDirectory.path,
          'totalSessions': sessions.length,
          'truncated': limit != null && sessions.length > limit,
          'sessions': [
            for (final session in listedSessions) _sessionMetadataJson(session),
          ],
        };
        progress(2, 2, 'Session list prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileListRegions(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Regions listed.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        progress(0, 2, 'Loading stored session regions.');
        final session = await _resolveSession(arguments);
        final response = {
          'kind': 'regionList',
          'session': _sessionMetadataJson(session),
          'availableProfileIds': [
            if (session.result.overallProfile != null) 'overall',
            for (final region in session.result.regions) region.regionId,
          ],
          'overallProfile': switch (session.result.overallProfile) {
            final ProfileRegionResult overall =>
              _regionListingJson(overall, scope: 'session'),
            _ => null,
          },
          'regions': [
            for (final region in session.result.regions)
              _regionListingJson(region, scope: 'region'),
          ],
        };
        progress(2, 2, 'Region list prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileLatestSession(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Latest session loaded.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        progress(0, 3, 'Resolving latest stored session.');
        final sessionsDirectory = _resolveSessionsDirectory(arguments);
        final sessions = await _discoverSessions(sessionsDirectory);
        if (sessions.isEmpty) {
          throw ArgumentError(
            'No profiling sessions were found under "${sessionsDirectory.path}".',
          );
        }
        final session = sessions.first;
        final treeOptions = _treeOptionsFromArguments(arguments);
        progress(1, 3, 'Preparing latest session view.');
        final prepared = await prepareSessionPresentation(
          runner,
          session.result,
          options: treeOptions,
        );
        final response = {
          'kind': 'latestSession',
          'session': _sessionMetadataJson(session),
          'summary': sessionPresentationJson(
            prepared.session,
            prepared.overallTree,
            prepared.overallBottomUpTree,
            prepared.overallMethodTable,
            prepared.regionTrees,
            prepared.regionBottomUpTrees,
            prepared.regionMethodTables,
          ),
        };
        progress(3, 3, 'Latest session prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileGetSession(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Session loaded.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        progress(0, 3, 'Resolving stored session.');
        final session = await _resolveSession(arguments);
        final treeOptions = _treeOptionsFromArguments(arguments);
        progress(1, 3, 'Preparing session view.');
        final prepared = await prepareSessionPresentation(
          runner,
          session.result,
          options: treeOptions,
        );
        final response = {
          'kind': 'session',
          'session': _sessionMetadataJson(session),
          'summary': sessionPresentationJson(
            prepared.session,
            prepared.overallTree,
            prepared.overallBottomUpTree,
            prepared.overallMethodTable,
            prepared.regionTrees,
            prepared.regionBottomUpTrees,
            prepared.regionMethodTables,
          ),
        };
        progress(3, 3, 'Session prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileGetRegion(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Region loaded.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        progress(0, 3, 'Resolving stored session region.');
        final session = await _resolveSession(arguments);
        final requestedRegionId = _requiredStringArgument(
          arguments,
          key: 'regionId',
        );
        final region = _resolveRequestedRegion(
          session.result,
          requestedRegionId,
        );
        final treeOptions = _treeOptionsFromArguments(arguments);
        progress(1, 3, 'Preparing region view.');
        final prepared = await prepareRegionPresentation(
          runner,
          region,
          options: treeOptions,
        );
        final response = {
          'kind': 'region',
          'scope': _profileScope(prepared.region),
          'session': _sessionMetadataJson(session),
          'profile': regionPresentationJson(
            prepared.region,
            prepared.callTree,
            prepared.bottomUpTree,
            prepared.methodTable,
          ),
        };
        progress(3, 3, 'Region prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileExplainHotspots(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Hotspots explained.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        final treeOptions = _treeOptionsFromArguments(arguments);
        final directPath = _optionalStringArgument(arguments, key: 'path');
        progress(0, 3, 'Resolving profile for hotspot analysis.');
        final explanation = await prepareProfileExplanation(
          runner,
          targetPath:
              directPath ?? (await _resolveSession(arguments)).directory.path,
          profileId: directPath != null
              ? _optionalStringArgument(arguments, key: 'profileId')
              : _optionalStringArgument(arguments, key: 'regionId'),
          options: treeOptions,
        );
        progress(2, 3, 'Building hotspot explanation.');
        final response = hotspotExplanationJson(explanation);
        progress(3, 3, 'Hotspot explanation prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileInspectMethod(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Method inspected.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        final options = _treeOptionsFromArguments(arguments);
        final directPath = _optionalStringArgument(arguments, key: 'path');
        progress(0, 3, 'Resolving profile for method inspection.');
        final inspection = await prepareProfileMethodInspection(
          runner,
          targetPath:
              directPath ?? (await _resolveSession(arguments)).directory.path,
          profileId: directPath != null
              ? _optionalStringArgument(arguments, key: 'profileId')
              : _optionalStringArgument(arguments, key: 'regionId'),
          methodId: _optionalStringArgument(arguments, key: 'methodId'),
          methodName: _optionalStringArgument(arguments, key: 'methodName'),
          pathLimit: arguments['pathLimit'] as int?,
          options: options,
        );
        progress(2, 3, 'Building method inspection response.');
        final response = methodInspectionJson(inspection);
        progress(3, 3, 'Method inspection prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileSearchMethods(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Methods searched.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        final options = _treeOptionsFromArguments(arguments);
        final directPath = _optionalStringArgument(arguments, key: 'path');
        progress(0, 3, 'Resolving profile for method search.');
        final search = await prepareProfileMethodSearch(
          runner,
          targetPath:
              directPath ?? (await _resolveSession(arguments)).directory.path,
          profileId: directPath != null
              ? _optionalStringArgument(arguments, key: 'profileId')
              : _optionalStringArgument(arguments, key: 'regionId'),
          query: _optionalStringArgument(arguments, key: 'query'),
          sortBy: switch (_optionalStringArgument(arguments, key: 'sortBy')) {
            final String value => ProfileMethodSearchSort.parse(value),
            _ => ProfileMethodSearchSort.total,
          },
          limit: arguments['limit'] as int?,
          options: options,
        );
        progress(2, 3, 'Building method search response.');
        final response = methodSearchJson(search);
        progress(3, 3, 'Method search prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileCompareMethod(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Method compared.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        final options = _treeOptionsFromArguments(arguments);
        progress(0, 3, 'Resolving method comparison targets.');
        final baselinePath = await _resolveComparisonTargetPath(
          arguments,
          pathKey: 'baselinePath',
          sessionPathKey: 'baselineSessionPath',
          sessionIdKey: 'baselineSessionId',
        );
        final currentPath = await _resolveComparisonTargetPath(
          arguments,
          pathKey: 'currentPath',
          sessionPathKey: 'currentSessionPath',
          sessionIdKey: 'currentSessionId',
        );
        progress(1, 3, 'Preparing method comparison.');
        final comparison = await prepareProfileMethodComparison(
          runner,
          baselinePath: baselinePath,
          currentPath: currentPath,
          baselineProfileId: _optionalStringArgument(
            arguments,
            key: 'baselineProfileId',
          ),
          currentProfileId: _optionalStringArgument(
            arguments,
            key: 'currentProfileId',
          ),
          methodId: _optionalStringArgument(arguments, key: 'methodId'),
          methodName: _optionalStringArgument(arguments, key: 'methodName'),
          pathLimit: arguments['pathLimit'] as int?,
          relationLimit: options.methodLimit,
          options: options,
        );
        progress(2, 3, 'Building method comparison response.');
        final response = methodComparisonJson(comparison);
        progress(3, 3, 'Method comparison prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileCompare(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Profiles compared.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        final treeOptions = _treeOptionsFromArguments(arguments);
        progress(0, 3, 'Resolving comparison targets.');
        final baselinePath = await _resolveComparisonTargetPath(
          arguments,
          pathKey: 'baselinePath',
          sessionPathKey: 'baselineSessionPath',
          sessionIdKey: 'baselineSessionId',
        );
        final currentPath = await _resolveComparisonTargetPath(
          arguments,
          pathKey: 'currentPath',
          sessionPathKey: 'currentSessionPath',
          sessionIdKey: 'currentSessionId',
        );
        progress(1, 3, 'Preparing comparison views.');
        final comparison = await prepareProfileComparison(
          runner,
          baselinePath: baselinePath,
          currentPath: currentPath,
          baselineProfileId: _optionalStringArgument(
            arguments,
            key: 'baselineProfileId',
          ),
          currentProfileId: _optionalStringArgument(
            arguments,
            key: 'currentProfileId',
          ),
          options: treeOptions,
        );
        progress(2, 3, 'Building comparison response.');
        final response = comparisonPresentationJson(comparison);
        progress(3, 3, 'Comparison prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _profileAnalyzeTrends(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Trends analyzed.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        final options = _treeOptionsFromArguments(arguments);
        progress(0, 4, 'Resolving trend targets.');
        final targetPaths = await _resolveTrendTargetPaths(arguments);
        progress(1, 4, 'Preparing trend views.');
        final trends = await prepareProfileTrends(
          runner,
          targetPaths: targetPaths,
          profileId: _optionalStringArgument(arguments, key: 'profileId'),
          options: options,
        );
        progress(3, 4, 'Building trend response.');
        final response = trendPresentationJson(trends);
        final sessionsDirectory = switch (_trendSessionsDirectory(arguments)) {
          final Directory directory => directory.path,
          _ => null,
        };
        progress(4, 4, 'Trend analysis prepared.');
        return {
          ...response,
          if (sessionsDirectory != null) 'sessionsDirectory': sessionsDirectory,
        };
      },
    );
  }

  Future<CallToolResult> _profileFindRegressions(CallToolRequest request) {
    return _runTool(
      request: request,
      successMessage: 'Regressions analyzed.',
      action: (progress) async {
        final arguments = request.arguments ?? const <String, Object?>{};
        progress(0, 3, 'Resolving stored sessions for regression analysis.');
        final sessionsDirectory = _resolveSessionsDirectory(arguments);
        final sessions = await _discoverSessions(sessionsDirectory);
        final currentSession = _selectStoredSession(
          sessions,
          selector: _optionalStringArgument(arguments, key: 'currentSessionId'),
          defaultIndex: 0,
          defaultLabel: 'latest',
        );
        final baselineSession = _selectStoredSession(
          sessions,
          selector:
              _optionalStringArgument(arguments, key: 'baselineSessionId'),
          defaultIndex: 1,
          defaultLabel: 'previous',
        );
        if (baselineSession.result.sessionId ==
            currentSession.result.sessionId) {
          throw ArgumentError(
            'Baseline and current sessions resolved to the same session '
            '"${currentSession.result.sessionId}".',
          );
        }

        final treeOptions = _treeOptionsFromArguments(arguments);
        progress(1, 3, 'Preparing regression comparison.');
        final comparison = await prepareProfileComparison(
          runner,
          baselinePath: baselineSession.directory.path,
          currentPath: currentSession.directory.path,
          baselineProfileId: _optionalStringArgument(
            arguments,
            key: 'baselineProfileId',
          ),
          currentProfileId: _optionalStringArgument(
            arguments,
            key: 'currentProfileId',
          ),
          options: treeOptions,
        );

        final response = {
          ...comparisonPresentationJson(comparison),
          'kind': 'regressionSearch',
          'sessionsDirectory': sessionsDirectory.path,
          'baselineSession': _sessionMetadataJson(baselineSession),
          'currentSession': _sessionMetadataJson(currentSession),
        };
        progress(3, 3, 'Regression analysis prepared.');
        return response;
      },
    );
  }

  Future<CallToolResult> _runTool({
    required CallToolRequest request,
    required String successMessage,
    required Future<Map<String, Object?>> Function(_ProgressReporter progress)
        action,
  }) async {
    try {
      final progressToken = request.meta?.progressToken;
      void emitProgress(num progress, num total, String message) {
        if (progressToken == null) {
          return;
        }
        notifyProgress(
          ProgressNotification(
            progressToken: progressToken,
            progress: progress,
            total: total,
            message: message,
          ),
        );
      }

      final result = await action(emitProgress);
      return CallToolResult(
        content: [
          TextContent(
            text: '$successMessage\n${_jsonEncoder.convert(result)}',
          ),
        ],
        structuredContent: result,
      );
    } catch (error) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: error.toString())],
      );
    }
  }

  Future<Map<String, Object?>> _summarizeWithCallTrees(
    String targetPath,
    ProfilePresentationOptions treeOptions,
  ) async {
    final summary = await runner.summarizeArtifact(targetPath);
    if (summary case {'regions': final Object? _}) {
      final prepared = await prepareSessionPresentation(
        runner,
        ProfileRunResult.fromJson(summary),
        options: treeOptions,
      );
      return sessionPresentationJson(
        prepared.session,
        prepared.overallTree,
        prepared.overallBottomUpTree,
        prepared.overallMethodTable,
        prepared.regionTrees,
        prepared.regionBottomUpTrees,
        prepared.regionMethodTables,
      );
    }
    if (summary case {'topSelfFrames': final Object? _}) {
      final prepared = await prepareRegionPresentation(
        runner,
        ProfileRegionResult.fromJson(summary),
        options: treeOptions,
      );
      return regionPresentationJson(
        prepared.region,
        prepared.callTree,
        prepared.bottomUpTree,
        prepared.methodTable,
      );
    }
    return summary;
  }

  Future<List<_StoredSession>> _discoverSessions(
    Directory sessionsDirectory,
  ) async {
    final sessions = <_StoredSession>[];
    for (final entity in sessionsDirectory.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      final sessionFile = File(path.join(entity.path, _sessionFileName));
      if (!sessionFile.existsSync()) {
        continue;
      }
      final stat = await sessionFile.stat();
      final result = await ProfileArtifacts.readSession(entity.path);
      sessions.add(
        _StoredSession(
          directory: Directory(path.normalize(path.absolute(entity.path))),
          result: result,
          modifiedTime: stat.modified.toUtc(),
        ),
      );
    }
    sessions.sort(
      (left, right) => right.modifiedTime.compareTo(left.modifiedTime),
    );
    return sessions;
  }

  Future<_StoredSession> _resolveSession(Map<String, Object?> arguments) async {
    return _resolveSessionWithKeys(
      arguments,
      sessionPathKey: 'sessionPath',
      sessionIdKey: 'sessionId',
    );
  }

  Future<String> _resolveComparisonTargetPath(
    Map<String, Object?> arguments, {
    required String pathKey,
    required String sessionPathKey,
    required String sessionIdKey,
  }) async {
    final directPath = _optionalStringArgument(arguments, key: pathKey);
    if (directPath != null) {
      return directPath;
    }
    final session = await _resolveSessionWithKeys(
      arguments,
      sessionPathKey: sessionPathKey,
      sessionIdKey: sessionIdKey,
    );
    return session.directory.path;
  }

  Future<List<String>> _resolveTrendTargetPaths(
    Map<String, Object?> arguments,
  ) async {
    final explicitPaths = arguments['paths'] as List<Object?>?;
    if (explicitPaths != null && explicitPaths.isNotEmpty) {
      final normalized = [
        for (final value in explicitPaths)
          path.normalize(path.absolute(value as String)),
      ];
      if (normalized.length < 2) {
        throw ArgumentError(
          'Trend analysis requires at least two explicit paths.',
        );
      }
      return normalized;
    }

    final sessionsDirectory = _resolveSessionsDirectory(arguments);
    final sessionIds =
        (arguments['sessionIds'] as List<Object?>? ?? const []).cast<String>();
    if (sessionIds.isNotEmpty) {
      if (sessionIds.length < 2) {
        throw ArgumentError(
          'Trend analysis requires at least two session ids.',
        );
      }
      final resolved = <String>[];
      for (final sessionId in sessionIds) {
        final session = await _resolveStoredSessionById(
          sessionsDirectory,
          sessionId,
        );
        resolved.add(session.directory.path);
      }
      return resolved;
    }

    final sessions = await _discoverSessions(sessionsDirectory);
    final limit = _listLimitFromArguments(arguments);
    final selected =
        limit == null ? sessions : sessions.take(limit).toList(growable: false);
    if (selected.length < 2) {
      throw ArgumentError(
        'Trend analysis requires at least two stored sessions.',
      );
    }
    return selected.reversed.map((session) => session.directory.path).toList();
  }

  Future<_StoredSession> _resolveSessionWithKeys(
    Map<String, Object?> arguments, {
    required String sessionPathKey,
    required String sessionIdKey,
  }) async {
    final sessionPath = _optionalStringArgument(arguments, key: sessionPathKey);
    if (sessionPath != null) {
      final sessionDirectory = Directory(
        path.normalize(path.absolute(sessionPath)),
      );
      if (!sessionDirectory.existsSync()) {
        throw ArgumentError('Session directory not found: $sessionPath');
      }
      final sessionFile =
          File(path.join(sessionDirectory.path, _sessionFileName));
      if (!sessionFile.existsSync()) {
        throw ArgumentError('No session.json found in "$sessionPath".');
      }
      final stat = await sessionFile.stat();
      return _StoredSession(
        directory: sessionDirectory,
        result: await ProfileArtifacts.readSession(sessionDirectory.path),
        modifiedTime: stat.modified.toUtc(),
      );
    }

    final sessionId = _optionalStringArgument(arguments, key: sessionIdKey);
    if (sessionId == null) {
      throw ArgumentError(
        'Either "$sessionPathKey" or "$sessionIdKey" must be provided.',
      );
    }

    final sessionsDirectory = _resolveSessionsDirectory(arguments);
    if (sessionId == 'latest' || sessionId == 'previous') {
      final sessions = await _discoverSessions(sessionsDirectory);
      if (sessions.isEmpty) {
        throw ArgumentError(
          'No profiling sessions were found under "${sessionsDirectory.path}".',
        );
      }
      if (sessionId == 'previous') {
        if (sessions.length < 2) {
          throw ArgumentError(
            'Unable to resolve the previous session because fewer than two stored sessions are available.',
          );
        }
        return sessions[1];
      }
      return sessions.first;
    }
    final sessionDirectory = Directory(
      path.join(sessionsDirectory.path, sessionId),
    );
    if (!sessionDirectory.existsSync()) {
      throw ArgumentError(
        'Session "$sessionId" was not found under "${sessionsDirectory.path}".',
      );
    }
    final sessionFile =
        File(path.join(sessionDirectory.path, _sessionFileName));
    if (!sessionFile.existsSync()) {
      throw ArgumentError(
        'No session.json found for session "$sessionId" under "${sessionsDirectory.path}".',
      );
    }
    final stat = await sessionFile.stat();
    return _StoredSession(
      directory:
          Directory(path.normalize(path.absolute(sessionDirectory.path))),
      result: await ProfileArtifacts.readSession(sessionDirectory.path),
      modifiedTime: stat.modified.toUtc(),
    );
  }

  Future<_StoredSession> _resolveStoredSessionById(
    Directory sessionsDirectory,
    String sessionId,
  ) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Session ids for trend analysis must not be empty.');
    }
    if (normalized == 'latest' || normalized == 'previous') {
      final sessions = await _discoverSessions(sessionsDirectory);
      if (normalized == 'latest') {
        if (sessions.isEmpty) {
          throw ArgumentError(
            'No profiling sessions were found under "${sessionsDirectory.path}".',
          );
        }
        return sessions.first;
      }
      if (sessions.length < 2) {
        throw ArgumentError(
          'Unable to resolve the previous session because fewer than two stored sessions are available.',
        );
      }
      return sessions[1];
    }

    final sessionDirectory = Directory(
      path.join(sessionsDirectory.path, normalized),
    );
    if (!sessionDirectory.existsSync()) {
      throw ArgumentError(
        'Session "$normalized" was not found under "${sessionsDirectory.path}".',
      );
    }
    final sessionFile =
        File(path.join(sessionDirectory.path, _sessionFileName));
    if (!sessionFile.existsSync()) {
      throw ArgumentError(
        'No session.json found for session "$normalized" under "${sessionsDirectory.path}".',
      );
    }
    final stat = await sessionFile.stat();
    return _StoredSession(
      directory:
          Directory(path.normalize(path.absolute(sessionDirectory.path))),
      result: await ProfileArtifacts.readSession(sessionDirectory.path),
      modifiedTime: stat.modified.toUtc(),
    );
  }
}

class _StoredSession {
  const _StoredSession({
    required this.directory,
    required this.result,
    required this.modifiedTime,
  });

  final Directory directory;
  final ProfileRunResult result;
  final DateTime modifiedTime;
}

_StoredSession _selectStoredSession(
  List<_StoredSession> sessions, {
  required String? selector,
  required int defaultIndex,
  required String defaultLabel,
}) {
  if (sessions.isEmpty) {
    throw ArgumentError('No profiling sessions are available.');
  }

  final normalized = selector?.trim();
  if (normalized == null || normalized.isEmpty) {
    if (sessions.length <= defaultIndex) {
      throw ArgumentError(
        'Unable to resolve the $defaultLabel session because only '
        '${sessions.length} stored session(s) are available.',
      );
    }
    return sessions[defaultIndex];
  }

  switch (normalized) {
    case 'latest':
      return sessions.first;
    case 'previous':
      if (sessions.length < 2) {
        throw ArgumentError(
          'Unable to resolve the previous session because fewer than two stored sessions are available.',
        );
      }
      return sessions[1];
  }

  return sessions.firstWhere(
    (session) => session.result.sessionId == normalized,
    orElse: () => throw ArgumentError(
      'Session "$normalized" was not found in the stored session list.',
    ),
  );
}

Directory _resolveSessionsDirectory(Map<String, Object?> arguments) {
  final explicitSessionsDirectory = _optionalStringArgument(
    arguments,
    key: 'sessionsDirectory',
  );
  if (explicitSessionsDirectory != null) {
    final directory = Directory(
      path.normalize(path.absolute(explicitSessionsDirectory)),
    );
    if (!directory.existsSync()) {
      throw ArgumentError(
        'Sessions directory not found: $explicitSessionsDirectory',
      );
    }
    return directory;
  }

  final rootDirectory =
      _optionalStringArgument(arguments, key: 'rootDirectory') ??
          Directory.current.path;
  final normalizedRoot = path.normalize(path.absolute(rootDirectory));
  final candidate = Directory(
    path.join(normalizedRoot, '.dart_tool', 'devtools_profiler', 'sessions'),
  );
  if (candidate.existsSync()) {
    return candidate;
  }

  final directDirectory = Directory(normalizedRoot);
  if (path.basename(directDirectory.path) == _sessionsDirectoryName &&
      directDirectory.existsSync()) {
    return directDirectory;
  }

  throw ArgumentError(
    'No profiler sessions directory found under "$rootDirectory".',
  );
}

Directory? _trendSessionsDirectory(Map<String, Object?> arguments) {
  if (arguments['paths'] case final List<Object?> paths when paths.isNotEmpty) {
    return null;
  }
  return _resolveSessionsDirectory(arguments);
}

Map<String, Object?> _sessionMetadataJson(_StoredSession session) {
  return {
    'sessionId': session.result.sessionId,
    'sessionPath': session.directory.path,
    'modified': session.modifiedTime.toIso8601String(),
    'workingDirectory': session.result.workingDirectory,
    'command': session.result.command,
    'exitCode': session.result.exitCode,
    'warningCount': session.result.warnings.length,
    'warnings': session.result.warnings,
    'supportedCaptureKinds': [
      for (final kind in session.result.supportedCaptureKinds) kind.name,
    ],
    'supportedIsolateScopes': [
      for (final scope in session.result.supportedIsolateScopes) scope.name,
    ],
    'regionCount': session.result.regions.length,
    'regionIds': [
      for (final region in session.result.regions) region.regionId,
    ],
    'hasOverallProfile': session.result.overallProfile != null,
    'vmServiceUri': session.result.vmServiceUri,
  };
}

Map<String, Object?> _regionListingJson(
  ProfileRegionResult region, {
  required String scope,
}) {
  return {
    'regionId': region.regionId,
    'name': region.name,
    'scope': scope,
    'attributes': region.attributes,
    'captureKinds': [for (final kind in region.captureKinds) kind.name],
    'isolateScope': region.isolateScope.name,
    'originIsolateId': region.isolateId,
    'isolateIds': region.isolateIds,
    'isolateCount': region.isolateIds.length,
    'parentRegionId': region.parentRegionId,
    'durationMicros': region.durationMicros,
    'sampleCount': region.sampleCount,
    'samplePeriodMicros': region.samplePeriodMicros,
    'succeeded': region.succeeded,
    'summaryPath': region.summaryPath,
    'rawProfilePath': region.rawProfilePath,
    'error': region.error,
    if (region.topSelfFrames.isNotEmpty)
      'topSelfFrame': region.topSelfFrames.first.toJson(),
    if (region.topTotalFrames.isNotEmpty)
      'topTotalFrame': region.topTotalFrames.first.toJson(),
  };
}

ProfileRegionResult _resolveRequestedRegion(
  ProfileRunResult session,
  String regionId,
) {
  if (regionId == 'overall') {
    final overallProfile = session.overallProfile;
    if (overallProfile == null) {
      throw ArgumentError(
        'Session "${session.sessionId}" does not have a whole-session profile.',
      );
    }
    return overallProfile;
  }

  return session.regions.firstWhere(
    (region) => region.regionId == regionId,
    orElse: () => throw ArgumentError(
      'Region "$regionId" was not found in session "${session.sessionId}".',
    ),
  );
}

String _profileScope(ProfileRegionResult region) {
  if (region.regionId == 'overall' || region.attributes['scope'] == 'session') {
    return 'session';
  }
  return 'region';
}

String _requiredStringArgument(
  Map<String, Object?> arguments, {
  required String key,
}) {
  final value = arguments[key] as String?;
  if (value == null || value.isEmpty) {
    throw ArgumentError('The "$key" argument is required.');
  }
  return value;
}

String? _optionalStringArgument(
  Map<String, Object?> arguments, {
  required String key,
}) {
  final value = arguments[key] as String?;
  if (value == null || value.isEmpty) return null;
  return value;
}

Duration? _optionalDurationSecondsArgument(
  Map<String, Object?> arguments, {
  String key = 'durationSeconds',
}) {
  final value = arguments[key];
  if (value == null) {
    return null;
  }
  if (value is! int || value <= 0) {
    throw ArgumentError(
      'The "$key" argument must be a positive integer.',
    );
  }
  return Duration(seconds: value);
}

Duration _requiredDurationSecondsArgument(
  Map<String, Object?> arguments, {
  String key = 'durationSeconds',
}) {
  final duration = _optionalDurationSecondsArgument(arguments, key: key);
  if (duration == null) {
    throw ArgumentError('The "$key" argument is required.');
  }
  return duration;
}

Uri _requiredUriArgument(
  Map<String, Object?> arguments, {
  required String key,
}) {
  final value = _requiredStringArgument(arguments, key: key);
  final uri = Uri.parse(value);
  if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw ArgumentError(
      'The "$key" argument must be an HTTP VM service URI.',
    );
  }
  return uri;
}

List<String> _stringListArgument(
  Map<String, Object?> arguments, {
  required String key,
}) {
  final values = arguments[key] as List<Object?>?;
  if (values == null || values.isEmpty) {
    throw ArgumentError('The "$key" argument is required.');
  }
  return values.map((value) => value as String).toList();
}

int? _listLimitFromArguments(Map<String, Object?> arguments) {
  final value = arguments['limit'];
  if (value == null) {
    return _defaultSessionListLimit;
  }
  if (value is! int || value < 0) {
    throw ArgumentError('The "limit" argument must be a non-negative integer.');
  }
  return value == 0 ? null : value;
}

ProfilePresentationOptions _treeOptionsFromArguments(
  Map<String, Object?> arguments,
) {
  return ProfilePresentationOptions(
    includeCallTree: arguments['includeCallTree'] as bool? ?? false,
    includeBottomUpTree: arguments['includeBottomUpTree'] as bool? ?? false,
    includeMethodTable: arguments['includeMethodTable'] as bool? ?? false,
    hideSdk: arguments['hideSdk'] as bool? ?? false,
    hideRuntimeHelpers: arguments['hideRuntimeHelpers'] as bool? ?? false,
    includePackages: _stringListOrEmpty(arguments['includePackages']),
    excludePackages: _stringListOrEmpty(arguments['excludePackages']),
    frameLimit: _treeLimitFromArgument(
      arguments,
      key: 'frameLimit',
      defaultValue: defaultFrameLimit,
    ),
    methodLimit: _treeLimitFromArgument(
      arguments,
      key: 'methodLimit',
      defaultValue: defaultFrameLimit,
    ),
    maxDepth: _treeLimitFromArgument(
      arguments,
      key: 'treeDepth',
      defaultValue: defaultTreeDepth,
    ),
    maxChildren: _treeLimitFromArgument(
      arguments,
      key: 'treeChildren',
      defaultValue: defaultTreeChildren,
    ),
  );
}

int? _treeLimitFromArgument(
  Map<String, Object?> arguments, {
  required String key,
  required int defaultValue,
}) {
  final value = arguments[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is! int || value < 0) {
    throw ArgumentError('The "$key" argument must be a non-negative integer.');
  }
  return value == 0 ? null : value;
}

List<String> _stringListOrEmpty(Object? value) {
  final values = value as List<Object?>?;
  if (values == null) {
    return const [];
  }
  return [
    for (final item in values)
      if (item is String && item.isNotEmpty) item,
  ];
}
