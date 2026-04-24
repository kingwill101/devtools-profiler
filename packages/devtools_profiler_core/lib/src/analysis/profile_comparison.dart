/// Structured profile comparison models and helpers.
///
/// This library compares two prepared profile regions or whole-session
/// summaries and derives stable deltas for CPU, method, and memory signals. It
/// also builds prioritized regression summaries that higher layers can present
/// directly to humans or agents.
///
/// The primary entrypoints are [compareProfileRegions] and
/// [summarizeProfileRegressions].
library;

export 'profile_comparison_models.dart';
export 'profile_region_comparison.dart';
export 'profile_regression_summary.dart';
