String readRequiredString(Map<String, Object?> map, String key) {
  final String value = readString(map[key]).trim();
  if (value.isEmpty) {
    throw ArgumentError.value(map[key], key, 'Required non-empty string');
  }
  return value;
}

String readString(Object? value) => value?.toString() ?? '';

int readRequiredInt(Map<String, Object?> map, String key) {
  final Object? value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw ArgumentError.value(value, key, 'Required integer');
}

int readPositiveInt(Map<String, Object?> map, String key) {
  final int value = readRequiredInt(map, key);
  if (value <= 0) {
    throw ArgumentError.value(value, key, 'Must be > 0');
  }
  return value;
}

int readNonNegativeInt(Map<String, Object?> map, String key) {
  final int value = readRequiredInt(map, key);
  if (value < 0) {
    throw ArgumentError.value(value, key, 'Must be >= 0');
  }
  return value;
}

bool readBool(Object? value, {required bool defaultValue}) {
  return value is bool ? value : defaultValue;
}

List<String> readStringList(Object? value) {
  if (value is! Iterable) {
    return const <String>[];
  }
  return List<String>.unmodifiable(
    value
        .map((Object? item) => item?.toString().trim() ?? '')
        .where((String item) => item.isNotEmpty),
  );
}

List<Map<String, Object?>> readMapList(Object? value) {
  if (value is! Iterable) {
    return const <Map<String, Object?>>[];
  }
  return List<Map<String, Object?>>.unmodifiable(
    value.whereType<Map>().map((Map item) => Map<String, Object?>.from(item)),
  );
}

void requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Required non-empty string');
  }
}

void requirePositive(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'Must be > 0');
  }
}

void requireNonNegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'Must be >= 0');
  }
}

void requireSerializableScalar(Object? value, String name) {
  if (value == null || value is bool || value is String) {
    return;
  }
  if (value is num && value.isFinite) {
    return;
  }
  throw ArgumentError.value(
    value,
    name,
    'Must be finite num, bool, String, or null',
  );
}
