import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../models/agro_device.dart';
import '../services/agro_device_service.dart';
import '../services/historical_export_repository.dart';
import '../services/historical_export_variable.dart';
import '../services/historical_export_workbook.dart';
import '../services/site_config_service.dart';
import '../utils/historical_export_filename.dart';
import '../utils/xlsx_download_adapter.dart';

enum _LoadState { loading, ready, error }

/// "Configuración → Exportar datos" — self-contained real page (pushed via
/// `Navigator.push`, not a dialog), visible to every active role (not
/// owner-gated like `TenantManagementPage`/`UserManagementPage`): any
/// authorized user should be able to export their own Tenant/Site's
/// historical data (Prompt_exportacion_historicos_excel §OBJETIVO).
///
/// Deliberately NOT a self-resolving page (no internal
/// `UserContextService.readUserContext` call): [isOwner]/[activeTenantId]/
/// [allowedSiteIds] are exactly what the dashboard bootstrap in `main.dart`
/// already resolved for the current session — reusing that instead of a
/// second read keeps this page's permission scoping identical to the rest
/// of the app's (§PERMISOS: "Reutilizar la lógica de permisos existente")
/// and costs 0 extra Firestore reads to open.
///
/// Scoped exclusively to the new Device-based architecture: every query
/// here goes through [AgroDeviceService]/[HistoricalExportRepository]
/// (`tenants/{t}/devices/{d}/historyHourly`) — no legacy
/// `tenants/{t}/sites/{s}/plcs/{p}` path, no PLC1/PLC2-specific code, no
/// Gene-Pig-specific aliasing (contrast with
/// `DeviceEnvironmentHistoryRepository`, which deliberately keeps a legacy
/// bridge for the live dashboard chart — that bridge is explicitly out of
/// scope for this exporter, per the prompt's own restriction).
class HistoricalExportPage extends StatefulWidget {
  const HistoricalExportPage({
    super.key,
    required this.isOwner,
    required this.activeTenantId,
    required this.allowedSiteIds,
    this.siteConfigService = const SiteConfigService(),
    this.deviceService = const AgroDeviceService(),
    this.exportRepository = const HistoricalExportRepository(),
    this.buildWorkbook = buildHistoricalExportWorkbook,
    this.downloadFile = downloadXlsxFile,
    this.initialFromDate,
    this.initialToDate,
  });

  final bool isOwner;

  /// Fixed tenant for a non-owner — ignored (no Cliente picker shown) when
  /// [isOwner] is true, which instead lists every active tenant.
  final String? activeTenantId;

  /// Sites a non-owner may see within their tenant — ignored when
  /// [isOwner] is true (owners see every active Site, same as the rest of
  /// the app's owner bypass).
  final List<String> allowedSiteIds;

  final SiteConfigService siteConfigService;
  final AgroDeviceService deviceService;
  final HistoricalExportRepository exportRepository;

  /// Pre-seeds the date range — mainly a widget-test seam (driving the real
  /// `showDatePicker` calendar UI to a specific date isn't practical in a
  /// test), but equally usable later for a genuine "recordar último rango"
  /// feature without any API change.
  final DateTime? initialFromDate;
  final DateTime? initialToDate;

  /// Injectable seams for widget tests — avoids touching real
  /// `dart:html`/building a real `.xlsx` just to test the page's
  /// selection/validation/permission logic.
  final List<int> Function(HistoricalExportRequest) buildWorkbook;
  final Future<void> Function(String filename, List<int> bytes) downloadFile;

  @override
  State<HistoricalExportPage> createState() => _HistoricalExportPageState();
}

class _HistoricalExportPageState extends State<HistoricalExportPage> {
  _LoadState _tenantsState = _LoadState.loading;
  List<TenantDocument> _tenants = const [];
  String? _selectedTenantId;
  String? _selectedTenantName;

  _LoadState _sitesState = _LoadState.loading;
  List<SiteDocument> _sites = const [];
  String? _selectedSiteId;
  String? _selectedSiteName;

  _LoadState _devicesState = _LoadState.loading;
  List<AgroDevice> _devices = const [];
  final Set<String> _selectedDeviceIds = {};

  final Set<String> _selectedVariableKeys = {
    for (final v in kHistoricalExportVariables) v.key,
  };

  DateTime? _fromDate;
  DateTime? _toDate;

  bool _exporting = false;
  String? _errorMessage;
  String? _exportSummary;

  @override
  void initState() {
    super.initState();
    _fromDate = widget.initialFromDate;
    _toDate = widget.initialToDate;
    _loadTenants();
  }

  Future<void> _loadTenants() async {
    if (!widget.isOwner) {
      final tenantId = widget.activeTenantId;
      // A non-owner never sees a Cliente picker, but the Excel header still
      // must show the real name ("Gene Pig"), never the raw tenantId slug
      // ("the-gene-pig") — §"TERMINOLOGÍA EN UI" applies to the generated
      // file too, not just the on-screen labels.
      final tenant = tenantId == null
          ? null
          : await widget.siteConfigService.fetchTenant(tenantId: tenantId);
      if (!mounted) return;
      setState(() {
        _selectedTenantId = tenantId;
        _selectedTenantName = tenant?.name ?? tenantId;
        _tenantsState = _LoadState.ready;
      });
      await _loadSites();
      return;
    }
    setState(() => _tenantsState = _LoadState.loading);
    try {
      final tenants = await widget.siteConfigService.fetchActiveTenants();
      if (!mounted) return;
      setState(() {
        _tenants = tenants;
        _selectedTenantId = tenants.isNotEmpty ? tenants.first.tenantId : null;
        _selectedTenantName = tenants.isNotEmpty ? tenants.first.name : null;
        _tenantsState = _LoadState.ready;
      });
      await _loadSites();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tenantsState = _LoadState.error;
        _errorMessage = 'No se pudieron cargar los clientes.';
      });
    }
  }

  Future<void> _loadSites() async {
    final tenantId = _selectedTenantId;
    if (tenantId == null) {
      setState(() {
        _sites = const [];
        _selectedSiteId = null;
        _sitesState = _LoadState.ready;
      });
      return;
    }
    setState(() => _sitesState = _LoadState.loading);
    try {
      final sites = await widget.siteConfigService.fetchActiveSitesForUser(
        tenantId: tenantId,
        allowedSiteIds: widget.isOwner ? const [] : widget.allowedSiteIds,
        ownerBypass: widget.isOwner,
      );
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _selectedSiteId = sites.isNotEmpty ? sites.first.siteId : null;
        _selectedSiteName = sites.isNotEmpty ? sites.first.name : null;
        _sitesState = _LoadState.ready;
      });
      await _loadDevices();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sitesState = _LoadState.error;
        _errorMessage = 'No se pudieron cargar los establecimientos.';
      });
    }
  }

  Future<void> _loadDevices() async {
    final tenantId = _selectedTenantId;
    final siteId = _selectedSiteId;
    if (tenantId == null || siteId == null) {
      setState(() {
        _devices = const [];
        _selectedDeviceIds.clear();
        _devicesState = _LoadState.ready;
      });
      return;
    }
    setState(() => _devicesState = _LoadState.loading);
    try {
      final devices = await widget.deviceService.listBySite(
        tenantId: tenantId,
        siteId: siteId,
      );
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _selectedDeviceIds
          ..clear()
          ..addAll(devices.map((d) => d.id));
        _devicesState = _LoadState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _devicesState = _LoadState.error;
        _errorMessage = 'No se pudieron cargar los equipos.';
      });
    }
  }

  void _onTenantChanged(String? tenantId) {
    if (tenantId == null || tenantId == _selectedTenantId) return;
    final tenant = _tenants.firstWhere((t) => t.tenantId == tenantId);
    setState(() {
      _selectedTenantId = tenantId;
      _selectedTenantName = tenant.name;
    });
    unawaited(_loadSites());
  }

  void _onSiteChanged(String? siteId) {
    if (siteId == null || siteId == _selectedSiteId) return;
    final site = _sites.firstWhere((s) => s.siteId == siteId);
    setState(() {
      _selectedSiteId = siteId;
      _selectedSiteName = site.name;
    });
    unawaited(_loadDevices());
  }

  /// `desde <= hasta`, ambas presentes — §"Rango de fechas".
  bool get _dateRangeValid =>
      _fromDate != null && _toDate != null && !_fromDate!.isAfter(_toDate!);

  bool get _canExport =>
      !_exporting &&
      _selectedDeviceIds.isNotEmpty &&
      _selectedVariableKeys.isNotEmpty &&
      _dateRangeValid;

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _fromDate : _toDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) => Localizations.override(
        context: context,
        // Spanish calendar conventions start the week on Monday.
        locale: const Locale('es'),
        delegates: GlobalMaterialLocalizations.delegates,
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = DateTime(picked.year, picked.month, picked.day);
      } else {
        _toDate = DateTime(picked.year, picked.month, picked.day);
      }
    });
  }

  Future<void> _export() async {
    if (!_canExport) return;
    setState(() {
      _exporting = true;
      _errorMessage = null;
      _exportSummary = null;
    });
    try {
      final tenantId = _selectedTenantId!;
      final siteId = _selectedSiteId!;
      final fromUtc = artDayStartUtc(
        _fromDate!.year,
        _fromDate!.month,
        _fromDate!.day,
      );
      final toUtcExclusive = artDayStartUtc(
        _toDate!.year,
        _toDate!.month,
        _toDate!.day,
      ).add(const Duration(days: 1));
      final selectedDevices = _devices
          .where((d) => _selectedDeviceIds.contains(d.id))
          .toList();
      final variables = kHistoricalExportVariables
          .where((v) => _selectedVariableKeys.contains(v.key))
          .toList();

      // One bounded `.get()` per selected Device — never one per variable
      // (every selected variable lives in the same `historyHourly`
      // document), never a stream (§FIRESTORE Y COSTOS).
      final pointsByDevice = await Future.wait(
        selectedDevices.map(
          (device) => widget.exportRepository.fetchHourlyRange(
            tenantId: tenantId,
            siteId: siteId,
            deviceId: device.id,
            fromUtc: fromUtc,
            toUtcExclusive: toUtcExclusive,
          ),
        ),
      );

      final deviceData = <HistoricalExportDeviceData>[];
      final emptyDeviceNames = <String>[];
      for (var i = 0; i < selectedDevices.length; i++) {
        final points = pointsByDevice[i];
        if (points.isEmpty) emptyDeviceNames.add(selectedDevices[i].name);
        deviceData.add(
          HistoricalExportDeviceData(
            deviceName: selectedDevices[i].name,
            points: points,
          ),
        );
      }

      final request = HistoricalExportRequest(
        clientName: _selectedTenantName ?? tenantId,
        establishmentName: _selectedSiteName ?? siteId,
        fromDate: _fromDate!,
        toDate: _toDate!,
        variables: variables,
        devices: deviceData,
      );
      final bytes = widget.buildWorkbook(request);
      final filename = buildHistoricalExportFilename(
        clientName: request.clientName,
        establishmentName: request.establishmentName,
        from: _fromDate!,
        to: _toDate!,
      );
      await widget.downloadFile(filename, bytes);

      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportSummary = emptyDeviceNames.isEmpty
            ? 'Exportación generada: $filename'
            : 'Exportación generada: $filename\n'
                  'Sin datos en el rango seleccionado: ${emptyDeviceNames.join(', ')}.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _errorMessage = 'No se pudo generar la exportación: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exportar datos')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                key: const ValueKey('export-error'),
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.isOwner) ...[
              const Text('Cliente'),
              DropdownButton<String>(
                key: const ValueKey('export-tenant-dropdown'),
                isExpanded: true,
                value: _selectedTenantId,
                items: [
                  for (final t in _tenants)
                    DropdownMenuItem(value: t.tenantId, child: Text(t.name)),
                ],
                onChanged: _tenantsState == _LoadState.loading
                    ? null
                    : _onTenantChanged,
              ),
              const SizedBox(height: 12),
            ],
            const Text('Establecimiento'),
            DropdownButton<String>(
              key: const ValueKey('export-site-dropdown'),
              isExpanded: true,
              value: _selectedSiteId,
              items: [
                for (final s in _sites)
                  DropdownMenuItem(value: s.siteId, child: Text(s.name)),
              ],
              onChanged: _sitesState == _LoadState.loading
                  ? null
                  : _onSiteChanged,
            ),
            const SizedBox(height: 12),
            const Text('Equipos'),
            if (_devicesState == _LoadState.ready && _devices.isEmpty)
              const Text(
                'Este establecimiento no tiene equipos disponibles.',
                key: ValueKey('export-no-devices'),
              ),
            for (final device in _devices)
              CheckboxListTile(
                key: ValueKey('export-device-${device.id}'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(device.name),
                value: _selectedDeviceIds.contains(device.id),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _selectedDeviceIds.add(device.id);
                  } else {
                    _selectedDeviceIds.remove(device.id);
                  }
                }),
              ),
            const SizedBox(height: 12),
            const Text('Variables'),
            for (final variable in kHistoricalExportVariables)
              CheckboxListTile(
                key: ValueKey('export-variable-${variable.key}'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(variable.columnHeader),
                value: _selectedVariableKeys.contains(variable.key),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _selectedVariableKeys.add(variable.key);
                  } else {
                    _selectedVariableKeys.remove(variable.key);
                  }
                }),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('export-from-date'),
                    onPressed: () => _pickDate(isFrom: true),
                    child: Text(
                      _fromDate == null
                          ? 'Desde'
                          : 'Desde: ${_formatDate(_fromDate!)}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('export-to-date'),
                    onPressed: () => _pickDate(isFrom: false),
                    child: Text(
                      _toDate == null
                          ? 'Hasta'
                          : 'Hasta: ${_formatDate(_toDate!)}',
                    ),
                  ),
                ),
              ],
            ),
            if (_fromDate != null && _toDate != null && !_dateRangeValid)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '"Desde" debe ser anterior o igual a "Hasta".',
                  key: ValueKey('export-date-range-error'),
                  style: TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('export-submit'),
              onPressed: _canExport ? _export : null,
              child: Text(_exporting ? 'Generando…' : 'Exportar'),
            ),
            if (_exportSummary != null) ...[
              const SizedBox(height: 12),
              Text(_exportSummary!, key: const ValueKey('export-summary')),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/'
    '${d.year}';
