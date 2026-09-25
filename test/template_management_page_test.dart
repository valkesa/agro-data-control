import 'package:agro_data_control/pages/template_management_page.dart';
import 'package:agro_data_control/services/device_template_repository.dart';
import 'package:agro_data_control/ui_templates/ui_templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TemplateManagementPage renderiza templates locales y remotos', (
    WidgetTester tester,
  ) async {
    final _FakeTemplateRepository repository = _FakeTemplateRepository();
    await _pumpTemplatePage(tester, repository);

    expect(find.text('Templates UI'), findsOneWidget);
    expect(find.text('room_climate'), findsOneWidget);
    expect(find.text('laboratory_basic'), findsOneWidget);
    expect(find.text('disinfection_arch'), findsOneWidget);
    expect(find.text('Remoto'), findsNWidgets(3));
    expect(find.text('Local'), findsNothing);
    expect(find.text('Restaurar desde plantilla local'), findsWidgets);
    expect(find.text('Sincronizar local'), findsNothing);
  });

  testWidgets(
    'editor expone secciones funcionales y guarda template completo',
    (WidgetTester tester) async {
      final _FakeTemplateRepository repository = _FakeTemplateRepository();
      await _pumpTemplatePage(tester, repository);

      await tester.tap(find.widgetWithText(FilledButton, 'Editar').last);
      await tester.pumpAndSettle();

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Métricas'), findsOneWidget);
      expect(find.text('Tablero'), findsOneWidget);
      expect(find.text('Tabla'), findsOneWidget);
      expect(find.text('id: room_climate'), findsOneWidget);
      expect(find.text('schemaVersion: 1'), findsOneWidget);
      expect(find.text('templateVersion: 4'), findsOneWidget);

      await tester.tap(find.text('Métricas'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Temperatura interior'),
        'Temperatura interior editada',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(repository.saveCalls, 1);
      expect(repository.lastExpectedVersion, 4);
      expect(repository.lastSavedTemplate?.id, 'room_climate');
      expect(
        repository.lastSavedTemplate?.metrics.first.label,
        'Temperatura interior editada',
      );
      expect(repository.lastSavedVersion, 5);
    },
  );

  testWidgets('editor valida ordenes duplicados de columnas', (
    WidgetTester tester,
  ) async {
    final _FakeTemplateRepository repository = _FakeTemplateRepository();
    await _pumpTemplatePage(tester, repository);

    await tester.tap(find.widgetWithText(FilledButton, 'Editar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tabla'));
    await tester.pumpAndSettle();

    final Finder orderFields = find.widgetWithText(TextField, 'Orden');
    expect(orderFields, findsWidgets);
    await tester.enterText(orderFields.at(0), '1');
    await tester.enterText(orderFields.at(1), '1');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se permiten órdenes duplicados en Tabla.'),
      findsOneWidget,
    );
    expect(repository.saveCalls, 0);
  });

  testWidgets('conflicto optimista conserva editor y ofrece recargar', (
    WidgetTester tester,
  ) async {
    final _FakeTemplateRepository repository = _FakeTemplateRepository()
      ..throwConflict = true;
    await _pumpTemplatePage(tester, repository);

    await tester.tap(find.widgetWithText(FilledButton, 'Editar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('El template cambió en Firestore'),
      findsOneWidget,
    );
    expect(find.text('Recargar'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });

  testWidgets(
    'editor guarda cambios permitidos de BoardSlot sin tocar claves',
    (WidgetTester tester) async {
      final _FakeTemplateRepository repository = _FakeTemplateRepository();
      await _pumpTemplatePage(tester, repository);
      final BoardSlot originalSlot = repository
          .recordFor('room_climate')
          .template
          .boardSlots
          .first;

      await tester.tap(find.widgetWithText(FilledButton, 'Editar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tablero'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Show label').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(repository.saveCalls, 1);
      final BoardSlot savedSlot =
          repository.lastSavedTemplate!.boardSlots.first;
      expect(savedSlot.showLabel, isFalse);
      expect(savedSlot.metricKey, originalSlot.metricKey);
      expect(savedSlot.position, originalSlot.position);
      expect(savedSlot.indicators, originalSlot.indicators);
      expect(savedSlot.visible, originalSlot.visible);
      expect(savedSlot.showIcon, originalSlot.showIcon);
      expect(savedSlot.size, originalSlot.size);
    },
  );

  testWidgets(
    'error Firestore generico conserva editor y cambios sin version local',
    (WidgetTester tester) async {
      final _FakeTemplateRepository repository = _FakeTemplateRepository()
        ..throwGenericSaveError = true;
      await _pumpTemplatePage(tester, repository);

      await tester.tap(find.widgetWithText(FilledButton, 'Editar').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre'),
        'Sala clima editada',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(repository.saveCalls, 1);
      expect(find.textContaining('No se pudo guardar'), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
      expect(find.text('Sala clima editada'), findsOneWidget);
      expect(find.text('templateVersion: 4'), findsOneWidget);
      expect(repository.lastSavedVersion, isNull);
      expect(repository.recordFor('room_climate').templateVersion, 4);
    },
  );

  testWidgets('dirty state pide confirmacion antes de cerrar', (
    WidgetTester tester,
  ) async {
    final _FakeTemplateRepository repository = _FakeTemplateRepository();
    await _pumpTemplatePage(tester, repository);

    await tester.tap(find.widgetWithText(FilledButton, 'Editar').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Nombre editado',
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Descartar cambios'), findsOneWidget);
    expect(find.text('Seguir editando'), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);
  });

  testWidgets('restaurar local muestra confirmacion explicita', (
    WidgetTester tester,
  ) async {
    final _FakeTemplateRepository repository = _FakeTemplateRepository();
    await _pumpTemplatePage(tester, repository);

    await tester.tap(
      find
          .widgetWithText(FilledButton, 'Restaurar desde plantilla local')
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Restaurar desde plantilla local'), findsWidgets);
    expect(
      find.text(
        'Esto reemplazará la configuración remota actual por la definición local incluida en la app.',
      ),
      findsOneWidget,
    );
  });

  test('DeviceTemplateRecord round-trip preserva UTF-8 acentuado', () {
    final DeviceTemplate local = getTemplateById('laboratory_basic')!;
    final DeviceTemplate template = DeviceTemplate(
      id: local.id,
      name: 'Laboratorio básico',
      boardPreset: local.boardPreset,
      metrics: local.metrics,
      indicators: local.indicators,
      boardSlots: local.boardSlots,
      tableSection: 'Arco de desinfección',
      tableColumns: local.tableColumns,
    );
    final DeviceTemplateRecord record = DeviceTemplateRecord(
      template: template,
      schemaVersion: 1,
      templateVersion: 1,
      enabled: true,
      description: 'Descripción con acento',
      tags: const <String>['climatización'],
    );

    final DeviceTemplateRecord? parsed = DeviceTemplateRecord.fromMap(
      record.toMap(),
    );

    expect(parsed?.template.name, 'Laboratorio básico');
    expect(parsed?.template.tableSection, 'Arco de desinfección');
    expect(parsed?.description, 'Descripción con acento');
    expect(parsed?.tags, contains('climatización'));
  });
}

Future<void> _pumpTemplatePage(
  WidgetTester tester,
  _FakeTemplateRepository repository,
) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: TemplateManagementPage(repository: repository)),
  );
  await tester.pumpAndSettle();
}

class _FakeTemplateRepository extends DeviceTemplateRepository {
  _FakeTemplateRepository() {
    final DeviceTemplate local = getTemplateById('room_climate')!;
    _records = <DeviceTemplateRecord>[
      for (final DeviceTemplate template in agroUiTemplates)
        DeviceTemplateRecord(
          template: template.id == local.id ? local : template,
          schemaVersion: 1,
          templateVersion: template.id == local.id ? 4 : 1,
          enabled: true,
          description: template.id == local.id
              ? 'Template remoto de prueba'
              : null,
          tags: template.id == local.id
              ? const <String>['test']
              : const <String>[],
        ),
    ];
  }

  late List<DeviceTemplateRecord> _records;
  int saveCalls = 0;
  int resetCalls = 0;
  int? lastExpectedVersion;
  int? lastSavedVersion;
  DeviceTemplate? lastSavedTemplate;
  bool throwConflict = false;
  bool throwGenericSaveError = false;

  DeviceTemplateRecord recordFor(String templateId) {
    return _records.singleWhere(
      (DeviceTemplateRecord record) => record.template.id == templateId,
    );
  }

  @override
  Future<List<DeviceTemplateRecord>> fetchTemplates() async {
    return _records;
  }

  @override
  Future<DeviceTemplateRecord?> fetchTemplate(String templateId) async {
    for (final DeviceTemplateRecord record in _records) {
      if (record.template.id == templateId) return record;
    }
    return null;
  }

  @override
  Future<int> saveTemplate({
    required DeviceTemplate template,
    required int expectedTemplateVersion,
    required bool enabled,
    String? description,
    List<String> tags = const <String>[],
  }) async {
    saveCalls += 1;
    lastExpectedVersion = expectedTemplateVersion;
    lastSavedTemplate = template;
    if (throwConflict) {
      throw DeviceTemplateVersionConflict(
        templateId: template.id,
        expectedVersion: expectedTemplateVersion,
        actualVersion: expectedTemplateVersion + 1,
      );
    }
    if (throwGenericSaveError) {
      throw StateError('firestore unavailable');
    }
    final int nextVersion = expectedTemplateVersion + 1;
    lastSavedVersion = nextVersion;
    _records = <DeviceTemplateRecord>[
      for (final DeviceTemplateRecord record in _records)
        if (record.template.id == template.id)
          DeviceTemplateRecord(
            template: template,
            schemaVersion: 1,
            templateVersion: nextVersion,
            enabled: enabled,
            description: description,
            tags: tags,
          )
        else
          record,
    ];
    return nextVersion;
  }

  @override
  Future<void> updateTemplateMetadata({
    required String templateId,
    required bool enabled,
    String? description,
    List<String> tags = const <String>[],
  }) async {}

  @override
  Future<void> resetTemplateToLocal({
    required DeviceTemplate template,
    bool enabled = true,
    String? description,
    List<String> tags = const <String>[],
  }) async {
    resetCalls += 1;
  }
}
