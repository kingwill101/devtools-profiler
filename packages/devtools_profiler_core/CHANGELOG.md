# Changelog

## 0.3.0

- Added inherited-stdio process IO mode for terminal UI and alternate-screen
  profiling targets.
- Added deterministic VM-service discovery for inherited-stdio Dart launches
  and Flutter `run` launches.
- Added optional interrupt signal handling so hosts can finalize available
  diagnostics before stopping an interrupted target.
- Reduced shutdown polling overhead by backing off exit-pause probes and adding
  bounded VM-service request timeouts during final capture.

## 0.2.1

- Added bare Dart file launch support by expanding file paths to
  `dart run <file>`.
- Improved short-lived Dart process profiling by holding isolates at exit long
  enough to capture final whole-session CPU and memory snapshots.

## 0.2.0

- Added memory class artifact inspection helpers for stored session, region, and
  raw memory profile artifacts.
- Added memory class comparison filters for minimum live bytes and class count
  limits.
- Added optional DTD disabling for attach sessions when region markers are not
  needed or the tooling daemon cannot start.
- Normalized artifact output directories to fully resolved paths and kept
  relative paths anchored against the profiled working directory.
- Allowed artifact readers to summarize per-profile artifact directories such
  as `overall/` and `regions/<id>/` in addition to `summary.json` files.
- Improved package detection for local checkout `file://.../<package>/lib/...`
  CPU frames so package filters work outside `.pub-cache`.

## 0.1.0

- Initial release of the pure-Dart profiler backend.
- Added launch and attach flows for Dart and Flutter VM-service targets.
- Added CPU summaries, call trees, method tables, memory summaries, and
  artifact readers.
- Added hotspot, comparison, method inspection, and trend analysis helpers.
