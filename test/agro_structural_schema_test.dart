// Tests for the new-schema Sites/Sectors/Devices structural model
// (AGRODATA — Nuevo esquema Firestore para Sites, Sectores y Devices).
//
// These are pure Dart unit tests: no Firestore emulator is wired into this
// project, so anything that would require a live Firestore round-trip
// (actually persisting a document, or asserting on real read counts) is
// verified by code review instead and documented as such in the delivery
// report. What IS tested here, without any network/emulator dependency:
//   - model (de)serialization and payload shape (toCreatePayload/toUpdatePayload)
//   - service-level validation, which runs and can throw BEFORE any
//     Firestore call is made (so it's exercised even without a backend)
//   - the pure Site/Sector/Device compatibility helpers
//   - that FirestorePaths for the legacy schema are unchanged
import 'package:agro_data_control/firebase/firestore_paths.dart';
import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/models/agro_sector.dart';
import 'package:agro_data_control/models/agro_site.dart';
import 'package:agro_data_control/services/site_config_service.dart';
import 'package:agro_data_control/services/agro_device_service.dart';
import 'package:agro_data_control/services/agro_sector_service.dart';
import 'package:agro_data_control/services/agro_site_hierarchy_service.dart';
import 'package:agro_data_control/services/plc_dashboard_service.dart';
import 'package:agro_data_control/services/user_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('1. Un Site puede crearse dentro de un tenant', () {
    test('toCreatePayload produces a well-formed creation payload', () {
      const AgroSite site = AgroSite(
        id: 'main_site',
        tenantId: 'the-gene-pig',
        name: 'Establecimiento principal',
        description: '',
        enabled: true,
        provisioningStatus: SiteProvisioningStatus.pendingBackend,
        createdAt: null,
        updatedAt: null,
      );
      final Map<String, Object?> payload = site.toCreatePayload();

      expect(payload['name'], 'Establecimiento principal');
      expect(payload['description'], '');
      expect(payload['enabled'], isTrue);
      expect(
        payload['provisioningStatus'],
        SiteProvisioningStatus.pendingBackend,
      );
      expect(payload.containsKey('createdAt'), isTrue);
      expect(payload.containsKey('updatedAt'), isTrue);
    });
  });

  group('2. Un Sector requiere un siteId', () {
    test(
      'create() rejects an empty siteId before touching Firestore',
      () async {
        const AgroSectorService service = AgroSectorService();
        await expectLater(
          service.create(
            tenantId: 'the-gene-pig',
            sectorId: 'genetica',
            siteId: '',
            name: 'Genetica',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('3. Un Device requiere un siteId', () {
    test(
      'create() rejects an empty siteId before touching Firestore',
      () async {
        const AgroDeviceService service = AgroDeviceService();
        await expectLater(
          service.create(
            tenantId: 'the-gene-pig',
            deviceId: 's7_principal',
            siteId: '',
            name: 'S7 principal',
            type: AgroDeviceType.s7,
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('create() also rejects an empty type', () async {
      const AgroDeviceService service = AgroDeviceService();
      await expectLater(
        service.create(
          tenantId: 'the-gene-pig',
          deviceId: 's7_principal',
          siteId: 'main_site',
          name: 'S7 principal',
          type: '',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('4-5. Compatibilidad Sector/Device por Site', () {
    const AgroSector sectorOnSiteA = AgroSector(
      id: 'genetica',
      tenantId: 'the-gene-pig',
      siteId: 'main_site',
      name: 'Genetica',
      description: '',
      enabled: true,
      createdAt: null,
      updatedAt: null,
    );
    const AgroDevice deviceOnSiteA = AgroDevice(
      id: 's7_principal',
      tenantId: 'the-gene-pig',
      siteId: 'main_site',
      name: 'S7 principal',
      type: AgroDeviceType.s7,
      model: 'S7-1200',
      description: '',
      enabled: true,
      createdAt: null,
      updatedAt: null,
    );
    const AgroDevice deviceOnSiteB = AgroDevice(
      id: 's7_secundario',
      tenantId: 'the-gene-pig',
      siteId: 'planta_pilar',
      name: 'S7 secundario',
      type: AgroDeviceType.s7,
      model: 'S7-1500',
      description: '',
      enabled: true,
      createdAt: null,
      updatedAt: null,
    );

    test('4. mismo Site -> compatibles', () {
      expect(
        deviceAndSectorBelongToSameSite(
          device: deviceOnSiteA,
          sector: sectorOnSiteA,
        ),
        isTrue,
      );
    });

    test('5. Sites distintos -> incompatibles', () {
      expect(
        deviceAndSectorBelongToSameSite(
          device: deviceOnSiteB,
          sector: sectorOnSiteA,
        ),
        isFalse,
      );
    });
  });

  group('6. No se permiten referencias entre tenants', () {
    test(
      'mismo siteId pero tenant distinto -> incompatible, aunque el string de siteId coincida',
      () {
        const AgroSector sectorTenantA = AgroSector(
          id: 'genetica',
          tenantId: 'the-gene-pig',
          siteId: 'main_site',
          name: 'Genetica',
          description: '',
          enabled: true,
          createdAt: null,
          updatedAt: null,
        );
        const AgroDevice deviceTenantB = AgroDevice(
          id: 's7_principal',
          tenantId: 'la-payana',
          siteId: 'main_site',
          name: 'S7 principal',
          type: AgroDeviceType.s7,
          model: 'S7-1200',
          description: '',
          enabled: true,
          createdAt: null,
          updatedAt: null,
        );

        expect(
          deviceAndSectorBelongToSameSite(
            device: deviceTenantB,
            sector: sectorTenantA,
          ),
          isFalse,
        );
        expect(
          sectorBelongsToTenant(sector: sectorTenantA, tenantId: 'la-payana'),
          isFalse,
        );
        expect(
          deviceBelongsToTenant(
            device: deviceTenantB,
            tenantId: 'the-gene-pig',
          ),
          isFalse,
        );
      },
    );
  });

  group('7. El esquema legacy continua funcionando sin cambios', () {
    test('rutas de Firestore del esquema legacy no cambiaron', () {
      expect(
        FirestorePaths.siteDoc('the-gene-pig', 'main_site'),
        'tenants/the-gene-pig/sites/main_site',
      );
      expect(
        FirestorePaths.plcsCollection('the-gene-pig', 'main_site'),
        'tenants/the-gene-pig/sites/main_site/plcs',
      );
      expect(
        FirestorePaths.plcConfigDoc('the-gene-pig', 'main_site', 'munters1'),
        'tenants/the-gene-pig/sites/main_site/plcs/munters1',
      );
    });
  });

  group(
    '9. No se modifican los documentos actuales de PLC LOGO! (campos legacy)',
    () {
      test(
        'AgroSite.toUpdatePayload nunca incluye campos legacy de sites (technicalId/backendUrl/active)',
        () {
          const AgroSite site = AgroSite(
            id: 'main_site',
            tenantId: 'the-gene-pig',
            name: 'Establecimiento principal',
            description: '',
            enabled: true,
            provisioningStatus: SiteProvisioningStatus.pendingBackend,
            createdAt: null,
            updatedAt: null,
          );
          final Map<String, Object?> payload = site.toUpdatePayload();

          expect(payload.containsKey('technicalId'), isFalse);
          expect(payload.containsKey('backendUrl'), isFalse);
          expect(payload.containsKey('active'), isFalse);
        },
      );

      test(
        'los paths de AgroSector/AgroDevice nunca apuntan a la coleccion plcs',
        () {
          expect(
            FirestorePaths.sectorDoc('the-gene-pig', 'genetica'),
            isNot(contains('/plcs/')),
          );
          expect(
            FirestorePaths.deviceDoc('the-gene-pig', 's7_principal'),
            isNot(contains('/plcs/')),
          );
        },
      );
    },
  );

  group('10. La deserializacion tolera campos opcionales faltantes', () {
    test('AgroSite.fromFirestore con mapa vacio usa defaults seguros', () {
      final AgroSite site = AgroSite.fromFirestore(
        'main_site',
        tenantId: 'the-gene-pig',
        data: const <String, Object?>{'name': 'Establecimiento principal'},
      );

      expect(site.name, 'Establecimiento principal');
      expect(site.description, '');
      expect(site.enabled, isTrue);
      expect(site.createdAt, isNull);
      expect(site.updatedAt, isNull);
    });

    test('AgroSector.fromFirestore tolera description/enabled ausentes', () {
      final AgroSector sector = AgroSector.fromFirestore(
        'genetica',
        tenantId: 'the-gene-pig',
        data: const <String, Object?>{
          'siteId': 'main_site',
          'name': 'Genetica',
        },
      );

      expect(sector.siteId, 'main_site');
      expect(sector.description, '');
      expect(sector.enabled, isTrue);
    });

    test(
      'AgroDevice.fromFirestore tolera model/description/enabled ausentes y type desconocido cae a "other"',
      () {
        final AgroDevice device = AgroDevice.fromFirestore(
          's7_principal',
          tenantId: 'the-gene-pig',
          data: const <String, Object?>{
            'siteId': 'main_site',
            'name': 'S7 principal',
          },
        );

        expect(device.siteId, 'main_site');
        expect(device.type, AgroDeviceType.other);
        expect(device.model, '');
        expect(device.description, '');
        expect(device.enabled, isTrue);
      },
    );
  });

  group('11. Alta de tenant estructural valida antes de escribir', () {
    const UserManagementService service = UserManagementService();

    test('rechaza lista de sectores vacia', () async {
      await expectLater(
        service.createTenant(
          tenantId: 'nuevo-tenant',
          tenantName: 'Nuevo tenant',
          siteId: 'genetica',
          siteName: 'Genetica',
          sectors: const <SectorCreateInput>[],
          devices: const <DeviceCreateInput>[
            DeviceCreateInput(
              deviceId: 'plc-munters-1',
              name: 'PLC Munters 1',
              type: 'logo',
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rechaza lista de devices vacia', () async {
      await expectLater(
        service.createTenant(
          tenantId: 'nuevo-tenant',
          tenantName: 'Nuevo tenant',
          siteId: 'genetica',
          siteName: 'Genetica',
          sectors: const <SectorCreateInput>[
            SectorCreateInput(sectorId: 'sala-1', name: 'Sala 1'),
          ],
          devices: const <DeviceCreateInput>[],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rechaza Sector IDs duplicados normalizados', () async {
      await expectLater(
        service.createTenant(
          tenantId: 'nuevo-tenant',
          tenantName: 'Nuevo tenant',
          siteId: 'genetica',
          siteName: 'Genetica',
          sectors: const <SectorCreateInput>[
            SectorCreateInput(sectorId: 'Sala 1', name: 'Sala 1'),
            SectorCreateInput(sectorId: 'sala-1', name: 'Sala 1 bis'),
          ],
          devices: const <DeviceCreateInput>[
            DeviceCreateInput(
              deviceId: 'plc-munters-1',
              name: 'PLC Munters 1',
              type: 'logo',
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rechaza Device IDs duplicados normalizados', () async {
      await expectLater(
        service.createTenant(
          tenantId: 'nuevo-tenant',
          tenantName: 'Nuevo tenant',
          siteId: 'genetica',
          siteName: 'Genetica',
          sectors: const <SectorCreateInput>[
            SectorCreateInput(sectorId: 'sala-1', name: 'Sala 1'),
          ],
          devices: const <DeviceCreateInput>[
            DeviceCreateInput(
              deviceId: 'PLC Munters 1',
              name: 'PLC Munters 1',
              type: 'logo',
            ),
            DeviceCreateInput(
              deviceId: 'plc-munters-1',
              name: 'PLC Munters 1 bis',
              type: 'logo',
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rechaza nombres obligatorios vacios', () async {
      await expectLater(
        service.createTenant(
          tenantId: 'nuevo-tenant',
          tenantName: 'Nuevo tenant',
          siteId: 'genetica',
          siteName: 'Genetica',
          sectors: const <SectorCreateInput>[
            SectorCreateInput(sectorId: 'sala-1', name: ''),
          ],
          devices: const <DeviceCreateInput>[
            DeviceCreateInput(
              deviceId: 'plc-munters-1',
              name: 'PLC Munters 1',
              type: 'logo',
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('12. Operatividad de Sites y snapshot', () {
    test('Site estructural pending_backend no es operativo', () {
      const SiteDocument site = SiteDocument(
        siteId: 'test_site',
        technicalId: 'test_site',
        name: 'Test Site',
        backendUrl: null,
        active: false,
        enabled: true,
        provisioningStatus: SiteProvisioningStatus.pendingBackend,
      );

      expect(site.isVisibleSite, isTrue);
      expect(site.isOperational, isFalse);
      expect(site.operationalStatusLabel, 'Pendiente de backend');
    });

    test('Site legacy active con backendUrl sigue operativo', () {
      const SiteDocument site = SiteDocument(
        siteId: 'genetica-1',
        technicalId: 'genetica-1',
        name: 'Genetica 1',
        backendUrl: 'https://agrodata-control.valke.com.ar/api/snapshot',
        active: true,
        enabled: true,
        provisioningStatus: null,
      );

      expect(site.isOperational, isTrue);
      expect(site.operationalStatusLabel, 'Listo');
    });

    test('Site disabled nunca es operativo', () {
      const SiteDocument site = SiteDocument(
        siteId: 'test_site',
        technicalId: 'test_site',
        name: 'Test Site',
        backendUrl: 'https://agrodata-control.valke.com.ar/api/snapshot',
        active: true,
        enabled: false,
        provisioningStatus: SiteProvisioningStatus.ready,
      );

      expect(site.isVisibleSite, isFalse);
      expect(site.isOperational, isFalse);
      expect(site.operationalStatusLabel, 'Deshabilitado');
    });

    test(
      'PlcDashboardService no usa endpoint global si el Site no esta operativo',
      () async {
        const PlcDashboardService service = PlcDashboardService(
          endpoint: null,
          tenantId: 'test_tenant_structural',
          siteId: 'test_site',
          allowGlobalEndpointFallback: false,
        );

        final LiveSnapshotResult result = await service.fetchLiveSnapshot();

        expect(result.isSuccess, isFalse);
        expect(result.isSiteNotOperational, isTrue);
        expect(result.endpoint, isNull);
      },
    );
  });
}
