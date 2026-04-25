import 'package:dart_mcp/server.dart';

final Tool profileRunTool = Tool(
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
        description: 'Whether to hide common profiler/runtime helper packages.',
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

final Tool profileAttachTool = Tool(
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
      'skipDtd': Schema.bool(
        description:
            'Skip the Dart Tooling Daemon for this attach session. '
            'Explicit region markers will be unavailable. '
            'Use this when the tooling daemon fails to start or is not needed.',
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
        description: 'Whether to hide common profiler/runtime helper packages.',
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
