// Etapa B5 — lectura/escritura de `alertRecipients/{recipientId}` en los 4
// niveles (tenant/site/device/room), usando los paths de Etapa B4.5. Mismo
// criterio de PATCH seguro que `hierarchical_alert_config_service.dart`:
// siempre `set(merge: true)`, nunca reenvío de `createdBy`/`createdAt` en
// una edición.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firestore_paths.dart';
import '../models/hierarchical_alert_catalog.dart';
import '../models/hierarchical_alert_recipient.dart';

class AlertRecipientScopeTarget {
  const AlertRecipientScopeTarget({
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
      AlertConfigScope.tenant => FirestorePaths.tenantAlertRecipientsCollection(
        tenantId,
      ),
      AlertConfigScope.site => FirestorePaths.siteAlertRecipientsCollection(
        tenantId,
        siteId!,
      ),
      AlertConfigScope.device => FirestorePaths.deviceAlertRecipientsCollection(
        tenantId,
        deviceId!,
      ),
      AlertConfigScope.room => FirestorePaths.roomAlertRecipientsCollection(
        tenantId,
        deviceId!,
        roomId!,
      ),
    };
  }
}

class HierarchicalAlertRecipientsService {
  const HierarchicalAlertRecipientsService();

  /// Una sola lectura de colección por nivel — nunca un listener por
  /// recipient (Etapa B5 §33/§34).
  Future<List<AlertRecipientOverride>> loadScopeRecipients(
    AlertRecipientScopeTarget target,
  ) async {
    final String path = target.collectionPath();
    debugPrint('[HierarchicalAlertRecipients] load path=$path');
    final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
        .instance
        .collection(path)
        .get();
    return List<AlertRecipientOverride>.unmodifiable(
      snap.docs.map(
        (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
            AlertRecipientOverride.fromRaw(doc.id, doc.data()),
      ),
    );
  }

  /// Crea un recipient nuevo en el scope actual. El llamador es responsable
  /// de chequear duplicados heredados antes (`findInheritedConflict`) — este
  /// método no lo hace, para mantenerlo puro respecto a Firestore.
  Future<void> addRecipient({
    required AlertRecipientScopeTarget target,
    required String recipientId,
    required String displayName,
    required String phoneE164,
    required bool enabled,
    required String uid,
  }) async {
    final String docPath = '${target.collectionPath()}/$recipientId';
    final Map<String, Object?> payload = <String, Object?>{
      'schemaVersion': 1,
      'displayName': displayName.trim(),
      'phoneE164': normalizeAlertRecipientPhoneE164(phoneE164),
      'enabled': enabled,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    };
    debugPrint('[HierarchicalAlertRecipients] create path=$docPath');
    await FirebaseFirestore.instance
        .doc(docPath)
        .set(payload, SetOptions(merge: true));
  }

  /// Edita nombre/teléfono/activo de un recipient propio del scope. Nunca
  /// reenvía `createdAt`/`createdBy` — quedan intactos por `merge: true`.
  Future<void> updateRecipient({
    required AlertRecipientScopeTarget target,
    required String recipientId,
    String? displayName,
    String? phoneE164,
    bool? enabled,
    required String uid,
  }) async {
    final String docPath = '${target.collectionPath()}/$recipientId';
    final Map<String, Object?> payload = <String, Object?>{
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
      if (displayName != null) 'displayName': displayName.trim(),
      if (phoneE164 != null)
        'phoneE164': normalizeAlertRecipientPhoneE164(phoneE164),
      'enabled': ?enabled,
    };
    debugPrint('[HierarchicalAlertRecipients] update path=$docPath');
    await FirebaseFirestore.instance
        .doc(docPath)
        .set(payload, SetOptions(merge: true));
  }

  /// Deshabilitar (Etapa B5 §30): acción normal, reversible — no borra el
  /// documento, solo `enabled=false`.
  Future<void> setEnabled({
    required AlertRecipientScopeTarget target,
    required String recipientId,
    required bool enabled,
    required String uid,
  }) {
    return updateRecipient(
      target: target,
      recipientId: recipientId,
      enabled: enabled,
      uid: uid,
    );
  }

  /// Eliminar (Etapa B5 §30): acción secundaria/administrativa, irreversible
  /// — borra el documento completo. El llamador debe garantizar que
  /// `recipientId` pertenece al scope actual (nunca a uno heredado).
  Future<void> deleteRecipient({
    required AlertRecipientScopeTarget target,
    required String recipientId,
  }) async {
    final String docPath = '${target.collectionPath()}/$recipientId';
    debugPrint('[HierarchicalAlertRecipients] delete path=$docPath');
    await FirebaseFirestore.instance.doc(docPath).delete();
  }
}
