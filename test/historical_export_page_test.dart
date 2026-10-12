import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/pages/historical_export_page.dart';
import 'package:agro_data_control/services/agro_device_service.dart';
import 'package:agro_data_control/services/historical_export_repository.dart';
import 'package:agro_data_control/services/historical_export_variable.dart';
import 'package:agro_data_control/services/historical_export_workbook.dart';
import 'package:agro_data_control/services/site_config_service.dart';

AgroDevice _device(String id, String name, {String siteId = 'las-heras'}) =>
    AgroDevice(
      id: id,
      tenantId: 'the-gene-pig',
      siteId: siteId,
      name: name,
      type: 'plc',
      model: '',
      description: '',
      enabled: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

class _FakeSiteConfigService extends SiteConfigService {
  const _FakeSiteConfigService({
    this.tenants = const [],
    this.sitesByTenant = const {},
  });
  final List<TenantDocument> tenants;
  final Map<String, List<SiteDocument>> sitesByTenant;

  @override
  Future<List<TenantDocument>> fetchActiveTenants() async => tenants;

  @override
  Future<TenantDocument?> fetchTenant({required String tenantId}) async {
    for (final t in tenants) {
      if (t.tenantId == tenantId) return t;
    }
    return null;
  }

  @override
  Future<List<SiteDocument>> fetchActiveSitesForUser({
    required String tenantId,
    required List<String> allowedSiteIds,
    bool ownerBypass = false,
  }) async {
    final all = sitesByTenant[tenantId] ?? const [];
    if (ownerBypass) return all;
    return all.where((s) => allowedSiteIds.contains(s.siteId)).toList();
  }
}

class _FakeDeviceService extends AgroDeviceService {
  const _FakeDeviceService(this.devicesBySite);
  final Map<String, List<AgroDevice>> devicesBySite;

  @override
  Future<List<AgroDevice>> listBySite({
    required String tenantId,
    required String siteId,
    bool includeDisabled = false,
  }) async => devicesBySite[siteId] ?? const [];
}

class _RecordingExportRepository extends HistoricalExportRepository {
  const _RecordingExportRepository(this.calls, this.pointsByDevice);
  final List<Map<String, Object?>> calls;
  final Map<String, List<HistoricalExportPoint>> pointsByDevice;

  @override
  Future<List<HistoricalExportPoint>> fetchHourlyRange({
    required String tenantId,
    required String siteId,
    required String deviceId,
    required DateTime fromUtc,
    required DateTime toUtcExclusive,
  }) async {
    calls.add({
      'tenantId': tenantId,
      'siteId': siteId,
      'deviceId': deviceId,
      'fromUtc': fromUtc,
      'toUtcExclusive': toUtcExclusive,
    });
    return pointsByDevice[deviceId] ?? const [];
  }
}

const _site = SiteDocument(
  siteId: 'las-heras',
  technicalId: 'las-heras',
  name: 'Las Heras',
  backendUrl: 'https://example.test',
  active: true,
  enabled: true,
  provisioningStatus: 'ready',
);

const _site2 = SiteDocument(
  siteId: 'genetica-1',
  technicalId: 'genetica-1',
  name: 'Genética',
  backendUrl: 'https://example.test',
  active: true,
  enabled: true,
  provisioningStatus: 'ready',
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  group('J. Permisos', () {
    testWidgets('owner ve selector de Cliente con todos los tenants activos', (
      tester,
    ) async {
      await _pump(
        tester,
        HistoricalExportPage(
          isOwner: true,
          activeTenantId: null,
          allowedSiteIds: const [],
          siteConfigService: const _FakeSiteConfigService(
            tenants: [
              TenantDocument(tenantId: 'the-gene-pig', name: 'Gene Pig', active: true),
              TenantDocument(tenantId: 'la-payana', name: 'La Payana', active: true),
            ],
            sitesByTenant: {
              'the-gene-pig': [_site],
            },
          ),
          deviceService: const _FakeDeviceService({}),
        ),
      );
      expect(find.byKey(const ValueKey('export-tenant-dropdown')), findsOneWidget);
      expect(find.text('Gene Pig'), findsWidgets);
    });

    testWidgets('no-owner no ve selector de Cliente, queda fijo a su tenant', (
      tester,
    ) async {
      await _pump(
        tester,
        HistoricalExportPage(
          isOwner: false,
          activeTenantId: 'the-gene-pig',
          allowedSiteIds: const ['las-heras'],
          siteConfigService: const _FakeSiteConfigService(
            sitesByTenant: {
              'the-gene-pig': [_site, _site2],
            },
          ),
          deviceService: const _FakeDeviceService({}),
        ),
      );
      expect(find.byKey(const ValueKey('export-tenant-dropdown')), findsNothing);
      // Only the allowed site shows, even though the tenant has two.
      expect(find.text('Las Heras'), findsOneWidget);
      expect(find.text('Genética'), findsNothing);
    });
  });

  group('B. Selección de tenant/site/device', () {
    testWidgets('selecciona automáticamente el primer site y carga sus Devices', (
      tester,
    ) async {
      await _pump(
        tester,
        HistoricalExportPage(
          isOwner: true,
          activeTenantId: null,
          allowedSiteIds: const [],
          siteConfigService: const _FakeSiteConfigService(
            tenants: [TenantDocument(tenantId: 'the-gene-pig', name: 'Gene Pig', active: true)],
            sitesByTenant: {
              'the-gene-pig': [_site],
            },
          ),
          deviceService: _FakeDeviceService({
            'las-heras': [_device('d1', 'Sala 1'), _device('d2', 'Sala 2')],
          }),
        ),
      );
      expect(find.byKey(const ValueKey('export-device-d1')), findsOneWidget);
      expect(find.byKey(const ValueKey('export-device-d2')), findsOneWidget);
      // Devices load pre-selected (both checked).
      final cb1 = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('export-device-d1')),
      );
      expect(cb1.value, isTrue);
    });

    testWidgets('establecimiento sin equipos muestra mensaje claro', (tester) async {
      await _pump(
        tester,
        HistoricalExportPage(
          isOwner: false,
          activeTenantId: 'the-gene-pig',
          allowedSiteIds: const ['las-heras'],
          siteConfigService: const _FakeSiteConfigService(
            sitesByTenant: {
              'the-gene-pig': [_site],
            },
          ),
          deviceService: const _FakeDeviceService({}),
        ),
      );
      expect(find.byKey(const ValueKey('export-no-devices')), findsOneWidget);
    });
  });

  group('C. Selección de variables', () {
    testWidgets('variables vienen todas preseleccionadas y son deseleccionables', (
      tester,
    ) async {
      await _pump(
        tester,
        HistoricalExportPage(
          isOwner: false,
          activeTenantId: 'the-gene-pig',
          allowedSiteIds: const ['las-heras'],
          siteConfigService: const _FakeSiteConfigService(
            sitesByTenant: {
              'the-gene-pig': [_site],
            },
          ),
          deviceService: _FakeDeviceService({
            'las-heras': [_device('d1', 'Sala 1')],
          }),
        ),
      );
      for (final v in kHistoricalExportVariables) {
        final checkbox = tester.widget<CheckboxListTile>(
          find.byKey(ValueKey('export-variable-${v.key}')),
        );
        expect(checkbox.value, isTrue);
      }
      await tester.tap(find.byKey(const ValueKey('export-variable-temperature')));
      await tester.pumpAndSettle();
      final after = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('export-variable-temperature')),
      );
      expect(after.value, isFalse);
    });
  });

  group('A. Validación de rango de fechas', () {
    testWidgets('Exportar queda deshabilitado sin fechas o sin devices/variables', (
      tester,
    ) async {
      await _pump(
        tester,
        HistoricalExportPage(
          isOwner: false,
          activeTenantId: 'the-gene-pig',
          allowedSiteIds: const ['las-heras'],
          siteConfigService: const _FakeSiteConfigService(
            sitesByTenant: {
              'the-gene-pig': [_site],
            },
          ),
          deviceService: _FakeDeviceService({
            'las-heras': [_device('d1', 'Sala 1')],
          }),
        ),
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('export-submit')),
      );
      expect(button.onPressed, isNull); // no dates picked yet
    });
  });

  group('D. Consulta del rango horario', () {
    testWidgets('fetchHourlyRange recibe tenantId/siteId/deviceId y rango ART correcto', (
      tester,
    ) async {
      final calls = <Map<String, Object?>>[];
      await _pump(
        tester,
        HistoricalExportPage(
          isOwner: false,
          activeTenantId: 'the-gene-pig',
          allowedSiteIds: const ['las-heras'],
          siteConfigService: const _FakeSiteConfigService(
            sitesByTenant: {
              'the-gene-pig': [_site],
            },
          ),
          deviceService: _FakeDeviceService({
            'las-heras': [_device('d1', 'Sala 1')],
          }),
          exportRepository: _RecordingExportRepository(calls, {
            'd1': [
              HistoricalExportPoint(DateTime.utc(2026, 9, 1, 3), {
                'temperature': {'avg': 20.0, 'sampleCount': 6},
              }),
            ],
          }),
          buildWorkbook: (_) => const [1, 2, 3],
          downloadFile: (filename, bytes) async {},
          initialFromDate: DateTime(2026, 9, 1),
          initialToDate: DateTime(2026, 9, 2),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('export-submit')));
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(calls.single['deviceId'], 'd1');
      expect(calls.single['tenantId'], 'the-gene-pig');
      expect(calls.single['siteId'], 'las-heras');
      expect(calls.single['fromUtc'], DateTime.utc(2026, 9, 1, 3));
      expect(calls.single['toUtcExclusive'], DateTime.utc(2026, 9, 3, 3));
    });

    testWidgets(
      'un no-owner exporta con el nombre amigable del cliente, no el slug técnico',
      (tester) async {
        HistoricalExportRequest? captured;
        await _pump(
          tester,
          HistoricalExportPage(
            isOwner: false,
            activeTenantId: 'the-gene-pig',
            allowedSiteIds: const ['las-heras'],
            siteConfigService: const _FakeSiteConfigService(
              // Not reached via fetchActiveTenants (no-owner never calls
              // it) — only via fetchTenant, which a non-owner DOES need to
              // resolve the Excel header's friendly name.
              tenants: [
                TenantDocument(tenantId: 'the-gene-pig', name: 'Gene Pig', active: true),
              ],
              sitesByTenant: {
                'the-gene-pig': [_site],
              },
            ),
            deviceService: _FakeDeviceService({
              'las-heras': [_device('d1', 'Sala 1')],
            }),
            exportRepository: _RecordingExportRepository([], const {}),
            buildWorkbook: (req) {
              captured = req;
              return const [1];
            },
            downloadFile: (filename, bytes) async {},
            initialFromDate: DateTime(2026, 9, 1),
            initialToDate: DateTime(2026, 9, 2),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('export-submit')));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!.clientName, 'Gene Pig');
        expect(captured!.establishmentName, 'Las Heras');
      },
    );

    testWidgets('resumen post-export avisa qué Device no tuvo datos (K)', (
      tester,
    ) async {
      await _pump(
        tester,
        HistoricalExportPage(
          isOwner: false,
          activeTenantId: 'the-gene-pig',
          allowedSiteIds: const ['las-heras'],
          siteConfigService: const _FakeSiteConfigService(
            sitesByTenant: {
              'the-gene-pig': [_site],
            },
          ),
          deviceService: _FakeDeviceService({
            'las-heras': [_device('d1', 'Sala vacía')],
          }),
          exportRepository: _RecordingExportRepository([], const {}),
          buildWorkbook: (_) => const [1],
          downloadFile: (filename, bytes) async {},
          initialFromDate: DateTime(2026, 9, 1),
          initialToDate: DateTime(2026, 9, 2),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('export-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('export-summary')), findsOneWidget);
      expect(find.textContaining('Sin datos en el rango'), findsOneWidget);
      final summary = tester.widget<Text>(
        find.byKey(const ValueKey('export-summary')),
      );
      expect(summary.data, contains('Sala vacía'));
    });
  });
}
