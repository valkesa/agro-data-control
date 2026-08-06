/// Pure, Firestore-free helpers shared by every structural entity service
/// (`AgroTenantService`, `AgroSiteService`, `AgroSectorService`,
/// `AgroDeviceService`, `AgroDeviceRoomService`) and by
/// `UserManagementService.createTenant`.
///
/// These only validate/normalize already-in-memory values — no I/O. Keeping
/// them here means id normalization, required-field checks, and duplicate-id
/// checks are defined exactly once instead of being reimplemented per
/// service/form (see the audit report
/// `no_git/informes_de_codigo/informe_auditoria_gestion_tenants_sites_devices_2026-08-05.html`
/// for the duplication this replaces).
library;

/// Normalizes a user-entered document ID: lowercase, trims, and collapses
/// anything outside `[a-z0-9_-]` into single dashes (no leading/trailing
/// dash). The single canonical implementation — previously duplicated as
/// `UserManagementService._normalizeDocumentId` and
/// `user_management_page.dart`'s `_normalizePreviewId`.
String normalizeStructuralId(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

/// Trims [value] and throws a `StateError` with a Spanish, user-facing
/// message if the result is empty. Returns the trimmed value otherwise.
String requireNonEmptyField(String value, String fieldLabel) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw StateError('$fieldLabel es requerido.');
  }
  return trimmed;
}

/// Throws a `StateError` if [ids] contains a repeated value once each has
/// already been normalized by the caller (so this only compares, it never
/// normalizes). `entityLabelPlural` feeds the Spanish error message, e.g.
/// `'Los Sector ID'`.
void requireUniqueNormalizedIds(List<String> ids, String entityLabelPlural) {
  if (ids.toSet().length != ids.length) {
    throw StateError('$entityLabelPlural no pueden repetirse.');
  }
}
