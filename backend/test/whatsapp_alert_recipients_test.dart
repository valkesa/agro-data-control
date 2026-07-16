import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/whatsapp_alert_recipients.dart';

void main() {
  _expect(
    maskWhatsAppPhone('5491138267368') == '+54 9 11 **** 7368',
    'masks valid Argentinian number',
  );
  _expect(
    maskWhatsAppPhone('+54 9 11 3826 7368') == '+54 9 11 **** 7368',
    'masks Argentinian number with symbols',
  );
  _expect(maskWhatsAppPhone('123') == '********', 'masks short number');
  _expect(maskWhatsAppPhone('') == '********', 'masks empty value');
  _expect(maskWhatsAppPhone('abc') == '********', 'masks invalid value');
  _expect(
    maskWhatsAppPhone('PENDING_PHONE') == '********',
    'does not expose placeholder phone',
  );
  _expect(
    maskWhatsAppPhone('123456789') == '********6789',
    'masks unrecognized number generically',
  );

  const AlertRecipient configured = AlertRecipient(
    scope: AlertRecipientScope.tenantSite,
    tenantId: 'the_good_pig',
    siteId: 'main_site',
    clientName: 'The Good Pig',
    siteName: 'Sitio principal',
    contactName: 'Gerardo',
    phone: '5491138267368',
  );
  _expect(configured.isConfigured, 'accepts configured recipient');

  const AlertRecipient global = AlertRecipient(
    scope: AlertRecipientScope.global,
    contactName: 'Gerardo',
    phone: '5491138267368',
  );
  _expect(global.isConfigured, 'accepts configured global recipient');
  _expect(
    global.displayClientName == 'Valke' &&
        global.displaySiteName == 'Todos los sitios',
    'uses global display names',
  );

  const AlertRecipient placeholder = AlertRecipient(
    scope: AlertRecipientScope.tenantSite,
    tenantId: 'PENDING_TENANT_ID',
    siteId: 'PENDING_SITE_ID',
    clientName: 'Pendiente',
    siteName: 'Pendiente',
    contactName: 'Pendiente',
    phone: 'PENDING_PHONE',
  );
  _expect(!placeholder.isConfigured, 'rejects placeholder recipient');
  const AlertRecipient phonePlaceholder = AlertRecipient(
    scope: AlertRecipientScope.global,
    contactName: 'Nombre Hermano',
    phone: '54911XXXXXXXX',
  );
  _expect(
    !phonePlaceholder.isConfigured,
    'rejects phone placeholder recipient',
  );

  final List<AlertRecipient> deduplicated =
      deduplicateAlertRecipients(<AlertRecipient>[
        global,
        configured,
        const AlertRecipient(
          scope: AlertRecipientScope.global,
          contactName: 'Otro formato',
          phone: '+54 9 11 3826 7368',
        ),
      ]);
  _expect(
    deduplicated.length == 1,
    'deduplicates recipients by normalized phone',
  );

  const WhatsAppAlertRecipientsConfig config = WhatsAppAlertRecipientsConfig();
  final List<AlertRecipient> validRecipients = config.recipientsFor(
    tenantId: 'the_good_pig',
    siteId: 'main_site',
  );
  _expect(validRecipients.length == 2, 'returns configured recipients deduped');
  _expect(
    validRecipients.first.scope == AlertRecipientScope.global,
    'keeps global recipient when duplicated with tenant/site recipient',
  );
  _expect(
    config
            .recipientsFor(tenantId: 'other_tenant', siteId: 'other_site')
            .length ==
        2,
    'returns global recipients for any tenant/site',
  );
  _expect(
    config
            .recipientsFor(
              tenantId: 'PENDING_TENANT_ID',
              siteId: 'PENDING_SITE_ID',
            )
            .length ==
        2,
    'exposes only global recipients for placeholder tenant/site',
  );
  _expect(
    config.globalRecipients().length == 2,
    'returns configured global recipients directly',
  );
  _expect(
    config
            .siteRecipientsFor(tenantId: 'the_good_pig', siteId: 'main_site')
            .length ==
        1,
    'returns configured site recipients without global recipients',
  );

  final Map<String, Object?> ownerWithoutTenant =
      buildWhatsAppAlertRecipientsResponse(
        recipientsConfig: config,
        runtimeControl: const <String, Object?>{'cooldownMinutes': 60},
        role: 'owner',
        userTenantId: null,
        queryTenantId: null,
        querySiteId: null,
      );
  _expect(ownerWithoutTenant['ok'] == true, 'owner without tenant succeeds');
  _expect(
    ownerWithoutTenant['runtimeControl'] is Map,
    'owner without tenant receives runtime control',
  );
  _expect(
    (ownerWithoutTenant['globalRecipients'] as List).length == 2 &&
        (ownerWithoutTenant['siteRecipients'] as List).isEmpty &&
        (ownerWithoutTenant['recipients'] as List).length == 2,
    'owner without tenant receives global recipients only',
  );

  final Map<String, Object?> ownerWithTenant =
      buildWhatsAppAlertRecipientsResponse(
        recipientsConfig: config,
        runtimeControl: const <String, Object?>{'cooldownMinutes': 60},
        role: 'owner',
        userTenantId: null,
        queryTenantId: 'the_good_pig',
        querySiteId: 'main_site',
      );
  _expect(
    (ownerWithTenant['globalRecipients'] as List).length == 2 &&
        (ownerWithTenant['siteRecipients'] as List).length == 1 &&
        ownerWithTenant['recipientCount'] == 2,
    'owner with tenant/site receives global and site recipients deduped',
  );

  final Map<String, Object?> tenantAdmin = buildWhatsAppAlertRecipientsResponse(
    recipientsConfig: config,
    runtimeControl: const <String, Object?>{'cooldownMinutes': 60},
    role: 'tenant_admin',
    userTenantId: 'the_good_pig',
    queryTenantId: 'other_tenant',
    querySiteId: 'main_site',
  );
  _expect(
    (tenantAdmin['siteRecipients'] as List).length == 1,
    'tenant_admin uses authenticated tenant and ignores query tenant',
  );

  final Map<String, Object?> tenantAdminWithoutSite =
      buildWhatsAppAlertRecipientsResponse(
        recipientsConfig: config,
        runtimeControl: const <String, Object?>{'cooldownMinutes': 60},
        role: 'tenant_admin',
        userTenantId: 'the_good_pig',
        queryTenantId: 'the_good_pig',
        querySiteId: null,
      );
  _expect(
    (tenantAdminWithoutSite['siteRecipients'] as List).isEmpty &&
        tenantAdminWithoutSite['ok'] == true,
    'missing siteRecipients does not fail the response',
  );

  _expect(
    alertPriorityOrder.length == 8 &&
        alertPriorityOrder[0] == AlertType.muntersDoorOpen &&
        alertPriorityOrder[1] == AlertType.roomDoorOpen &&
        alertPriorityOrder[2] == AlertType.temperatureInterior &&
        alertPriorityOrder[3] == AlertType.highTemperatureHeatingActive &&
        alertPriorityOrder[4] == AlertType.lowTemperatureHumidifierActive &&
        alertPriorityOrder[5] == AlertType.highDifferentialPressure &&
        alertPriorityOrder[6] == AlertType.highHumidity &&
        alertPriorityOrder[7] == AlertType.dewPointRisk,
    'keeps expected alert priority order',
  );
  _expect(
    alertPriorityOrder.toSet().length == alertPriorityOrder.length,
    'keeps alert priority order without duplicates',
  );
  _expect(
    AlertType.muntersDoorOpen.id == 'munters_door_open' &&
        AlertType.roomDoorOpen.id == 'room_door_open' &&
        AlertType.temperatureInterior.id == 'temperature_interior' &&
        AlertType.highTemperatureHeatingActive.id ==
            'high_temperature_heating_active' &&
        AlertType.lowTemperatureHumidifierActive.id ==
            'low_temperature_humidifier_active' &&
        AlertType.highDifferentialPressure.id == 'high_differential_pressure' &&
        AlertType.highHumidity.id == 'high_humidity' &&
        AlertType.dewPointRisk.id == 'dew_point_risk',
    'keeps stable alert ids',
  );
  _expect(
    alertPriorityIndex(AlertType.muntersDoorOpen) == 0 &&
        alertPriorityIndex(AlertType.highDifferentialPressure) == 5 &&
        alertPriorityIndex(AlertType.dewPointRisk) == 7,
    'keeps stable alert priority indexes',
  );
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
