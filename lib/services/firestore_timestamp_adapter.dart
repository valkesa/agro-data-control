import 'package:cloud_firestore/cloud_firestore.dart';

/// N7.1 — every N7.x pure model (`LayoutTemplate`, `CellLayoutPreset`,
/// `BoardPreset`, `DeviceBoardLayout`, ...) accepts `createdAt`/`updatedAt`
/// only as a `DateTime` or a canonical UTC ISO-8601 string, by design (see
/// `LayoutTemplate.fromMap`'s doc comment: "A future Firestore adapter must
/// convert SDK Timestamp values at the persistence boundary, outside this
/// model"). A raw Firestore snapshot gives back a `Timestamp` instead — this
/// is that adapter, applied once per repository read, right before handing
/// the map to the model's `fromMap`.
Map<String, Object?> normalizeFirestoreTimestamps(
  Map<String, Object?> raw, {
  required List<String> timestampFields,
}) {
  final Map<String, Object?> result = Map<String, Object?>.from(raw);
  for (final String field in timestampFields) {
    final Object? value = result[field];
    if (value is Timestamp) {
      result[field] = value.toDate().toUtc().toIso8601String();
    }
  }
  return result;
}
