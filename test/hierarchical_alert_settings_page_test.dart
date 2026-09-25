// Widget tests for HierarchicalAlertSettingsPage (Etapa B5). No Firebase is
// initialized — every service the page depends on is a fake subclass that
// overrides the Firestore-touching methods, following the same
// "inject a service, default it to the real one" pattern already used by
// TenantManagementPage.

import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/models/agro_device_room.dart';
import 'package:agro_data_control/models/agro_site.dart';
import 'package:agro_data_control/models/agro_tenant.dart';
import 'package:agro_data_control/models/hierarchical_alert_catalog.dart';
import 'package:agro_data_control/models/hierarchical_alert_config.dart';
import 'package:agro_data_control/models/hierarchical_alert_recipient.dart';
import 'package:agro_data_control/pages/alerts/hierarchical_alert_settings_page.dart';
import 'package:agro_data_control/pages/alerts/widgets/alert_config_table.dart';
import 'package:agro_data_control/services/agro_device_room_service.dart';
import 'package:agro_data_control/services/agro_device_service.dart';
import 'package:agro_data_control/services/agro_site_service.dart';
import 'package:agro_data_control/services/agro_tenant_service.dart';
import 'package:agro_data_control/services/control_dashboard_config_service.dart';
import 'package:agro_data_control/services/hierarchical_alert_config_service.dart';
import 'package:agro_data_control/services/hierarchical_alert_recipients_service.dart';
import 'package:agro_data_control/services/user_management_service.dart';
import 'package:agro_data_control/services/whatsapp_alert_recipients_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAgroSiteService extends AgroSiteService {
  const _FakeAgroSiteService();

  @override
  Future<List<AgroSite>> listByTenant(String tenantId) async {
    return [
      AgroSite.fromFirestore(
        'las-heras',
        tenantId: tenantId,
        data: {'name': 'Las Heras'},
      ),
    ];
  }
}

/// Distingue Sites por tenant real — necesario para probar que un cambio
/// de Tenant (owner) efectivamente recarga la cadena en vez de conservar
/// datos del tenant anterior (Etapa B5.1 §4).
class _FakeMultiTenantSiteService extends AgroSiteService {
  const _FakeMultiTenantSiteService();

  @override
  Future<List<AgroSite>> listByTenant(String tenantId) async {
    if (tenantId == 'the-gene-pig') {
      return [
        AgroSite.fromFirestore(
          'las-heras',
          tenantId: tenantId,
          data: {'name': 'Las Heras'},
        ),
      ];
    }
    return [
      AgroSite.fromFirestore(
        'roque-perez',
        tenantId: tenantId,
        data: {'name': 'Roque Pérez'},
      ),
    ];
  }
}

class _FakeAgroTenantService extends AgroTenantService {
  const _FakeAgroTenantService();

  @override
  Future<List<AgroTenant>> listTenantsForAdministration() async {
    return [
      AgroTenant.fromFirestore('the-gene-pig', {
        'name': 'The Gene Pig',
        'active': true,
        'createdByUid': 'owner-uid',
      }),
      AgroTenant.fromFirestore('la-payana', {
        'name': 'La Payana',
        'active': true,
        'createdByUid': 'owner-uid',
      }),
    ];
  }
}

class _FakeAgroDeviceService extends AgroDeviceService {
  const _FakeAgroDeviceService();

  @override
  Future<List<AgroDevice>> listBySite({
    required String tenantId,
    required String siteId,
    bool includeDisabled = false,
  }) async {
    return [
      AgroDevice.fromFirestore(
        'laboratorio',
        tenantId: tenantId,
        data: {'name': 'Laboratorio', 'siteId': siteId, 'enabled': true},
      ),
    ];
  }

  @override
  Future<List<AgroDevice>> listByTenant(String tenantId) async {
    return [
      AgroDevice.fromFirestore(
        'laboratorio',
        tenantId: tenantId,
        data: {'name': 'Laboratorio', 'siteId': 'las-heras', 'enabled': true},
      ),
    ];
  }
}

class _FakeAgroDeviceRoomService extends AgroDeviceRoomService {
  const _FakeAgroDeviceRoomService();

  @override
  Future<List<AgroDeviceRoom>> listByDevice({
    required String tenantId,
    required String deviceId,
    bool includeDisabled = false,
  }) async {
    return const <AgroDeviceRoom>[]; // Laboratorio no tiene Rooms explícitas.
  }
}

class _FakeHierarchicalAlertConfigService
    extends HierarchicalAlertConfigService {
  const _FakeHierarchicalAlertConfigService();

  @override
  Future<Map<String, AlertConfigOverride>> loadScopeOverrides(
    AlertConfigScopeTarget target,
  ) async {
    if (target.scope == AlertConfigScope.tenant) {
      return {
        'temperature_interior': const AlertConfigOverride(
          enabled: true,
          thresholds: AlertThresholds(min: 20, max: 30),
        ),
      };
    }
    return const {};
  }
}

/// Define un `order` a nivel Tenant para `dew_point_risk` (catálogo real =
/// 9) — usado para probar que un override de un nivel gana sobre el order
/// real del catálogo (Etapa B5.1 §10/§18), visible desde un scope más
/// específico (Site) que no define su propio `order`.
class _FakeOrderOverrideConfigService extends HierarchicalAlertConfigService {
  const _FakeOrderOverrideConfigService();

  @override
  Future<Map<String, AlertConfigOverride>> loadScopeOverrides(
    AlertConfigScopeTarget target,
  ) async {
    if (target.scope == AlertConfigScope.tenant) {
      return {'dew_point_risk': const AlertConfigOverride(order: 2)};
    }
    return const {};
  }
}

class _FakeHierarchicalAlertRecipientsService
    extends HierarchicalAlertRecipientsService {
  const _FakeHierarchicalAlertRecipientsService();

  @override
  Future<List<AlertRecipientOverride>> loadScopeRecipients(
    AlertRecipientScopeTarget target,
  ) async {
    return const <AlertRecipientOverride>[];
  }
}

/// Fixture realista para la tabla resumen (pedido 2026-09-10): Nicolás en
/// Tenant, Enzo/Mauro en el device Laboratorio — mismo escenario real de
/// The Gene Pig / Las Heras usado en toda la Etapa B6.
class _FakeSummaryRecipientsService extends HierarchicalAlertRecipientsService {
  const _FakeSummaryRecipientsService();

  @override
  Future<List<AlertRecipientOverride>> loadScopeRecipients(
    AlertRecipientScopeTarget target,
  ) async {
    if (target.scope == AlertConfigScope.tenant) {
      return const <AlertRecipientOverride>[
        AlertRecipientOverride(
          id: 'nicolas-rivas',
          displayName: 'Nicolás Rivas',
          phoneE164: '+5491169384562',
          enabled: true,
        ),
      ];
    }
    if (target.scope == AlertConfigScope.device &&
        target.deviceId == 'laboratorio') {
      return const <AlertRecipientOverride>[
        AlertRecipientOverride(
          id: 'enzo',
          displayName: 'Enzo',
          phoneE164: '+5491123040959',
          enabled: true,
        ),
        AlertRecipientOverride(
          id: 'mauro',
          displayName: 'Mauro',
          phoneE164: '+5492227516703',
          enabled: true,
        ),
      ];
    }
    return const <AlertRecipientOverride>[];
  }
}

class _FakeGlobalLegacyRecipientsService
    extends WhatsAppAlertRecipientsService {
  const _FakeGlobalLegacyRecipientsService();

  @override
  Future<WhatsAppAlertRecipientsResult> fetchRecipients({
    required String siteId,
  }) async {
    return const WhatsAppAlertRecipientsResult.success(
      enabled: true,
      recipientCount: 2,
      recipients: <WhatsAppAlertRecipient>[],
      globalRecipients: <WhatsAppAlertRecipient>[
        WhatsAppAlertRecipient(
          clientName: '',
          siteName: '',
          contactName: 'Gerardo',
          phoneMasked: '+54 9 11 **** 7368',
        ),
        WhatsAppAlertRecipient(
          clientName: '',
          siteName: '',
          contactName: 'Demián',
          phoneMasked: '+54 9 11 **** 0079',
        ),
      ],
    );
  }
}

class _FakeControlDashboardConfigService extends ControlDashboardConfigService {
  const _FakeControlDashboardConfigService();

  @override
  Future<ControlDashboardConfigResult> readConfig({
    required String tenantId,
    required String siteId,
  }) async {
    return ControlDashboardConfigResult.notFound(path: 'fake/path');
  }
}

class _FakeWhatsAppAlertRecipientsService
    extends WhatsAppAlertRecipientsService {
  const _FakeWhatsAppAlertRecipientsService();

  @override
  Future<WhatsAppAlertRecipientsResult> fetchRecipients({
    required String siteId,
  }) async {
    return const WhatsAppAlertRecipientsResult.error('sin backend en test');
  }
}

/// A diferencia del fake de arriba, simula que el backend legacy SÍ
/// devuelve destinatarios activos — usado para probar el banner de
/// advertencia (Etapa B5.1 §15-17).
class _FakeLegacyRecipientsPresentService
    extends WhatsAppAlertRecipientsService {
  const _FakeLegacyRecipientsPresentService();

  @override
  Future<WhatsAppAlertRecipientsResult> fetchRecipients({
    required String siteId,
  }) async {
    return const WhatsAppAlertRecipientsResult.success(
      enabled: true,
      recipientCount: 2,
      recipients: <WhatsAppAlertRecipient>[],
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets(
    'selector cascada Tenant(fijo)->Site->Device y breadcrumb (Etapa B5 §2/§3)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'admin-a',
            userRole: UserAppRole.tenantAdmin,
            initialTenantId: 'the-gene-pig',
            editableTenantId: 'the-gene-pig',
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeWhatsAppAlertRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tenant_admin no ve un dropdown de Tenant (fijo a su propio tenant).
      expect(find.text('the-gene-pig'), findsOneWidget);
      // No hay Site seleccionada todavía -> scope = Tenant, se ve la nota
      // de herencia (Etapa B5 §4).
      expect(find.textContaining('Estos valores se heredan'), findsOneWidget);
      // No es solo lectura: tenant_admin puede editar su propio tenant.
      expect(find.textContaining('Solo lectura'), findsNothing);

      // Selecciona el Site "Las Heras".
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Site'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Las Heras').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Las Heras'), findsWidgets);

      // Selecciona el Device "Laboratorio".
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Device'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laboratorio').last);
      await tester.pumpAndSettle();

      // Breadcrumb final: the-gene-pig -> Las Heras -> Laboratorio.
      expect(find.textContaining('Laboratorio'), findsWidgets);
      // Laboratorio no tiene Rooms explícitas -> no aparece selector Room
      // (Etapa B5 §2 "Room": "Si el Device no tiene Rooms: scope = Device").
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Room'),
        findsNothing,
      );

      // El catálogo completo se muestra (fallback documentado, Etapa B5 §8).
      expect(find.text('Temperatura interior'), findsOneWidget);
      expect(find.text('Puerta Munters abierta'), findsOneWidget);
    },
  );

  testWidgets(
    'rol sin permiso de edición muestra banner de solo lectura (Etapa B5 §38)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'operator-a',
            userRole: UserAppRole.tenantOperator,
            initialTenantId: 'the-gene-pig',
            editableTenantId: null,
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeWhatsAppAlertRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Solo lectura'), findsOneWidget);
    },
  );

  testWidgets(
    'efectivo muestra origen Tenant cuando no hay override más específico',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'admin-a',
            userRole: UserAppRole.tenantAdmin,
            initialTenantId: 'the-gene-pig',
            editableTenantId: 'the-gene-pig',
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeWhatsAppAlertRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Efectivo: Activada (definido en tenant por el fake) — la tabla
      // muestra el switch de "Activada" ya prendido para
      // temperature_interior, sin necesidad de expandir nada (Etapa
      // 2026-09-08: vista de tabla, todo visible a la vez).
      final Switch enabledSwitch = tester.widget<Switch>(
        find.descendant(
          of: find.byKey(alertCellKey('temperature_interior', 'enabled')),
          matching: find.byType(Switch),
        ),
      );
      expect(enabledSwitch.value, isTrue);
    },
  );

  testWidgets(
    'initialSiteId válido se aplica al iniciar (Etapa B5.1 §1-3/§5)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'admin-a',
            userRole: UserAppRole.tenantAdmin,
            initialTenantId: 'the-gene-pig',
            initialSiteId: 'las-heras',
            editableTenantId: 'the-gene-pig',
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeWhatsAppAlertRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Breadcrumb: the-gene-pig -> Las Heras, visible sin tocar nada.
      expect(find.textContaining('the-gene-pig'), findsWidgets);
      expect(find.textContaining('Las Heras'), findsWidgets);
      // scope efectivo = Site, no Tenant: la nota de herencia de Tenant no
      // debe aparecer.
      expect(find.textContaining('Estos valores se heredan'), findsNothing);
      // El dropdown de Device ya está habilitado porque el Site se aplicó
      // (si siguiera en scope Tenant, Device mostraría el campo estático
      // deshabilitado con valor "—").
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Device'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'initialSiteId inválido cae a scope Tenant sin crashear (Etapa B5.1 §3/§6)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'admin-a',
            userRole: UserAppRole.tenantAdmin,
            initialTenantId: 'the-gene-pig',
            initialSiteId: 'site-inexistente',
            editableTenantId: 'the-gene-pig',
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeWhatsAppAlertRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No crash: llegamos hasta acá sin que pumpAndSettle lance nada.
      expect(tester.takeException(), isNull);
      // Fallback seguro: scope Tenant, no se inventó ni seleccionó Las
      // Heras (el único Site real) para reemplazar al inexistente.
      expect(find.textContaining('Estos valores se heredan'), findsOneWidget);
      expect(find.textContaining('Las Heras'), findsNothing);
    },
  );

  testWidgets(
    'cambio de Tenant (owner) limpia Site/Device/Room y recarga (Etapa B5.1 §4)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'owner-uid',
            userRole: UserAppRole.owner,
            initialTenantId: 'the-gene-pig',
            initialSiteId: 'las-heras',
            tenantService: const _FakeAgroTenantService(),
            siteService: const _FakeMultiTenantSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeWhatsAppAlertRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Arranca con el initialSiteId aplicado: Las Heras, scope Site.
      expect(find.textContaining('Las Heras'), findsWidgets);
      expect(find.textContaining('Estos valores se heredan'), findsNothing);

      // Owner cambia de Tenant a La Payana.
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Tenant'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('La Payana').last);
      await tester.pumpAndSettle();

      // Site/Device/Room se limpiaron: vuelve a scope Tenant (no se
      // reutilizó 'las-heras', que ni siquiera existe en La Payana), y el
      // Site nuevo del tenant (Roque Pérez) aparece en la lista pero NO
      // queda seleccionado automáticamente.
      expect(find.textContaining('Estos valores se heredan'), findsOneWidget);
      expect(find.textContaining('Las Heras'), findsNothing);
    },
  );

  testWidgets(
    'order efectivo sin override coincide con el catálogo real (Etapa B5.1 §10/§18)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'admin-a',
            userRole: UserAppRole.tenantAdmin,
            initialTenantId: 'the-gene-pig',
            editableTenantId: 'the-gene-pig',
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeWhatsAppAlertRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // munters_door_open no tiene override en ningún nivel -> el order
      // efectivo debe ser el order REAL del catálogo (1), nunca 0. La
      // tabla ya muestra todas las filas sin necesidad de expandir nada.
      final AlertDefinition muntersDef = AlertDefinitionCatalog.byId(
        'munters_door_open',
      );
      expect(muntersDef.order, 1);
      final TextField orderField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(alertCellKey('munters_door_open', 'order')),
          matching: find.byType(TextField),
        ),
      );
      expect(orderField.controller?.text, muntersDef.order.toString());
    },
  );

  testWidgets(
    'order override en Tenant gana sobre el catálogo, visto desde Site (Etapa B5.1 §10/§18)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'admin-a',
            userRole: UserAppRole.tenantAdmin,
            initialTenantId: 'the-gene-pig',
            initialSiteId: 'las-heras',
            editableTenantId: 'the-gene-pig',
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeOrderOverrideConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeWhatsAppAlertRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(AlertDefinitionCatalog.byId('dew_point_risk').order, 9);
      // El Tenant define order=2 -> gana sobre el 9 real del catálogo.
      final TextField orderField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(alertCellKey('dew_point_risk', 'order')),
          matching: find.byType(TextField),
        ),
      );
      expect(orderField.controller?.text, '2');
    },
  );

  testWidgets(
    'tabla: switch aplicado directo (sin "Heredar (Sí)"), guardado en bloque (Etapa 2026-09-08)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'admin-a',
            userRole: UserAppRole.tenantAdmin,
            initialTenantId: 'the-gene-pig',
            editableTenantId: 'the-gene-pig',
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeWhatsAppAlertRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // munters_door_open no tiene override en ningún nivel -> "Activada"
      // efectivo es true (default de catálogo) y la tabla ya muestra esa
      // fila sin necesidad de expandir nada.
      final Finder enabledCell = find.byKey(
        alertCellKey('munters_door_open', 'enabled'),
      );
      final Switch enabledSwitch = tester.widget<Switch>(
        find.descendant(of: enabledCell, matching: find.byType(Switch)),
      );
      expect(enabledSwitch.value, isTrue);
      // Nunca más una tercera opción "Heredar (Sí)".
      expect(find.textContaining('Heredar ('), findsNothing);
      // El "Orden" de munters_door_open (1) ya se ve como valor real
      // precargado en el TextField, no como hint "Efectivo: 1".
      final TextField orderField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(alertCellKey('munters_door_open', 'order')),
          matching: find.byType(TextField),
        ),
      );
      expect(orderField.controller?.text, '1');

      // Solo VER el valor aplicado no ensucia nada: "Guardar cambios"
      // sigue deshabilitado.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar cambios'),
            )
            .onPressed,
        isNull,
      );

      // Tocar el switch SÍ crea un override propio (a diferencia de los
      // ChoiceChip de antes, un Switch siempre pasa al otro estado) ->
      // "Guardar cambios" se habilita con contador.
      await tester.tap(
        find.descendant(of: enabledCell, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Guardar cambios (1)'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar cambios (1)'),
            )
            .onPressed,
        isNotNull,
      );

      // Un Switch no puede "volver a heredar" solo con tocarlo de nuevo —
      // cada toque fija un valor explícito (true o false), nunca null. Para
      // eso existe el ícono de reset ("Volver a heredar"), que aparece
      // porque ya hay un override propio.
      await tester.tap(
        find.descendant(
          of: enabledCell,
          matching: find.byTooltip('Volver a heredar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar cambios'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'banner legacy queda claramente separado de la lista de modernos (Etapa B5.1 §15-17)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'admin-a',
            userRole: UserAppRole.tenantAdmin,
            initialTenantId: 'the-gene-pig',
            initialSiteId: 'las-heras',
            editableTenantId: 'the-gene-pig',
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeLegacyRecipientsPresentService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // La sección editable ("Propios de Site") sigue existiendo y
      // separada del banner legacy — la lista efectiva de solo lectura se
      // sacó de acá (Etapa 2026-09-10, redundante con
      // RecipientsSummaryTable, arriba en la misma pantalla).
      expect(find.text('Propios de Site: Las Heras'), findsOneWidget);
      // El banner legacy es una advertencia aparte, no una fila mezclada
      // en la lista de "propios".
      expect(
        find.textContaining('todavía participan del envío productivo'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Temperatura alta con calefacción activa muestra su máximo como link de solo lectura (pedido 2026-09-08)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'admin-a',
            userRole: UserAppRole.tenantAdmin,
            initialTenantId: 'the-gene-pig',
            editableTenantId: 'the-gene-pig',
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            // El tenant define temperature_interior.max = 30.
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeHierarchicalAlertRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService:
                const _FakeWhatsAppAlertRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // La tabla ya muestra todas las filas — no hace falta expandir nada.
      final Finder maxCell = find.byKey(
        alertCellKey('high_temperature_heating_active', 'threshold.max'),
      );
      expect(maxCell, findsOneWidget);
      // El valor real (30, definido en temperature_interior a nivel
      // Tenant) se ve como texto de solo lectura...
      expect(
        find.descendant(of: maxCell, matching: find.text('30.0')),
        findsOneWidget,
      );
      // ...pero NO es un campo editable: la celda no tiene ningún TextField.
      expect(
        find.descendant(of: maxCell, matching: find.byType(TextField)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'resumen de destinatarios (owner) muestra legacy global + tenant + device '
    'juntos, sin depender del selector de Device (pedido 2026-09-10)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'owner-uid',
            userRole: UserAppRole.owner,
            initialTenantId: 'the-gene-pig',
            tenantService: const _FakeAgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeSummaryRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService: const _FakeGlobalLegacyRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Colapsada por default (pedido 2026-09-10): no se ve ningún
      // destinatario todavía, y no se disparó ningún read porque el
      // panel nunca se abrió.
      expect(find.text('Gerardo'), findsNothing);
      expect(
        find.text('Resumen de destinatarios (todo el Tenant)'),
        findsOneWidget,
      );

      // Abrir el panel — recién ahí debería pedir los datos. Está al final
      // de la página (pedido 2026-09-10): hay que scrollear hasta que sea
      // hit-testable antes de tocarlo.
      final Finder summaryHeader = find.text(
        'Resumen de destinatarios (todo el Tenant)',
      );
      await tester.ensureVisible(summaryHeader);
      await tester.pumpAndSettle();
      await tester.tap(summaryHeader);
      await tester.pumpAndSettle();

      // Ningún Device está seleccionado (scope = Tenant) y sin embargo el
      // resumen ya muestra los 4 destinatarios reales — ese es justamente
      // el punto: no depende de "(Sin Device — nivel Site)".
      expect(find.text('Gerardo'), findsOneWidget);
      expect(find.text('Demián'), findsOneWidget);
      expect(find.text('Nicolás Rivas'), findsOneWidget);
      expect(find.text('Enzo'), findsOneWidget);
      expect(find.text('Mauro'), findsOneWidget);

      // Gerardo (legacy global) se hereda a todos los niveles.
      final Finder gerardoRow = find
          .ancestor(of: find.text('Gerardo'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: gerardoRow, matching: find.text('legacy')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: gerardoRow, matching: find.text('todos')),
        findsNWidgets(3), // Tenant, Site, Device.
      );

      // Enzo (device Laboratorio) sólo tiene valor concreto en Device.
      final Finder enzoRow = find
          .ancestor(of: find.text('Enzo'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: enzoRow, matching: find.text('Laboratorio')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: enzoRow, matching: find.text('-')),
        findsNWidgets(3), // Global, Tenant, Site.
      );
    },
  );

  testWidgets(
    'resumen de destinatarios (tenant_admin) NO ve legacy/global — solo '
    'tenant/site/device de su propio tenant (corrección 2026-09-10)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          HierarchicalAlertSettingsPage(
            currentUserUid: 'admin-a',
            userRole: UserAppRole.tenantAdmin,
            initialTenantId: 'the-gene-pig',
            editableTenantId: 'the-gene-pig',
            tenantService: const AgroTenantService(),
            siteService: const _FakeAgroSiteService(),
            deviceService: const _FakeAgroDeviceService(),
            roomService: const _FakeAgroDeviceRoomService(),
            configService: const _FakeHierarchicalAlertConfigService(),
            recipientsService: const _FakeSummaryRecipientsService(),
            controlDashboardConfigService:
                const _FakeControlDashboardConfigService(),
            legacyRecipientsService: const _FakeGlobalLegacyRecipientsService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder summaryHeader = find.text(
        'Resumen de destinatarios (todo el Tenant)',
      );
      await tester.ensureVisible(summaryHeader);
      await tester.pumpAndSettle();
      await tester.tap(summaryHeader);
      await tester.pumpAndSettle();

      // Los técnicos globales de Valke (legacy) no son asunto de un cliente
      // — un tenant_admin no debe verlos ni saber que existen.
      expect(find.text('Gerardo'), findsNothing);
      expect(find.text('Demián'), findsNothing);
      expect(find.text('legacy'), findsNothing);
      // Tampoco la columna "Global" en sí (ni siquiera vacía).
      expect(find.text('Global'), findsNothing);

      // Pero sí ve la configuración real de SU tenant, en todos los
      // niveles que le corresponden administrar.
      expect(find.text('Nicolás Rivas'), findsOneWidget);
      expect(find.text('Enzo'), findsOneWidget);
      expect(find.text('Mauro'), findsOneWidget);
    },
  );
}
