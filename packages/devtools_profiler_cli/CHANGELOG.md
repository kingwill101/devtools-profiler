# Changelog

## Unreleased

- Added `inspect-classes` and the `profile_inspect_classes` MCP tool for
  inspecting memory class allocations from stored artifacts.
- Added comparison filters for memory class output, including minimum live bytes
  and memory class count limits.
- Added `attach --skip-dtd` and the matching MCP option for whole-session attach
  profiling when explicit region markers are unavailable.
- Improved CLI and JSON output by surfacing region preparation warnings,
  baseline/current comparison warnings, and sample-count fallback warnings.
- Improved package-filtered output for local checkout frames when used with a
  backend that recognizes local package file paths.

## 0.1.0

- Initial release of the terminal and MCP profiler frontend.
- Added CLI commands for capture, artifact inspection, comparison, and trends.
- Added MCP tools for agent-driven profiling and artifact analysis.
