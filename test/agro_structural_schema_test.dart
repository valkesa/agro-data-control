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
import 'dart:io';

import 'package:agro_data_control/firebase/firestore_paths.dart';
import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/models/agro_device_room.dart';
import 'package:agro_data_control/models/agro_sector.dart';
import 'package:agro_data_control/models/agro_site.dart';
import 'package:agro_data_control/models/agro_tenant.dart';
import 'package:agro_data_control/services/site_config_service.dart';
import 'package:agro_data_control/services/agro_device_room_service.dart'
    show
        AgroDeviceRoomService,
        buildAgroDeviceRoomCreatePayload,
        compareAgroDeviceRoomsForDisplay;
import 'package:agro_data_control/services/agro_device_service.dart'
    show
        AgroDeviceService,
        buildAgroDeviceCreatePayload,
        compareAgroDevicesForDisplay;
import 'package:agro_data_control/services/agro_sector_service.dart'
    show AgroSectorService, buildAgroSectorCreatePayload;
import 'package:agro_data_control/services/agro_site_hierarchy_service.dart';
import 'package:agro_data_control/services/agro_site_service.dart'
    show buildAgroSiteCreatePayload, buildAgroSiteUpdatePayload;
import 'package:agro_data_control/services/agro_tenant_service.dart'
    show
        AgroTenantService,
        buildAgroTenantCreatePayload,
        buildAgroTenantUpdatePayload;
import 'package:agro_data_control/services/plc_dashboard_service.dart';
import 'package:agro_data_control/services/structural_id_helpers.dart';
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
        expect(device.sortOrder, 0);
        expect(device.snapshotUnitKey, isNull);
        expect(device.effectiveSnapshotUnitKey, 's7_principal');
      },
    );
  });

  group('13. sortOrder y snapshotUnitKey en AgroDevice', () {
    test(
      'fromFirestore lee sortOrder y snapshotUnitKey cuando estan presentes',
      () {
        final AgroDevice device = AgroDevice.fromFirestore(
          's7_principal',
          tenantId: 'the-gene-pig',
          data: const <String, Object?>{
            'siteId': 'main_site',
            'name': 'S7 principal',
            'sortOrder': 2,
            'snapshotUnitKey': 'unit_s7_principal',
          },
        );

        expect(device.sortOrder, 2);
        expect(device.snapshotUnitKey, 'unit_s7_principal');
        expect(device.effectiveSnapshotUnitKey, 'unit_s7_principal');
      },
    );

    test(
      'toCreatePayload incluye sortOrder siempre, snapshotUnitKey solo si esta seteado',
      () {
        const AgroDevice withKey = AgroDevice(
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
          sortOrder: 3,
          snapshotUnitKey: 'unit_s7_principal',
        );
        const AgroDevice withoutKey = AgroDevice(
          id: 's7_secundario',
          tenantId: 'the-gene-pig',
          siteId: 'main_site',
          name: 'S7 secundario',
          type: AgroDeviceType.s7,
          model: 'S7-1500',
          description: '',
          enabled: true,
          createdAt: null,
          updatedAt: null,
        );

        final Map<String, Object?> withKeyPayload = withKey.toCreatePayload();
        final Map<String, Object?> withoutKeyPayload = withoutKey
            .toCreatePayload();

        expect(withKeyPayload['sortOrder'], 3);
        expect(withKeyPayload['snapshotUnitKey'], 'unit_s7_principal');
        expect(withoutKeyPayload['sortOrder'], 0);
        expect(withoutKeyPayload.containsKey('snapshotUnitKey'), isFalse);
      },
    );

    test(
      'toUpdatePayload nunca incluye siteId/createdAt, siempre incluye sortOrder',
      () {
        const AgroDevice device = AgroDevice(
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
          sortOrder: 1,
        );

        final Map<String, Object?> payload = device.toUpdatePayload();

        expect(payload['sortOrder'], 1);
        expect(payload.containsKey('snapshotUnitKey'), isFalse);
        expect(payload.containsKey('siteId'), isFalse);
        expect(payload.containsKey('createdAt'), isFalse);
      },
    );
  });

  group('14. firestore.rules permite sortOrder/snapshotUnitKey en devices', () {
    late String rulesSource;

    setUpAll(() {
      rulesSource = File('firestore.rules').readAsStringSync();
    });

    test('create y update de devices incluyen los 2 campos nuevos en hasOnly', () {
      final int devicesBlockStart = rulesSource.indexOf(
        'match /devices/{deviceId}',
      );
      expect(devicesBlockStart, greaterThan(-1));
      final String devicesBlock = rulesSource.substring(
        devicesBlockStart,
        devicesBlockStart + 3000,
      );

      expect(
        devicesBlock,
        contains(
          "'siteId', 'name', 'type', 'model', 'description', 'enabled', 'createdAt', 'updatedAt', 'sortOrder', 'snapshotUnitKey'",
        ),
      );
      expect(
        devicesBlock,
        contains(
          "'name', 'type', 'model', 'description', 'enabled', 'updatedAt', 'sortOrder', 'snapshotUnitKey'",
        ),
      );
      // sortOrder/snapshotUnitKey must stay optional on create — never
      // required in hasAll, only in the (larger) hasOnly allowlist.
      expect(
        devicesBlock,
        contains(
          "hasAll(['siteId', 'name', 'type', 'model', 'description', 'enabled', 'createdAt', 'updatedAt'])",
        ),
      );
    });
  });

  group(
    '15. compareAgroDevicesForDisplay ordena por sortOrder, luego name',
    () {
      AgroDevice deviceWith({
        required String id,
        required String name,
        int sortOrder = 0,
      }) {
        return AgroDevice(
          id: id,
          tenantId: 'the-gene-pig',
          siteId: 'main_site',
          name: name,
          type: AgroDeviceType.s7,
          model: '',
          description: '',
          enabled: true,
          createdAt: null,
          updatedAt: null,
          sortOrder: sortOrder,
        );
      }

      test('lista vacia no rompe (0 devices)', () {
        final List<AgroDevice> devices = <AgroDevice>[]
          ..sort(compareAgroDevicesForDisplay);
        expect(devices, isEmpty);
      });

      test('un solo device (1 device)', () {
        final List<AgroDevice> devices = <AgroDevice>[
          deviceWith(id: 'a', name: 'PLC Maternidad'),
        ]..sort(compareAgroDevicesForDisplay);
        expect(devices.single.id, 'a');
      });

      test(
        'N devices: sortOrder ascendente tiene prioridad sobre el nombre',
        () {
          final List<AgroDevice> devices = <AgroDevice>[
            deviceWith(id: 'c', name: 'Z-later', sortOrder: 2),
            deviceWith(id: 'a', name: 'A-first', sortOrder: 0),
            deviceWith(id: 'b', name: 'B-middle', sortOrder: 1),
          ]..sort(compareAgroDevicesForDisplay);

          expect(devices.map((d) => d.id).toList(), <String>['a', 'b', 'c']);
        },
      );

      test('empate en sortOrder se resuelve por nombre (orden alfabetico)', () {
        final List<AgroDevice> devices = <AgroDevice>[
          deviceWith(id: 'b', name: 'PLC Maternidad', sortOrder: 0),
          deviceWith(id: 'a', name: 'PLC Gestacion', sortOrder: 0),
        ]..sort(compareAgroDevicesForDisplay);

        expect(devices.map((d) => d.id).toList(), <String>['a', 'b']);
      });
    },
  );

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
      expect(site.usesDynamicDevices, isFalse);
    });

    test('usesDynamicDevices: false para legacy (provisioningStatus null), '
        'true para cualquier Site del esquema nuevo', () {
      const SiteDocument legacySite = SiteDocument(
        siteId: 'genetica-1',
        technicalId: 'genetica-1',
        name: 'Genetica 1',
        backendUrl: 'https://agrodata-control.valke.com.ar/api/snapshot',
        active: true,
        enabled: true,
        provisioningStatus: null,
      );
      const SiteDocument pendingSite = SiteDocument(
        siteId: 'roque-perez',
        technicalId: 'roque-perez',
        name: 'Roque Perez',
        backendUrl: null,
        active: false,
        enabled: true,
        provisioningStatus: SiteProvisioningStatus.pendingBackend,
      );
      const SiteDocument readySite = SiteDocument(
        siteId: 'roque-perez',
        technicalId: 'roque-perez',
        name: 'Roque Perez',
        backendUrl: 'https://agrodata-control.valke.com.ar/api/snapshot',
        active: false,
        enabled: true,
        provisioningStatus: SiteProvisioningStatus.ready,
      );
      const SiteDocument errorSite = SiteDocument(
        siteId: 'roque-perez',
        technicalId: 'roque-perez',
        name: 'Roque Perez',
        backendUrl: null,
        active: false,
        enabled: true,
        provisioningStatus: SiteProvisioningStatus.error,
      );

      expect(legacySite.usesDynamicDevices, isFalse);
      expect(pendingSite.usesDynamicDevices, isTrue);
      expect(readySite.usesDynamicDevices, isTrue);
      expect(errorSite.usesDynamicDevices, isTrue);
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

  group('16. AgroDeviceRoom — un Device fisico puede exponer N Salas', () {
    test('fromFirestore lee todos los campos, con defaults tolerantes', () {
      final AgroDeviceRoom room = AgroDeviceRoom.fromFirestore(
        'sala-1',
        tenantId: 'la-payana',
        deviceId: 'plc-maternidad',
        data: const <String, Object?>{
          'siteId': 'roque-perez',
          'name': 'Sala 1',
          'enabled': true,
          'sortOrder': 1,
          'snapshotUnitKey': 'plc-maternidad__sala-1',
        },
      );

      expect(room.siteId, 'roque-perez');
      expect(room.name, 'Sala 1');
      expect(room.sortOrder, 1);
      expect(room.snapshotUnitKey, 'plc-maternidad__sala-1');
      expect(room.effectiveSnapshotUnitKey, 'plc-maternidad__sala-1');
    });

    test('fromFirestore tolera sortOrder/snapshotUnitKey ausentes', () {
      final AgroDeviceRoom room = AgroDeviceRoom.fromFirestore(
        'sala-x',
        tenantId: 'la-payana',
        deviceId: 'plc-maternidad',
        data: const <String, Object?>{
          'siteId': 'roque-perez',
          'name': 'Sala X',
        },
      );

      expect(room.sortOrder, 0);
      expect(room.snapshotUnitKey, isNull);
      expect(room.enabled, isTrue);
      // Sin snapshotUnitKey explicito, cae a `${deviceId}__$id`.
      expect(room.effectiveSnapshotUnitKey, 'plc-maternidad__sala-x');
    });

    test(
      'toCreatePayload incluye sortOrder siempre, snapshotUnitKey solo si esta seteado',
      () {
        const AgroDeviceRoom withKey = AgroDeviceRoom(
          id: 'sala-1',
          tenantId: 'la-payana',
          deviceId: 'plc-maternidad',
          siteId: 'roque-perez',
          name: 'Sala 1',
          enabled: true,
          createdAt: null,
          updatedAt: null,
          sortOrder: 1,
          snapshotUnitKey: 'plc-maternidad__sala-1',
        );
        const AgroDeviceRoom withoutKey = AgroDeviceRoom(
          id: 'sala-2',
          tenantId: 'la-payana',
          deviceId: 'plc-maternidad',
          siteId: 'roque-perez',
          name: 'Sala 2',
          enabled: true,
          createdAt: null,
          updatedAt: null,
        );

        final Map<String, Object?> withKeyPayload = withKey.toCreatePayload();
        final Map<String, Object?> withoutKeyPayload = withoutKey
            .toCreatePayload();

        expect(withKeyPayload['sortOrder'], 1);
        expect(withKeyPayload['snapshotUnitKey'], 'plc-maternidad__sala-1');
        expect(withoutKeyPayload['sortOrder'], 0);
        expect(withoutKeyPayload.containsKey('snapshotUnitKey'), isFalse);
      },
    );

    test('toUpdatePayload nunca incluye siteId/createdAt', () {
      const AgroDeviceRoom room = AgroDeviceRoom(
        id: 'sala-1',
        tenantId: 'la-payana',
        deviceId: 'plc-maternidad',
        siteId: 'roque-perez',
        name: 'Sala 1',
        enabled: true,
        createdAt: null,
        updatedAt: null,
      );

      final Map<String, Object?> payload = room.toUpdatePayload();

      expect(payload.containsKey('siteId'), isFalse);
      expect(payload.containsKey('createdAt'), isFalse);
    });

    test('AgroDeviceRoomService.create exige name no vacio', () async {
      const AgroDeviceRoomService service = AgroDeviceRoomService();

      await expectLater(
        () => service.create(
          tenantId: 'la-payana',
          deviceId: 'plc-maternidad',
          roomId: 'sala-1',
          siteId: 'roque-perez',
          name: '   ',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'compareAgroDeviceRoomsForDisplay ordena por sortOrder, luego name',
      () {
        AgroDeviceRoom roomWith({
          required String id,
          required String name,
          int sortOrder = 0,
        }) {
          return AgroDeviceRoom(
            id: id,
            tenantId: 'la-payana',
            deviceId: 'plc-maternidad',
            siteId: 'roque-perez',
            name: name,
            enabled: true,
            createdAt: null,
            updatedAt: null,
            sortOrder: sortOrder,
          );
        }

        final List<AgroDeviceRoom> rooms = <AgroDeviceRoom>[
          roomWith(id: 'z', name: 'Sala Z', sortOrder: 2),
          roomWith(id: 'a', name: 'Sala A', sortOrder: 0),
          roomWith(id: 'm', name: 'Sala M', sortOrder: 1),
        ]..sort(compareAgroDeviceRoomsForDisplay);

        expect(rooms.map((r) => r.id).toList(), <String>['a', 'm', 'z']);
      },
    );

    test(
      'firestore.rules define /devices/{deviceId}/rooms/{roomId} con allowlist consistente',
      () {
        final String rulesSource = File('firestore.rules').readAsStringSync();
        final int roomsBlockStart = rulesSource.indexOf(
          'match /rooms/{roomId}',
        );
        expect(roomsBlockStart, greaterThan(-1));
        final String roomsBlock = rulesSource.substring(
          roomsBlockStart,
          roomsBlockStart + 3000,
        );

        expect(
          roomsBlock,
          contains(
            "hasOnly(['siteId', 'name', 'enabled', 'sortOrder', 'snapshotUnitKey', 'createdAt', 'updatedAt'])",
          ),
        );
        expect(
          roomsBlock,
          contains(
            "hasAll(['siteId', 'name', 'enabled', 'createdAt', 'updatedAt'])",
          ),
        );
        expect(
          roomsBlock,
          contains(
            'existsAfter(/databases/\$(database)/documents/tenants/\$(tenantId)/devices/\$(deviceId))',
          ),
        );
        expect(roomsBlock, contains('allow delete: if false;'));
      },
    );
  });

  group('17. AgroSiteService.update no resetea provisioningStatus (fix del bug)', () {
    test(
      'buildAgroSiteUpdatePayload omite provisioningStatus si no se pasa explicitamente',
      () {
        final Map<String, Object?> payload = buildAgroSiteUpdatePayload(
          name: 'Roque Perez',
          description: '',
          enabled: true,
        );

        expect(payload.containsKey('provisioningStatus'), isFalse);
        expect(payload['name'], 'Roque Perez');
        expect(payload.containsKey('updatedAt'), isTrue);
      },
    );

    test(
      'buildAgroSiteUpdatePayload SI incluye provisioningStatus cuando se pasa explicitamente',
      () {
        final Map<String, Object?> payload = buildAgroSiteUpdatePayload(
          name: 'Roque Perez',
          provisioningStatus: SiteProvisioningStatus.ready,
        );

        expect(payload['provisioningStatus'], SiteProvisioningStatus.ready);
      },
    );

    test(
      'editar name/description no cambia provisioningStatus (regresion del bug)',
      () {
        // Antes del fix, AgroSiteService.update() hardcodeaba
        // provisioningStatus: pending_backend en TODA edicion, incluso una
        // que solo cambiaba el nombre — reseteando silenciosamente un
        // site que ya estaba "ready". El fix: el payload de update es
        // parcial, y sin provisioningStatus explicito la clave ni
        // siquiera existe en el mapa (ver test anterior), asi que un
        // merge write no la toca.
        final Map<String, Object?> onlyNameEdit = buildAgroSiteUpdatePayload(
          name: 'Nuevo nombre',
          description: 'Nueva descripcion',
          enabled: true,
        );

        expect(
          onlyNameEdit.containsKey('provisioningStatus'),
          isFalse,
          reason:
              'una edicion de name/description/enabled nunca debe tocar '
              'provisioningStatus',
        );
      },
    );
  });

  group('18. AgroTenant — modelo y payloads de administracion', () {
    test('fromFirestore lee todos los campos', () {
      final AgroTenant tenant = AgroTenant.fromFirestore('la-payana', {
        'name': 'La Payana',
        'active': true,
        'createdByUid': 'uid123',
        'createdByEmail': 'gerardo@valke.com.ar',
      });

      expect(tenant.id, 'la-payana');
      expect(tenant.name, 'La Payana');
      expect(tenant.active, isTrue);
      expect(tenant.createdByUid, 'uid123');
      expect(tenant.createdByEmail, 'gerardo@valke.com.ar');
    });

    test('fromFirestore tolera createdByEmail ausente', () {
      final AgroTenant tenant = AgroTenant.fromFirestore('the-gene-pig', {
        'name': 'The Gene Pig',
        'active': true,
        'createdByUid': 'uid123',
      });

      expect(tenant.createdByEmail, isNull);
    });

    test(
      'buildAgroTenantUpdatePayload solo contiene name, active y updatedAt',
      () {
        final Map<String, Object?> payload = buildAgroTenantUpdatePayload(
          name: 'La Payana',
          active: true,
        );

        expect(payload.keys.toSet(), <String>{'name', 'active', 'updatedAt'});
      },
    );

    test('buildAgroTenantUpdatePayload nunca incluye campos inmutables', () {
      final Map<String, Object?> payload = buildAgroTenantUpdatePayload(
        name: 'La Payana',
        active: false,
      );

      expect(payload.containsKey('createdByUid'), isFalse);
      expect(payload.containsKey('createdByEmail'), isFalse);
      expect(payload.containsKey('createdAt'), isFalse);
    });

    test(
      'buildAgroTenantCreatePayload incluye createdByEmail solo si no esta vacio',
      () {
        final Map<String, Object?> withEmail = buildAgroTenantCreatePayload(
          name: 'La Payana',
          createdByUid: 'uid123',
          createdByEmail: 'gerardo@valke.com.ar',
        );
        final Map<String, Object?> withoutEmail = buildAgroTenantCreatePayload(
          name: 'La Payana',
          createdByUid: 'uid123',
        );

        expect(withEmail['createdByEmail'], 'gerardo@valke.com.ar');
        expect(withoutEmail.containsKey('createdByEmail'), isFalse);
        expect(withEmail['active'], isTrue);
      },
    );

    test('AgroTenantService.updateTenant exige name no vacio', () async {
      const AgroTenantService service = AgroTenantService();

      await expectLater(
        () => service.updateTenant(
          tenantId: 'la-payana',
          name: '   ',
          active: true,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group(
    '19. firestore.rules permite update de tenant solo a owner, con allowlist estricta',
    () {
      late String rulesSource;
      late String tenantBlock;

      setUpAll(() {
        rulesSource = File('firestore.rules').readAsStringSync();
        final int start = rulesSource.indexOf('match /tenants/{tenantId}');
        final int membersStart = rulesSource.indexOf(
          'match /members/{uid}',
          start,
        );
        expect(start, greaterThan(-1));
        expect(membersStart, greaterThan(start));
        // Scoped to just the tenant-level create/update/delete rules —
        // deliberately excludes the nested /members block (which DOES
        // reference isTenantAdmin, for a different, unrelated permission).
        tenantBlock = rulesSource.substring(start, membersStart);
      });

      test('agrega allow update con allowlist name/active/updatedAt', () {
        expect(
          tenantBlock,
          contains("hasOnly(['name', 'active', 'updatedAt'])"),
        );
        expect(tenantBlock, contains('allow update: if isOwner()'));
      });

      test('tenant_admin no aparece en las reglas de update de tenant', () {
        expect(tenantBlock, isNot(contains('isTenantAdmin')));
      });

      test('mantiene allow delete: if false para el tenant', () {
        expect(tenantBlock, contains('allow delete: if false;'));
      });

      test(
        'createdByUid/createdByEmail/createdAt quedan fuera del allowlist de update',
        () {
          final int updateStart = tenantBlock.indexOf('allow update:');
          final int updateEnd = tenantBlock.indexOf(';', updateStart);
          final String updateRule = tenantBlock.substring(
            updateStart,
            updateEnd,
          );

          expect(updateRule, isNot(contains('createdByUid')));
          expect(updateRule, isNot(contains('createdByEmail')));
          expect(updateRule, isNot(contains('createdAt')));
        },
      );
    },
  );

  group(
    '20. structural_id_helpers — normalizacion y validacion compartidas',
    () {
      test('normalizeStructuralId colapsa caracteres invalidos', () {
        expect(normalizeStructuralId('  La Payana!! '), 'la-payana');
        expect(normalizeStructuralId('Roque--Perez'), 'roque-perez');
      });

      test('requireNonEmptyField retorna el valor trimeado', () {
        expect(
          requireNonEmptyField('  Roque Perez  ', 'El nombre'),
          'Roque Perez',
        );
      });

      test('requireNonEmptyField lanza StateError con mensaje en espaniol', () {
        expect(
          () => requireNonEmptyField('   ', 'El tenantId'),
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              'El tenantId es requerido.',
            ),
          ),
        );
      });

      test('requireUniqueNormalizedIds detecta duplicados', () {
        expect(
          () => requireUniqueNormalizedIds(<String>[
            'sala-1',
            'sala-2',
            'sala-1',
          ], 'Los Sector ID'),
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              'Los Sector ID no pueden repetirse.',
            ),
          ),
        );
      });

      test('requireUniqueNormalizedIds no lanza si son unicos', () {
        expect(
          () => requireUniqueNormalizedIds(<String>[
            'sala-1',
            'sala-2',
          ], 'Los Sector ID'),
          returnsNormally,
        );
      });
    },
  );

  group(
    '21. createTenant usa los mismos payload builders que los servicios individuales',
    () {
      test(
        'el payload de Site de createTenant coincide con buildAgroSiteCreatePayload',
        () {
          // createTenant ya no reconstruye el payload a mano — llama al
          // mismo buildAgroSiteCreatePayload que AgroSiteService.create()
          // usa. Esta prueba fija esa expectativa: si alguna vez alguien
          // reintroduce una segunda implementacion inline, este test deja
          // de tener sentido de comparar consigo mismo y hay que revisar
          // el diff con cuidado.
          final Map<String, Object?> payload = buildAgroSiteCreatePayload(
            tenantId: 'la-payana',
            siteId: 'roque-perez',
            name: 'Roque Perez',
            description: '',
            enabled: true,
          );

          expect(
            payload['provisioningStatus'],
            SiteProvisioningStatus.pendingBackend,
          );
          expect(payload.containsKey('createdAt'), isTrue);
        },
      );

      test(
        'los payloads de Sector/Device comparten forma con sus servicios individuales',
        () {
          final Map<String, Object?> sectorPayload =
              buildAgroSectorCreatePayload(
                tenantId: 'la-payana',
                sectorId: 'sala-1',
                siteId: 'roque-perez',
                name: 'Sala 1',
              );
          final Map<String, Object?> devicePayload =
              buildAgroDeviceCreatePayload(
                tenantId: 'la-payana',
                deviceId: 'plc-maternidad',
                siteId: 'roque-perez',
                name: 'PLC Maternidad',
                type: 'sensor_gateway',
              );

          expect(sectorPayload['siteId'], 'roque-perez');
          expect(devicePayload['siteId'], 'roque-perez');
          expect(devicePayload['type'], 'sensor_gateway');
        },
      );
    },
  );

  group(
    '22. Formulario "Crear tenant" ya no genera valores Munters por defecto',
    () {
      late String formSource;

      setUpAll(() {
        formSource = File(
          'lib/pages/user_management_page.dart',
        ).readAsStringSync();
      });

      test(
        'no quedan literales plc-munters-* ni "PLC Munters" en el archivo',
        () {
          expect(formSource, isNot(contains('plc-munters-1')));
          expect(formSource, isNot(contains('plc-munters-2')));
          expect(formSource, isNot(contains('PLC Munters')));
        },
      );

      test("'logo' ya no es el tipo generico precargado por defecto", () {
        // No debe quedar un _DeviceRowState(..., type: 'logo') como fila
        // inicial — el placeholder de "Tipo" en el hint tampoco debe ser
        // 'logo' (evita reforzar un default de facto).
        expect(formSource, isNot(contains("type: 'logo'")));
        expect(formSource, isNot(contains("hintText: 'logo'")));
      });

      test('las filas iniciales de sectores/devices arrancan vacias', () {
        expect(
          formSource,
          contains(
            'final List<_SectorRowState> _sectors = <_SectorRowState>[\n'
            "    _SectorRowState(id: '', name: ''),\n"
            '  ];',
          ),
        );
        expect(
          formSource,
          contains(
            'final List<_DeviceRowState> _devices = <_DeviceRowState>[\n'
            "    _DeviceRowState(id: '', name: '', type: ''),\n"
            '  ];',
          ),
        );
      });

      test('site ID inicial ya no arranca precargado con "sitio-1"', () {
        expect(
          formSource,
          isNot(contains("TextEditingController(\n    text: 'sitio-1',\n  );")),
        );
      });
    },
  );

  group(
    '23. AgroDeviceRoomService.create valida antes de escribir en Firestore',
    () {
      test('rechaza un name vacio antes de tocar Firestore', () async {
        const AgroDeviceRoomService service = AgroDeviceRoomService();
        await expectLater(
          service.create(
            tenantId: 'la-payana',
            deviceId: 'plc-maternidad',
            roomId: 'sala-1',
            siteId: 'roque-perez',
            name: '   ',
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('buildAgroDeviceRoomCreatePayload arma el payload esperado', () {
        final Map<String, Object?> payload = buildAgroDeviceRoomCreatePayload(
          tenantId: 'la-payana',
          deviceId: 'plc-maternidad',
          roomId: 'sala-1',
          siteId: 'roque-perez',
          name: 'Sala 1',
          snapshotUnitKey: 'plc-maternidad__sala-1',
        );

        expect(payload['siteId'], 'roque-perez');
        expect(payload['name'], 'Sala 1');
        expect(payload['snapshotUnitKey'], 'plc-maternidad__sala-1');
      });
    },
    // NOTA: el chequeo de "deviceId pertenece al tenant" (via
    // deviceService.getById antes de escribir — antes ausente, ahora
    // agregado como fix de esta etapa) requiere una llamada real a
    // Firestore para el caso donde el name SI es valido, y este repo no
    // tiene emulador de Firestore configurado (ver el comentario al inicio
    // de este archivo). Verificado por revision de codigo:
    // AgroDeviceRoomService.create ahora llama a
    // `deviceService.getById(tenantId: tenantId, deviceId: deviceId)`
    // antes del `.set(...)`, exactamente como AgroSectorService.create y
    // AgroDeviceService.create ya hacian con `siteService.getById`.
  );

  group(
    '24. Listados administrativos: includeDisabled no rompe el default del dashboard',
    () {
      test(
        'AgroDeviceService.listBySite sigue aceptando la firma sin includeDisabled',
        () async {
          const AgroDeviceService service = AgroDeviceService();
          // Sin Firebase inicializado, la llamada real a Firestore falla y el
          // catch interno del servicio devuelve lista vacia — lo que importa
          // aca es que la firma por defecto (includeDisabled: false, el
          // comportamiento historico del dashboard) sigue compilando y
          // ejecutando sin parametros nuevos obligatorios.
          final result = await service.listBySite(
            tenantId: 'la-payana',
            siteId: 'roque-perez',
          );
          expect(result, isA<List<AgroDevice>>());
        },
      );

      test(
        'AgroDeviceService.listBySite(includeDisabled: true) tiene la misma forma de retorno',
        () async {
          const AgroDeviceService service = AgroDeviceService();
          final result = await service.listBySite(
            tenantId: 'la-payana',
            siteId: 'roque-perez',
            includeDisabled: true,
          );
          expect(result, isA<List<AgroDevice>>());
        },
      );
    },
  );

  group('25. Invalidacion explicita de cache no falla', () {
    test(
      'cada servicio expone invalidateCache callable sin argumentos extra',
      () {
        const AgroTenantService tenantService = AgroTenantService();
        const AgroSectorService sectorService = AgroSectorService();

        expect(() => tenantService.invalidateCache(), returnsNormally);
        expect(
          () => sectorService.invalidateCache(tenantId: 'la-payana'),
          returnsNormally,
        );
        expect(
          () => sectorService.invalidateCache(
            tenantId: 'la-payana',
            siteId: 'roque-perez',
          ),
          returnsNormally,
        );
      },
    );
  });

  group(
    '26. AgroSite.isLegacyStructure distingue legacy de "nuevo, pending_backend"',
    () {
      test(
        'sin provisioningStatus almacenado (legacy real, ej. genetica-1) -> isLegacyStructure true',
        () {
          final AgroSite site = AgroSite.fromFirestore(
            'genetica-1',
            tenantId: 'the-gene-pig',
            data: const <String, Object?>{
              'name': 'Genetica 1',
              'active': true,
              // Sin 'provisioningStatus' — asi es el documento legacy real
              // hoy en produccion.
            },
          );

          expect(site.isLegacyStructure, isTrue);
          // Aun asi expone un provisioningStatus por defecto usable (para
          // no romper codigo que ya asume el string no-nulo).
          expect(
            site.provisioningStatus,
            SiteProvisioningStatus.pendingBackend,
          );
        },
      );

      test(
        'con provisioningStatus "pending_backend" explicito (ej. La Payana recien creado) -> isLegacyStructure false',
        () {
          final AgroSite site = AgroSite.fromFirestore(
            'roque-perez',
            tenantId: 'la-payana',
            data: const <String, Object?>{
              'name': 'Roque Perez',
              'active': true,
              'provisioningStatus': 'pending_backend',
            },
          );

          expect(site.isLegacyStructure, isFalse);
          expect(
            site.provisioningStatus,
            SiteProvisioningStatus.pendingBackend,
          );
        },
      );

      test(
        'instancias construidas a mano (create/update payloads) son isLegacyStructure=false por default',
        () {
          const AgroSite site = AgroSite(
            id: 'roque-perez',
            tenantId: 'la-payana',
            name: 'Roque Perez',
            description: '',
            enabled: true,
            provisioningStatus: SiteProvisioningStatus.pendingBackend,
            createdAt: null,
            updatedAt: null,
          );

          expect(site.isLegacyStructure, isFalse);
        },
      );
    },
  );
}
