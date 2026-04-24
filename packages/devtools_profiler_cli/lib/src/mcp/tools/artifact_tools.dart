import 'package:dart_mcp/server.dart';

final Tool profileSummarizeTool = Tool(
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

final Tool profileReadArtifactTool = Tool(
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

final Tool profileListSessionsTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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

final Tool profileListRegionsTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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

final Tool profileLatestSessionTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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

final Tool profileGetSessionTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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

final Tool profileGetRegionTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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
