import 'package:flutter/material.dart';

import '../models/agro_device.dart';
import '../models/agro_device_room.dart';
import '../models/agro_device_type_catalog.dart';
import '../models/agro_sector.dart';
import '../models/agro_site.dart';
import '../models/agro_tenant.dart';
import '../services/agro_device_provisioning_service.dart';
import '../services/agro_device_room_service.dart';
import '../services/agro_device_service.dart';
import '../services/agro_sector_service.dart';
import '../services/agro_site_service.dart';
import '../services/agro_tenant_service.dart';
import '../services/firestore_error_messages.dart';
import '../services/global_board_configuration_service.dart';
import '../services/structural_id_helpers.dart';
import 'device_board_config_page.dart';

/// Status filter for the tenant list — operates purely in memory over the
/// already-fetched list, never triggers another Firestore read.
enum TenantStatusFilter { all, active, inactive }

/// Pure, Firestore-free: filters [tenants] by [filter] and then by [query]
/// (case-insensitive substring match against name OR id). Extracted as a
/// standalone function so search/filter behavior is unit-testable without
/// pumping a widget or touching Firestore.
List<AgroTenant> filterTenants(
  List<AgroTenant> tenants, {
  required String query,
  required TenantStatusFilter filter,
}) {
  final String normalizedQuery = query.trim().toLowerCase();
  return tenants
      .where((AgroTenant tenant) {
        final bool matchesFilter = switch (filter) {
          TenantStatusFilter.all => true,
          TenantStatusFilter.active => tenant.active,
          TenantStatusFilter.inactive => !tenant.active,
        };
        if (!matchesFilter) {
          return false;
        }
        if (normalizedQuery.isEmpty) {
          return true;
        }
        return tenant.name.toLowerCase().contains(normalizedQuery) ||
            tenant.id.toLowerCase().contains(normalizedQuery);
      })
      .toList(growable: false);
}

enum _TenantsLoadState { loading, loaded, error }

enum _StructureLoadState { idle, loading, loaded, error }

/// "Configuración → Administración → Gestión de clientes" — a real page
/// (pushed via `Navigator.push`, not a dialog), owner-only. Lists existing
/// tenants and lets an owner view/edit their general info (name, active)
/// and browse their Site/Sector/Device structure read-only.
///
/// Explicitly NOT in scope here (see the Etapa 2 delivery report): adding
/// new sites/sectors/devices/rooms, editing sites/sectors/devices, a device
/// type catalog, or refreshing the live operational dashboard.
class TenantManagementPage extends StatefulWidget {
  const TenantManagementPage({
    super.key,
    this.tenantService = const AgroTenantService(),
    this.siteService = const AgroSiteService(),
    this.sectorService = const AgroSectorService(),
    this.deviceService = const AgroDeviceService(),
    this.roomService = const AgroDeviceRoomService(),
    this.provisioningService = const AgroDeviceProvisioningService(),
  });

  final AgroTenantService tenantService;
  final AgroSiteService siteService;
  final AgroSectorService sectorService;
  final AgroDeviceService deviceService;
  final AgroDeviceRoomService roomService;
  final AgroDeviceProvisioningService provisioningService;

  @override
  State<TenantManagementPage> createState() => _TenantManagementPageState();
}

class _TenantManagementPageState extends State<TenantManagementPage> {
  _TenantsLoadState _tenantsState = _TenantsLoadState.loading;
  List<AgroTenant> _tenants = const <AgroTenant>[];
  String? _tenantsErrorMessage;

  // Owned here (not created inline in `_TenantListPanel.build()`) so its
  // identity survives rebuilds — a controller recreated on every keystroke
  // would reset the cursor to the end of the field after each character,
  // making it impossible to edit anywhere but the end of the query.
  final TextEditingController _searchController = TextEditingController();
  TenantStatusFilter _filter = TenantStatusFilter.all;

  AgroTenant? _selectedTenant;
  _StructureLoadState _structureState = _StructureLoadState.idle;
  List<AgroSite> _sites = const <AgroSite>[];
  List<AgroSector> _sectors = const <AgroSector>[];
  List<AgroDevice> _devices = const <AgroDevice>[];
  String? _structureErrorMessage;

  // "Seleccionar o destacar el site/sector recién creado" — set right
  // after a successful create, consumed by `_SiteTile` to auto-expand.
  // Intentionally not cleared automatically: the highlight naturally stops
  // mattering once the admin navigates away (clears with `_clearSelection`)
  // or creates something else (overwritten).
  String? _highlightSiteId;
  String? _highlightSectorId;
  String? _highlightDeviceId;

  @override
  void initState() {
    super.initState();
    _loadTenants();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Tenants list ──────────────────────────────────────────────────────

  Future<void> _loadTenants() async {
    setState(() {
      _tenantsState = _TenantsLoadState.loading;
      _tenantsErrorMessage = null;
    });
    try {
      final List<AgroTenant> tenants = await widget.tenantService
          .listTenantsForAdministration();
      if (!mounted) return;
      setState(() {
        _tenants = tenants;
        _tenantsState = _TenantsLoadState.loaded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tenantsErrorMessage =
            'No se pudo cargar la lista de tenants: ${describeFirestoreError(error)}';
        _tenantsState = _TenantsLoadState.error;
      });
    }
  }

  /// "Actualizar" on the list: invalidates the tenant cache, re-fetches, and
  /// keeps the current selection if that tenant still exists in the fresh
  /// list — never touches any other tenant's structure.
  Future<void> _refreshTenants() async {
    widget.tenantService.invalidateCache();
    final String? previouslySelectedId = _selectedTenant?.id;
    await _loadTenants();
    if (!mounted || previouslySelectedId == null) return;
    final AgroTenant? stillExists = _tenants
        .where((AgroTenant t) => t.id == previouslySelectedId)
        .cast<AgroTenant?>()
        .firstWhere((_) => true, orElse: () => null);
    setState(() => _selectedTenant = stillExists);
  }

  // ── Selected tenant's structure ───────────────────────────────────────

  Future<void> _selectTenant(AgroTenant tenant) async {
    setState(() {
      _selectedTenant = tenant;
      _structureState = _StructureLoadState.loading;
      _structureErrorMessage = null;
    });
    await _loadStructure(tenant.id);
  }

  void _clearSelection() {
    setState(() {
      _selectedTenant = null;
      _structureState = _StructureLoadState.idle;
      _sites = const <AgroSite>[];
      _sectors = const <AgroSector>[];
      _devices = const <AgroDevice>[];
      _highlightSiteId = null;
      _highlightSectorId = null;
      _highlightDeviceId = null;
    });
  }

  Future<void> _loadStructure(String tenantId) async {
    try {
      // Exactly 3 grouped queries, scoped to this tenant only — never a
      // query per site/sector/device, never for a tenant the admin didn't
      // open. Rooms and live snapshots are intentionally not loaded here.
      final List<AgroSite> sites = await widget.siteService.listByTenant(
        tenantId,
      );
      final List<AgroSector> sectors = await widget.sectorService.listByTenant(
        tenantId,
      );
      final List<AgroDevice> devices = await widget.deviceService.listByTenant(
        tenantId,
      );
      if (!mounted || _selectedTenant?.id != tenantId) return;
      setState(() {
        _sites = sites;
        _sectors = sectors;
        _devices = devices;
        _structureState = _StructureLoadState.loaded;
      });
    } catch (error) {
      if (!mounted || _selectedTenant?.id != tenantId) return;
      setState(() {
        _structureErrorMessage =
            'No se pudo cargar la estructura: ${describeFirestoreError(error)}';
        _structureState = _StructureLoadState.error;
      });
    }
  }

  Future<void> _refreshStructure() async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    widget.siteService.invalidateCache(tenantId: tenant.id);
    widget.sectorService.invalidateCache(tenantId: tenant.id);
    widget.deviceService.invalidateCache(tenantId: tenant.id);
    setState(() => _structureState = _StructureLoadState.loading);
    await _loadStructure(tenant.id);
  }

  /// Re-fetches only the currently selected tenant's structure — used after
  /// any Site/Sector write. Never touches other tenants' cached lists.
  Future<void> _finishStructureRefresh(String successMessage) async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
    setState(() => _structureState = _StructureLoadState.loading);
    await _loadStructure(tenant.id);
  }

  // ── Sites ────────────────────────────────────────────────────────────

  Future<void> _addSite() async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    final String? newSiteId = await showDialog<String>(
      context: context,
      builder: (context) =>
          _AddSiteDialog(siteService: widget.siteService, tenantId: tenant.id),
    );
    if (newSiteId == null || !mounted) return;
    widget.siteService.invalidateCache(tenantId: tenant.id);
    setState(() {
      _highlightSiteId = newSiteId;
      // Clear any Sector/Device highlight left over from a PREVIOUS add —
      // otherwise `_SiteTile.initiallyExpanded` (which also checks
      // `highlightSectorId`/`highlightDeviceId` against ITS OWN children)
      // can force-expand a completely unrelated Site that happens to
      // contain a Sector/Device with a matching id from an earlier action.
      _highlightSectorId = null;
      _highlightDeviceId = null;
    });
    await _finishStructureRefresh('Site creado.');
  }

  Future<void> _editSite(AgroSite site) async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    if (site.isLegacyStructure) {
      // Defense-in-depth: the "Editar" action is already hidden for legacy
      // sites in the UI, but don't rely solely on that — see the class doc
      // comment on `_SiteTile` for the full convivencia decision.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se puede editar una estructura legacy.'),
        ),
      );
      return;
    }
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EditSiteDialog(
        siteService: widget.siteService,
        tenantId: tenant.id,
        site: site,
      ),
    );
    if (saved != true || !mounted) return;
    widget.siteService.invalidateCache(tenantId: tenant.id);
    await _finishStructureRefresh('Site actualizado.');
  }

  Future<void> _toggleSiteEnabled(AgroSite site, bool nextEnabled) async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    if (site.isLegacyStructure) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se puede editar una estructura legacy.'),
        ),
      );
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildToggleEnabledDialog(
        entityKind: 'site',
        entityName: site.name.isEmpty ? site.id : site.name,
        activating: nextEnabled,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      // Always resend the current name/description — AgroSiteService.update
      // has no partial-per-field mode for these two, only provisioningStatus
      // is optional-and-preserved. Omitting description here would blank it.
      await widget.siteService.update(
        tenantId: tenant.id,
        siteId: site.id,
        name: site.name,
        description: site.description,
        enabled: nextEnabled,
      );
      if (!mounted) return;
      widget.siteService.invalidateCache(tenantId: tenant.id);
      await _finishStructureRefresh('Site actualizado.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: ${describeFirestoreError(error)}'),
        ),
      );
    }
  }

  // ── Sectors ──────────────────────────────────────────────────────────

  Future<void> _addSector(AgroSite site) async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    final String? newSectorId = await showDialog<String>(
      context: context,
      builder: (context) => _AddSectorDialog(
        sectorService: widget.sectorService,
        tenantId: tenant.id,
        site: site,
      ),
    );
    if (newSectorId == null || !mounted) return;
    widget.sectorService.invalidateCache(tenantId: tenant.id, siteId: site.id);
    setState(() {
      _highlightSiteId = site.id;
      _highlightSectorId = newSectorId;
      // Same reasoning as `_addSite`: a stale Device highlight from a
      // previous action could otherwise force-expand an unrelated Site.
      _highlightDeviceId = null;
    });
    await _finishStructureRefresh('Sector creado.');
  }

  Future<void> _editSector(AgroSector sector) async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EditSectorDialog(
        sectorService: widget.sectorService,
        tenantId: tenant.id,
        sector: sector,
      ),
    );
    if (saved != true || !mounted) return;
    widget.sectorService.invalidateCache(
      tenantId: tenant.id,
      siteId: sector.siteId,
    );
    await _finishStructureRefresh('Sector actualizado.');
  }

  Future<void> _toggleSectorEnabled(AgroSector sector, bool nextEnabled) async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildToggleEnabledDialog(
        entityKind: 'sector',
        entityName: sector.name.isEmpty ? sector.id : sector.name,
        activating: nextEnabled,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.sectorService.update(
        tenantId: tenant.id,
        sectorId: sector.id,
        name: sector.name,
        description: sector.description,
        enabled: nextEnabled,
      );
      if (!mounted) return;
      widget.sectorService.invalidateCache(
        tenantId: tenant.id,
        siteId: sector.siteId,
      );
      await _finishStructureRefresh('Sector actualizado.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: ${describeFirestoreError(error)}'),
        ),
      );
    }
  }

  // ── Devices ──────────────────────────────────────────────────────────
  //
  // Unlike Sites, Devices are never legacy — the legacy PLC LOGO! schema
  // lives entirely under `sites/{siteId}/plcs/{plcId}`, never in this
  // `devices` collection. So, unlike `_editSite`/`_toggleSiteEnabled`,
  // none of the handlers below check `site.isLegacyStructure`: a Device
  // (and its Sectors) under a legacy Site is exactly as manageable as one
  // under a brand new Site. See `_SiteTile`'s doc comment for the Etapa 4
  // correction of the Etapa 3 restriction that used to (incorrectly) hide
  // "Agregar sector"/"Agregar device" under legacy Sites too.

  Future<void> _addDevice(AgroSite site) async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    final List<AgroSector> siteSectors = _sectors
        .where((AgroSector s) => s.siteId == site.id)
        .toList(growable: false);
    final String? newDeviceId = await showDialog<String>(
      context: context,
      builder: (context) => _AddDeviceDialog(
        deviceService: widget.deviceService,
        provisioningService: widget.provisioningService,
        tenantId: tenant.id,
        site: site,
        availableSectors: siteSectors,
      ),
    );
    if (newDeviceId == null || !mounted) return;
    widget.deviceService.invalidateCache(tenantId: tenant.id, siteId: site.id);
    setState(() {
      _highlightSiteId = site.id;
      _highlightDeviceId = newDeviceId;
      // Same reasoning as `_addSite`: a stale Sector highlight from a
      // previous action could otherwise force-expand an unrelated Site.
      _highlightSectorId = null;
    });
    await _finishStructureRefresh('Device creado.');
  }

  Future<void> _editDevice(AgroDevice device) async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    final List<AgroSector> siteSectors = _sectors
        .where((AgroSector s) => s.siteId == device.siteId)
        .toList(growable: false);
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EditDeviceDialog(
        deviceService: widget.deviceService,
        tenantId: tenant.id,
        device: device,
        availableSectors: siteSectors,
      ),
    );
    if (saved != true || !mounted) return;
    widget.deviceService.invalidateCache(tenantId: tenant.id);
    await _finishStructureRefresh('Device actualizado.');
  }

  Future<void> _toggleDeviceEnabled(AgroDevice device, bool nextEnabled) async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildToggleEnabledDialog(
        entityKind: 'device',
        entityName: device.name.isEmpty ? device.id : device.name,
        activating: nextEnabled,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.deviceService.update(
        tenantId: tenant.id,
        deviceId: device.id,
        siteId: device.siteId,
        name: device.name,
        type: device.type,
        model: device.model,
        description: device.description,
        enabled: nextEnabled,
        sortOrder: device.sortOrder,
        snapshotUnitKey: device.snapshotUnitKey,
        sectorIds: device.sectorIds,
      );
      if (!mounted) return;
      widget.deviceService.invalidateCache(tenantId: tenant.id);
      await _finishStructureRefresh('Device actualizado.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: ${describeFirestoreError(error)}'),
        ),
      );
    }
  }

  // ── Edit / enable-disable ─────────────────────────────────────────────

  Future<void> _editName() async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EditTenantNameDialog(
        tenantService: widget.tenantService,
        tenantId: tenant.id,
        initialName: tenant.name,
        active: tenant.active,
      ),
    );
    if (saved != true || !mounted) return;
    await _afterTenantWrite('Tenant actualizado.');
  }

  Future<void> _toggleActive(bool nextActive) async {
    final AgroTenant? tenant = _selectedTenant;
    if (tenant == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildToggleEnabledDialog(
        entityKind: 'tenant',
        entityName: tenant.name,
        activating: nextActive,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.tenantService.updateTenant(
        tenantId: tenant.id,
        name: tenant.name,
        active: nextActive,
      );
      if (!mounted) return;
      await _afterTenantWrite('Tenant actualizado.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: ${describeFirestoreError(error)}'),
        ),
      );
    }
  }

  Future<void> _afterTenantWrite(String successMessage) async {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
    await _refreshTenants();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de clientes')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth >= 900;
          final Widget listPanel = _TenantListPanel(
            state: _tenantsState,
            errorMessage: _tenantsErrorMessage,
            tenants: filterTenants(
              _tenants,
              query: _searchController.text,
              filter: _filter,
            ),
            selectedTenantId: _selectedTenant?.id,
            searchController: _searchController,
            filter: _filter,
            onSearchChanged: () => setState(() {}),
            onFilterChanged: (value) => setState(() => _filter = value),
            onSelect: _selectTenant,
            onRefresh: _refreshTenants,
          );

          if (!isWide) {
            if (_selectedTenant == null) {
              return listPanel;
            }
            return _TenantDetailPanel(
              tenant: _selectedTenant!,
              structureState: _structureState,
              structureErrorMessage: _structureErrorMessage,
              sites: _sites,
              sectors: _sectors,
              devices: _devices,
              highlightSiteId: _highlightSiteId,
              highlightSectorId: _highlightSectorId,
              highlightDeviceId: _highlightDeviceId,
              onBack: _clearSelection,
              onEditName: _editName,
              onToggleActive: _toggleActive,
              onRefreshStructure: _refreshStructure,
              onAddSite: _addSite,
              onEditSite: _editSite,
              onToggleSiteEnabled: _toggleSiteEnabled,
              onAddSector: _addSector,
              onEditSector: _editSector,
              onToggleSectorEnabled: _toggleSectorEnabled,
              onAddDevice: _addDevice,
              onEditDevice: _editDevice,
              onToggleDeviceEnabled: _toggleDeviceEnabled,
              tenantId: _selectedTenant!.id,
              roomService: widget.roomService,
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 360, child: listPanel),
              const VerticalDivider(width: 1, color: Color(0xFF334155)),
              Expanded(
                child: _selectedTenant == null
                    ? const _NoTenantSelectedPlaceholder()
                    : _TenantDetailPanel(
                        tenant: _selectedTenant!,
                        structureState: _structureState,
                        structureErrorMessage: _structureErrorMessage,
                        sites: _sites,
                        sectors: _sectors,
                        devices: _devices,
                        highlightSiteId: _highlightSiteId,
                        highlightSectorId: _highlightSectorId,
                        highlightDeviceId: _highlightDeviceId,
                        onEditName: _editName,
                        onToggleActive: _toggleActive,
                        onRefreshStructure: _refreshStructure,
                        onAddSite: _addSite,
                        onEditSite: _editSite,
                        onToggleSiteEnabled: _toggleSiteEnabled,
                        onAddSector: _addSector,
                        onEditSector: _editSector,
                        onToggleSectorEnabled: _toggleSectorEnabled,
                        onAddDevice: _addDevice,
                        onEditDevice: _editDevice,
                        onToggleDeviceEnabled: _toggleDeviceEnabled,
                        tenantId: _selectedTenant!.id,
                        roomService: widget.roomService,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TenantListPanel extends StatelessWidget {
  const _TenantListPanel({
    required this.state,
    required this.errorMessage,
    required this.tenants,
    required this.selectedTenantId,
    required this.searchController,
    required this.filter,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onSelect,
    required this.onRefresh,
  });

  final _TenantsLoadState state;
  final String? errorMessage;
  final List<AgroTenant> tenants;
  final String? selectedTenantId;
  // Owned by the parent State (not created here) so its identity — and the
  // user's cursor position — survives rebuilds triggered on every keystroke.
  final TextEditingController searchController;
  final TenantStatusFilter filter;
  final VoidCallback onSearchChanged;
  final ValueChanged<TenantStatusFilter> onFilterChanged;
  final ValueChanged<AgroTenant> onSelect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Tenants',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: () => onRefresh(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Buscar por nombre o Tenant ID',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => onSearchChanged(),
            controller: searchController,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: filter == TenantStatusFilter.all,
                onSelected: (_) => onFilterChanged(TenantStatusFilter.all),
              ),
              ChoiceChip(
                label: const Text('Activos'),
                selected: filter == TenantStatusFilter.active,
                onSelected: (_) => onFilterChanged(TenantStatusFilter.active),
              ),
              ChoiceChip(
                label: const Text('Inactivos'),
                selected: filter == TenantStatusFilter.inactive,
                onSelected: (_) => onFilterChanged(TenantStatusFilter.inactive),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (state) {
      case _TenantsLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case _TenantsLoadState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              errorMessage ?? 'Error al cargar tenants.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        );
      case _TenantsLoadState.loaded:
        if (tenants.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No hay tenants que coincidan con la búsqueda/filtro.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: tenants.length,
          itemBuilder: (context, index) {
            final AgroTenant tenant = tenants[index];
            return _TenantListTile(
              tenant: tenant,
              selected: tenant.id == selectedTenantId,
              onTap: () => onSelect(tenant),
            );
          },
        );
    }
  }
}

class _TenantListTile extends StatelessWidget {
  const _TenantListTile({
    required this.tenant,
    required this.selected,
    required this.onTap,
  });

  final AgroTenant tenant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: const Color(0xFF1E293B),
      onTap: onTap,
      leading: _TenantStatusDot(active: tenant.active),
      title: Text(tenant.name.isEmpty ? tenant.id : tenant.name),
      subtitle: Text(
        tenant.id,
        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }
}

class _TenantStatusDot extends StatelessWidget {
  const _TenantStatusDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? const Color(0xFF22C55E) : const Color(0xFF6B7280),
      ),
    );
  }
}

class _NoTenantSelectedPlaceholder extends StatelessWidget {
  const _NoTenantSelectedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Seleccioná un tenant de la lista para ver su información.',
        style: TextStyle(color: Color(0xFF94A3B8)),
      ),
    );
  }
}

class _TenantDetailPanel extends StatelessWidget {
  const _TenantDetailPanel({
    required this.tenant,
    required this.structureState,
    required this.structureErrorMessage,
    required this.sites,
    required this.sectors,
    required this.devices,
    required this.onEditName,
    required this.onToggleActive,
    required this.onRefreshStructure,
    required this.onAddSite,
    required this.onEditSite,
    required this.onToggleSiteEnabled,
    required this.onAddSector,
    required this.onEditSector,
    required this.onToggleSectorEnabled,
    required this.onAddDevice,
    required this.onEditDevice,
    required this.onToggleDeviceEnabled,
    required this.tenantId,
    required this.roomService,
    this.highlightSiteId,
    this.highlightSectorId,
    this.highlightDeviceId,
    this.onBack,
  });

  final AgroTenant tenant;
  final _StructureLoadState structureState;
  final String? structureErrorMessage;
  final List<AgroSite> sites;
  final List<AgroSector> sectors;
  final List<AgroDevice> devices;
  final String? highlightSiteId;
  final String? highlightSectorId;
  final String? highlightDeviceId;
  final VoidCallback onEditName;
  final ValueChanged<bool> onToggleActive;
  final Future<void> Function() onRefreshStructure;
  final VoidCallback onAddSite;
  final ValueChanged<AgroSite> onEditSite;
  final void Function(AgroSite site, bool enabled) onToggleSiteEnabled;
  final ValueChanged<AgroSite> onAddSector;
  final ValueChanged<AgroSector> onEditSector;
  final void Function(AgroSector sector, bool enabled) onToggleSectorEnabled;
  final ValueChanged<AgroSite> onAddDevice;
  final ValueChanged<AgroDevice> onEditDevice;
  final void Function(AgroDevice device, bool enabled) onToggleDeviceEnabled;
  final String tenantId;
  final AgroDeviceRoomService roomService;
  final VoidCallback? onBack;

  bool get _hasLegacyStructure =>
      sites.any((AgroSite site) => site.isLegacyStructure);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onBack != null) ...[
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Volver a la lista'),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tenant.name.isEmpty ? tenant.id : tenant.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onEditName,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Editar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _ReadOnlyField(label: 'Tenant ID', value: tenant.id),
                  _ReadOnlyField(
                    label: 'Creado por',
                    value: tenant.createdByUid,
                  ),
                  if (tenant.createdByEmail != null)
                    _ReadOnlyField(
                      label: 'Email de creación',
                      value: tenant.createdByEmail!,
                    ),
                  _ReadOnlyField(
                    label: 'Creado',
                    value: _formatDate(tenant.createdAt),
                  ),
                  _ReadOnlyField(
                    label: 'Actualizado',
                    value: _formatDate(tenant.updatedAt),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        tenant.active ? 'Activo' : 'Inactivo',
                        style: TextStyle(
                          color: tenant.active
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Switch(value: tenant.active, onChanged: onToggleActive),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_hasLegacyStructure)
            Card(
              color: const Color(0xFF3F2D12),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.history, color: Color(0xFFF59E0B), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Este cliente contiene dispositivos legacy '
                        'administrados únicamente para compatibilidad.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_hasLegacyStructure) const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Estructura',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onAddSite,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Agregar site'),
              ),
              IconButton(
                tooltip: 'Actualizar estructura',
                onPressed: () => onRefreshStructure(),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          _buildStructureBody(context),
        ],
      ),
    );
  }

  Widget _buildStructureBody(BuildContext context) {
    switch (structureState) {
      case _StructureLoadState.idle:
      case _StructureLoadState.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      case _StructureLoadState.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            structureErrorMessage ?? 'Error al cargar la estructura.',
            style: const TextStyle(color: Color(0xFFEF4444)),
          ),
        );
      case _StructureLoadState.loaded:
        if (sites.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Este tenant todavía no tiene sites.',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          );
        }
        return Column(
          children: [
            for (final AgroSite site in sites)
              _SiteTile(
                site: site,
                sectors: sectors
                    .where((AgroSector s) => s.siteId == site.id)
                    .toList(growable: false),
                devices: devices
                    .where((AgroDevice d) => d.siteId == site.id)
                    .toList(growable: false),
                highlighted: site.id == highlightSiteId,
                highlightSectorId: highlightSectorId,
                highlightDeviceId: highlightDeviceId,
                onEdit: () => onEditSite(site),
                onToggleEnabled: (value) => onToggleSiteEnabled(site, value),
                onAddSector: () => onAddSector(site),
                onEditSector: onEditSector,
                onToggleSectorEnabled: onToggleSectorEnabled,
                onAddDevice: () => onAddDevice(site),
                onEditDevice: onEditDevice,
                onToggleDeviceEnabled: onToggleDeviceEnabled,
                tenantId: tenantId,
                roomService: roomService,
              ),
          ],
        );
    }
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return 'Sin datos';
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One Site, expandable to show its Sectores/Devices.
///
/// Only the Site document ITSELF is ever legacy
/// ([AgroSite.isLegacyStructure]) — its own name/description/enabled/
/// provisioningStatus stay strictly read-only ([siteFieldsEditable] gates
/// "Editar" + the enable switch). Sectors and Devices are a different
/// story: nothing under `sectors`/`devices` is ever legacy — the legacy
/// PLC LOGO! schema lives entirely under `sites/{siteId}/plcs/{plcId}`,
/// a collection this screen never reads or writes. So "Agregar sector",
/// "Agregar device", and every Sector/Device's own Editar/enable-switch
/// are available under EVERY Site, including legacy ones — this is the
/// Etapa 4 correction of an Etapa 3 restriction that (incorrectly) hid
/// those too whenever the parent Site was legacy.
///
/// None of this is a data or Firestore-rules restriction to begin with —
/// `existsAfter()` in firestore.rules only checks that a Site DOCUMENT
/// exists at `siteId`, with zero awareness of whether that document has a
/// stored `provisioningStatus` (new schema) or not (legacy, e.g.
/// `the-gene-pig`/`genetica-1`). A brand new Sector or Device with
/// `siteId: 'genetica-1'` is already valid today, confirmed by reading the
/// rules and the real document (see the Etapa 3 delivery report, §8).
class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.site,
    required this.sectors,
    required this.devices,
    required this.onEdit,
    required this.onToggleEnabled,
    required this.onAddSector,
    required this.onEditSector,
    required this.onToggleSectorEnabled,
    required this.onAddDevice,
    required this.onEditDevice,
    required this.onToggleDeviceEnabled,
    required this.tenantId,
    required this.roomService,
    this.highlighted = false,
    this.highlightSectorId,
    this.highlightDeviceId,
  });

  final AgroSite site;
  final List<AgroSector> sectors;
  final List<AgroDevice> devices;
  final bool highlighted;
  final String? highlightSectorId;
  final String? highlightDeviceId;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onAddSector;
  final ValueChanged<AgroSector> onEditSector;
  final void Function(AgroSector sector, bool enabled) onToggleSectorEnabled;
  final VoidCallback onAddDevice;
  final ValueChanged<AgroDevice> onEditDevice;
  final void Function(AgroDevice device, bool enabled) onToggleDeviceEnabled;
  final String tenantId;
  final AgroDeviceRoomService roomService;

  @override
  Widget build(BuildContext context) {
    final bool siteFieldsEditable = !site.isLegacyStructure;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ExpansionTile(
        initiallyExpanded:
            highlighted ||
            (highlightSectorId != null &&
                sectors.any((AgroSector s) => s.id == highlightSectorId)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                site.name.isEmpty ? site.id : site.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (site.isLegacyStructure)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: _Badge(label: 'Legacy', color: Color(0xFFF59E0B)),
              ),
            if (!site.enabled)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: _Badge(label: 'Deshabilitado', color: Color(0xFF6B7280)),
              ),
            if (siteFieldsEditable) ...[
              IconButton(
                tooltip: 'Editar site',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              Switch(value: site.enabled, onChanged: onToggleEnabled),
            ],
          ],
        ),
        subtitle: Text(
          '${site.id} · ${SiteProvisioningStatus.label(site.provisioningStatus)} · '
          '${sectors.length} sectores · ${devices.length} devices',
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                const Text(
                  'Sectores',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAddSector,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text(
                    'Agregar sector',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),
          if (sectors.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Este site todavía no tiene sectores.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
              ),
            )
          else
            for (final AgroSector sector in sectors)
              ListTile(
                dense: true,
                title: Text(sector.name.isEmpty ? sector.id : sector.name),
                subtitle: Text(sector.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!sector.enabled)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: _Badge(
                          label: 'Deshabilitado',
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Editar sector',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onEditSector(sector),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    Switch(
                      value: sector.enabled,
                      onChanged: (value) =>
                          onToggleSectorEnabled(sector, value),
                    ),
                  ],
                ),
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Text(
                  'Devices',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAddDevice,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text(
                    'Agregar device',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Este site todavía no tiene devices.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
              ),
            )
          else
            for (final AgroDevice device in devices)
              _DeviceTile(
                tenantId: tenantId,
                device: device,
                roomService: roomService,
                highlighted: device.id == highlightDeviceId,
                onEdit: () => onEditDevice(device),
                onToggleEnabled: (value) =>
                    onToggleDeviceEnabled(device, value),
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

enum _RoomsLoadState { idle, loading, loaded, error }

/// One Device, expandable to show its Rooms. Unlike Sites/Sectors, Rooms
/// are loaded on demand — only when THIS tile is expanded, never up front
/// for every Device in the Site (see the Etapa 4 report §15: at most 1
/// extra query per Device the admin actually opens, never a query per
/// Device just for being listed).
///
/// Room add/edit/enable-disable are handled entirely inside this widget
/// (its own dialogs, its own Firestore calls via [roomService], its own
/// error `SnackBar`, its own reload-after-write) rather than bubbling up
/// to `_TenantManagementPageState` — Rooms never affect anything outside
/// this one Device's subtree (no cross-tenant/cross-site highlight or
/// reload is ever needed for them), so routing every write through the
/// page's shared handlers would only add plumbing without benefit.
class _DeviceTile extends StatefulWidget {
  const _DeviceTile({
    required this.tenantId,
    required this.device,
    required this.roomService,
    required this.onEdit,
    required this.onToggleEnabled,
    this.highlighted = false,
  });

  final String tenantId;
  final AgroDevice device;
  final AgroDeviceRoomService roomService;
  final bool highlighted;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleEnabled;

  @override
  State<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends State<_DeviceTile> {
  _RoomsLoadState _state = _RoomsLoadState.idle;
  List<AgroDeviceRoom> _rooms = const <AgroDeviceRoom>[];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // `ExpansionTile.initiallyExpanded` only affects the initial visual
    // state — it does NOT invoke `onExpansionChanged` — so a just-created
    // Device (rendered already expanded via `widget.highlighted`) would
    // otherwise show an empty Rooms section forever until manually
    // collapsed and re-expanded. Trigger the same on-demand load here.
    if (widget.highlighted) {
      _loadRooms();
    }
  }

  Future<void> _loadRooms() async {
    setState(() {
      _state = _RoomsLoadState.loading;
      _errorMessage = null;
    });
    try {
      final List<AgroDeviceRoom> rooms = await widget.roomService.listByDevice(
        tenantId: widget.tenantId,
        deviceId: widget.device.id,
        includeDisabled: true,
      );
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _state = _RoomsLoadState.loaded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'No se pudieron cargar las rooms: ${describeFirestoreError(error)}';
        _state = _RoomsLoadState.error;
      });
    }
  }

  Future<void> _addRoom() async {
    final String? newRoomId = await showDialog<String>(
      context: context,
      builder: (context) => _AddRoomDialog(
        roomService: widget.roomService,
        tenantId: widget.tenantId,
        device: widget.device,
      ),
    );
    if (newRoomId == null || !mounted) return;
    widget.roomService.invalidateCache(
      tenantId: widget.tenantId,
      deviceId: widget.device.id,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Room creada.')));
    await _loadRooms();
  }

  Future<void> _editRoom(AgroDeviceRoom room) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EditRoomDialog(
        roomService: widget.roomService,
        tenantId: widget.tenantId,
        room: room,
      ),
    );
    if (saved != true || !mounted) return;
    widget.roomService.invalidateCache(
      tenantId: widget.tenantId,
      deviceId: widget.device.id,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Room actualizada.')));
    await _loadRooms();
  }

  Future<void> _toggleRoomEnabled(AgroDeviceRoom room, bool nextEnabled) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildToggleEnabledDialog(
        entityKind: 'room',
        entityName: room.name.isEmpty ? room.id : room.name,
        activating: nextEnabled,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.roomService.update(
        tenantId: widget.tenantId,
        deviceId: widget.device.id,
        roomId: room.id,
        siteId: room.siteId,
        name: room.name,
        enabled: nextEnabled,
        sortOrder: room.sortOrder,
        snapshotUnitKey: room.snapshotUnitKey,
      );
      if (!mounted) return;
      widget.roomService.invalidateCache(
        tenantId: widget.tenantId,
        deviceId: widget.device.id,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Room actualizada.')));
      await _loadRooms();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: ${describeFirestoreError(error)}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AgroDevice device = widget.device;
    final AgroDeviceTypeDefinition? typeDefinition = findAgroDeviceType(
      device.type,
    );
    return Card(
      margin: const EdgeInsets.only(top: 6),
      color: widget.highlighted ? const Color(0xFF15202B) : null,
      child: ExpansionTile(
        initiallyExpanded: widget.highlighted,
        onExpansionChanged: (expanded) {
          if (expanded && _state == _RoomsLoadState.idle) {
            _loadRooms();
          }
        },
        title: Text(
          device.name.isEmpty ? device.id : device.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${device.id} · ${describeDeviceType(device.type)}'
          '${device.model.isNotEmpty ? ' · ${device.model}' : ''}'
          ' · orden ${device.sortOrder}'
          '${device.snapshotUnitKey != null ? ' · ${device.snapshotUnitKey}' : ''}'
          '${device.sectorIds.isNotEmpty ? ' · ${device.sectorIds.length} sector(es)' : ''}',
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Purely structural — never touches the backend/snapshot, just
            // "does this device's OWN metadata have a key configured".
            // Only meaningful for a no-Rooms device: a Rooms-using device's
            // own `snapshotUnitKey` is never read by the dashboard (see
            // `SnapshotUnitKeyOwner`'s doc comment), so its completeness is
            // reported per-Room instead, once expanded (see
            // `_buildRoomsBody`).
            if (device.enabled &&
                // Requires a POSITIVELY known, catalogued no-Rooms type —
                // not merely "not known to use rooms". An uncatalogued/
                // historic `type` (e.g. La Payana's real device, stored as
                // `"unknown"` by an out-of-band script) might actually
                // have Rooms of its own (it does) that this collapsed row
                // can't see without violating the on-demand-only Rooms
                // load — showing the badge there would be a false
                // "incomplete" warning on an already fully-configured
                // device. `typeDefinition == null` deliberately shows
                // nothing rather than guessing.
                typeDefinition != null &&
                !typeDefinition.usesRooms &&
                (device.snapshotUnitKey == null ||
                    device.snapshotUnitKey!.trim().isEmpty))
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: _Badge(
                  label: 'Pendiente de vincular al snapshot',
                  color: Color(0xFFF59E0B),
                ),
              ),
            if (!device.enabled)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: _Badge(label: 'Deshabilitado', color: Color(0xFF6B7280)),
              ),
            IconButton(
              key: const ValueKey('device-tile-board-config'),
              tooltip: 'Configuración de Board',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => DeviceBoardConfigPage(
                    isOwner: true,
                    tenantId: widget.tenantId,
                    device: device,
                    globalConfigurationService:
                        sharedGlobalBoardConfigurationService,
                  ),
                ),
              ),
              icon: const Icon(Icons.dashboard_customize_outlined),
            ),
            IconButton(
              tooltip: 'Editar device',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            Switch(value: device.enabled, onChanged: widget.onToggleEnabled),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Text(
                  'Rooms'
                  '${typeDefinition != null ? ' (${typeDefinition.label})' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addRoom,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text(
                    'Agregar room',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),
          _buildRoomsBody(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildRoomsBody() {
    switch (_state) {
      case _RoomsLoadState.idle:
        return const SizedBox.shrink();
      case _RoomsLoadState.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _RoomsLoadState.error:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            _errorMessage ?? 'Error al cargar las rooms.',
            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11.5),
          ),
        );
      case _RoomsLoadState.loaded:
        if (_rooms.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Este device todavía no tiene rooms — hoy actúa como una '
              'única unidad de telemetría.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
          );
        }
        final int linkedCount = _rooms
            .where(
              (AgroDeviceRoom room) =>
                  room.snapshotUnitKey != null &&
                  room.snapshotUnitKey!.trim().isNotEmpty,
            )
            .length;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                '$linkedCount de ${_rooms.length} rooms vinculadas al snapshot',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: linkedCount == _rooms.length
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFF59E0B),
                ),
              ),
            ),
            for (final AgroDeviceRoom room in _rooms)
              ListTile(
                dense: true,
                title: Text(room.name.isEmpty ? room.id : room.name),
                subtitle: Text(
                  '${room.id} · orden ${room.sortOrder}'
                  '${room.snapshotUnitKey != null ? ' · ${room.snapshotUnitKey}' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!room.enabled)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: _Badge(
                          label: 'Deshabilitado',
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Editar room',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _editRoom(room),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    Switch(
                      value: room.enabled,
                      onChanged: (value) => _toggleRoomEnabled(room, value),
                    ),
                  ],
                ),
              ),
          ],
        );
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Small preview line under an ID field showing what
/// [normalizeStructuralId] will turn the raw input into — mirrors
/// `_NormalizedIdPreview` in `user_management_page.dart` (kept as a
/// separate small widget here rather than importing that file's private
/// class across files).
class _NormalizedIdPreview extends StatelessWidget {
  const _NormalizedIdPreview({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final String normalized = normalizeStructuralId(value);
    if (value.trim().isEmpty || normalized == value.trim()) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'ID final: $normalized',
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
      ),
    );
  }
}

/// Inline error banner shown INSIDE a still-open dialog after a failed
/// save — the dialog must never pop on error, so the user's typed data
/// (and the specific reason it failed) stay visible for a retry.
class _InlineDialogError extends StatelessWidget {
  const _InlineDialogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5),
      ),
    );
  }
}

class _EditTenantNameDialog extends StatefulWidget {
  const _EditTenantNameDialog({
    required this.tenantService,
    required this.tenantId,
    required this.initialName,
    required this.active,
  });

  final AgroTenantService tenantService;
  final String tenantId;
  final String initialName;
  final bool active;

  @override
  State<_EditTenantNameDialog> createState() => _EditTenantNameDialogState();
}

class _EditTenantNameDialogState extends State<_EditTenantNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorMessage = 'El nombre del tenant es obligatorio.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.tenantService.updateTenant(
        tenantId: widget.tenantId,
        name: trimmed,
        active: widget.active,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = describeFirestoreError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar tenant'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isSaving,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          if (_errorMessage != null)
            _InlineDialogError(message: _errorMessage!),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Shared enable/disable confirmation — used for Tenant, Site, and Sector
/// alike (same shape, different copy per entity). Extracted here once it
/// was clear all three needed the exact same interaction, per "extraer
/// componentes compartidos solo cuando exista reutilización real."
class _ConfirmToggleEnabledDialog extends StatelessWidget {
  const _ConfirmToggleEnabledDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  final String title;
  final String body;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Builds the exact confirmation copy for toggling `active`/`enabled` on a
/// Tenant, Site, or Sector — the wording is deliberately specific per
/// entity (matches what was asked for verbatim), not templated from a
/// single generic sentence.
_ConfirmToggleEnabledDialog _buildToggleEnabledDialog({
  required String
  entityKind, // 'tenant' | 'site' | 'sector' | 'device' | 'room'
  required String entityName,
  required bool activating,
}) {
  final String title = switch (entityKind) {
    'tenant' => activating ? 'Habilitar tenant' : 'Deshabilitar tenant',
    'site' => activating ? 'Habilitar site' : 'Deshabilitar site',
    'sector' => activating ? 'Habilitar sector' : 'Deshabilitar sector',
    'device' => activating ? 'Habilitar device' : 'Deshabilitar device',
    _ => activating ? 'Habilitar room' : 'Deshabilitar room',
  };
  final String body = switch (entityKind) {
    'tenant' =>
      activating
          ? 'Se volverá a habilitar el acceso operativo de "$entityName" '
                'según los permisos y estados actuales de sus sites y devices.'
          : 'Al deshabilitar "$entityName" dejará de estar disponible en la '
                'operación normal. No se eliminarán sus sites, sectores, '
                'devices ni datos históricos.',
    'site' =>
      activating
          ? 'Este site volverá a estar disponible según su estado de '
                'provisioning y la configuración de sus devices.'
          : 'Al deshabilitar este site dejará de estar disponible en la '
                'operación normal. Sus sectores, devices y datos históricos '
                'no serán eliminados.',
    'sector' =>
      activating
          ? 'Este sector volverá a mostrarse en la operación normal.'
          : 'Al deshabilitar este sector dejará de mostrarse en la '
                'operación normal. No se eliminarán sus datos ni se '
                'modificarán automáticamente los devices relacionados.',
    'device' =>
      activating
          ? 'Este device volverá a mostrarse y operar normalmente.'
          : 'Al deshabilitar este device dejará de mostrarse y operar '
                'normalmente. No se eliminarán sus rooms, configuración ni '
                'datos históricos.',
    _ =>
      activating
          ? 'Esta room volverá a mostrarse en la operación normal.'
          : 'Al deshabilitar esta room dejará de mostrarse en la operación '
                'normal. No se eliminarán datos ni se modificarán otras '
                'rooms ni el device.',
  };
  return _ConfirmToggleEnabledDialog(
    title: title,
    body: body,
    confirmLabel: activating ? 'Habilitar' : 'Deshabilitar',
  );
}

class _AddSiteDialog extends StatefulWidget {
  const _AddSiteDialog({required this.siteService, required this.tenantId});

  final AgroSiteService siteService;
  final String tenantId;

  @override
  State<_AddSiteDialog> createState() => _AddSiteDialogState();
}

class _AddSiteDialogState extends State<_AddSiteDialog> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  bool _enabled = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String siteId = normalizeStructuralId(_idController.text);
    final String name = _nameController.text.trim();
    if (siteId.isEmpty) {
      setState(() => _errorMessage = 'El Site ID es obligatorio.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = 'El nombre del site es obligatorio.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.siteService.create(
        tenantId: widget.tenantId,
        siteId: siteId,
        name: name,
        description: _descController.text.trim(),
        enabled: _enabled,
      );
      if (!mounted) return;
      // Returns the normalized new Site ID so the caller can highlight it.
      Navigator.of(context).pop(siteId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = describeFirestoreError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar site'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _idController,
                enabled: !_isSaving,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Site ID'),
                onChanged: (_) => setState(() {}),
              ),
              _NormalizedIdPreview(value: _idController.text),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Habilitado'),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'El site nace con provisioningStatus "pending_backend" — '
                  'no se puede elegir otro estado en el alta.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              ),
              if (_errorMessage != null)
                _InlineDialogError(message: _errorMessage!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }
}

class _EditSiteDialog extends StatefulWidget {
  const _EditSiteDialog({
    required this.siteService,
    required this.tenantId,
    required this.site,
  });

  final AgroSiteService siteService;
  final String tenantId;
  final AgroSite site;

  @override
  State<_EditSiteDialog> createState() => _EditSiteDialogState();
}

class _EditSiteDialogState extends State<_EditSiteDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.site.name,
  );
  late final TextEditingController _descController = TextEditingController(
    text: widget.site.description,
  );
  late bool _enabled = widget.site.enabled;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'El nombre del site es obligatorio.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      // provisioningStatus is intentionally never passed here — this form
      // can never change it (see AgroSiteService.update's doc comment: an
      // omitted provisioningStatus leaves the stored value untouched).
      await widget.siteService.update(
        tenantId: widget.tenantId,
        siteId: widget.site.id,
        name: name,
        description: _descController.text.trim(),
        enabled: _enabled,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = describeFirestoreError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar site: ${widget.site.id}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Habilitado'),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              if (_errorMessage != null)
                _InlineDialogError(message: _errorMessage!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _AddSectorDialog extends StatefulWidget {
  const _AddSectorDialog({
    required this.sectorService,
    required this.tenantId,
    required this.site,
  });

  final AgroSectorService sectorService;
  final String tenantId;
  // The parent Site — preselected and NOT changeable inside this dialog,
  // per the requirement that a Sector's site can never be picked/changed
  // from a general-purpose form.
  final AgroSite site;

  @override
  State<_AddSectorDialog> createState() => _AddSectorDialogState();
}

class _AddSectorDialogState extends State<_AddSectorDialog> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  bool _enabled = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String sectorId = normalizeStructuralId(_idController.text);
    final String name = _nameController.text.trim();
    if (sectorId.isEmpty) {
      setState(() => _errorMessage = 'El Sector ID es obligatorio.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = 'El nombre del sector es obligatorio.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.sectorService.create(
        tenantId: widget.tenantId,
        sectorId: sectorId,
        siteId: widget.site.id,
        name: name,
        description: _descController.text.trim(),
        enabled: _enabled,
      );
      if (!mounted) return;
      Navigator.of(context).pop(sectorId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = describeFirestoreError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar sector'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Site: ${widget.site.name.isEmpty ? widget.site.id : widget.site.name}',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _idController,
                enabled: !_isSaving,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Sector ID'),
                onChanged: (_) => setState(() {}),
              ),
              _NormalizedIdPreview(value: _idController.text),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Habilitado'),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              if (_errorMessage != null)
                _InlineDialogError(message: _errorMessage!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }
}

class _EditSectorDialog extends StatefulWidget {
  const _EditSectorDialog({
    required this.sectorService,
    required this.tenantId,
    required this.sector,
  });

  final AgroSectorService sectorService;
  final String tenantId;
  final AgroSector sector;

  @override
  State<_EditSectorDialog> createState() => _EditSectorDialogState();
}

class _EditSectorDialogState extends State<_EditSectorDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.sector.name,
  );
  late final TextEditingController _descController = TextEditingController(
    text: widget.sector.description,
  );
  late bool _enabled = widget.sector.enabled;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'El nombre del sector es obligatorio.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.sectorService.update(
        tenantId: widget.tenantId,
        sectorId: widget.sector.id,
        name: name,
        description: _descController.text.trim(),
        enabled: _enabled,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = describeFirestoreError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar sector: ${widget.sector.id}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Habilitado'),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              if (_errorMessage != null)
                _InlineDialogError(message: _errorMessage!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _RoomFormRow {
  _RoomFormRow({required String id, required String name, int sortOrder = 0})
    : idController = TextEditingController(text: id),
      nameController = TextEditingController(text: name),
      sortOrderController = TextEditingController(text: sortOrder.toString()),
      snapshotController = TextEditingController();

  final TextEditingController idController;
  final TextEditingController nameController;
  final TextEditingController sortOrderController;
  final TextEditingController snapshotController;
  bool enabled = true;

  void dispose() {
    idController.dispose();
    nameController.dispose();
    sortOrderController.dispose();
    snapshotController.dispose();
  }
}

/// Add/Edit Device forms share this: a Checkbox list of the parent Site's
/// Sectors, letting the admin associate the Device with zero or more of
/// them — see `AgroDeviceService._validateSectorIds` for why every checked
/// Sector is guaranteed (server-side, not just here) to belong to the same
/// Site as the Device.
class _SectorMultiSelect extends StatelessWidget {
  const _SectorMultiSelect({
    required this.availableSectors,
    required this.selectedSectorIds,
    required this.onChanged,
    required this.enabled,
  });

  final List<AgroSector> availableSectors;
  final Set<String> selectedSectorIds;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (availableSectors.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Este site todavía no tiene sectores para asociar.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final AgroSector sector in availableSectors)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              sector.name.isEmpty ? sector.id : sector.name,
              style: const TextStyle(fontSize: 13),
            ),
            value: selectedSectorIds.contains(sector.id),
            onChanged: !enabled
                ? null
                : (checked) {
                    final Set<String> next = Set<String>.of(selectedSectorIds);
                    if (checked == true) {
                      next.add(sector.id);
                    } else {
                      next.remove(sector.id);
                    }
                    onChanged(next);
                  },
          ),
      ],
    );
  }
}

class _DeviceTypeDropdown extends StatelessWidget {
  const _DeviceTypeDropdown({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final AgroDeviceTypeDefinition value;
  final ValueChanged<AgroDeviceTypeDefinition> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AgroDeviceTypeDefinition>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Tipo *'),
      items: [
        for (final AgroDeviceTypeDefinition type in selectableAgroDeviceTypes())
          DropdownMenuItem(value: type, child: Text(type.label)),
      ],
      onChanged: !enabled
          ? null
          : (type) {
              if (type != null) onChanged(type);
            },
    );
  }
}

class _AddDeviceDialog extends StatefulWidget {
  const _AddDeviceDialog({
    required this.deviceService,
    required this.provisioningService,
    required this.tenantId,
    required this.site,
    required this.availableSectors,
  });

  final AgroDeviceService deviceService;
  final AgroDeviceProvisioningService provisioningService;
  final String tenantId;
  // The parent Site — preselected and NOT changeable inside this dialog,
  // matching `_AddSectorDialog`'s convention.
  final AgroSite site;
  final List<AgroSector> availableSectors;

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _sortOrderController = TextEditingController(
    text: '0',
  );
  final TextEditingController _snapshotController = TextEditingController();
  AgroDeviceTypeDefinition _type = selectableAgroDeviceTypes().first;
  bool _enabled = true;
  Set<String> _selectedSectorIds = <String>{};
  List<_RoomFormRow> _roomRows = <_RoomFormRow>[];
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (_type.usesRooms) {
      _regenerateRooms(_type.defaultRoomCount);
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _modelController.dispose();
    _descController.dispose();
    _sortOrderController.dispose();
    _snapshotController.dispose();
    for (final _RoomFormRow row in _roomRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _regenerateRooms(int count) {
    for (final _RoomFormRow row in _roomRows) {
      row.dispose();
    }
    setState(() {
      _roomRows = [
        for (int i = 0; i < count; i++)
          _RoomFormRow(
            id: 'sala-${i + 1}',
            name: 'Sala ${i + 1}',
            sortOrder: i,
          ),
      ];
    });
  }

  void _onTypeChanged(AgroDeviceTypeDefinition next) {
    setState(() => _type = next);
    if (next.usesRooms && _roomRows.isEmpty) {
      _regenerateRooms(next.defaultRoomCount);
    } else if (!next.usesRooms && _roomRows.isNotEmpty) {
      for (final _RoomFormRow row in _roomRows) {
        row.dispose();
      }
      setState(() => _roomRows = <_RoomFormRow>[]);
    }
  }

  Future<void> _save() async {
    final String deviceId = normalizeStructuralId(_idController.text);
    final String name = _nameController.text.trim();
    if (deviceId.isEmpty) {
      setState(() => _errorMessage = 'El Device ID es obligatorio.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = 'El nombre del device es obligatorio.');
      return;
    }
    final int sortOrder = int.tryParse(_sortOrderController.text.trim()) ?? 0;
    final String? snapshotUnitKey = _snapshotController.text.trim().isEmpty
        ? null
        : _snapshotController.text.trim();

    List<AgroDeviceRoomDraft> rooms = const <AgroDeviceRoomDraft>[];
    if (_type.usesRooms) {
      if (_roomRows.isEmpty) {
        setState(
          () => _errorMessage =
              'Definí al menos 1 room para este tipo de device.',
        );
        return;
      }
      final Set<String> seenIds = <String>{};
      final Set<String> seenSnapshotKeys = <String>{};
      final List<AgroDeviceRoomDraft> drafts = <AgroDeviceRoomDraft>[];
      for (final _RoomFormRow row in _roomRows) {
        final String roomId = normalizeStructuralId(row.idController.text);
        final String roomName = row.nameController.text.trim();
        final String snapshotKey = row.snapshotController.text.trim();
        if (roomId.isEmpty) {
          setState(() => _errorMessage = 'El Room ID es obligatorio.');
          return;
        }
        if (roomName.isEmpty) {
          setState(
            () => _errorMessage = 'El nombre de la room es obligatorio.',
          );
          return;
        }
        if (!seenIds.add(roomId)) {
          setState(() => _errorMessage = 'Hay Room IDs duplicados: "$roomId".');
          return;
        }
        if (snapshotKey.isNotEmpty && !seenSnapshotKeys.add(snapshotKey)) {
          setState(
            () => _errorMessage =
                'Hay snapshotUnitKey duplicados: "$snapshotKey".',
          );
          return;
        }
        drafts.add(
          AgroDeviceRoomDraft(
            id: roomId,
            name: roomName,
            enabled: row.enabled,
            sortOrder:
                int.tryParse(row.sortOrderController.text.trim()) ??
                drafts.length,
            snapshotUnitKey: snapshotKey.isEmpty ? null : snapshotKey,
          ),
        );
      }
      rooms = drafts;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      if (_type.usesRooms) {
        await widget.provisioningService.createDeviceWithRooms(
          tenantId: widget.tenantId,
          siteId: widget.site.id,
          deviceId: deviceId,
          name: name,
          type: _type.id,
          model: _modelController.text.trim(),
          description: _descController.text.trim(),
          enabled: _enabled,
          sortOrder: sortOrder,
          sectorIds: _selectedSectorIds.toList(),
          rooms: rooms,
        );
      } else {
        await widget.deviceService.create(
          tenantId: widget.tenantId,
          deviceId: deviceId,
          siteId: widget.site.id,
          name: name,
          type: _type.id,
          model: _modelController.text.trim(),
          description: _descController.text.trim(),
          enabled: _enabled,
          sortOrder: sortOrder,
          snapshotUnitKey: snapshotUnitKey,
          sectorIds: _selectedSectorIds.toList(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(deviceId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = describeFirestoreError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar device'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Site *: ${widget.site.name.isEmpty ? widget.site.id : widget.site.name}',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _idController,
                enabled: !_isSaving,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Device ID *'),
                onChanged: (_) => setState(() {}),
              ),
              _NormalizedIdPreview(value: _idController.text),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  helperText: _type.usesRooms
                      ? 'Con este tipo (multisala), en el dashboard se '
                            'muestra el nombre de cada room, no este campo.'
                      : 'Este es el nombre que se muestra en el dashboard.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 10),
              _DeviceTypeDropdown(
                value: _type,
                enabled: !_isSaving,
                onChanged: _onTypeChanged,
              ),
              const SizedBox(height: 4),
              Text(
                _type.description,
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _modelController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Modelo (opcional, ej. S7-1200)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sortOrderController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Orden',
                  helperText:
                      'Define la posición del device en la lista/grilla '
                      'del dashboard (Vista general del ambiente, Vista de '
                      'tabla, etc.), de menor a mayor. Si dos devices '
                      'quedan con el mismo valor, se desempata '
                      'alfabéticamente por Nombre.',
                  helperMaxLines: 4,
                ),
              ),
              if (!_type.usesRooms) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _snapshotController,
                  enabled: !_isSaving,
                  decoration: const InputDecoration(
                    labelText: 'snapshotUnitKey (opcional)',
                    helperText:
                        'Debe coincidir con la clave que entrega el backend. '
                        'Si se deja vacío, se usa el Device ID.',
                    helperMaxLines: 2,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Habilitado'),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Sectores asociados',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              _SectorMultiSelect(
                availableSectors: widget.availableSectors,
                selectedSectorIds: _selectedSectorIds,
                enabled: !_isSaving,
                onChanged: (next) => setState(() => _selectedSectorIds = next),
              ),
              if (_type.usesRooms) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Rooms',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _regenerateRooms(_type.defaultRoomCount),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: Text(
                        'Generar ${_type.defaultRoomCount}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => setState(
                              () => _roomRows.add(
                                _RoomFormRow(
                                  id: 'sala-${_roomRows.length + 1}',
                                  name: 'Sala ${_roomRows.length + 1}',
                                  sortOrder: _roomRows.length,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text(
                        'Agregar fila',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                for (int i = 0; i < _roomRows.length; i++)
                  _RoomFormRowEditor(
                    row: _roomRows[i],
                    enabled: !_isSaving,
                    onRemove: () => setState(() {
                      _roomRows[i].dispose();
                      _roomRows.removeAt(i);
                    }),
                    onEnabledChanged: (value) =>
                        setState(() => _roomRows[i].enabled = value),
                  ),
              ],
              const SizedBox(height: 12),
              const Text(
                '* No se puede modificar después de crear el device.',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
              if (_errorMessage != null)
                _InlineDialogError(message: _errorMessage!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }
}

/// One editable row in the "Agregar device" room generator table.
class _RoomFormRowEditor extends StatelessWidget {
  const _RoomFormRowEditor({
    required this.row,
    required this.enabled,
    required this.onRemove,
    required this.onEnabledChanged,
  });

  final _RoomFormRow row;
  final bool enabled;
  final VoidCallback onRemove;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1E293B),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.idController,
                    enabled: enabled,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                      labelText: 'Room ID',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.nameController,
                    enabled: enabled,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 20,
                  child: IconButton(
                    tooltip: 'Quitar fila',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    onPressed: enabled ? onRemove : null,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: row.sortOrderController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                      labelText: 'Orden',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.snapshotController,
                    enabled: enabled,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                      labelText: 'snapshotUnitKey (opcional)',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Switch(
                  value: row.enabled,
                  onChanged: enabled
                      ? (value) => onEnabledChanged(value)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditDeviceDialog extends StatefulWidget {
  const _EditDeviceDialog({
    required this.deviceService,
    required this.tenantId,
    required this.device,
    required this.availableSectors,
  });

  final AgroDeviceService deviceService;
  final String tenantId;
  final AgroDevice device;
  final List<AgroSector> availableSectors;

  @override
  State<_EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<_EditDeviceDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.device.name,
  );
  late final TextEditingController _modelController = TextEditingController(
    text: widget.device.model,
  );
  late final TextEditingController _descController = TextEditingController(
    text: widget.device.description,
  );
  late final TextEditingController _sortOrderController = TextEditingController(
    text: widget.device.sortOrder.toString(),
  );
  late final TextEditingController _snapshotController = TextEditingController(
    text: widget.device.snapshotUnitKey ?? '',
  );
  late bool _enabled = widget.device.enabled;
  late Set<String> _selectedSectorIds = widget.device.sectorIds.toSet();
  bool _isSaving = false;
  String? _errorMessage;

  bool get _usesRooms =>
      findAgroDeviceType(widget.device.type)?.usesRooms ?? false;

  @override
  void dispose() {
    _nameController.dispose();
    _modelController.dispose();
    _descController.dispose();
    _sortOrderController.dispose();
    _snapshotController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'El nombre del device es obligatorio.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      // `siteId`/Device ID/`type`/`createdAt` are intentionally never sent
      // as changed here — siteId is required only to locate/validate the
      // document (AgroDeviceService.update signature), type stays
      // read-only after creation (see the Etapa 4 report §13).
      await widget.deviceService.update(
        tenantId: widget.tenantId,
        deviceId: widget.device.id,
        siteId: widget.device.siteId,
        name: name,
        type: widget.device.type,
        model: _modelController.text.trim(),
        description: _descController.text.trim(),
        enabled: _enabled,
        sortOrder: int.tryParse(_sortOrderController.text.trim()) ?? 0,
        snapshotUnitKey: _snapshotController.text.trim().isEmpty
            ? null
            : _snapshotController.text.trim(),
        sectorIds: _selectedSectorIds.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = describeFirestoreError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar device: ${widget.device.id}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReadOnlyField(
                label: 'Tipo',
                value: describeDeviceType(widget.device.type),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _modelController,
                enabled: !_isSaving,
                decoration: const InputDecoration(labelText: 'Modelo'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descController,
                enabled: !_isSaving,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sortOrderController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Orden'),
              ),
              if (!_usesRooms) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _snapshotController,
                  enabled: !_isSaving,
                  decoration: const InputDecoration(
                    labelText: 'snapshotUnitKey (opcional)',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Habilitado'),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Sectores asociados',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              _SectorMultiSelect(
                availableSectors: widget.availableSectors,
                selectedSectorIds: _selectedSectorIds,
                enabled: !_isSaving,
                onChanged: (next) => setState(() => _selectedSectorIds = next),
              ),
              if (_errorMessage != null)
                _InlineDialogError(message: _errorMessage!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _AddRoomDialog extends StatefulWidget {
  const _AddRoomDialog({
    required this.roomService,
    required this.tenantId,
    required this.device,
  });

  final AgroDeviceRoomService roomService;
  final String tenantId;
  // The parent Device — preselected and NOT changeable inside this dialog.
  final AgroDevice device;

  @override
  State<_AddRoomDialog> createState() => _AddRoomDialogState();
}

class _AddRoomDialogState extends State<_AddRoomDialog> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _sortOrderController = TextEditingController(
    text: '0',
  );
  final TextEditingController _snapshotController = TextEditingController();
  bool _enabled = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _sortOrderController.dispose();
    _snapshotController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String roomId = normalizeStructuralId(_idController.text);
    final String name = _nameController.text.trim();
    if (roomId.isEmpty) {
      setState(() => _errorMessage = 'El Room ID es obligatorio.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = 'El nombre de la room es obligatorio.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.roomService.create(
        tenantId: widget.tenantId,
        deviceId: widget.device.id,
        roomId: roomId,
        siteId: widget.device.siteId,
        name: name,
        enabled: _enabled,
        sortOrder: int.tryParse(_sortOrderController.text.trim()) ?? 0,
        snapshotUnitKey: _snapshotController.text.trim().isEmpty
            ? null
            : _snapshotController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(roomId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = describeFirestoreError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar room'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Device: ${widget.device.name.isEmpty ? widget.device.id : widget.device.name}',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _idController,
                enabled: !_isSaving,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Room ID'),
                onChanged: (_) => setState(() {}),
              ),
              _NormalizedIdPreview(value: _idController.text),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sortOrderController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Orden'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _snapshotController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'snapshotUnitKey (opcional)',
                  helperText:
                      'Debe coincidir con la clave que entrega el backend. '
                      'Si se deja vacío, se usa "deviceId__roomId".',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Habilitado'),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              if (_errorMessage != null)
                _InlineDialogError(message: _errorMessage!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }
}

class _EditRoomDialog extends StatefulWidget {
  const _EditRoomDialog({
    required this.roomService,
    required this.tenantId,
    required this.room,
  });

  final AgroDeviceRoomService roomService;
  final String tenantId;
  final AgroDeviceRoom room;

  @override
  State<_EditRoomDialog> createState() => _EditRoomDialogState();
}

class _EditRoomDialogState extends State<_EditRoomDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.room.name,
  );
  late final TextEditingController _sortOrderController = TextEditingController(
    text: widget.room.sortOrder.toString(),
  );
  late final TextEditingController _snapshotController = TextEditingController(
    text: widget.room.snapshotUnitKey ?? '',
  );
  late bool _enabled = widget.room.enabled;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _sortOrderController.dispose();
    _snapshotController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'El nombre de la room es obligatorio.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      // Room ID/deviceId/createdAt are never sent — immutable after
      // creation (matches firestore.rules). `siteId` IS passed, but only
      // to scope the site-wide snapshotUnitKey uniqueness check — it's
      // never part of the write payload (buildAgroDeviceRoomUpdatePayload
      // never includes it).
      await widget.roomService.update(
        tenantId: widget.tenantId,
        deviceId: widget.room.deviceId,
        roomId: widget.room.id,
        siteId: widget.room.siteId,
        name: name,
        enabled: _enabled,
        sortOrder: int.tryParse(_sortOrderController.text.trim()) ?? 0,
        snapshotUnitKey: _snapshotController.text.trim().isEmpty
            ? null
            : _snapshotController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = describeFirestoreError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar room: ${widget.room.id}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sortOrderController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Orden'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _snapshotController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'snapshotUnitKey (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Habilitado'),
                  const Spacer(),
                  Switch(
                    value: _enabled,
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              if (_errorMessage != null)
                _InlineDialogError(message: _errorMessage!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
