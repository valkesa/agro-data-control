import '../models/agro_device.dart';
import '../models/agro_sector.dart';
import '../models/agro_site.dart';

/// Pure, dependency-free validation helpers for the Site/Sector/Device
/// hierarchy. These only compare already-loaded model instances — no
/// Firestore access here — so they're cheap to call from UI/service code
/// and trivial to unit test.
///
/// Structural rules (see AGRODATA new schema spec):
///   Sector -> belongs to exactly one Site
///   Device -> belongs to exactly one Site
///   Device -> may handle variables from several Sectors, as long as every
///             one of those Sectors belongs to the same Site as the Device
///   Device -> must never reference a Sector/Site from another tenant
///
/// Variables are not modeled yet; this helper is prepared for the future
/// rule `variable.siteId == device.siteId == sector.siteId`.

/// A Sector belongs to the given tenant.
bool sectorBelongsToTenant({
  required AgroSector sector,
  required String tenantId,
}) => sector.tenantId == tenantId;

/// A Device belongs to the given tenant.
bool deviceBelongsToTenant({
  required AgroDevice device,
  required String tenantId,
}) => device.tenantId == tenantId;

/// A Sector belongs to the given Site (same tenant AND same site id).
bool sectorBelongsToSite({
  required AgroSector sector,
  required AgroSite site,
}) => sector.tenantId == site.tenantId && sector.siteId == site.id;

/// A Device belongs to the given Site (same tenant AND same site id).
bool deviceBelongsToSite({
  required AgroDevice device,
  required AgroSite site,
}) => device.tenantId == site.tenantId && device.siteId == site.id;

/// Future rule: a Device can only handle variables from Sectors that
/// belong to the same Site as the Device itself. Not used yet (variables
/// aren't modeled), but kept ready for when that layer is implemented.
bool deviceAndSectorBelongToSameSite({
  required AgroDevice device,
  required AgroSector sector,
}) {
  return device.tenantId == sector.tenantId && device.siteId == sector.siteId;
}
