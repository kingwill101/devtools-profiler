Map<String, String> castStringMap(Object? value) {
  final raw = value as Map<Object?, Object?>? ?? const {};
  return {
    for (final entry in raw.entries)
      entry.key.toString(): entry.value?.toString() ?? '',
  };
}

List<String>? castNullableStringList(Object? value) {
  final raw = value as List<Object?>?;
  if (raw == null) {
    return null;
  }
  return [for (final entry in raw) entry?.toString() ?? ''];
}

List<String> legacyIsolateIds(String? isolateId) {
  if (isolateId == null || isolateId.isEmpty) {
    return const [];
  }
  return [isolateId];
}

Map<String, Object?> castJsonMap(Map<Object?, Object?> value) {
  return value.map((key, mappedValue) => MapEntry(key.toString(), mappedValue));
}
