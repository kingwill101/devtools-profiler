/// Region-marking APIs for Dart and Flutter programs profiled by DevTools.
///
/// This library is the app-side entrypoint for explicit profiling regions.
/// Use [profileRegion] to wrap one async operation in a named region, or use
/// [startProfileRegion] when the region lifetime cannot be expressed as a
/// single closure.
///
/// The region helpers only work when the target process was launched by
/// `devtools_profiler` in `run` mode. When no matching profiler session is
/// configured, region helpers throw [ProfileRegionConfigurationException]
/// instead of silently dropping markers.
///
/// ```dart
/// import 'package:devtools_region_profiler/devtools_region_profiler.dart';
///
/// Future<void> warmUp() async {
///   await profileRegion(
///     'startup',
///     attributes: {'phase': 'bootstrap'},
///     () async {
///       await loadConfiguration();
///       await warmCaches();
///     },
///   );
/// }
/// ```
///
/// Regions can be nested. Nested calls inherit the active parent region unless
/// [ProfileRegionOptions.parentRegionId] is set explicitly.
library;

export 'package:devtools_profiler_protocol/devtools_profiler_protocol.dart';

export 'src/profile_region.dart';
