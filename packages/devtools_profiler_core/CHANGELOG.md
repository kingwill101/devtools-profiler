# Changelog

## Unreleased

- Added memory class artifact inspection helpers for stored session, region, and
  raw memory profile artifacts.
- Added memory class comparison filters for minimum live bytes and class count
  limits.
- Added optional DTD disabling for attach sessions when region markers are not
  needed or the tooling daemon cannot start.
- Normalized relative artifact output directories against the profiled working
  directory.
- Improved package detection for local checkout `file://.../<package>/lib/...`
  CPU frames so package filters work outside `.pub-cache`.

## 0.1.0

- Initial release of the pure-Dart profiler backend.
- Added launch and attach flows for Dart and Flutter VM-service targets.
- Added CPU summaries, call trees, method tables, memory summaries, and
  artifact readers.
- Added hotspot, comparison, method inspection, and trend analysis helpers.
