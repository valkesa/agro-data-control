import 'layout_validation_issue.dart';

abstract final class BoardParsing {
  static Never fail(
    String code,
    String message, {
    String? itemId,
    String? metricKey,
  }) {
    throw LayoutValidationException(
      LayoutValidationIssue(
        code: code,
        message: message,
        itemId: itemId,
        metricKey: metricKey,
      ),
    );
  }

  static void fields(Map<String, Object?> map, Set<String> allowed) {
    for (final field in map.keys) {
      if (!allowed.contains(field)) {
        fail('unknown_field', 'Unknown N3 field: $field');
      }
    }
  }

  static String string(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      fail('invalid_string', 'Invalid $field');
    }
    return value;
  }

  static int integer(Object? value, String field) {
    if (value is! int) fail('invalid_integer', 'Expected integer $field');
    return value;
  }

  static bool boolean(Object? value, String field) {
    if (value is! bool) fail('invalid_boolean', 'Expected boolean $field');
    return value;
  }

  static List<Object?> list(Object? value, String field) {
    if (value is! List) fail('invalid_list', 'Expected list $field');
    return List<Object?>.from(value);
  }

  static Map<String, Object?> map(Object? value, String field) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      fail('invalid_map', 'Expected map $field');
    }
    return Map<String, Object?>.from(value);
  }

  static DateTime? date(Object? value, String field) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      final date = DateTime.tryParse(value);
      if (date != null && date.isUtc && date.toIso8601String() == value) {
        return date;
      }
    }
    fail(
      'invalid_date',
      'Expected canonical UTC ISO-8601 or DateTime for $field',
    );
  }
}
