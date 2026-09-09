# CPU view benchmark

From the workspace root:

```bash
dart run packages/devtools_profiler_core/benchmark/cpu_views_benchmark.dart
```

The benchmark compares:

- **independent**: build each of the three views from raw samples;
- **shared**: build the complete top-down tree once, then derive bottom-up and
  method-table views from it, as CLI/MCP presentation does.

Each case contains 20,000 samples, 128 functions, and either 8 or 32 frames per
sample. Each mode gets three warm-up iterations and seven measured iterations.
Output is JSON Lines containing median microseconds and a checksum of the
complete serialized views. Checksums should match between modes at each depth.
Serialization is outside the timed section. No timing threshold is asserted in
unit tests.

## Local migration measurement

On Linux x64 with Dart 3.13.1 in JIT mode:

| Stack depth | Before this optimization | Updated independent builds | Updated shared build |
| --- | ---: | ---: | ---: |
| 8 | 441 ms | 296 ms | 80 ms |
| 32 | 1,885 ms | 882 ms | 403 ms |

The "before" column used a saved copy of the CPU sources from immediately
before the frame-cache/shared-tree changes, with the same benchmark and
dependencies. All three paths produced matching checksums for each input.
The updated independent path includes frame caching but still builds the
top-down paths three times. Sharing eliminates those repeated builds.

These are synthetic, local measurements, not end-to-end profiling speedups.
They exclude VM collection, artifact IO, JSON encoding, and terminal rendering.
The cases emphasize repeated function metadata and shared paths; profiles with
many distinct stacks, different filters, or more functions may behave
differently. Use a production artifact and measure peak memory as well as
elapsed time before drawing conclusions about a particular workload.
