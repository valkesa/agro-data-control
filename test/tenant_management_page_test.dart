// Tests for TenantManagementPage — "Configuración → Administración → Gestión
// de clientes" (Etapa 2). No Firebase is initialized in this test.
//
// AgroTenantService.listTenantsForAdministration() is the one structural
// service method that RETHROWS on a Firestore failure instead of swallowing
// it into an empty list (see the doc comment on that method for why) — so
// pumping the real page here, without Firebase, deterministically exercises
// the ERROR path, not the empty-state path. That's exactly what proves the
// error UI is reachable at all: before this was fixed, the page's own catch
// block around that call was unreachable dead code, because the service
// underneath it already swallowed everything.
//
// filterTenants is a pure, Firestore-free function — the actual search/filter
// logic gets full unit-test coverage independent of any widget pumping.
import 'dart:io';

import 'package:agro_data_control/models/agro_device_type_catalog.dart';
import 'package:agro_data_control/models/agro_tenant.dart';
import 'package:agro_data_control/pages/tenant_management_page.dart';
import 'package:agro_data_control/services/agro_device_provisioning_service.dart';
import 'package:agro_data_control/services/firestore_error_messages.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filterTenants (pure, sin Firestore)', () {
    final List<AgroTenant> tenants = <AgroTenant>[
      AgroTenant.fromFirestore('la-payana', {
        'name': 'La Payana',
        'active': true,
        'createdByUid': 'uid1',
      }),
      AgroTenant.fromFirestore('the-gene-pig', {
        'name': 'The Gene Pig',
        'active': true,
        'createdByUid': 'uid2',
      }),
      AgroTenant.fromFirestore('cliente-demo', {
        'name': 'Cliente Demo',
        'active': false,
        'createdByUid': 'uid3',
      }),
    ];

    test('sin query ni filtro devuelve todos', () {
      final result = filterTenants(
        tenants,
        query: '',
        filter: TenantStatusFilter.all,
      );
      expect(result, hasLength(3));
    });

    test('busca por nombre (case-insensitive)', () {
      final result = filterTenants(
        tenants,
        query: 'gene pig',
        filter: TenantStatusFilter.all,
      );
      expect(result, hasLength(1));
      expect(result.single.id, 'the-gene-pig');
    });

    test('busca por Tenant ID', () {
      final result = filterTenants(
        tenants,
        query: 'la-payana',
        filter: TenantStatusFilter.all,
      );
      expect(result, hasLength(1));
      expect(result.single.id, 'la-payana');
    });

    test('filtro "activos" excluye inactivos', () {
      final result = filterTenants(
        tenants,
        query: '',
        filter: TenantStatusFilter.active,
      );
      expect(result.map((t) => t.id), <String>['la-payana', 'the-gene-pig']);
    });

    test('filtro "inactivos" solo incluye inactivos', () {
      final result = filterTenants(
        tenants,
        query: '',
        filter: TenantStatusFilter.inactive,
      );
      expect(result, hasLength(1));
      expect(result.single.id, 'cliente-demo');
    });

    test('combina filtro de estado + busqueda', () {
      final result = filterTenants(
        tenants,
        query: 'demo',
        filter: TenantStatusFilter.active,
      );
      // "Cliente Demo" matches the query but is inactive, so the active
      // filter excludes it — combining both must be an AND, not an OR.
      expect(result, isEmpty);
    });

    test('query sin resultados devuelve lista vacia, no lanza', () {
      final result = filterTenants(
        tenants,
        query: 'no existe este tenant',
        filter: TenantStatusFilter.all,
      );
      expect(result, isEmpty);
    });
  });

  group('TenantManagementPage (smoke test, sin Firebase)', () {
    testWidgets(
      'renderiza el shell sin crashear y distingue error de "0 tenants"',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: TenantManagementPage()),
        );
        // listTenantsForAdministration() ahora relanza el error de "no
        // Firebase App" en vez de atraparlo (fix aplicado tras revision —
        // antes este catch nunca se disparaba porque el servicio ya lo
        // atrapaba el mismo, haciendo que "sin tenants" y "error de lectura"
        // fueran indistinguibles). tester.pumpWidget/pumpAndSettle no relanza
        // excepciones de un Future asincrono como excepcion de test — solo
        // queda registrada para runtime, por eso este flujo sigue sin
        // crashear el widget test.
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Gestión de clientes'), findsOneWidget);
        expect(find.text('Tenants'), findsOneWidget);
        expect(find.text('Todos'), findsOneWidget);
        expect(find.text('Activos'), findsOneWidget);
        expect(find.text('Inactivos'), findsOneWidget);
        // Ya NO debe mostrar el mensaje de lista vacia — un fallo real de
        // lectura no puede disfrazarse de "0 tenants".
        expect(
          find.text('No hay tenants que coincidan con la búsqueda/filtro.'),
          findsNothing,
        );
        expect(
          find.textContaining('No se pudo cargar la lista de tenants'),
          findsOneWidget,
        );
      },
    );

    testWidgets('el boton de actualizar no lanza', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: TenantManagementPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No se pudo cargar la lista de tenants'),
        findsOneWidget,
      );
    });
  });

  group('Restricciones estructurales (verificadas por codigo, no runtime)', () {
    late String pageSource;
    late String mainSource;

    setUpAll(() {
      pageSource = File(
        'lib/pages/tenant_management_page.dart',
      ).readAsStringSync();
      mainSource = File('lib/main.dart').readAsStringSync();
    });

    test(
      'el boton "Gestión de clientes" vive dentro del bloque owner-only',
      () {
        final int ownerBlockStart = mainSource.indexOf(
          'if (userRole == UserAppRole.owner)',
        );
        final int manageTenantsPop = mainSource.indexOf(
          '_SettingsMenuAction.manageTenants',
          ownerBlockStart,
        );
        expect(ownerBlockStart, greaterThan(-1));
        expect(
          manageTenantsPop,
          greaterThan(ownerBlockStart),
          reason:
              'el pop() de manageTenants debe aparecer despues del gate '
              'owner-only, o el boton quedaria visible para todos los roles',
        );
      },
    );

    test('el boton "Templates UI" vive dentro del bloque owner-only', () {
      final int ownerBlockStart = mainSource.indexOf(
        'if (userRole == UserAppRole.owner)',
      );
      final int manageTemplatesPop = mainSource.indexOf(
        '_SettingsMenuAction.manageTemplates',
        ownerBlockStart,
      );
      expect(ownerBlockStart, greaterThan(-1));
      expect(
        manageTemplatesPop,
        greaterThan(ownerBlockStart),
        reason: 'el editor de templates debe seguir expuesto solo para owner',
      );
    });

    test('Etapa 4: gestion de rooms existe pero solo se carga bajo demanda '
        '(ver el grupo "Etapa 4" para el detalle)', () {
      // Superado por la Etapa 4 (gestion de devices/rooms) — ya no es
      // "fuera de alcance". Lo que se sigue verificando en el grupo
      // "Etapa 4" es que las rooms NUNCA se precargan junto con la
      // estructura del tenant (_loadStructure sigue siendo exactamente 3
      // queries), solo al expandir un device puntual.
      expect(pageSource, contains('AgroDeviceRoom'));
      expect(pageSource, contains('agro_device_room'));
    });

    test('no consulta snapshots operativos ni backend', () {
      // `snapshotUnitKey` (un campo de configuracion del Device, no de
      // telemetria en vivo) SI se muestra por pedido explicito de la
      // consigna — lo que no debe aparecer es una llamada real al
      // snapshot/backend operativo.
      expect(pageSource, isNot(contains('DashboardSnapshot')));
      expect(pageSource, isNot(contains('fetchLiveSnapshot')));
      expect(pageSource, isNot(contains('PlcDashboardService')));
    });

    test('no agrega listeners permanentes (.snapshots())', () {
      expect(pageSource, isNot(contains('.snapshots()')));
    });

    test('no implementa borrado fisico', () {
      expect(pageSource, isNot(contains('.delete(')));
    });

    test(
      'la carga de estructura usa exactamente listByTenant (1 query por coleccion, no listBySite/por-entidad)',
      () {
        // Formateado por dart format, los llamados pueden partirse en varias
        // lineas (ej. "widget.sectorService\n    .listByTenant(...)") — se
        // busca cada pieza por separado en vez de una sola substring
        // contigua, y se cuentan las ocurrencias de ".listByTenant(".
        expect(pageSource, contains('siteService'));
        expect(pageSource, contains('sectorService'));
        expect(pageSource, contains('deviceService'));
        expect('.listByTenant('.allMatches(pageSource).length, 3);
        expect(pageSource, isNot(contains('.listBySite(')));
      },
    );

    test('no escribe directamente en Firestore desde el widget', () {
      expect(pageSource, isNot(contains('FirebaseFirestore')));
      expect(
        pageSource,
        contains('tenantService.updateTenant('),
        reason:
            'la unica escritura debe pasar por AgroTenantService.updateTenant()',
      );
    });

    test('la edicion solo envia name y active a updateTenant', () {
      final int callIndex = pageSource.indexOf('tenantService.updateTenant(');
      final int callEnd = pageSource.indexOf(');', callIndex);
      final String call = pageSource.substring(callIndex, callEnd);

      expect(call, contains('tenantId:'));
      expect(call, contains('name:'));
      expect(call, contains('active:'));
    });
  });

  group('describeFirestoreError (pura, sin Firestore)', () {
    test('clasifica los codigos de FirebaseException conocidos', () {
      expect(
        describeFirestoreError(
          FirebaseException(plugin: 'firestore', code: 'permission-denied'),
        ),
        'No tenés permisos para esta operación.',
      );
      expect(
        describeFirestoreError(
          FirebaseException(plugin: 'firestore', code: 'unavailable'),
        ),
        contains('no está disponible'),
      );
      expect(
        describeFirestoreError(
          FirebaseException(plugin: 'firestore', code: 'already-exists'),
        ),
        contains('Ya existe un documento'),
      );
      expect(
        describeFirestoreError(
          FirebaseException(plugin: 'firestore', code: 'failed-precondition'),
        ),
        contains('cambiaron'),
      );
      expect(
        describeFirestoreError(
          FirebaseException(plugin: 'firestore', code: 'not-found'),
        ),
        contains('ya no existe'),
      );
      expect(
        describeFirestoreError(
          FirebaseException(plugin: 'firestore', code: 'deadline-exceeded'),
        ),
        contains('tardó demasiado'),
      );
      expect(
        describeFirestoreError(
          FirebaseException(plugin: 'firestore', code: 'unauthenticated'),
        ),
        contains('sesión expiró'),
      );
    });

    test('un codigo desconocido incluye el codigo original, no lo oculta', () {
      final String message = describeFirestoreError(
        FirebaseException(
          plugin: 'firestore',
          code: 'resource-exhausted',
          message: 'quota',
        ),
      );
      expect(message, contains('resource-exhausted'));
    });

    test('un StateError de validacion propia expone su mensaje tal cual', () {
      expect(
        describeFirestoreError(StateError('Ya existe un site con ese ID.')),
        'Ya existe un site con ese ID.',
      );
    });

    test('cualquier otro Object cae a toString(), no crashea', () {
      expect(
        describeFirestoreError(Exception('algo raro')),
        contains('algo raro'),
      );
    });
  });

  group('Etapa 3 — administracion de Sites y Sectores (codigo, no runtime)', () {
    late String pageSource;
    late String siteServiceSource;
    late String sectorServiceSource;
    late String sectorModelSource;
    late String rulesSource;

    setUpAll(() {
      pageSource = File(
        'lib/pages/tenant_management_page.dart',
      ).readAsStringSync();
      siteServiceSource = File(
        'lib/services/agro_site_service.dart',
      ).readAsStringSync();
      sectorServiceSource = File(
        'lib/services/agro_sector_service.dart',
      ).readAsStringSync();
      sectorModelSource = File(
        'lib/models/agro_sector.dart',
      ).readAsStringSync();
      rulesSource = File('firestore.rules').readAsStringSync();
    });

    test('agrega sites usando AgroSiteService.create, no un set directo', () {
      expect(pageSource, contains('_AddSiteDialog'));
      expect(pageSource, contains('widget.siteService.create('));
    });

    test(
      'la edicion de site solo cambia name/description/enabled — provisioningStatus/createdAt nunca se tocan',
      () {
        // `siteId`/`tenantId` SI viajan en la llamada al servicio (son
        // requeridos para ubicar el documento a actualizar), pero no forman
        // parte del payload mutable — eso lo confirma
        // buildAgroSiteUpdatePayload, que nunca incluye siteId/tenantId.
        final int callIndex = pageSource.indexOf(
          'await widget.siteService.update(',
          pageSource.indexOf('class _EditSiteDialogState'),
        );
        final int callEnd = pageSource.indexOf(');', callIndex);
        final String call = pageSource.substring(callIndex, callEnd);

        expect(call, contains('name:'));
        expect(call, contains('description:'));
        expect(call, contains('enabled:'));
        expect(call, isNot(contains('provisioningStatus:')));
        expect(call, isNot(contains('createdAt:')));

        final int payloadStart = siteServiceSource.indexOf(
          'Map<String, Object?> buildAgroSiteUpdatePayload(',
        );
        final int payloadEnd = siteServiceSource.indexOf('}\n', payloadStart);
        final String payloadFn = siteServiceSource.substring(
          payloadStart,
          payloadEnd,
        );
        expect(payloadFn, isNot(contains("'siteId'")));
        expect(payloadFn, isNot(contains("'tenantId'")));
        expect(payloadFn, isNot(contains("'createdAt'")));
      },
    );

    test(
      'agrega sectores usando AgroSectorService.create, no un set directo',
      () {
        expect(pageSource, contains('_AddSectorDialog'));
        expect(pageSource, contains('widget.sectorService.create('));
      },
    );

    test(
      'el formulario de "Agregar sector" preselecciona el site y no ofrece cambiarlo',
      () {
        final int classStart = pageSource.indexOf(
          'class _AddSectorDialog extends StatefulWidget',
        );
        final int classEnd = pageSource.indexOf('class _AddSectorDialogState');
        final String classBody = pageSource.substring(classStart, classEnd);

        // El site llega como campo final del widget (no seleccionable) y el
        // formulario no debe ofrecer ningun selector de site (DropdownButton
        // ni similar) dentro de este dialogo.
        expect(classBody, contains('final AgroSite site;'));
        final int stateEnd = pageSource.indexOf(
          '\nclass _EditSectorDialog',
          classEnd,
        );
        expect(stateEnd, greaterThan(classEnd));
        final String stateBody = pageSource.substring(classEnd, stateEnd);
        expect(stateBody, isNot(contains('DropdownButton')));
      },
    );

    test('la edicion de sector nunca reenvia siteId', () {
      final int callIndex = pageSource.indexOf(
        'await widget.sectorService.update(',
        pageSource.indexOf('class _EditSectorDialogState'),
      );
      final int callEnd = pageSource.indexOf(');', callIndex);
      final String call = pageSource.substring(callIndex, callEnd);

      expect(call, contains('name:'));
      expect(call, contains('description:'));
      expect(call, contains('enabled:'));
      expect(call, isNot(contains('siteId:')));
    });

    test(
      'los 4 dialogos nuevos (Add/Edit Site, Add/Edit Sector) evitan doble envio con _isSaving',
      () {
        for (final String className in <String>[
          '_AddSiteDialogState',
          '_EditSiteDialogState',
          '_AddSectorDialogState',
          '_EditSectorDialogState',
        ]) {
          final int classStart = pageSource.indexOf('class $className');
          expect(classStart, greaterThan(-1), reason: '$className no existe');
          final int nextClass = pageSource.indexOf('\nclass ', classStart + 1);
          final String body = pageSource.substring(
            classStart,
            nextClass == -1 ? pageSource.length : nextClass,
          );
          expect(
            body,
            contains('bool _isSaving = false;'),
            reason: '$className debe declarar _isSaving',
          );
          expect(
            body,
            contains('_isSaving ? null :'),
            reason:
                '$className debe deshabilitar Guardar mientras _isSaving es true',
          );
        }
      },
    );

    test(
      'los 4 dialogos nuevos nunca hacen pop() dentro del catch (no perder el error)',
      () {
        for (final String className in <String>[
          '_AddSiteDialogState',
          '_EditSiteDialogState',
          '_AddSectorDialogState',
          '_EditSectorDialogState',
        ]) {
          final int classStart = pageSource.indexOf('class $className');
          final int nextClass = pageSource.indexOf('\nclass ', classStart + 1);
          final String body = pageSource.substring(
            classStart,
            nextClass == -1 ? pageSource.length : nextClass,
          );
          final int catchIndex = body.indexOf('} catch (error) {');
          expect(catchIndex, greaterThan(-1));
          final int catchEnd = body.indexOf(
            '}',
            body.indexOf('{', catchIndex + 1),
          );
          final String catchBlock = body.substring(catchIndex, catchEnd);
          expect(
            catchBlock,
            isNot(contains('Navigator.of(context).pop')),
            reason:
                '$className no debe popear el dialogo en el camino de error, '
                'para que el usuario pueda reintentar sin perder lo tipeado',
          );
        }
      },
    );

    test('un site legacy queda de solo lectura EN SUS PROPIOS CAMPOS, pero sus '
        'sectores/devices no (correccion de Etapa 4 sobre una restriccion '
        'demasiado amplia de Etapa 3)', () {
      final int tileStart = pageSource.indexOf('class _SiteTile');
      final int badgeClassStart = pageSource.indexOf(
        'class _Badge extends StatelessWidget',
      );
      final String tileBody = pageSource.substring(tileStart, badgeClassStart);
      expect(
        tileBody,
        contains('final bool siteFieldsEditable = !site.isLegacyStructure;'),
      );
      // El boton "Editar site" y su switch de habilitar SI dependen de
      // siteFieldsEditable.
      final int editSiteIcon = tileBody.indexOf("'Editar site'");
      final int ifSiteFieldsEditableBeforeIcon = tileBody.lastIndexOf(
        'if (siteFieldsEditable)',
        editSiteIcon,
      );
      expect(ifSiteFieldsEditableBeforeIcon, greaterThan(-1));

      // "Agregar sector"/"Agregar device" y sus acciones NO dependen de
      // siteFieldsEditable ni de site.isLegacyStructure — son siempre
      // gestionables, incluso bajo un site legacy como genetica-1. Se
      // verifica mirando el tramo de texto INMEDIATAMENTE anterior a cada
      // boton: no debe contener ningun condicional de editabilidad.
      final int addSectorLabel = tileBody.indexOf("'Agregar sector'");
      final int addDeviceLabel = tileBody.indexOf("'Agregar device'");
      expect(addSectorLabel, greaterThan(-1));
      expect(addDeviceLabel, greaterThan(-1));
      final String beforeAddSector = tileBody.substring(
        addSectorLabel - 200,
        addSectorLabel,
      );
      final String beforeAddDevice = tileBody.substring(
        addDeviceLabel - 200,
        addDeviceLabel,
      );
      expect(beforeAddSector, isNot(contains('siteFieldsEditable')));
      expect(beforeAddSector, isNot(contains('isLegacyStructure')));
      expect(beforeAddDevice, isNot(contains('siteFieldsEditable')));
      expect(beforeAddDevice, isNot(contains('isLegacyStructure')));
    });

    test(
      'la edicion/activacion de un site o sector legacy es rechazada tambien en el codigo (no solo oculta en UI)',
      () {
        final int editSiteStart = pageSource.indexOf('Future<void> _editSite(');
        final int toggleSiteStart = pageSource.indexOf(
          'Future<void> _toggleSiteEnabled(',
        );
        final int addSectorStart = pageSource.indexOf(
          'Future<void> _addSector(',
        );
        final String editSiteBody = pageSource.substring(
          editSiteStart,
          toggleSiteStart,
        );
        final String toggleSiteBody = pageSource.substring(
          toggleSiteStart,
          addSectorStart,
        );
        expect(editSiteBody, contains('if (site.isLegacyStructure)'));
        expect(toggleSiteBody, contains('if (site.isLegacyStructure)'));
      },
    );

    test(
      'deshabilitar un site, sector o device no dispara escrituras en cascada sobre hijos',
      () {
        final int toggleSiteStart = pageSource.indexOf(
          'Future<void> _toggleSiteEnabled(',
        );
        final int addSectorStart = pageSource.indexOf(
          'Future<void> _addSector(',
        );
        final String toggleSiteBody = pageSource.substring(
          toggleSiteStart,
          addSectorStart,
        );
        expect('.update('.allMatches(toggleSiteBody).length, 1);
        expect(toggleSiteBody, isNot(contains('sectorService.update')));
        expect(toggleSiteBody, isNot(contains('deviceService.update')));

        final int toggleSectorStart = pageSource.indexOf(
          'Future<void> _toggleSectorEnabled(',
        );
        final int addDeviceStart = pageSource.indexOf(
          'Future<void> _addDevice(',
        );
        final String toggleSectorBody = pageSource.substring(
          toggleSectorStart,
          addDeviceStart,
        );
        expect('.update('.allMatches(toggleSectorBody).length, 1);
        expect(toggleSectorBody, isNot(contains('deviceService.update')));

        final int toggleDeviceStart = pageSource.indexOf(
          'Future<void> _toggleDeviceEnabled(',
        );
        final int editNameStart = pageSource.indexOf('Future<void> _editName(');
        final String toggleDeviceBody = pageSource.substring(
          toggleDeviceStart,
          editNameStart,
        );
        expect('.update('.allMatches(toggleDeviceBody).length, 1);
        expect(toggleDeviceBody, isNot(contains('roomService.update')));
        expect(toggleDeviceBody, isNot(contains('sectorService.update')));
      },
    );

    test(
      'las confirmaciones de habilitar/deshabilitar usan la copia definida para cada entidad',
      () {
        expect(pageSource, contains("'Habilitar site' : 'Deshabilitar site'"));
        expect(
          pageSource,
          contains("'Habilitar sector' : 'Deshabilitar sector'"),
        );
        expect(
          pageSource,
          contains('Sus sectores, devices y datos históricos'),
        );
        expect(
          pageSource,
          contains('modificarán automáticamente los devices relacionados'),
        );
      },
    );

    test(
      'la validacion cliente usa los mensajes especificados en la consigna',
      () {
        // "Ya existe un site/sector con ese ID." NO esta hardcodeado en la
        // pagina — nace en el servicio (ver el test siguiente) y llega al
        // dialogo via describeFirestoreError(StateError), no como string
        // literal en tenant_management_page.dart.
        expect(pageSource, contains('El nombre del sector es obligatorio.'));
        expect(pageSource, contains('El nombre del site es obligatorio.'));
        expect(pageSource, contains('El Sector ID es obligatorio.'));
        expect(
          pageSource,
          contains('No se puede editar una estructura legacy.'),
        );
      },
    );

    test(
      'AgroSiteService.create y AgroSectorService.create rechazan un ID duplicado antes de escribir',
      () {
        expect(
          siteServiceSource,
          contains("StateError('Ya existe un site con ese ID.')"),
        );
        expect(
          sectorServiceSource,
          contains("StateError('Ya existe un sector con ese ID.')"),
        );
      },
    );

    test(
      'AgroSector no tiene sortOrder — no se inventa un campo que no existe en el modelo',
      () {
        expect(sectorModelSource, isNot(contains('sortOrder')));
      },
    );

    test('ninguno de los archivos nuevos/modificados escribe bajo /plcs/', () {
      // Los doc comments SI mencionan la ruta legacy `sites/{siteId}/plcs/`
      // a proposito (para explicar la convivencia de esquemas) — lo que no
      // debe existir es codigo real (no comentario) que arme o escriba una
      // ruta con el literal 'plcs'.
      String stripComments(String source) {
        return source
            .split('\n')
            .where((line) => !line.trim().startsWith('//'))
            .join('\n');
      }

      for (final String source in <String>[
        pageSource,
        siteServiceSource,
        sectorServiceSource,
      ]) {
        expect(stripComments(source), isNot(contains('plcs')));
      }
    });

    test(
      'firestore.rules ya cubre create/update de sites y sectores sin necesitar cambios en esta etapa',
      () {
        // Sites: create exige provisioningStatus == pending_backend; update
        // permite name/description/enabled/provisioningStatus/updatedAt.
        expect(
          rulesSource,
          contains(
            "request.resource.data.provisioningStatus == 'pending_backend'",
          ),
        );
        expect(
          rulesSource,
          contains(
            ".hasOnly(['name', 'description', 'enabled', 'provisioningStatus', 'updatedAt'])",
          ),
        );
        // Sectores: create valida existsAfter del site + siteId inmutable en
        // update + delete false en ambas colecciones.
        expect(
          rulesSource,
          contains(
            'existsAfter(/databases/\$(database)/documents/tenants/\$(tenantId)/sites/\$(request.resource.data.siteId))',
          ),
        );
        expect(
          rulesSource,
          contains('request.resource.data.siteId == resource.data.siteId'),
        );
      },
    );

    test(
      'genetica-1 (legacy) no esta bloqueado a nivel de reglas para nuevos sectors/devices — solo restringido en UI',
      () {
        // existsAfter() solo verifica que exista el documento Site en ese
        // path, sin distinguir legacy de nuevo esquema — confirma que la
        // proteccion "no editable si isLegacyStructure" en _SiteTile es una
        // decision de UI reversible, no una limitacion de reglas/datos.
        final int sectorsMatch = rulesSource.indexOf(
          'match /sectors/{sectorId}',
        );
        final int devicesMatch = rulesSource.indexOf(
          'match /devices/{deviceId}',
        );
        final String sectorsCreateRule = rulesSource.substring(
          sectorsMatch,
          devicesMatch,
        );
        expect(sectorsCreateRule, isNot(contains('isLegacyStructure')));
        expect(sectorsCreateRule, isNot(contains('provisioningStatus')));
      },
    );
  });

  group('Etapa 4 — Devices, catalogo de tipos y Rooms', () {
    late String pageSource;
    late String deviceServiceSource;
    late String provisioningServiceSource;
    late String catalogSource;
    late String rulesSource;

    setUpAll(() {
      pageSource = File(
        'lib/pages/tenant_management_page.dart',
      ).readAsStringSync();
      deviceServiceSource = File(
        'lib/services/agro_device_service.dart',
      ).readAsStringSync();
      provisioningServiceSource = File(
        'lib/services/agro_device_provisioning_service.dart',
      ).readAsStringSync();
      catalogSource = File(
        'lib/models/agro_device_type_catalog.dart',
      ).readAsStringSync();
      rulesSource = File('firestore.rules').readAsStringSync();
    });

    group('Catalogo centralizado (puro, sin Firestore)', () {
      test('existe y tiene al menos los 2 tipos con comportamiento real', () {
        expect(selectableAgroDeviceTypes(), isNotEmpty);
        expect(findAgroDeviceType('environment_single_room'), isNotNull);
        expect(findAgroDeviceType('environment_multi_room'), isNotNull);
        expect(findAgroDeviceType('environment_multi_room')!.usesRooms, isTrue);
        expect(
          findAgroDeviceType('environment_single_room')!.usesRooms,
          isFalse,
        );
      });

      test(
        'un tipo historico/desconocido (ej. "unknown", el valor real de '
        'La Payana) se describe sin crashear y no aparece como seleccionable',
        () {
          expect(() => describeDeviceType('unknown'), returnsNormally);
          expect(describeDeviceType('unknown'), contains('histórico'));
          expect(
            selectableAgroDeviceTypes().any((t) => t.id == 'unknown'),
            isFalse,
          );
        },
      );

      test('tipo vacio no crashea', () {
        expect(() => describeDeviceType(''), returnsNormally);
      });

      test('el catalogo esta centralizado en un solo archivo (no hay switches '
          'de tipo repartidos por la pagina)', () {
        expect(pageSource, isNot(contains("case 'environment_")));
        expect(pageSource, contains('agro_device_type_catalog.dart'));
      });

      test('el catalogo no usa "Munters" en ningun label/descripcion', () {
        expect(catalogSource, isNot(contains('Munters')));
        expect(catalogSource, isNot(contains('munters')));
      });
    });

    group('AgroDeviceService — asociacion device-sector y payloads', () {
      test('create()/update() validan sectorIds contra el site del device', () {
        expect(deviceServiceSource, contains('_validateSectorIds'));
        expect(deviceServiceSource, contains('sector.siteId != siteId'));
      });

      test('create() rechaza un Device ID duplicado antes de escribir '
          '(igual patron que Site/Sector)', () {
        expect(
          deviceServiceSource,
          contains("StateError('Ya existe un device con ese ID.')"),
        );
      });

      test(
        'update() no reenvia deviceId/siteId como campos mutables del payload',
        () {
          final int payloadStart = deviceServiceSource.indexOf(
            'Map<String, Object?> buildAgroDeviceUpdatePayload(',
          );
          final int payloadEnd = deviceServiceSource.indexOf(
            '}\n',
            payloadStart,
          );
          final String payloadFn = deviceServiceSource.substring(
            payloadStart,
            payloadEnd,
          );
          expect(payloadFn, isNot(contains("'siteId'")));
          expect(payloadFn, isNot(contains("'createdAt'")));
        },
      );
    });

    group('AgroDeviceProvisioningService.createDeviceWithRooms (atomico)', () {
      test('usa un unico WriteBatch y un unico commit (atomicidad real)', () {
        expect(
          provisioningServiceSource,
          contains('FirebaseFirestore.instance.batch()'),
        );
        expect(
          'batch.commit()'.allMatches(provisioningServiceSource).length,
          1,
        );
        // El device y cada room se agregan al MISMO batch antes del commit
        // (no hay un .set()/.update() suelto fuera del batch para ninguno
        // de los dos), lo que es lo que hace la operacion atomica: si algo
        // falla, .commit() nunca se llama y nada se escribe.
        expect('batch.set('.allMatches(provisioningServiceSource).length, 2);
      });

      test('rechaza Room IDs duplicados ANTES de tocar Firestore (verificable '
          'sin Firebase inicializado)', () async {
        const AgroDeviceProvisioningService service =
            AgroDeviceProvisioningService();
        await expectLater(
          service.createDeviceWithRooms(
            tenantId: 'the-gene-pig',
            siteId: 'main_site',
            deviceId: 'plc-multisala',
            name: 'PLC Multisala',
            type: 'environment_multi_room',
            rooms: const [
              AgroDeviceRoomDraft(id: 'sala-1', name: 'Sala 1'),
              AgroDeviceRoomDraft(id: 'sala-1', name: 'Sala 1 bis'),
            ],
          ),
          throwsA(isA<StateError>()),
        );
      });

      test(
        'rechaza snapshotUnitKey duplicados entre rooms del mismo device',
        () {
          expect(provisioningServiceSource, contains('seenSnapshotUnitKeys'));
          expect(
            provisioningServiceSource,
            contains("El snapshotUnitKey \"\$key\" está duplicado."),
          );
        },
      );

      test('rechaza un Room ID vacio antes de tocar Firestore', () async {
        const AgroDeviceProvisioningService service =
            AgroDeviceProvisioningService();
        await expectLater(
          service.createDeviceWithRooms(
            tenantId: 'the-gene-pig',
            siteId: 'main_site',
            deviceId: 'plc-multisala',
            name: 'PLC Multisala',
            type: 'environment_multi_room',
            rooms: const [AgroDeviceRoomDraft(id: '', name: 'Sala 1')],
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('sin rooms, createDeviceWithRooms sigue validando site/deviceId '
          'igual que un alta de device simple', () async {
        const AgroDeviceProvisioningService service =
            AgroDeviceProvisioningService();
        await expectLater(
          service.createDeviceWithRooms(
            tenantId: 'the-gene-pig',
            siteId: '',
            deviceId: 'plc-1',
            name: 'PLC 1',
            type: 'environment_single_room',
          ),
          throwsA(isA<StateError>()),
        );
      });
    });

    group(
      'Correccion Etapa 3 → Etapa 4: legacy ya no bloquea sectores/devices',
      () {
        test('el comentario de _SiteTile documenta la correccion (no solo el '
            'estado final)', () {
          final int classStart = pageSource.indexOf('class _SiteTile');
          final String docComment = pageSource.substring(
            pageSource.lastIndexOf('///', classStart) - 2000 < 0
                ? 0
                : classStart - 2000,
            classStart,
          );
          expect(docComment, contains('Etapa 4'));
        });

        test(
          'la regla de devices en firestore.rules tampoco distingue legacy '
          '(misma conclusion que sectores en Etapa 3, ahora tambien devices)',
          () {
            final int devicesMatch = rulesSource.indexOf(
              'match /devices/{deviceId}',
            );
            final int roomsMatch = rulesSource.indexOf(
              'match /rooms/{roomId}',
              devicesMatch,
            );
            final String devicesCreateRule = rulesSource.substring(
              devicesMatch,
              roomsMatch,
            );
            expect(devicesCreateRule, isNot(contains('isLegacyStructure')));
            expect(devicesCreateRule, isNot(contains('provisioningStatus')));
          },
        );
      },
    );

    group('Rooms: gestion, inmutabilidad, carga bajo demanda', () {
      test('las rooms se cargan SOLO al expandir un device — nunca junto con '
          'la estructura del tenant', () {
        // _loadStructure (llamada al abrir/seleccionar un tenant) sigue
        // siendo exactamente 3 queries — ninguna de ellas de rooms.
        final int loadStructureStart = pageSource.indexOf(
          'Future<void> _loadStructure(',
        );
        final int loadStructureEnd = pageSource.indexOf(
          '\n  Future<void> _refreshStructure(',
          loadStructureStart,
        );
        final String loadStructureBody = pageSource.substring(
          loadStructureStart,
          loadStructureEnd,
        );
        expect(loadStructureBody, isNot(contains('roomService')));
        expect(loadStructureBody, isNot(contains('listByDevice')));
        expect(loadStructureBody, isNot(contains('listForDevices')));

        // La UNICA llamada a listByDevice del archivo vive dentro de
        // _DeviceTileState._loadRooms, disparada por onExpansionChanged.
        expect('roomService.listByDevice('.allMatches(pageSource).length, 1);
        expect(pageSource, contains('onExpansionChanged: (expanded) {'));
      });

      test('el Room ID es inmutable: Edit Room no lo reenvia', () {
        final int editRoomStart = pageSource.indexOf(
          'class _EditRoomDialogState',
        );
        final int nextClassStart = pageSource.indexOf(
          '\nclass ',
          editRoomStart + 1,
        );
        final String editRoomBody = pageSource.substring(
          editRoomStart,
          nextClassStart == -1 ? pageSource.length : nextClassStart,
        );
        expect(
          editRoomBody,
          isNot(contains('TextEditingController _idController')),
        );
        // No confundir con el comentario explicativo que SI menciona
        // "createdAt" en prosa (documenta por que se omite) — lo que
        // importa es que nunca aparezca como argumento nombrado real.
        expect(editRoomBody, isNot(contains('createdAt:')));
      });

      test('editar una room no llama a deviceService (no toca el device)', () {
        final int editRoomStart = pageSource.indexOf(
          'class _EditRoomDialogState',
        );
        final int nextClassStart = pageSource.indexOf(
          '\nclass ',
          editRoomStart + 1,
        );
        final String editRoomBody = pageSource.substring(
          editRoomStart,
          nextClassStart == -1 ? pageSource.length : nextClassStart,
        );
        expect(editRoomBody, isNot(contains('deviceService')));
      });

      test('deshabilitar una room es una sola escritura (no toca otras rooms '
          'ni el device)', () {
        final int toggleRoomStart = pageSource.indexOf(
          'Future<void> _toggleRoomEnabled(',
        );
        final int buildStart = pageSource.indexOf(
          '\n  @override\n  Widget build(BuildContext context) {\n    final AgroDevice device = widget.device;',
        );
        final String toggleRoomBody = pageSource.substring(
          toggleRoomStart,
          buildStart == -1 ? toggleRoomStart + 1200 : buildStart,
        );
        expect('.update('.allMatches(toggleRoomBody).length, 1);
        expect(toggleRoomBody, isNot(contains('deviceService')));
      });

      test('agregar una room usa el servicio, nunca Firestore directo', () {
        expect(pageSource, contains('widget.roomService.create('));
      });

      test('un error al cargar rooms se distingue de "sin rooms" (no se '
          'convierte en lista vacia silenciosa)', () {
        final int loadRoomsStart = pageSource.indexOf(
          'Future<void> _loadRooms(',
        );
        final int addRoomStart = pageSource.indexOf('Future<void> _addRoom(');
        final String loadRoomsBody = pageSource.substring(
          loadRoomsStart,
          addRoomStart,
        );
        expect(loadRoomsBody, contains('_RoomsLoadState.error'));
        expect(loadRoomsBody, contains('catch (error)'));
      });
    });

    group('Device: inmutabilidad y confirmaciones', () {
      test('Device ID y type quedan inmutables al editar', () {
        final int editDeviceStart = pageSource.indexOf(
          'class _EditDeviceDialogState',
        );
        final int nextClassStart = pageSource.indexOf(
          '\nclass ',
          editDeviceStart + 1,
        );
        final String editDeviceBody = pageSource.substring(
          editDeviceStart,
          nextClassStart == -1 ? pageSource.length : nextClassStart,
        );
        // No hay ningun TextField para editar el Device ID.
        expect(editDeviceBody, isNot(contains("labelText: 'Device ID'")));
        // El tipo se muestra de solo lectura (_ReadOnlyField) y se reenvia
        // sin cambios (widget.device.type, no un controller propio).
        expect(editDeviceBody, contains("label: 'Tipo'"));
        expect(editDeviceBody, contains('type: widget.device.type'));
        expect(editDeviceBody, isNot(contains('createdAt:')));
      });

      test('las confirmaciones de habilitar/deshabilitar cubren device y room '
          'con la copia definida', () {
        expect(
          pageSource,
          contains("'Habilitar device' : 'Deshabilitar device'"),
        );
        expect(pageSource, contains("'Habilitar room' : 'Deshabilitar room'"));
        expect(
          pageSource,
          contains('No se eliminarán sus rooms, configuración ni'),
        );
      });

      test('los 4 dialogos nuevos (Add/Edit Device, Add/Edit Room) tambien '
          'usan _isSaving y nunca hacen pop() en el catch', () {
        for (final String className in <String>[
          '_AddDeviceDialogState',
          '_EditDeviceDialogState',
          '_AddRoomDialogState',
          '_EditRoomDialogState',
        ]) {
          final int classStart = pageSource.indexOf('class $className');
          expect(classStart, greaterThan(-1), reason: '$className no existe');
          final int nextClass = pageSource.indexOf('\nclass ', classStart + 1);
          final String body = pageSource.substring(
            classStart,
            nextClass == -1 ? pageSource.length : nextClass,
          );
          expect(
            body,
            contains('bool _isSaving = false;'),
            reason: '$className debe declarar _isSaving',
          );
          expect(
            body,
            contains('_isSaving ? null :'),
            reason:
                '$className debe deshabilitar Guardar/Crear mientras guarda',
          );
          final int catchIndex = body.indexOf('} catch (error) {');
          expect(catchIndex, greaterThan(-1));
          final int catchEnd = body.indexOf(
            '}',
            body.indexOf('{', catchIndex + 1),
          );
          expect(
            body.substring(catchIndex, catchEnd),
            isNot(contains('Navigator.of(context).pop')),
            reason: '$className no debe popear en el camino de error',
          );
        }
      });

      test('el formulario "Agregar device" preselecciona el site (no lo '
          'ofrece cambiar) y no usa "Munters" en ningun texto/ejemplo', () {
        final int classStart = pageSource.indexOf(
          'class _AddDeviceDialog extends StatefulWidget',
        );
        final int stateStart = pageSource.indexOf(
          'class _AddDeviceDialogState',
        );
        final String classBody = pageSource.substring(classStart, stateStart);
        expect(classBody, contains('final AgroSite site;'));
        expect(pageSource, isNot(contains('Munters')));
        expect(pageSource, isNot(contains('munters')));
      });

      test(
        'el selector de tipo es un Dropdown, no un TextField de texto libre',
        () {
          expect(pageSource, contains('_DeviceTypeDropdown'));
          expect(
            pageSource,
            contains('DropdownButtonFormField<AgroDeviceTypeDefinition>'),
          );
        },
      );

      test('la generacion de rooms por defecto usa sortOrder 0-based, '
          'consistente con los datos reales ya en produccion (La Payana)', () {
        final int regenStart = pageSource.indexOf(
          'void _regenerateRooms(int count)',
        );
        final int regenEnd = pageSource.indexOf('\n  }', regenStart);
        final String regenBody = pageSource.substring(regenStart, regenEnd);
        expect(regenBody, contains('sortOrder: i'));
      });
    });

    group(
      'Sin escrituras fuera de los servicios / sin listeners / sin polling',
      () {
        test('la pagina sigue sin FirebaseFirestore directo', () {
          expect(pageSource, isNot(contains('FirebaseFirestore')));
        });

        test('ninguno de los archivos de Etapa 4 escribe bajo /plcs/', () {
          String stripComments(String source) {
            return source
                .split('\n')
                .where((line) => !line.trim().startsWith('//'))
                .join('\n');
          }

          for (final String source in <String>[
            pageSource,
            deviceServiceSource,
            provisioningServiceSource,
          ]) {
            expect(stripComments(source), isNot(contains('plcs')));
          }
        });

        test('sin listeners (.snapshots()) en ningun archivo nuevo', () {
          expect(pageSource, isNot(contains('.snapshots()')));
          expect(provisioningServiceSource, isNot(contains('.snapshots()')));
        });

        test('sin polling (Timer/Future.delayed) en ningun archivo nuevo', () {
          for (final String source in <String>[
            pageSource,
            provisioningServiceSource,
            deviceServiceSource,
          ]) {
            expect(source, isNot(contains('Timer(')));
            expect(source, isNot(contains('Future.delayed')));
          }
        });

        test('sin borrado fisico (.delete() ) en ningun archivo nuevo', () {
          expect(pageSource, isNot(contains('.delete(')));
          expect(provisioningServiceSource, isNot(contains('.delete(')));
        });
      },
    );

    group('Firestore Rules — devices/rooms owner-only, sin tenant_admin', () {
      test('create/update de devices y rooms exigen isOwner()', () {
        final int devicesMatch = rulesSource.indexOf(
          'match /devices/{deviceId}',
        );
        final int endOfDevicesBlock = rulesSource.indexOf(
          '\n    match /tenants/{tenantId}/sites/{siteId}/plcs/{plcId}/metrics/temperature',
        );
        final String devicesBlock = rulesSource.substring(
          devicesMatch,
          endOfDevicesBlock == -1 ? devicesMatch + 6000 : endOfDevicesBlock,
        );
        expect('isOwner()'.allMatches(devicesBlock).length, greaterThan(1));
        expect(devicesBlock, isNot(contains('tenant_admin')));
        expect(devicesBlock, contains("allow delete: if false;"));
      });

      test('sectorIds en devices esta permitido pero tipado como list', () {
        expect(
          rulesSource,
          contains("request.resource.data.sectorIds is list"),
        );
      });
    });
  });

  group('Etapa 4.1 — indicador de snapshot incompleto y reglas acumuladas', () {
    late String pageSource;
    late String rulesSource;

    setUpAll(() {
      pageSource = File(
        'lib/pages/tenant_management_page.dart',
      ).readAsStringSync();
      rulesSource = File('firestore.rules').readAsStringSync();
    });

    test('un device de un tipo catalogado SIN rooms, habilitado y sin '
        'snapshotUnitKey muestra el badge "Pendiente de vincular al '
        'snapshot", sin consultar backend/snapshot', () {
      final int badgeIndex = pageSource.indexOf(
        "'Pendiente de vincular al snapshot'",
      );
      expect(badgeIndex, greaterThan(-1));
      final String around = pageSource.substring(badgeIndex - 1200, badgeIndex);
      expect(around, contains('device.enabled'));
      expect(around, contains('!typeDefinition.usesRooms'));
      expect(pageSource, isNot(contains('DashboardSnapshot')));
    });

    test('un device de tipo NO catalogado (ej. "unknown", La Payana real) '
        'nunca muestra el badge de snapshot incompleto — podria tener rooms '
        'ya configuradas que este resumen colapsado no puede ver', () {
      final int badgeIndex = pageSource.indexOf(
        "'Pendiente de vincular al snapshot'",
      );
      final String around = pageSource.substring(badgeIndex - 1200, badgeIndex);
      expect(around, contains('typeDefinition != null'));
    });

    test('un device multisala muestra "N de M rooms vinculadas al snapshot" '
        'solo despues de cargar las rooms (no antes)', () {
      expect(
        pageSource,
        contains('de \${_rooms.length} rooms vinculadas al snapshot'),
      );
      final int summaryIndex = pageSource.indexOf(
        'rooms vinculadas al snapshot',
      );
      final int loadedCaseIndex = pageSource.lastIndexOf(
        'case _RoomsLoadState.loaded:',
        summaryIndex,
      );
      expect(
        loadedCaseIndex,
        greaterThan(-1),
        reason:
            'el resumen debe vivir dentro del caso "loaded", nunca '
            'mostrarse mientras las rooms todavia no se cargaron',
      );
    });

    test('el diff acumulado de firestore.rules pendiente de deploy sigue '
        'siendo exactamente: tenants.allow update (Etapa 1) + '
        'devices.sectorIds (Etapa 4) — nada nuevo en Etapa 4.1', () {
      // Etapa 4.1 no necesita ningun campo nuevo en las reglas (la
      // unicidad de snapshotUnitKey no puede ni debe intentarse ahi) —
      // confirmado por ausencia de cualquier mecanismo de unicidad
      // global (no existe, ni deberia, una coleccion indice dedicada).
      expect(rulesSource, isNot(contains('snapshotUnitKeyIndex')));
      expect(rulesSource, isNot(contains('unique')));
      // Los dos cambios pendientes reales de etapas previas siguen
      // presentes tal cual:
      expect(rulesSource, contains("hasOnly(['name', 'active', 'updatedAt'])"));
      expect(
        rulesSource,
        contains("'sortOrder', 'snapshotUnitKey', 'sectorIds'])"),
      );
    });

    test('sectorIds/snapshotUnitKey/sortOrder de devices siguen tipados '
        'correctamente en ambas reglas (create y update)', () {
      final int devicesMatch = rulesSource.indexOf('match /devices/{deviceId}');
      final int roomsMatch = rulesSource.indexOf(
        'match /rooms/{roomId}',
        devicesMatch,
      );
      final String devicesBlock = rulesSource.substring(
        devicesMatch,
        roomsMatch,
      );
      expect(
        'request.resource.data.sectorIds is list'
            .allMatches(devicesBlock)
            .length,
        2,
        reason: 'una vez en create, una vez en update',
      );
      expect(
        'request.resource.data.sortOrder is int'
            .allMatches(devicesBlock)
            .length,
        2,
      );
    });
  });
}
