// Etapa B5 — lectura/escritura de `alertConfig/{alertId}` en los 4 niveles
// (tenant/site/device/room), usando los paths de Etapa B4.
//
// PATCH seguro (Etapa B5 §21 / hallazgo de B4.1): la lección de B4.1 fue que
// un PATCH REST sin `updateMask.fieldPaths` reemplaza el documento entero.
// `cloud_firestore` no habla REST crudo, pero tiene su propia trampa
// equivalente, específica de este SDK, que hay que conocer para no
// reintroducir el mismo problema con otra forma:
//
//   `DocumentReference.set(data, SetOptions(merge: true))` con una clave
//   punteada como `'thresholds.max'` NO la interpreta como un field-path
//   anidado — la trata como el nombre LITERAL de un campo top-level (mirar
//   `_CodecUtility.replaceValueWithDelegatesInMap` en el paquete
//   `cloud_firestore`: no convierte strings con puntos a `FieldPath`).
//   Solo `DocumentReference.update(data)` hace esa conversión
//   (`replaceValueWithDelegatesInMapFieldPath`, que sí llama a
//   `FieldPath.fromString` por cada clave). Por eso:
//
//   - Documento NUEVO -> [buildAlertConfigCreatePayload] + `.set(merge: true)`:
//     `thresholds` va como mapa anidado real (sin puntos) porque no hay
//     hermanos previos que preservar.
//   - Documento EXISTENTE -> [buildAlertConfigUpdatePayload] + `.update()`:
//     los campos de `thresholds` van con claves punteadas
//     (`'thresholds.max'`), y "Heredar" un campo suelto usa
//     `FieldValue.delete()` en ESA clave puntual — así una edición de un
//     solo umbral nunca toca a sus hermanos ni al resto del documento.
//
// Auditoría (Etapa B5 §23 / B4.1): `createdAt`/`createdBy` solo se escriben
// en el payload de creación. Un `buildAlertConfigUpdatePayload` jamás los
// incluye — como es un `.update()` real (no un `.set()` con merge), omitir
// una clave dejta el valor guardado intacto, que es la inmutabilidad que
// exige `canUpdateAlertConfig` en `firestore.rules`.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/hierarchical_alert_catalog.dart';
import '../models/hierarchical_alert_config.dart';

class AlertConfigScopeTarget {
  const AlertConfigScopeTarget({
    required this.tenantId,
    required this.scope,
    this.siteId,
    this.deviceId,
    this.roomId,
  });

  final String tenantId;
  final AlertConfigScope scope;
  final String? siteId;
  final String? deviceId;
  final String? roomId;

  String collectionPath() {
    return switch (scope) {
      AlertConfigScope.tenant => FirestorePaths.tenantAlertConfigCollection(
        tenantId,
      ),
      AlertConfigScope.site => FirestorePaths.siteAlertConfigCollection(
        tenantId,
        siteId!,
      ),
      AlertConfigScope.device => FirestorePaths.deviceAlertConfigCollection(
        tenantId,
        deviceId!,
      ),
      AlertConfigScope.room => FirestorePaths.roomAlertConfigCollection(
        tenantId,
        deviceId!,
        roomId!,
      ),
    };
  }
}

/// Payload para un documento que **ya existe** — pensado exclusivamente
/// para `.update()`. Diff puro entre `current` (lo último leído) y
/// `desired` (lo que el usuario dejó armado); devuelve `null` si no hay
/// ningún cambio real que escribir.
Map<String, Object?>? buildAlertConfigUpdatePayload({
  required AlertConfigOverride current,
  required AlertConfigOverride desired,
  required String uid,
}) {
  final Map<String, Object?> payload = <String, Object?>{};

  void diffNullable(String field, Object? currentValue, Object? desiredValue) {
    if (currentValue == desiredValue) return;
    payload[field] = desiredValue ?? FieldValue.delete();
  }

  diffNullable('enabled', current.enabled, desired.enabled);
  diffNullable('visualEnabled', current.visualEnabled, desired.visualEnabled);
  diffNullable(
    'whatsappEnabled',
    current.whatsappEnabled,
    desired.whatsappEnabled,
  );
  diffNullable(
    'whatsappDelayMinutes',
    current.whatsappDelayMinutes,
    desired.whatsappDelayMinutes,
  );
  diffNullable(
    'cooldownMinutes',
    current.cooldownMinutes,
    desired.cooldownMinutes,
  );
  diffNullable('order', current.order, desired.order);

  if (desired.thresholds.isEmpty && !current.thresholds.isEmpty) {
    // Se borraron todos los umbrales de este scope: eliminar el mapa
    // completo en vez de dejar `thresholds: {}` colgando (ver comentario de
    // archivo — un mapa vacío pasaría `hasFunctionalAlertConfigOverride()`
    // en Rules por presencia de clave, no por contenido).
    payload['thresholds'] = FieldValue.delete();
  } else {
    diffNullable(
      'thresholds.min',
      current.thresholds.min,
      desired.thresholds.min,
    );
    diffNullable(
      'thresholds.max',
      current.thresholds.max,
      desired.thresholds.max,
    );
    diffNullable(
      'thresholds.margin',
      current.thresholds.margin,
      desired.thresholds.margin,
    );
    diffNullable(
      'thresholds.sensorFailureMin',
      current.thresholds.sensorFailureMin,
      desired.thresholds.sensorFailureMin,
    );
  }

  if (payload.isEmpty) {
    return null;
  }

  payload['schemaVersion'] = 1;
  payload['updatedAt'] = FieldValue.serverTimestamp();
  payload['updatedBy'] = uid;
  // NUNCA createdAt/createdBy acá — este payload es solo para `.update()`
  // sobre un documento que ya existe.
  return payload;
}

/// Payload para un documento **nuevo** — pensado exclusivamente para
/// `.set(data, SetOptions(merge: true))`. `thresholds` es un mapa anidado
/// real (sin claves punteadas): al ser la primera escritura no hay
/// hermanos previos que preservar, así que no hace falta la semántica de
/// field-path de `.update()`.
Map<String, Object?>? buildAlertConfigCreatePayload({
  required AlertConfigOverride desired,
  required String uid,
}) {
  if (!desired.hasFunctionalOverride) {
    return null;
  }
  return <String, Object?>{
    'schemaVersion': 1,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': uid,
    if (desired.enabled != null) 'enabled': desired.enabled,
    if (desired.visualEnabled != null) 'visualEnabled': desired.visualEnabled,
    if (desired.whatsappEnabled != null)
      'whatsappEnabled': desired.whatsappEnabled,
    if (desired.whatsappDelayMinutes != null)
      'whatsappDelayMinutes': desired.whatsappDelayMinutes,
    if (desired.cooldownMinutes != null)
      'cooldownMinutes': desired.cooldownMinutes,
    if (desired.order != null) 'order': desired.order,
    if (!desired.thresholds.isEmpty)
      'thresholds': desired.thresholds.toFirestoreMap(),
  };
}

class HierarchicalAlertConfigService {
  const HierarchicalAlertConfigService();

  /// Una sola lectura de colección por nivel — nunca un `.get()` por
  /// alertId, nunca un listener (Etapa B5 §33/§34).
  Future<Map<String, AlertConfigOverride>> loadScopeOverrides(
    AlertConfigScopeTarget target,
  ) async {
    final String path = target.collectionPath();
    debugPrint('[HierarchicalAlertConfig] load path=$path');
    final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
        .instance
        .collection(path)
        .get();
    return <String, AlertConfigOverride>{
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs)
        doc.id: AlertConfigOverride.fromRaw(doc.data()),
    };
  }

  /// Guarda el override de una alerta en un scope. Si tras el diff el
  /// documento quedaría sin ningún campo funcional, borra el documento
  /// completo en vez de dejar un doc "vacío" que desplazaría el fallback
  /// legacy (Etapa B5 §22).
  Future<void> saveOverride({
    required AlertConfigScopeTarget target,
    required String alertId,
    required AlertConfigOverride current,
    required AlertConfigOverride desired,
    required bool documentExists,
    required String uid,
  }) async {
    final DocumentReference<Map<String, dynamic>> docRef = FirebaseFirestore
        .instance
        .doc('${target.collectionPath()}/$alertId');

    if (!desired.hasFunctionalOverride) {
      if (documentExists) {
        debugPrint(
          '[HierarchicalAlertConfig] delete empty doc path=${docRef.path}',
        );
        await docRef.delete();
      }
      return;
    }

    if (!documentExists) {
      final Map<String, Object?>? payload = buildAlertConfigCreatePayload(
        desired: desired,
        uid: uid,
      );
      if (payload == null) return;
      debugPrint(
        '[HierarchicalAlertConfig] create path=${docRef.path} fields=${payload.keys}',
      );
      await docRef.set(payload, SetOptions(merge: true));
      return;
    }

    final Map<String, Object?>? payload = buildAlertConfigUpdatePayload(
      current: current,
      desired: desired,
      uid: uid,
    );
    if (payload == null) return;
    debugPrint(
      '[HierarchicalAlertConfig] update path=${docRef.path} fields=${payload.keys}',
    );
    await docRef.update(payload);
  }
}
