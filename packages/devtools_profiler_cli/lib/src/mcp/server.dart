import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:devtools_profiler_core/devtools_profiler_core.dart';
import 'package:stream_channel/stream_channel.dart';

import 'tool_definitions.dart';
import 'tool_handlers.dart';

const _serverName = 'devtools-profiler';
const _serverVersion = '0.1.0';

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
    final handlers = McpToolHandlers(
      runner: runner,
      notifyProgress: notifyProgress,
    );
    registerTool(profileRunTool, handlers.profileRun);
    registerTool(profileAttachTool, handlers.profileAttach);
    registerTool(profileSummarizeTool, handlers.profileSummarize);
    registerTool(profileReadArtifactTool, handlers.profileReadArtifact);
    registerTool(profileListSessionsTool, handlers.profileListSessions);
    registerTool(profileLatestSessionTool, handlers.profileLatestSession);
    registerTool(profileGetSessionTool, handlers.profileGetSession);
    registerTool(profileListRegionsTool, handlers.profileListRegions);
    registerTool(profileGetRegionTool, handlers.profileGetRegion);
    registerTool(profileExplainHotspotsTool, handlers.profileExplainHotspots);
    registerTool(profileInspectMethodTool, handlers.profileInspectMethod);
    registerTool(profileSearchMethodsTool, handlers.profileSearchMethods);
    registerTool(profileCompareMethodTool, handlers.profileCompareMethod);
    registerTool(profileCompareTool, handlers.profileCompare);
    registerTool(profileAnalyzeTrendsTool, handlers.profileAnalyzeTrends);
    registerTool(profileFindRegressionsTool, handlers.profileFindRegressions);
  }

  /// The profiler backend used by all tool calls.
  final ProfileRunner runner;
}
