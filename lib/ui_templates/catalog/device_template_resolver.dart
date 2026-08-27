import '../../models/agro_device.dart';
import '../models/device_template.dart';
import 'agro_ui_templates.dart';

class DeviceTemplateResolver {
  const DeviceTemplateResolver();

  static const String roomClimateTemplateId = 'room_climate';
  static const String laboratoryBasicTemplateId = 'laboratory_basic';
  static const String disinfectionArchTemplateId = 'disinfection_arch';
  static const String genePigTenantId = 'the-gene-pig';
  static const String genePigGeneticaSiteId = 'genetica-1';
  static const String genePigLaboratoryDeviceId = 'plc-genetica-laboratorio';
  static const String genePigDisinfectionArchDeviceId =
      'plc-genetica-arcodesinf';

  String? templateIdForLegacyRoom({
    required String? tenantId,
    required String? siteId,
  }) {
    final String tenant = tenantId?.trim() ?? '';
    final String site = siteId?.trim() ?? '';
    if (tenant == genePigTenantId && site == genePigGeneticaSiteId) {
      return roomClimateTemplateId;
    }
    return null;
  }

  String? templateIdForDevice(AgroDevice device) {
    final String? byIdentity = _templateIdForKnownDeviceIdentity(device);
    if (byIdentity != null) {
      return byIdentity;
    }
    return templateIdForDeviceType(device.type);
  }

  DeviceTemplate? templateForDevice(AgroDevice device) {
    final String? templateId = templateIdForDevice(device);
    return templateId == null ? null : templateForId(templateId);
  }

  String? templateIdForDeviceType(String deviceType) {
    return switch (deviceType.trim().toLowerCase()) {
      'environment_single_room' ||
      'environment_multi_room' => roomClimateTemplateId,
      'laboratory_basic' || 'laboratory' => laboratoryBasicTemplateId,
      'disinfection_arch' => disinfectionArchTemplateId,
      _ => null,
    };
  }

  DeviceTemplate? templateForId(String templateId) =>
      getTemplateById(templateId);

  String? _templateIdForKnownDeviceIdentity(AgroDevice device) {
    final String id = device.id.trim().toLowerCase();
    if (id == genePigLaboratoryDeviceId) {
      return laboratoryBasicTemplateId;
    }
    if (id == genePigDisinfectionArchDeviceId) {
      return disinfectionArchTemplateId;
    }
    return null;
  }
}
