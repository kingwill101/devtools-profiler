# Use The Profiler With Marionette

Use Marionette to drive a Flutter application and DevTools Profiler to measure
the resulting workload. Both connect to the app's Dart VM service, but they
serve different purposes:

- Marionette inspects widgets and invokes UI or custom application actions.
- DevTools Profiler captures CPU, memory, and named regions, then analyzes
  stored artifacts.
- Your application defines when a scenario starts and finishes.

This is a composition guide, not a built-in Marionette integration. The
profiler packages do not depend on Flutter or Marionette.

For a runnable repository example, see the
[Marionette demo](../devtools_profiler_core/test/fixtures/profiled_flutter_app/README.md#marionette--profiler-demo).
It includes a custom action, seeded worker workload, optional region capture,
and a manual UI.

## Prepare The Target App

Follow Marionette's [getting started guide][] and [custom extensions guide][].
Add these dependencies to the Flutter app, not to the profiler:

```bash
flutter pub add marionette_flutter devtools_region_profiler
dart pub global activate marionette_mcp
```

Initialize `MarionetteBinding.ensureInitialized()` in debug mode before
`runApp`, as shown in Marionette's setup instructions. Keep the normal Flutter
binding for other modes. Register custom actions after initializing the binding.

Configure your agent with two separate stdio MCP servers:

```json
{
  "mcpServers": {
    "marionette": {
      "command": "marionette_mcp",
      "args": []
    },
    "profiler": {
      "command": "devtools-profiler",
      "args": ["mcp"]
    }
  }
}
```

Adapt this configuration to your MCP client. Both executables must be installed
and visible on its PATH. You can also use the profiler CLI in another terminal
instead of configuring its MCP server.

## Choose A Capture Workflow

### Existing App: Whole-Session Attach

Start the prepared app in debug mode:

```bash
flutter run --debug -d linux --host-vmservice-port=0
```

Connect Marionette using the VM service URI printed by Flutter. In another
terminal, start a bounded capture using that same app's URI:

```bash
devtools-profiler attach \
  --duration 30s \
  --call-tree --bottom-up --method-table \
  --cwd /path/to/flutter/app \
  http://127.0.0.1:8181/abcd/
```

Replace the example URI with the actual URI, retaining its authentication path.
Once capture is active, use Marionette to perform the scenario. Keep the work
inside the capture window and wait for application-level completion.

Attach does not stop the app. Repeat it for further windows. Each attach clears
the VM's existing CPU samples; do not overlap captures or run another CPU
profiler that clears the same buffer.

**Attach alone does not configure explicit region markers.** It does not inject
the DTD/session configuration into an already-running app. Do not call region
helpers in an ordinary Marionette-only launch: without profiler configuration
they throw `ProfileRegionConfigurationException`.

If your agent cannot issue another tool call while a capture tool is waiting,
run the profiler CLI in a separate terminal/process and drive Marionette from
the agent. Do not assume the client executes MCP calls concurrently.

### Named Regions: Let The Profiler Launch The App

For region-level attribution, launch the app through the profiler:

```bash
devtools-profiler run \
  --duration 2m \
  --vm-service-timeout 5m \
  --call-tree --bottom-up --method-table \
  --cwd /path/to/flutter/app \
  -- flutter run --debug -d linux --host-vmservice-port=0
```

The profiler injects session configuration for region markers. Connect Marionette
to this launched app, rather than launching a second copy or attaching a second
profiler. Use the actual VM service URI; `devtools-profiler discover` can help
find it when multiple tools are involved.

The duration starts after VM service attachment. Allow enough time to connect,
warm up, and finish the scenario: reaching the duration ends the profiling run
and stops the launched target. Desktop is the simplest starting point. On
mobile devices, VM service forwarding does not by itself make the profiler's
local DTD endpoint reachable from the app.

## Wrap A Custom Action In A Region

The following registration snippet belongs in your app's debug setup. It assumes
you implement `runSearchScenario` and launch through the profiler as above.

```dart
import 'package:devtools_region_profiler/devtools_region_profiler.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void registerProfilingScenarios() {
  registerMarionetteExtension(
    name: 'scenarios.search',
    description: 'Runs a repeatable search workload and captures its region.',
    inputSchema: ExtensionInputSchema(
      properties: {
        'seed': ExtensionParam.integer(
          description: 'Seed for deterministic input generation.',
        ),
      },
      required: ['seed'],
    ),
    callback: (params) async {
      // VM service extension parameters arrive as strings.
      final seed = int.tryParse(params['seed'] ?? '');
      if (seed == null) {
        return MarionetteExtensionResult.invalidParams('seed must be an integer');
      }
      await profileRegion(
        'search',
        attributes: {
          'scenario': 'search',
          'scenarioVersion': '1',
          'seed': '$seed',
          'dataset': 'synthetic-v1',
        },
        options: const ProfileRegionOptions(
          isolateScope: ProfileIsolateScope.all,
        ),
        () async {
          await runSearchScenario(seed: seed);
        },
      );
      return MarionetteExtensionResult.success({'completed': true, 'seed': seed});
    },
  );
}
```

Marionette promotes this schema-bearing extension to the `scenarios_search`
tool. Its generic extension caller still uses the original `scenarios.search`
name. Check Marionette's current documentation for schema and naming rules.

Await the actual work, not merely navigation or task scheduling. For worker
isolates, await their results before ending the region. All-isolate scope
captures other isolates during the interval; it does not prove every sampled
operation was caused by this action. Use current-isolate scope when that is the
intended measurement boundary.

For long-running actions that exceed client timeouts, use app-defined start and
status actions with a run ID. Keep the region around the background workload,
not just around the action that enqueues it. Do not let polling start duplicate
workloads.

## Custom Region Data Today And Possible Extensions

Region markers already accept custom `Map<String, String>` attributes. Use small
string values for scenario identity, seeds, input sizes, and feature flags. Keep names
stable across runs and put changing parameters in attributes. Avoid secrets,
user content, and large payloads.

Attributes are metadata, not automatically aggregated performance metrics or
comparison filters. Returning a result from a Marionette action also does not
automatically add that result to profiler artifacts.

Possible future additions, not current APIs:

- Completion-time metrics with explicit units, such as processed items or bytes.
- Timestamped events within a region, such as a cache miss or worker handoff.
- Comparison checks that flag mismatched scenario versions and input parameters.

These would need shared artifact models and matching CLI/MCP analysis support.
Keep action registration in Marionette rather than adding a second action
registry to the lightweight region package.

## Compare Repeatable Runs

1. Reset app state and seed the same dataset before each measured run.
2. Warm up separately; avoid including startup in steady-state comparisons.
3. Execute the same scenario with the same parameters and completion condition.
4. Save the session paths and use `devtools-profiler browse` to select matching
   baseline/current regions, or `devtools-profiler compare --help` for explicit
   session and profile selectors.
5. Repeat measurements. Inspect sample counts, capture warnings, and missing
   frames before interpreting a difference as an improvement.

Example agent instruction:

> Connect Marionette to the profiler-launched app. Reset the synthetic dataset
> and warm up search. Run scenarios_search with seed 42 and wait for completion.
> After capture finishes, compare its search region with the matching baseline.
> Report scenario mismatches and capture warnings alongside any timing changes.

Marionette's documented binding and extension setup is debug-only. Use this
workflow to validate automation, capture, and attribution; debug timings are not
representative release performance. Do not assume Marionette actions remain
available in profile mode. For performance conclusions, reproduce the workload
in a supported profile-mode target with separately verified automation.
Flutter release/AOT and web targets do not expose the VM service this profiler
requires. Keep SDK, device, build mode, and workload parameters consistent.

[getting started guide]: https://github.com/leancodepl/marionette_mcp/blob/main/docs/getting-started.md
[custom extensions guide]: https://github.com/leancodepl/marionette_mcp/blob/main/docs/custom-extensions.md
