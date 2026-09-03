import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('firestore.indexes.json cubre las consultas de room_wash_events', () {
    final Map<String, Object?> json =
        jsonDecode(File('firestore.indexes.json').readAsStringSync())
            as Map<String, Object?>;
    final List<Object?> indexes = json['indexes']! as List<Object?>;

    expect(
      indexes,
      contains(
        _roomWashIndex(<String>['tenantId:ASCENDING', 'washedAt:ASCENDING']),
      ),
    );
    expect(
      indexes,
      contains(
        _roomWashIndex(<String>[
          'tenantId:ASCENDING',
          'roomId:ASCENDING',
          'washedAt:ASCENDING',
        ]),
      ),
    );
    expect(
      indexes,
      contains(
        _roomWashIndex(<String>[
          'tenantId:ASCENDING',
          'roomNumber:ASCENDING',
          'washedAt:DESCENDING',
        ]),
      ),
    );
  });
}

Matcher _roomWashIndex(List<String> fields) {
  return predicate<Object?>((Object? value) {
    if (value is! Map<String, Object?>) return false;
    if (value['collectionGroup'] != 'room_wash_events') return false;
    if (value['queryScope'] != 'COLLECTION') return false;
    final Object? rawFields = value['fields'];
    if (rawFields is! List<Object?> || rawFields.length != fields.length) {
      return false;
    }
    for (int i = 0; i < fields.length; i++) {
      final Object? rawField = rawFields[i];
      if (rawField is! Map<String, Object?>) return false;
      final List<String> expected = fields[i].split(':');
      if (rawField['fieldPath'] != expected[0]) return false;
      if (rawField['order'] != expected[1]) return false;
    }
    return true;
  });
}
