import 'package:dart_mcp/server.dart';

final Tool profileDiscoverAppsTool = Tool(
  name: 'profile_discover_apps',
  title: 'Profile Discover Apps',
  description:
      'Discover running Flutter and Dart applications on the local machine '
      'that expose a Dart VM service URI. Use the returned URIs with '
      'profile_attach or profile_get_session.',
  inputSchema: Schema.object(properties: {}, additionalProperties: false),
  outputSchema: Schema.object(
    description: 'List of discovered application VM service URIs.',
    additionalProperties: true,
  ),
  annotations: ToolAnnotations(
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    readOnlyHint: true,
    title: 'Profile Discover Apps',
  ),
);

final Tool profileFrameProfileTool = Tool(
  name: 'profile_frame_profile',
  title: 'Profile Frame Profile',
  description:
      'Profile frame timing and detect jank from a running Flutter application. '
      'Connects to the VM service URI, samples frame events from the VM '
      'timeline for the requested duration, and returns frame timing metrics '
      'including P90, P99, max frame times, jank percentage, and phase '
      'breakdowns (build, layout, paint). Use profile_discover_apps to find '
      'available VM service URIs.',
  inputSchema: Schema.object(
    properties: {
      'vmServiceUri': Schema.string(
        description:
            'The VM service WebSocket URI (e.g. '
            'ws://127.0.0.1:8181/abc123/ws).',
      ),
      'durationSeconds': Schema.int(
        description: 'Duration to profile frames in seconds (default: 5).',
      ),
    },
    required: ['vmServiceUri'],
    additionalProperties: false,
  ),
  outputSchema: Schema.object(
    description: 'Frame timing analysis results.',
    additionalProperties: true,
  ),
  annotations: ToolAnnotations(
    destructiveHint: false,
    idempotentHint: false,
    openWorldHint: false,
    readOnlyHint: true,
    title: 'Profile Frame Profile',
  ),
);

final Tool profileTimelineTool = Tool(
  name: 'profile_timeline',
  title: 'Profile Timeline',
  description:
      'Profile VM timeline frame timing and detect jank from a running '
      'Flutter application. Connects to the VM service URI, samples frame '
      'events from the VM timeline for the requested duration, and returns '
      'frame timing metrics including P90, P99, max frame times, jank '
      'percentage, and phase breakdowns (build, layout, paint). Use '
      'profile_discover_apps to find available VM service URIs.',
  inputSchema: Schema.object(
    properties: {
      'vmServiceUri': Schema.string(
        description:
            'The VM service WebSocket URI (e.g. '
            'ws://127.0.0.1:8181/abc123/ws).',
      ),
      'durationSeconds': Schema.int(
        description: 'Duration to profile frames in seconds (default: 5).',
      ),
    },
    required: ['vmServiceUri'],
    additionalProperties: false,
  ),
  outputSchema: Schema.object(
    description: 'Frame timing analysis results.',
    additionalProperties: true,
  ),
  annotations: ToolAnnotations(
    destructiveHint: false,
    idempotentHint: false,
    openWorldHint: false,
    readOnlyHint: true,
    title: 'Profile Timeline',
  ),
);

final Tool profileMemorySnapshotTool = Tool(
  name: 'profile_memory_snapshot',
  title: 'Profile Memory Snapshot',
  description:
      'Capture an allocation profile and memory snapshot from a running '
      'Dart or Flutter application. Returns the top allocation classes sorted '
      'by current heap size. Optionally save the snapshot and force garbage '
      'collection before capture.',
  inputSchema: Schema.object(
    properties: {
      'vmServiceUri': Schema.string(
        description:
            'The VM service WebSocket URI (e.g. '
            'ws://127.0.0.1:8181/abc123/ws).',
      ),
      'name': Schema.string(
        description:
            'Optional name for this snapshot. Auto-generates when omitted.',
      ),
      'forceGc': Schema.bool(
        description:
            'Force garbage collection before the snapshot (default: true).',
      ),
      'topN': Schema.int(
        description:
            'Number of top allocation classes to include (default: 50).',
      ),
    },
    required: ['vmServiceUri'],
    additionalProperties: false,
  ),
  outputSchema: Schema.object(
    description: 'Memory snapshot with class allocation details.',
    additionalProperties: true,
  ),
  annotations: ToolAnnotations(
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    readOnlyHint: true,
    title: 'Profile Memory Snapshot',
  ),
);

final Tool profileWidgetTreeTool = Tool(
  name: 'profile_widget_tree',
  title: 'Profile Widget Tree',
  description:
      'Capture the current Flutter widget tree from a running application. '
      'Returns the tree structure with node types and descriptions. Use '
      '--summary for a condensed tree or --project-only to filter framework '
      'widgets.',
  inputSchema: Schema.object(
    properties: {
      'vmServiceUri': Schema.string(
        description:
            'The VM service WebSocket URI (e.g. '
            'ws://127.0.0.1:8181/abc123/ws).',
      ),
      'maxDepth': Schema.int(description: 'Maximum tree depth (default: 15).'),
      'summary': Schema.bool(
        description: 'Use the summary tree (Flutter widgets only).',
      ),
      'projectOnly': Schema.bool(
        description: 'Filter to project widgets only.',
      ),
    },
    required: ['vmServiceUri'],
    additionalProperties: false,
  ),
  outputSchema: Schema.object(
    description: 'Captured Flutter widget tree.',
    additionalProperties: true,
  ),
  annotations: ToolAnnotations(
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    readOnlyHint: true,
    title: 'Profile Widget Tree',
  ),
);

final Tool profileNavigationStackTool = Tool(
  name: 'profile_navigation_stack',
  title: 'Profile Navigation Stack',
  description:
      'Inspect the Flutter navigation route stack from a running application. '
      'Returns the ordered list of routes with their types, settings names, '
      'and which route is currently displayed.',
  inputSchema: Schema.object(
    properties: {
      'vmServiceUri': Schema.string(
        description:
            'The VM service WebSocket URI (e.g. '
            'ws://127.0.0.1:8181/abc123/ws).',
      ),
    },
    required: ['vmServiceUri'],
    additionalProperties: false,
  ),
  outputSchema: Schema.object(
    description: 'Captured Flutter navigation route stack.',
    additionalProperties: true,
  ),
  annotations: ToolAnnotations(
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    readOnlyHint: true,
    title: 'Profile Navigation Stack',
  ),
);

final Tool profileScreenshotTool = Tool(
  name: 'profile_screenshot',
  title: 'Profile Screenshot',
  description:
      'Capture a screenshot from a running Flutter application. '
      'Uses the ext.flutter.inspector.screenshot service extension. '
      'Returns base64-encoded PNG image data.',
  inputSchema: Schema.object(
    properties: {
      'vmServiceUri': Schema.string(
        description:
            'The VM service WebSocket URI (e.g. '
            'ws://127.0.0.1:8181/abc123/ws).',
      ),
      'width': Schema.int(description: 'Image width in pixels (default: 800).'),
      'height': Schema.int(
        description: 'Image height in pixels (default: 600).',
      ),
      'maxPixelRatio': Schema.int(
        description: 'Maximum pixel ratio for retina screens (default: 3).',
      ),
    },
    required: ['vmServiceUri'],
    additionalProperties: false,
  ),
  outputSchema: Schema.object(
    description: 'Captured Flutter app screenshot.',
    additionalProperties: true,
  ),
  annotations: ToolAnnotations(
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    readOnlyHint: true,
    title: 'Profile Screenshot',
  ),
);

final Tool profileDebugDumpTool = Tool(
  name: 'profile_debug_dump',
  title: 'Profile Debug Dump',
  description:
      'Call Flutter debug dump service extensions (app, render, layer, focus, '
      'semantics) for diagnostic information from a running application.',
  inputSchema: Schema.object(
    properties: {
      'vmServiceUri': Schema.string(
        description:
            'The VM service WebSocket URI (e.g. '
            'ws://127.0.0.1:8181/abc123/ws).',
      ),
      'kind': Schema.string(
        description:
            'What to dump: app, render, layer, focus, semantics (default: app).',
      ),
    },
    required: ['vmServiceUri'],
    additionalProperties: false,
  ),
  outputSchema: Schema.object(
    description: 'Debug dump diagnostic output.',
    additionalProperties: true,
  ),
  annotations: ToolAnnotations(
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    readOnlyHint: true,
    title: 'Profile Debug Dump',
  ),
);

final Tool profileStreamLogsTool = Tool(
  name: 'profile_stream_logs',
  title: 'Profile Stream Logs',
  description:
      'Capture log and output streams (Logging, Stdout, Stderr) from a '
      'running Dart or Flutter application for a specified duration. '
      'Returns structured log entries with timestamps.',
  inputSchema: Schema.object(
    properties: {
      'vmServiceUri': Schema.string(
        description:
            'The VM service WebSocket URI (e.g. '
            'ws://127.0.0.1:8181/abc123/ws).',
      ),
      'durationSeconds': Schema.int(
        description: 'Duration to capture logs in seconds (default: 10).',
      ),
    },
    required: ['vmServiceUri'],
    additionalProperties: false,
  ),
  outputSchema: Schema.object(
    description: 'Captured log entries.',
    additionalProperties: true,
  ),
  annotations: ToolAnnotations(
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
    readOnlyHint: true,
    title: 'Profile Stream Logs',
  ),
);
