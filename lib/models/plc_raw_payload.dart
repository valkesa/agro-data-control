class PlcRawPayload {
  const PlcRawPayload(this.data);

  final Map<String, dynamic> data;

  Object? resolvePath(List<String> path) {
    Object? current = data;

    for (final segment in path) {
      if (current is Map<String, dynamic>) {
        current = current[segment];
        continue;
      }

      if (current is List) {
        final int? index = int.tryParse(segment);
        if (index == null || index < 0 || index >= current.length) {
          return null;
        }
        current = current[index];
        continue;
      }

      return null;
    }

    return current;
  }

  Object? firstValue(List<List<String>> paths) {
    for (final path in paths) {
      final Object? value = resolvePath(path);
      if (value != null) {
        return value;
      }
    }

    return null;
  }
}
