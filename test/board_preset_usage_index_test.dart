import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'firestore.indexes.json cubre el conteo de uso de BoardPreset por Device',
    () {
      final json =
          jsonDecode(File('firestore.indexes.json').readAsStringSync())
              as Map<String, Object?>;
      final overrides = json['fieldOverrides']! as List<Object?>;

      expect(
        overrides,
        contains(
          predicate<Object?>((value) {
            if (value is! Map<String, Object?> ||
                value['collectionGroup'] != 'settings' ||
                value['fieldPath'] != 'sourceBoardPresetId') {
              return false;
            }
            final indexes = value['indexes'];
            return indexes is List<Object?> &&
                indexes.any(
                  (index) =>
                      index is Map<String, Object?> &&
                      index['queryScope'] == 'COLLECTION_GROUP' &&
                      index['order'] == 'ASCENDING',
                );
          }),
        ),
      );
    },
  );
}
