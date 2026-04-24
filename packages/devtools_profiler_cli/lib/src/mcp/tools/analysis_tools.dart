import 'package:dart_mcp/server.dart';

final Tool profileExplainHotspotsTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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

final Tool profileInspectMethodTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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

final Tool profileSearchMethodsTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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

final Tool profileCompareMethodTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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
        description: 'Optional direct path to the baseline session directory.',
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

final Tool profileCompareTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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
        description: 'Optional direct path to the baseline session directory.',
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

final Tool profileAnalyzeTrendsTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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

final Tool profileFindRegressionsTool = Tool(
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
        description: 'A direct path to a devtools_profiler sessions directory.',
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
