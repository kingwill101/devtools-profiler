# Interactive analysis proposal

Status: initial summary browser and shared frame alignment implemented.
The remaining items below are a roadmap, not shipped capabilities.

The first implementation uses the core runtime and Style's cell-aware clipping,
with a vertically stacked list/preview and a scrollable details mode. It
deliberately does not load raw samples, auto-match region names, or introduce a
widget framework. Full filtered analysis is available through the exported
comparison command. Multi-run CLI/MCP analysis rebuilds raw frames when
available and preserves missing observations across output formats.

## Recommendation

Add an explicit `browse` command for stored sessions, using Artisanal's
core TEA runtime. Keep existing one-shot commands as the primary scripting
interface. Do not automatically enter raw mode when a command lacks arguments.

A session browser with a comparison preview is a better first step than a
full live dashboard: it addresses session selection and cross-run investigation
without adding capture lifecycle state to the UI.

## Existing foundations

- `profiles` already discovers sessions and supports compact/extended listings.
- `compare` supports two-run and multi-run comparisons.
- `compare-method`, `trends --last N`, and `regress` provide drill-down and
  regression workflows.
- Shared presentation preparation already supplies CLI and MCP analysis.
- Current terminal rendering uses Artisanal Console tables and definition lists.

Reuse session discovery and prepared analysis; do not parse rendered text or
spawn the CLI recursively from the browser.

## Relevant Artisanal 0.6 capabilities

The installed package's changelog documents:

- Shared command-palette matching, stable item IDs, viewport windows, and
  `CommandPaletteOverlay` / `CommandPaletteComponent`: useful for searchable
  session and action selection.
- `FrameView` and `FrameLayout`: positioned panes with fixed, percentage, and
  weighted-fill sizing; suitable for a session list and comparison preview.
- Focused runtime, layout, style, and charting imports: no need to add the
  widget framework for this small UI.
- Charting primitives, including sparklines and histograms: useful for repeated
  measurements, provided exact values and units remain visible.
- Capability-aware Console operations and corrected non-interactive behavior:
  useful for a static rendering refresh independently of a TUI.

These are available capabilities, not claims that the profiler uses them today.

## First browser slice

1. Discover session summaries without loading every raw CPU artifact.
2. Search by session ID, command, and directory.
3. Select a baseline and current run explicitly; show their roles at all times.
4. Choose whole-session or matching named regions. Region IDs are run-local;
   repeated names require disambiguation, not silent first-match selection.
5. Preview duration, sample count, memory deltas, warnings, and hotspot changes.
6. Offer method inspection and an exact reproducible one-shot command.

Use a two-pane layout on wide terminals and one pane with a details toggle on
narrow terminals. Support keyboard-only navigation, visible key hints,
Escape/back, Ctrl+C/quit, resizing, and terminal restoration after errors.
Refuse non-TTY input/output with an actionable one-shot alternative.
Never consume MCP stdin or emit terminal escapes into JSON/CSV output.

Cache only selected prepared artifacts with a bounded policy. Discard stale
asynchronous results after selection changes; rendering must not perform I/O.

## Comparison correctness before decoration

The old multi-run terminal table keyed frames by display name and labeled
missing entries "eliminated", even though its input was top-frame lists.
This is now corrected through shared core alignment, used by terminal, CSV,
JSON, MCP, and the browser. Exact locations are retained rather than guessing
cross-checkout equivalence.

Recommended semantics:

- Match by canonical function identity including location, not name alone.
  Normalize checkout roots/package versions deliberately and test collisions.
- Distinguish "not in selected top frames", "not sampled", and unavailable data.
  Do not infer zero cost from any of them.
- Compute comparisons from complete filtered data; limit only displayed rows.
- Show percentage-point changes separately from estimated sampled CPU time.
  Neither is elapsed wall time or a direct throughput measurement.
- Warn about different sample periods, capture durations, region scopes,
  filters, SDK/build modes, or incomplete isolate coverage when known.
  Unknown capture metadata must remain unknown, not assumed compatible.
- For repeated benchmarks, group comparable workloads and show sample size,
  median and dispersion before introducing statistical regression claims.
  A fixed capture-window duration is not itself a benchmark performance metric.

New analysis semantics belong in core and must remain accessible via MCP.

## Delivery and validation

1. Shared cross-run comparison correctness with fixtures for truncated top
   lists, same-name functions, missing data, and different capture settings.
2. Static rendering refresh: compact metric header, explicit baseline/current
   labels, units, signed deltas, and bounded terminal widths.
3. Read-only browser reusing those models and renderers.
4. Repeated-run grouping and distribution summaries after capture metadata and
   comparability rules are defined.

Test plain/no-color and Unicode output, narrow and wide layouts, JSON/CSV
isolation, and deterministic keyboard navigation. Exercise a real PTY for
resize, cancellation, interrupted artifact loading, and terminal restoration.
Benchmark discovery with many sessions and memory usage with large CPU
artifacts; do not load all samples just to paint a session list.
