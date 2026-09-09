# Changelog

## 0.3.0

- Required Dart 3.13 or later and refreshed test dependencies.

## 0.2.0

- Added `extra` field to `ProfileRegionOptions` for tool-specific metadata.
  Tools like `lualike` can attach arbitrary data (e.g.
  `{'luaFile': 'calls.lua'}`) that persists in session artifacts.
- Updated `copyWith`, `toJson`, and `fromJson` to handle `extra`.

## 0.1.0

- Initial release of the shared profiler protocol models.
- Added capture-kind and isolate-scope contracts for region profiling.
- Added JSON-friendly region option serialization helpers.
