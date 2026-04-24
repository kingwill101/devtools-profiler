# AGENTS.md

Guidance for AI agents working in this repository.

## Repository Purpose

This is a profiler-focused Dart workspace for CLI-first and agent-first
profiling.

The repository exists to provide:

- a CLI for profiling Dart and Flutter VM-service programs;
- a local stdio MCP server for agent-driven profiling;
- pure-Dart core profiling logic and artifact models;
- a lightweight region-marking package for profiled applications.

Do not add Flutter UI, web UI, or browser-only runtime dependencies to the
profiler packages. The profiler may run `flutter` commands as profiling
targets, but the profiler packages themselves should remain pure Dart unless
the user explicitly changes that direction.

## Workspace Layout

The active packages are:

- `packages/devtools_profiler_protocol`: shared serializable protocol models.
- `packages/devtools_region_profiler`: app-side APIs for marking profile
  regions.
- `packages/devtools_profiler_core`: VM service, DTD, CPU, memory, artifact,
  comparison, hotspot, and trend logic.
- `packages/devtools_profiler_cli`: command-line interface, terminal
  presentation, and MCP server.

Keep new profiler work inside these packages unless a new package is explicitly
requested.

## Dependency Rules

- Use hosted `devtools_shared` for shared VM and memory models; do not vendor
  package trees into this workspace.
- Keep `dart_mcp` on the supported `^0.5.0` line unless the user asks for an
  upgrade.
- Do not introduce dependencies on `devtools_app`, Flutter widgets, web-only
  libraries, or browser APIs.
- `devtools_profiler_core` may depend on `vm_service`, `dtd`, and
  `devtools_shared`.
- `devtools_profiler_cli` may depend on terminal/MCP/presentation packages such
  as `artisanal` and `dart_mcp`.
- `devtools_region_profiler` should stay small and safe to add to Dart or
  Flutter applications being profiled.

## Development Rules

- Prefer small, package-scoped changes.
- Split large CLI commands into focused files instead of growing a monolithic
  command file.
- Preserve agent-facing output quality: summaries should be readable by humans
  and structured enough for LLMs to reason over.
- Keep call tree, bottom-up tree, method table, memory, comparison, hotspot, and
  trend data available through both CLI and MCP paths when adding related
  capabilities.
- When adding profiling behavior, cover both whole-session profiling and
  region-scoped profiling unless there is a clear reason not to.
- For Flutter targets, remember that release mode, AOT builds, and browser/web
  targets do not expose the Dart VM service needed by this profiler.

## Dart Style

- Follow idiomatic Dart and keep code easy to scan in split-screen views.
- Prefer multi-line strings over string concatenation for large text blocks,
  command output fixtures, JSON examples, and terminal snapshots.
- Keep lines near 80 characters where practical. Long identifiers and URLs may
  exceed that when wrapping would make the code harder to read.
- Use records for short-lived grouped return values instead of introducing
  one-off classes.
- Use patterns, `if-case`, and switch expressions when they make parsing or
  dispatch logic clearer.
- Use class modifiers such as `sealed`, `final`, `base`, and `interface` when
  they describe the intended inheritance boundary.
- Use digit separators for large numeric literals, for example timeouts,
  sample counts, and byte sizes.
- Use wildcard variables for intentionally unused callback parameters.
- Use null-aware collection elements when conditionally including nullable
  values in list or map literals.
- Use dot shorthands only when the inferred type is obvious from context.

## Dart Documentation

- Use `///` documentation comments for public APIs.
- Consider documenting private helpers when they encode profiler behavior,
  artifact contracts, protocol semantics, or VM-service assumptions.
- Start doc comments with a short, single-sentence summary.
- Put a blank line after the first sentence when adding more detail.
- Avoid repeating information that is already obvious from the declaration.
- Start method comments with third-person verbs, such as "Returns", "Starts",
  or "Captures".
- Start non-boolean property comments with a noun phrase.
- Start boolean property comments with "Whether".
- Use square brackets for in-scope identifiers, such as [ProfileRunRequest],
  [Duration], and [StateError].
- Explain parameters, return values, and exceptions in prose rather than using
  tag-style documentation.
- Prefer fenced Markdown code blocks for examples in documentation comments.
- Keep Markdown simple; avoid HTML in documentation comments.

## Validation

Run formatting, analysis, and tests before handing work back:

```bash
dart format .
dart analyze .
dart test packages/devtools_profiler_protocol
dart test packages/devtools_region_profiler
dart test packages/devtools_profiler_core
dart test packages/devtools_profiler_cli
```

If the local `dart` wrapper is blocked by environment-specific toolchain
writes, use a direct Dart SDK binary available in the current environment. Use
the same binary for `pub get`, `format`, `analyze`, and `test`.

## Documentation

Keep the root `README.md` end-user focused. Package READMEs should explain how
that package is used and how it fits into the profiler system. Prefer examples
that agents can execute directly from the CLI.
