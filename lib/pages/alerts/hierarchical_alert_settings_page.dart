import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/agro_device.dart';
import '../../models/agro_device_room.dart';
import '../../models/agro_site.dart';
import '../../models/agro_tenant.dart';
import '../../models/hierarchical_alert_catalog.dart';
import '../../models/hierarchical_alert_config.dart';
import '../../models/hierarchical_alert_recipient.dart';
import '../../services/agro_device_room_service.dart';
import '../../services/agro_device_service.dart';
import '../../services/agro_site_service.dart';
import '../../services/agro_tenant_service.dart';
import '../../services/control_dashboard_config_service.dart';
import '../../services/firestore_error_messages.dart';
import '../../services/hierarchical_alert_config_service.dart';
import '../../services/hierarchical_alert_recipients_service.dart';
import '../../services/legacy_alert_config_adapter.dart';
import '../../services/user_management_service.dart';
import '../../services/whatsapp_alert_recipients_service.dart';
import 'widgets/alert_config_table.dart';
import 'widgets/hierarchical_recipients_section.dart';
import 'widgets/recipients_summary_table.dart';

enum _LoadState { idle, loading, loaded, error }

/// "Configuración → Alertas (jerárquico)" — Etapa B5. Pantalla real
/// (`Navigator.push`), reemplaza conceptualmente al diálogo plano de
/// `_AlertSettingsDialog` en `main.dart`, pero convive con él (legacy no se
/// elimina — Etapa B5 §31/Restricciones).
///
/// Principio rector (Etapa B5 §1): esta pantalla es visualización + edición
/// + persistencia. NO reimplementa reglas de negocio nuevas — el resolver
/// de herencia en `models/hierarchical_alert_config.dart` y
/// `models/hierarchical_alert_recipient.dart` es una réplica deliberada,
/// campo por campo, del backend (B2/B3/B4.5), no un diseño alternativo.
class HierarchicalAlertSettingsPage extends StatefulWidget {
  const HierarchicalAlertSettingsPage({
    super.key,
    required this.currentUserUid,
    required this.userRole,
    required this.initialTenantId,
    this.initialSiteId,
    this.editableTenantId,
    this.tenantService = const AgroTenantService(),
    this.siteService = const AgroSiteService(),
    this.deviceService = const AgroDeviceService(),
    this.roomService = const AgroDeviceRoomService(),
    this.configService = const HierarchicalAlertConfigService(),
    this.recipientsService = const HierarchicalAlertRecipientsService(),
    this.controlDashboardConfigService = const ControlDashboardConfigService(),
    this.legacyRecipientsService = const WhatsAppAlertRecipientsService(),
  });

  final String currentUserUid;
  final String? userRole;
  final String initialTenantId;
  final String? initialSiteId;

  /// Tenant sobre el que un `tenant_admin` puede editar (el suyo). `null`
  /// para owner (puede editar cualquiera) o para roles de solo lectura.
  final String? editableTenantId;

  final AgroTenantService tenantService;
  final AgroSiteService siteService;
  final AgroDeviceService deviceService;
  final AgroDeviceRoomService roomService;
  final HierarchicalAlertConfigService configService;
  final HierarchicalAlertRecipientsService recipientsService;
  final ControlDashboardConfigService controlDashboardConfigService;
  final WhatsAppAlertRecipientsService legacyRecipientsService;

  bool get isOwner => userRole == UserAppRole.owner;

  @override
  State<HierarchicalAlertSettingsPage> createState() =>
      _HierarchicalAlertSettingsPageState();
}

class _HierarchicalAlertSettingsPageState
    extends State<HierarchicalAlertSettingsPage> {
  _LoadState _tenantsState = _LoadState.idle;
  List<AgroTenant> _tenants = const <AgroTenant>[];
  String? _tenantsError;

  _LoadState _structureState = _LoadState.idle;
  List<AgroSite> _sites = const <AgroSite>[];
  List<AgroDevice> _devices = const <AgroDevice>[];
  List<AgroDeviceRoom> _rooms = const <AgroDeviceRoom>[];
  String? _structureError;

  _LoadState _configState = _LoadState.idle;
  String? _configError;
  Map<String, AlertConfigOverride> _tenantOverrides = const {};
  Map<String, AlertConfigOverride> _siteOverrides = const {};
  Map<String, AlertConfigOverride> _deviceOverrides = const {};
  Map<String, AlertConfigOverride> _roomOverrides = const {};
  Map<String, AlertConfigOverride>? _legacyOverrides;

  /// Ediciones sin guardar del scope actual — solo contiene una entrada
  /// para un `alertId` cuando su draft realmente difiere de lo último
  /// guardado (ver `_updateDraft`). Vacío = nada para guardar.
  final Map<String, AlertConfigOverride> _drafts =
      <String, AlertConfigOverride>{};
  bool _savingAll = false;

  Map<String, AlertRecipientOverride> _tenantRecipients = const {};
  Map<String, AlertRecipientOverride> _siteRecipients = const {};
  Map<String, AlertRecipientOverride> _deviceRecipients = const {};
  Map<String, AlertRecipientOverride> _roomRecipients = const {};
  int? _legacyRecipientsCount;

  /// Etapa 2026-09-10: tabla resumen de TODOS los destinatarios del Tenant
  /// (legacy global + modernos Tenant/Site/Device), independiente del
  /// Site/Device seleccionado — pedido explícito del usuario para no tener
  /// que ir cambiando el selector para ver quién recibe qué.
  List<RecipientSummaryRow> _recipientsSummaryRows =
      const <RecipientSummaryRow>[];
  _LoadState _recipientsSummaryState = _LoadState.idle;

  /// Colapsada por default (pedido 2026-09-10): no se piden los datos de
  /// Firestore hasta que el usuario la abre — ver [_loadRecipientsSummary],
  /// que solo se llama desde el `onExpansionChanged` de abajo, nunca desde
  /// `_loadStructure`.
  bool _recipientsSummaryExpanded = false;

  String? _tenantId;
  String? _siteId;
  String? _deviceId;
  String? _roomId;

  @override
  void initState() {
    super.initState();
    _tenantId = widget.initialTenantId;
    if (widget.isOwner) {
      _loadTenants();
    } else {
      _tenantsState = _LoadState.loaded;
      _tenants = <AgroTenant>[];
    }
    // Etapa B5.1 §1-3: `widget.initialSiteId` solo se aplica en esta
    // primera carga (nunca en una carga disparada por `_selectTenant`), y
    // solo si el Site existe realmente en la lista del Tenant recién
    // cargada — ver `_loadStructure(applyInitialSiteId: true)`.
    _loadStructure(applyInitialSiteId: true);
  }

  bool get _canEdit {
    if (_tenantId == null) return false;
    if (widget.isOwner) return true;
    return widget.editableTenantId != null &&
        widget.editableTenantId == _tenantId;
  }

  AlertConfigScope get _scope {
    if (_roomId != null) return AlertConfigScope.room;
    if (_deviceId != null) return AlertConfigScope.device;
    if (_siteId != null) return AlertConfigScope.site;
    return AlertConfigScope.tenant;
  }

  /// Nombre concreto del nodo del scope actual (Tenant/Site/Device/Room) —
  /// pedido 2026-09-10: sin esto, la sección de "Agregar destinatario" solo
  /// decía "Site" o "Device" en genérico, sin decir CUÁL, y no quedaba
  /// claro dónde se estaba agregando. Mismo criterio de resolución que
  /// `_buildBreadcrumb`.
  String get _scopeTargetLabel {
    switch (_scope) {
      case AlertConfigScope.tenant:
        return _tenants
                .cast<AgroTenant?>()
                .firstWhere((t) => t?.id == _tenantId, orElse: () => null)
                ?.name ??
            _tenantId ??
            '—';
      case AlertConfigScope.site:
        return _sites
                .cast<AgroSite?>()
                .firstWhere((s) => s?.id == _siteId, orElse: () => null)
                ?.name ??
            _siteId!;
      case AlertConfigScope.device:
        return _selectedDevice?.name ?? _deviceId!;
      case AlertConfigScope.room:
        return _rooms
                .cast<AgroDeviceRoom?>()
                .firstWhere((r) => r?.id == _roomId, orElse: () => null)
                ?.name ??
            _roomId!;
    }
  }

  AgroDevice? get _selectedDevice {
    if (_deviceId == null) return null;
    for (final AgroDevice device in _devices) {
      if (device.id == _deviceId) return device;
    }
    return null;
  }

  // ── Carga: tenants (solo owner) ─────────────────────────────────────────

  Future<void> _loadTenants() async {
    setState(() => _tenantsState = _LoadState.loading);
    try {
      final List<AgroTenant> tenants = await widget.tenantService
          .listTenantsForAdministration();
      if (!mounted) return;
      setState(() {
        _tenants = tenants;
        _tenantsState = _LoadState.loaded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tenantsError = describeFirestoreError(error);
        _tenantsState = _LoadState.error;
      });
    }
  }

  // ── Carga: Sites/Devices/Rooms del tenant seleccionado ──────────────────

  /// Carga Sites/Devices/Rooms del tenant seleccionado.
  ///
  /// [applyInitialSiteId] solo debe ser `true` en la carga inicial de la
  /// página (Etapa B5.1 §1-4): resuelve `widget.initialSiteId` DESPUÉS de
  /// tener la lista real de Sites del Tenant, y únicamente si ese Site
  /// pertenece a esa lista — nunca se asigna `_siteId` a ciegas antes de
  /// validar que exista. Si `initialSiteId` es `null`, vacío, o no
  /// pertenece al Tenant, el fallback seguro es quedarse en scope Tenant
  /// (no se inventa ni se selecciona automáticamente otro Site).
  /// `_selectTenant` nunca pasa `true` acá — un cambio manual de Tenant no
  /// debe reutilizar el `initialSiteId` de otro Tenant.
  Future<void> _loadStructure({bool applyInitialSiteId = false}) async {
    final String? tenantId = _tenantId;
    if (tenantId == null) return;
    setState(() {
      _structureState = _LoadState.loading;
      _structureError = null;
    });
    try {
      final List<AgroSite> sites = await widget.siteService.listByTenant(
        tenantId,
      );

      String? resolvedSiteId = _siteId;
      if (applyInitialSiteId &&
          resolvedSiteId == null &&
          widget.initialSiteId != null &&
          widget.initialSiteId!.trim().isNotEmpty &&
          sites.any((AgroSite site) => site.id == widget.initialSiteId)) {
        resolvedSiteId = widget.initialSiteId;
      }

      List<AgroDevice> devices = const <AgroDevice>[];
      if (resolvedSiteId != null) {
        devices = await widget.deviceService.listBySite(
          tenantId: tenantId,
          siteId: resolvedSiteId,
        );
      }
      List<AgroDeviceRoom> rooms = const <AgroDeviceRoom>[];
      if (_deviceId != null) {
        rooms = await widget.roomService.listByDevice(
          tenantId: tenantId,
          deviceId: _deviceId!,
        );
      }
      if (!mounted || _tenantId != tenantId) return;
      setState(() {
        _sites = sites;
        _siteId = resolvedSiteId;
        _devices = devices;
        _rooms = rooms;
        _structureState = _LoadState.loaded;
      });
      await _loadConfigAndRecipients();
      // Solo se piden los datos del resumen si el panel ya estaba abierto
      // (p.ej. el usuario cambió de Tenant/Site con el resumen expandido) —
      // nunca en la carga inicial (colapsado por default, sin reads).
      if (_recipientsSummaryExpanded) {
        unawaited(_loadRecipientsSummary(tenantId, sites));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _structureError = describeFirestoreError(error);
        _structureState = _LoadState.error;
      });
    }
  }

  void _selectTenant(String? tenantId) {
    if (tenantId == null || tenantId == _tenantId) return;
    setState(() {
      _tenantId = tenantId;
      _siteId = null;
      _deviceId = null;
      _roomId = null;
      _sites = const <AgroSite>[];
      _devices = const <AgroDevice>[];
      _rooms = const <AgroDeviceRoom>[];
      // El resumen es por-Tenant — un cambio de Tenant nunca debe seguir
      // mostrando datos del anterior. Si el panel estaba abierto,
      // `_loadStructure` lo vuelve a pedir para el Tenant nuevo.
      _recipientsSummaryRows = const <RecipientSummaryRow>[];
      _recipientsSummaryState = _LoadState.idle;
    });
    _loadStructure();
  }

  Future<void> _selectSite(String? siteId) async {
    if (siteId == _siteId) return;
    setState(() {
      _siteId = siteId;
      _deviceId = null;
      _roomId = null;
      _devices = const <AgroDevice>[];
      _rooms = const <AgroDeviceRoom>[];
    });
    if (siteId == null) {
      await _loadConfigAndRecipients();
      return;
    }
    setState(() => _structureState = _LoadState.loading);
    try {
      final List<AgroDevice> devices = await widget.deviceService.listBySite(
        tenantId: _tenantId!,
        siteId: siteId,
      );
      if (!mounted || _siteId != siteId) return;
      setState(() {
        _devices = devices;
        _structureState = _LoadState.loaded;
      });
      await _loadConfigAndRecipients();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _structureError = describeFirestoreError(error);
        _structureState = _LoadState.error;
      });
    }
  }

  Future<void> _selectDevice(String? deviceId) async {
    if (deviceId == _deviceId) return;
    setState(() {
      _deviceId = deviceId;
      _roomId = null;
      _rooms = const <AgroDeviceRoom>[];
    });
    if (deviceId == null) {
      await _loadConfigAndRecipients();
      return;
    }
    setState(() => _structureState = _LoadState.loading);
    try {
      final List<AgroDeviceRoom> rooms = await widget.roomService.listByDevice(
        tenantId: _tenantId!,
        deviceId: deviceId,
      );
      if (!mounted || _deviceId != deviceId) return;
      setState(() {
        _rooms = rooms;
        _structureState = _LoadState.loaded;
      });
      await _loadConfigAndRecipients();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _structureError = describeFirestoreError(error);
        _structureState = _LoadState.error;
      });
    }
  }

  Future<void> _selectRoom(String? roomId) async {
    if (roomId == _roomId) return;
    setState(() => _roomId = roomId);
    await _loadConfigAndRecipients();
  }

  // ── Carga: alertConfig/alertRecipients de los niveles del scope actual ──
  //
  // Etapa B5 §33/§34: exactamente una lectura de colección por nivel
  // aplicable, bajo demanda al cambiar de selector — nunca un listener,
  // nunca refresco periódico.

  Future<void> _loadConfigAndRecipients() async {
    final String? tenantId = _tenantId;
    if (tenantId == null) return;
    setState(() {
      _configState = _LoadState.loading;
      _configError = null;
      // Cualquier cambio de scope descarta ediciones sin guardar del scope
      // anterior — nunca se "arrastran" drafts de un Tenant/Site/Device/Room
      // a otro.
      _drafts.clear();
    });
    try {
      final Map<String, AlertConfigOverride> tenantOverrides = await widget
          .configService
          .loadScopeOverrides(
            AlertConfigScopeTarget(
              tenantId: tenantId,
              scope: AlertConfigScope.tenant,
            ),
          );
      final Map<String, AlertRecipientOverride> tenantRecipients = await widget
          .recipientsService
          .loadScopeRecipients(
            AlertRecipientScopeTarget(
              tenantId: tenantId,
              scope: AlertConfigScope.tenant,
            ),
          )
          .then(_byId);

      Map<String, AlertConfigOverride> siteOverrides = const {};
      Map<String, AlertRecipientOverride> siteRecipients = const {};
      Map<String, AlertConfigOverride>? legacyOverrides;
      int? legacyRecipientsCount;
      if (_siteId != null) {
        siteOverrides = await widget.configService.loadScopeOverrides(
          AlertConfigScopeTarget(
            tenantId: tenantId,
            scope: AlertConfigScope.site,
            siteId: _siteId,
          ),
        );
        siteRecipients = await widget.recipientsService
            .loadScopeRecipients(
              AlertRecipientScopeTarget(
                tenantId: tenantId,
                scope: AlertConfigScope.site,
                siteId: _siteId,
              ),
            )
            .then(_byId);
        legacyOverrides = await _loadLegacyOverrides(tenantId, _siteId!);
        legacyRecipientsCount = await _loadLegacyRecipientsCount(_siteId!);
      }

      Map<String, AlertConfigOverride> deviceOverrides = const {};
      Map<String, AlertRecipientOverride> deviceRecipients = const {};
      if (_deviceId != null) {
        deviceOverrides = await widget.configService.loadScopeOverrides(
          AlertConfigScopeTarget(
            tenantId: tenantId,
            scope: AlertConfigScope.device,
            deviceId: _deviceId,
          ),
        );
        deviceRecipients = await widget.recipientsService
            .loadScopeRecipients(
              AlertRecipientScopeTarget(
                tenantId: tenantId,
                scope: AlertConfigScope.device,
                deviceId: _deviceId,
              ),
            )
            .then(_byId);
      }

      Map<String, AlertConfigOverride> roomOverrides = const {};
      Map<String, AlertRecipientOverride> roomRecipients = const {};
      if (_roomId != null) {
        roomOverrides = await widget.configService.loadScopeOverrides(
          AlertConfigScopeTarget(
            tenantId: tenantId,
            scope: AlertConfigScope.room,
            deviceId: _deviceId,
            roomId: _roomId,
          ),
        );
        roomRecipients = await widget.recipientsService
            .loadScopeRecipients(
              AlertRecipientScopeTarget(
                tenantId: tenantId,
                scope: AlertConfigScope.room,
                deviceId: _deviceId,
                roomId: _roomId,
              ),
            )
            .then(_byId);
      }

      if (!mounted) return;
      setState(() {
        _tenantOverrides = tenantOverrides;
        _siteOverrides = siteOverrides;
        _deviceOverrides = deviceOverrides;
        _roomOverrides = roomOverrides;
        _legacyOverrides = legacyOverrides;
        _tenantRecipients = tenantRecipients;
        _siteRecipients = siteRecipients;
        _deviceRecipients = deviceRecipients;
        _roomRecipients = roomRecipients;
        _legacyRecipientsCount = legacyRecipientsCount;
        _configState = _LoadState.loaded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _configError = describeFirestoreError(error);
        _configState = _LoadState.error;
      });
    }
  }

  Map<String, AlertRecipientOverride> _byId(List<AlertRecipientOverride> list) {
    return <String, AlertRecipientOverride>{
      for (final AlertRecipientOverride o in list) o.id: o,
    };
  }

  /// El legacy es site-scoped únicamente (Etapa B2/B3) — si el read falla o
  /// el documento no existe, se documenta como "sin capa legacy" en vez de
  /// fingir un valor. Nunca lanza: un fallo de legacy no debe tumbar toda
  /// la pantalla moderna.
  Future<Map<String, AlertConfigOverride>?> _loadLegacyOverrides(
    String tenantId,
    String siteId,
  ) async {
    try {
      final ControlDashboardConfigResult result = await widget
          .controlDashboardConfigService
          .readConfig(tenantId: tenantId, siteId: siteId);
      if (!result.exists || result.errorMessage != null) return null;
      return legacyAlertConfigOverridesFromControlDashboard(
        alertSettings: result.alertSettings,
        thresholds: result.thresholds,
      );
    } catch (_) {
      return null;
    }
  }

  /// Etapa B5 §31: advertencia técnica de "existen destinatarios legacy",
  /// sin intentar mezclarlos con los modernos (los legacy llegan con el
  /// teléfono enmascarado desde el backend, no se pueden deduplicar por
  /// número real). Solo se muestra a owner/tenant_admin.
  Future<int?> _loadLegacyRecipientsCount(String siteId) async {
    if (!widget.isOwner && widget.userRole != UserAppRole.tenantAdmin) {
      return null;
    }
    try {
      final WhatsAppAlertRecipientsResult result = await widget
          .legacyRecipientsService
          .fetchRecipients(siteId: siteId);
      if (!result.ok) return null;
      return result.recipientCount;
    } catch (_) {
      return null;
    }
  }

  /// Etapa 2026-09-10: arma la tabla resumen completa del Tenant —
  /// destinatarios legacy globales + modernos en Tenant/Site/Device, todos
  /// juntos, independiente del scope seleccionado en los selectores de
  /// arriba. Solo lecturas one-shot (sin listeners); acotado al Tenant
  /// actual, nunca a "todos los tenants".
  Future<void> _loadRecipientsSummary(
    String tenantId,
    List<AgroSite> sites,
  ) async {
    if (!widget.isOwner && widget.userRole != UserAppRole.tenantAdmin) {
      setState(() {
        _recipientsSummaryRows = const <RecipientSummaryRow>[];
        _recipientsSummaryState = _LoadState.loaded;
      });
      return;
    }
    setState(() => _recipientsSummaryState = _LoadState.loading);
    try {
      final String tenantDisplayName =
          _tenants
              .cast<AgroTenant?>()
              .firstWhere((t) => t?.id == tenantId, orElse: () => null)
              ?.name ??
          tenantId;

      // Etapa 2026-09-10 (corrección): los destinatarios "global" (legacy
      // Gerardo/Demián, y cualquier futuro scope global en el sistema
      // moderno) son contactos técnicos internos de Valke que aplican a
      // TODOS los tenants — un tenant_admin no debe verlos, ni saber que
      // existen. Solo owner los carga; para tenant_admin ni siquiera se
      // pide el read.
      List<WhatsAppAlertRecipient> legacyGlobals =
          const <WhatsAppAlertRecipient>[];
      if (widget.isOwner && sites.isNotEmpty) {
        final WhatsAppAlertRecipientsResult legacyResult = await widget
            .legacyRecipientsService
            .fetchRecipients(siteId: sites.first.id);
        if (legacyResult.ok) legacyGlobals = legacyResult.globalRecipients;
      }

      final List<AlertRecipientOverride> tenantRecipients = await widget
          .recipientsService
          .loadScopeRecipients(
            AlertRecipientScopeTarget(
              tenantId: tenantId,
              scope: AlertConfigScope.tenant,
            ),
          );

      final List<List<AlertRecipientOverride>> siteRecipientsLists =
          await Future.wait(<Future<List<AlertRecipientOverride>>>[
            for (final AgroSite site in sites)
              widget.recipientsService.loadScopeRecipients(
                AlertRecipientScopeTarget(
                  tenantId: tenantId,
                  scope: AlertConfigScope.site,
                  siteId: site.id,
                ),
              ),
          ]);

      final List<AgroDevice> allDevices = await widget.deviceService
          .listByTenant(tenantId);
      final List<List<AlertRecipientOverride>> deviceRecipientsLists =
          await Future.wait(<Future<List<AlertRecipientOverride>>>[
            for (final AgroDevice device in allDevices)
              widget.recipientsService.loadScopeRecipients(
                AlertRecipientScopeTarget(
                  tenantId: tenantId,
                  scope: AlertConfigScope.device,
                  deviceId: device.id,
                ),
              ),
          ]);

      final List<RecipientSummaryRow> rows = <RecipientSummaryRow>[
        for (final WhatsAppAlertRecipient r in legacyGlobals)
          RecipientSummaryRow(
            displayName: r.contactName,
            phoneDisplay: r.phoneMasked,
            globalValue: 'legacy',
            tenantValue: kRecipientSummaryInherited,
            siteValue: kRecipientSummaryInherited,
            deviceValue: kRecipientSummaryInherited,
            isLegacy: true,
          ),
        for (final AlertRecipientOverride r in tenantRecipients)
          RecipientSummaryRow(
            displayName: r.displayName,
            phoneDisplay: r.phoneE164,
            globalValue: kRecipientSummaryNotApplicable,
            tenantValue: tenantDisplayName,
            siteValue: kRecipientSummaryInherited,
            deviceValue: kRecipientSummaryInherited,
            isLegacy: false,
          ),
        for (int i = 0; i < sites.length; i++)
          for (final AlertRecipientOverride r in siteRecipientsLists[i])
            RecipientSummaryRow(
              displayName: r.displayName,
              phoneDisplay: r.phoneE164,
              globalValue: kRecipientSummaryNotApplicable,
              tenantValue: kRecipientSummaryNotApplicable,
              siteValue: sites[i].name,
              deviceValue: kRecipientSummaryInherited,
              isLegacy: false,
            ),
        for (int i = 0; i < allDevices.length; i++)
          for (final AlertRecipientOverride r in deviceRecipientsLists[i])
            RecipientSummaryRow(
              displayName: r.displayName,
              phoneDisplay: r.phoneE164,
              globalValue: kRecipientSummaryNotApplicable,
              tenantValue: kRecipientSummaryNotApplicable,
              siteValue: kRecipientSummaryNotApplicable,
              deviceValue: allDevices[i].name,
              isLegacy: false,
            ),
      ];

      if (!mounted || _tenantId != tenantId) return;
      setState(() {
        _recipientsSummaryRows = rows;
        _recipientsSummaryState = _LoadState.loaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recipientsSummaryRows = const <RecipientSummaryRow>[];
        _recipientsSummaryState = _LoadState.error;
      });
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas — configuración jerárquica')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSelectorRow(constraints.maxWidth),
                    const SizedBox(height: 12),
                    _buildBreadcrumb(),
                    const SizedBox(height: 16),
                    if (_structureState == _LoadState.error)
                      _ErrorBanner(
                        message: _structureError ?? 'Error al cargar.',
                        onRetry: _loadStructure,
                      ),
                    if (!_canEdit) _buildReadOnlyBanner(),
                    if (_legacyRecipientsCount != null &&
                        _legacyRecipientsCount! > 0)
                      _buildLegacyRecipientsBanner(),
                    const SizedBox(height: 8),
                    _buildBody(),
                    if (_tenantId != null) ...[
                      const SizedBox(height: 24),
                      _buildRecipientsSummarySection(),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Etapa 2026-09-10: tabla resumen de TODOS los destinatarios del Tenant
  /// actual (legacy global + modernos Tenant/Site/Device) — NO respeta el
  /// Site/Device seleccionado arriba, es deliberadamente panorámica. Solo
  /// owner/tenant_admin la ven (mismo gate que el conteo legacy), porque
  /// expone teléfonos (aunque enmascarados para legacy).
  ///
  /// Colapsada por default: no dispara ningún read de Firestore hasta que
  /// el usuario la abre (`onExpansionChanged` es lo único que llama a
  /// `_loadRecipientsSummary`).
  Widget _buildRecipientsSummarySection() {
    if (!widget.isOwner && widget.userRole != UserAppRole.tenantAdmin) {
      return const SizedBox.shrink();
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: _recipientsSummaryExpanded,
        tilePadding: EdgeInsets.zero,
        title: const Text(
          'Resumen de destinatarios (todo el Tenant)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFE5E7EB),
          ),
        ),
        subtitle: const Text(
          'Legacy + modernos, todos los Sites/Devices — no depende de los '
          'filtros de arriba.',
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        onExpansionChanged: (expanded) {
          setState(() => _recipientsSummaryExpanded = expanded);
          if (expanded &&
              _recipientsSummaryState == _LoadState.idle &&
              _tenantId != null) {
            _loadRecipientsSummary(_tenantId!, _sites);
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: switch (_recipientsSummaryState) {
              _LoadState.loading => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              _LoadState.error => const Text(
                'No se pudo cargar el resumen de destinatarios.',
                style: TextStyle(color: Color(0xFFF87171)),
              ),
              _ => RecipientsSummaryTable(
                rows: _recipientsSummaryRows,
                showGlobalColumn: widget.isOwner,
              ),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorRow(double maxWidth) {
    final bool narrow = maxWidth < 640;
    final List<Widget> selectors = [
      _TenantDropdown(
        isOwner: widget.isOwner,
        tenants: _tenants,
        loading: _tenantsState == _LoadState.loading,
        error: _tenantsState == _LoadState.error ? _tenantsError : null,
        value: _tenantId,
        onChanged: _selectTenant,
      ),
      _ScopeDropdown<AgroSite>(
        label: 'Site',
        noneLabel: '(Sin Site — nivel Tenant)',
        items: _sites,
        idOf: (s) => s.id,
        labelOf: (s) => s.name,
        value: _siteId,
        enabled: _tenantId != null,
        onChanged: _selectSite,
      ),
      _ScopeDropdown<AgroDevice>(
        label: 'Device',
        noneLabel: '(Sin Device — nivel Site)',
        items: _devices,
        idOf: (d) => d.id,
        labelOf: (d) => d.name,
        value: _deviceId,
        enabled: _siteId != null,
        onChanged: _selectDevice,
      ),
      if (_rooms.isNotEmpty)
        _ScopeDropdown<AgroDeviceRoom>(
          label: 'Room',
          noneLabel: '(Sin Room — nivel Device)',
          items: _rooms,
          idOf: (r) => r.id,
          labelOf: (r) => r.name,
          value: _roomId,
          enabled: _deviceId != null,
          onChanged: _selectRoom,
        ),
    ];
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final widget in selectors) ...[
            widget,
            const SizedBox(height: 8),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (final widget in selectors) ...[
          Expanded(child: widget),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildBreadcrumb() {
    final List<String> parts = <String>[
      _tenants
              .cast<AgroTenant?>()
              .firstWhere((t) => t?.id == _tenantId, orElse: () => null)
              ?.name ??
          _tenantId ??
          '—',
      if (_siteId != null)
        _sites
                .cast<AgroSite?>()
                .firstWhere((s) => s?.id == _siteId, orElse: () => null)
                ?.name ??
            _siteId!,
      if (_deviceId != null) _selectedDevice?.name ?? _deviceId!,
      if (_roomId != null)
        _rooms
                .cast<AgroDeviceRoom?>()
                .firstWhere((r) => r?.id == _roomId, orElse: () => null)
                ?.name ??
            _roomId!,
    ];
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(
            text: 'Configurando: ',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          TextSpan(
            text: parts.join('  →  '),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFE5E7EB),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: Color(0xFF94A3B8)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Solo lectura: tu rol no permite editar esta configuración.',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegacyRecipientsBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF3F2D12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF8A5A00)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: Color(0xFFF59E0B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // Etapa B5.1 §15-17: nunca dar a entender que la lista de
                // abajo ("Destinatarios configurados en el sistema
                // jerárquico") es el total absoluto de quién recibe
                // WhatsApp hoy — el envío productivo real sigue siendo el
                // sistema legacy. El teléfono legacy llega enmascarado
                // desde el backend, así que no se puede deduplicar contra
                // los modernos por número real; se muestra como
                // advertencia separada en vez de intentarlo.
                'Existen $_legacyRecipientsCount destinatarios legacy que '
                'todavía participan del envío productivo de WhatsApp en '
                'este site y no aparecen en la lista de abajo (no se '
                'pueden cruzar por teléfono real — el sistema legacy solo '
                'expone el número enmascarado).',
                style: const TextStyle(color: Color(0xFFF59E0B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_configState == _LoadState.loading ||
        _structureState == _LoadState.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Cargando configuración…'),
            ],
          ),
        ),
      );
    }
    if (_configState == _LoadState.error) {
      return _ErrorBanner(
        message: _configError ?? 'Error al cargar.',
        onRetry: _loadConfigAndRecipients,
      );
    }
    if (_configState != _LoadState.loaded) {
      return const SizedBox.shrink();
    }
    if (_scope == AlertConfigScope.tenant) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _InheritanceNote(
            text:
                'Estos valores se heredan en todos los Sites/Devices/Rooms del Tenant salvo overrides inferiores.',
          ),
          const SizedBox(height: 12),
          _buildAlertsTable(),
          const SizedBox(height: 24),
          _buildRecipientsSection(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAlertsTable(),
        const SizedBox(height: 24),
        _buildRecipientsSection(),
      ],
    );
  }

  Widget _buildAlertsTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AlertConfigTable(
          definitions: AlertDefinitionCatalog.applicableFor(
            scope: _scope,
            deviceHasRooms: _rooms.isNotEmpty,
          ),
          canEdit: _canEdit,
          effectiveFor: _resolveAlertEffective,
          draftFor: (alertId) => _drafts[alertId] ?? _ownOverrideFor(alertId),
          onFieldChanged: _updateDraft,
          resolveLinkedAlert: _resolveAlertEffective,
        ),
        if (_canEdit) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_drafts.isNotEmpty)
                TextButton(
                  onPressed: _savingAll ? null : () => setState(_drafts.clear),
                  child: const Text('Cancelar cambios'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (_drafts.isNotEmpty && !_savingAll)
                    ? _saveAllDirty
                    : null,
                child: _savingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _drafts.isEmpty
                            ? 'Guardar cambios'
                            : 'Guardar cambios (${_drafts.length})',
                      ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// El override YA GUARDADO (no el draft) del scope que se está editando
  /// para una alerta — equivalente al que antes calculaba
  /// `AlertConfigCard._ownOverride` por cada card, ahora centralizado acá
  /// porque la tabla edita varias alertas a la vez.
  AlertConfigOverride _ownOverrideFor(String alertId) {
    return switch (_scope) {
      AlertConfigScope.tenant =>
        _tenantOverrides[alertId] ?? AlertConfigOverride.empty,
      AlertConfigScope.site =>
        _siteOverrides[alertId] ?? AlertConfigOverride.empty,
      AlertConfigScope.device =>
        _deviceOverrides[alertId] ?? AlertConfigOverride.empty,
      AlertConfigScope.room =>
        _roomOverrides[alertId] ?? AlertConfigOverride.empty,
    };
  }

  bool _ownDocumentExistsFor(String alertId) {
    return switch (_scope) {
      AlertConfigScope.tenant => _tenantOverrides.containsKey(alertId),
      AlertConfigScope.site => _siteOverrides.containsKey(alertId),
      AlertConfigScope.device => _deviceOverrides.containsKey(alertId),
      AlertConfigScope.room => _roomOverrides.containsKey(alertId),
    };
  }

  /// Aplica un cambio de campo al draft de una alerta. Si el resultado
  /// vuelve a coincidir con lo último guardado (p. ej. el usuario deshizo
  /// su propio cambio), el draft se descarta en vez de quedar "sucio" sin
  /// necesidad — mismo criterio que ya usaba `AlertConfigCard._isDirty`.
  void _updateDraft(
    String alertId,
    AlertConfigOverride Function(AlertConfigOverride current) update,
  ) {
    final AlertConfigOverride current =
        _drafts[alertId] ?? _ownOverrideFor(alertId);
    final AlertConfigOverride next = update(current);
    setState(() {
      if (alertConfigOverridesEqual(next, _ownOverrideFor(alertId))) {
        _drafts.remove(alertId);
      } else {
        _drafts[alertId] = next;
      }
    });
  }

  /// Resuelve el efectivo de CUALQUIER alerta del catálogo para el scope
  /// actual, considerando también cualquier draft sin guardar de ESA MISMA
  /// alerta (para que la tabla muestre una vista previa en vivo mientras se
  /// edita) — usado tanto para la fila propia de cada alerta como para los
  /// campos de `AlertDefinition.thresholdLinks` que espejan OTRA alerta.
  /// Nunca duplica el algoritmo de herencia: siempre llama a
  /// `resolveEffectiveAlertConfig`.
  EffectiveAlertConfig _resolveAlertEffective(String alertId) {
    final AlertDefinition definition = AlertDefinitionCatalog.byId(alertId);
    final AlertConfigOverride ownDraftOrSaved =
        _drafts[alertId] ?? _ownOverrideFor(alertId);
    final AlertConfigOverride tenantArg = _scope == AlertConfigScope.tenant
        ? ownDraftOrSaved
        : (_tenantOverrides[alertId] ?? AlertConfigOverride.empty);
    final AlertConfigOverride? siteArg = _siteId == null
        ? null
        : (_scope == AlertConfigScope.site
              ? ownDraftOrSaved
              : (_siteOverrides[alertId] ?? AlertConfigOverride.empty));
    final AlertConfigOverride? deviceArg = _deviceId == null
        ? null
        : (_scope == AlertConfigScope.device
              ? ownDraftOrSaved
              : (_deviceOverrides[alertId] ?? AlertConfigOverride.empty));
    final AlertConfigOverride? roomArg = _roomId == null
        ? null
        : (_scope == AlertConfigScope.room
              ? ownDraftOrSaved
              : (_roomOverrides[alertId] ?? AlertConfigOverride.empty));
    return resolveEffectiveAlertConfig(
      alertId: alertId,
      catalogOrder: definition.order,
      legacy: _legacyOverrides == null
          ? null
          : (_legacyOverrides![alertId] ?? AlertConfigOverride.empty),
      tenant: tenantArg,
      site: siteArg,
      device: deviceArg,
      room: roomArg,
    );
  }

  /// Guarda TODAS las alertas con drafts pendientes de una sola vez (botón
  /// "Guardar cambios" de la tabla — pedido del usuario 2026-09-08: editar
  /// varias filas y guardar todo junto, como una planilla, en vez de un
  /// botón Guardar por alerta).
  Future<void> _saveAllDirty() async {
    if (_drafts.isEmpty) return;
    setState(() => _savingAll = true);
    try {
      final AlertConfigScopeTarget target = AlertConfigScopeTarget(
        tenantId: _tenantId!,
        scope: _scope,
        siteId: _siteId,
        deviceId: _deviceId,
        roomId: _roomId,
      );
      for (final MapEntry<String, AlertConfigOverride> entry
          in _drafts.entries) {
        await widget.configService.saveOverride(
          target: target,
          alertId: entry.key,
          current: _ownOverrideFor(entry.key),
          desired: entry.value,
          documentExists: _ownDocumentExistsFor(entry.key),
          uid: widget.currentUserUid,
        );
      }
      _drafts.clear();
      await _reloadCurrentScopeConfig();
    } finally {
      if (mounted) setState(() => _savingAll = false);
    }
  }

  Future<void> _reloadCurrentScopeConfig() async {
    final AlertConfigScopeTarget target = AlertConfigScopeTarget(
      tenantId: _tenantId!,
      scope: _scope,
      siteId: _siteId,
      deviceId: _deviceId,
      roomId: _roomId,
    );
    final Map<String, AlertConfigOverride> fresh = await widget.configService
        .loadScopeOverrides(target);
    if (!mounted) return;
    setState(() {
      switch (_scope) {
        case AlertConfigScope.tenant:
          _tenantOverrides = fresh;
          break;
        case AlertConfigScope.site:
          _siteOverrides = fresh;
          break;
        case AlertConfigScope.device:
          _deviceOverrides = fresh;
          break;
        case AlertConfigScope.room:
          _roomOverrides = fresh;
          break;
      }
    });
  }

  Widget _buildRecipientsSection() {
    final List<HierarchicalAlertRecipient> effective =
        resolveHierarchicalAlertRecipients(
          tenant: _tenantRecipients.values.toList(),
          site: _siteId != null ? _siteRecipients.values.toList() : null,
          device: _deviceId != null ? _deviceRecipients.values.toList() : null,
          room: _roomId != null ? _roomRecipients.values.toList() : null,
        );
    return HierarchicalRecipientsSection(
      scope: _scope,
      scopeName: _scopeTargetLabel,
      canEdit: _canEdit,
      effectiveRecipients: effective,
      ownScopeRecipients: _recipientsForCurrentScope(),
      onAdd: _addRecipient,
      onSetEnabled: _setRecipientEnabled,
      onDelete: _deleteRecipient,
    );
  }

  Map<String, AlertRecipientOverride> _recipientsForCurrentScope() {
    return switch (_scope) {
      AlertConfigScope.tenant => _tenantRecipients,
      AlertConfigScope.site => _siteRecipients,
      AlertConfigScope.device => _deviceRecipients,
      AlertConfigScope.room => _roomRecipients,
    };
  }

  AlertRecipientScopeTarget get _recipientTarget => AlertRecipientScopeTarget(
    tenantId: _tenantId!,
    scope: _scope,
    siteId: _siteId,
    deviceId: _deviceId,
    roomId: _roomId,
  );

  Future<String?> _addRecipient({
    required String displayName,
    required String phoneE164,
  }) async {
    final String recipientId = normalizeAlertRecipientPhoneE164(
      phoneE164,
    ).replaceAll(RegExp(r'[^0-9]'), '');
    if (recipientId.isEmpty) {
      return 'Teléfono inválido.';
    }
    try {
      await widget.recipientsService.addRecipient(
        target: _recipientTarget,
        recipientId: recipientId,
        displayName: displayName,
        phoneE164: phoneE164,
        enabled: true,
        uid: widget.currentUserUid,
      );
      await _reloadCurrentScopeRecipients();
      return null;
    } catch (error) {
      return describeFirestoreError(error);
    }
  }

  Future<void> _setRecipientEnabled(String recipientId, bool enabled) async {
    await widget.recipientsService.setEnabled(
      target: _recipientTarget,
      recipientId: recipientId,
      enabled: enabled,
      uid: widget.currentUserUid,
    );
    await _reloadCurrentScopeRecipients();
  }

  Future<void> _deleteRecipient(String recipientId) async {
    await widget.recipientsService.deleteRecipient(
      target: _recipientTarget,
      recipientId: recipientId,
    );
    await _reloadCurrentScopeRecipients();
  }

  Future<void> _reloadCurrentScopeRecipients() async {
    final List<AlertRecipientOverride> fresh = await widget.recipientsService
        .loadScopeRecipients(_recipientTarget);
    if (!mounted) return;
    setState(() {
      final Map<String, AlertRecipientOverride> byId = _byId(fresh);
      switch (_scope) {
        case AlertConfigScope.tenant:
          _tenantRecipients = byId;
          break;
        case AlertConfigScope.site:
          _siteRecipients = byId;
          break;
        case AlertConfigScope.device:
          _deviceRecipients = byId;
          break;
        case AlertConfigScope.room:
          _roomRecipients = byId;
          break;
      }
    });
  }
}

class _TenantDropdown extends StatelessWidget {
  const _TenantDropdown({
    required this.isOwner,
    required this.tenants,
    required this.loading,
    required this.error,
    required this.value,
    required this.onChanged,
  });

  final bool isOwner;
  final List<AgroTenant> tenants;
  final bool loading;
  final String? error;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!isOwner) {
      return _StaticScopeField(label: 'Tenant', value: value ?? '—');
    }
    if (loading) {
      return const _StaticScopeField(label: 'Tenant', value: 'Cargando…');
    }
    if (error != null) {
      return _StaticScopeField(label: 'Tenant', value: 'Error: $error');
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Tenant'),
      items: [
        for (final AgroTenant tenant in tenants)
          DropdownMenuItem(
            value: tenant.id,
            child: Text(tenant.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ScopeDropdown<T> extends StatelessWidget {
  const _ScopeDropdown({
    required this.label,
    required this.noneLabel,
    required this.items,
    required this.idOf,
    required this.labelOf,
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String label;

  /// Texto de la opción "sin selección" — deliberadamente NO dice "Todo el
  /// {label}" (sonaba a "agregado de todos los {label}", lo que confundía
  /// con la union de todos los devices en vez de "quedate en el nivel
  /// padre", que es lo que realmente hace).
  final String noneLabel;
  final List<T> items;
  final String Function(T) idOf;
  final String Function(T) labelOf;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return _StaticScopeField(label: label, value: '—');
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(noneLabel, overflow: TextOverflow.ellipsis),
        ),
        for (final T item in items)
          DropdownMenuItem(
            value: idOf(item),
            child: Text(labelOf(item), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _StaticScopeField extends StatelessWidget {
  const _StaticScopeField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Text(value),
    );
  }
}

class _InheritanceNote extends StatelessWidget {
  const _InheritanceNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF94A3B8))),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF3B1D1D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFEF4444)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Error al cargar: $message',
                style: const TextStyle(color: Color(0xFFFCA5A5)),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
