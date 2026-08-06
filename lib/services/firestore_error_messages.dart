import 'package:cloud_firestore/cloud_firestore.dart';

/// Turns a Firestore failure into a specific, user-facing Spanish message
/// instead of a raw exception `toString()`. Pure — no I/O, easy to unit
/// test independent of Firestore.
///
/// Used by administrative screens (`TenantManagementPage` and friends) that
/// need to tell an owner "this is genuinely empty" apart from "your read
/// was denied", "Firestore is unavailable", or "you tried to create
/// something that already exists" — see
/// `AgroTenantService.listTenantsForAdministration`'s doc comment for why
/// those list methods rethrow instead of swallowing errors into an empty
/// list, which is what makes reaching this classifier possible at all.
String describeFirestoreError(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'No tenés permisos para esta operación.';
      case 'unavailable':
        return 'Firestore no está disponible en este momento. Probá de nuevo en unos segundos.';
      case 'already-exists':
        return 'Ya existe un documento con ese ID.';
      case 'failed-precondition':
        return 'La operación no se pudo completar porque los datos cambiaron '
            'mientras tanto. Actualizá e intentá de nuevo.';
      case 'not-found':
        return 'El documento ya no existe.';
      case 'deadline-exceeded':
        return 'La operación tardó demasiado y se canceló. Probá de nuevo.';
      case 'unauthenticated':
        return 'Tu sesión expiró. Volvé a iniciar sesión.';
      default:
        return 'Error de Firestore (${error.code}): ${error.message ?? error.code}';
    }
  }
  // A StateError from a service's own pre-write validation (e.g. "Ya existe
  // un site con ese ID.") already carries a specific, user-facing Spanish
  // message as `error.message` — surface it directly instead of wrapping it.
  if (error is StateError) {
    return error.message;
  }
  return error.toString();
}
