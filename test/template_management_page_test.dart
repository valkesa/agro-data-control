import 'package:agro_data_control/pages/template_management_page.dart';
import 'package:agro_data_control/services/device_template_repository.dart';
import 'package:agro_data_control/ui_templates/ui_templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TemplateManagementPage renderiza templates locales y remotos', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateManagementPage(repository: _FakeTemplateRepository()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Templates UI'), findsOneWidget);
    expect(find.text('room_climate'), findsOneWidget);
    expect(find.text('laboratory_basic'), findsOneWidget);
    expect(find.text('disinfection_arch'), findsOneWidget);
    expect(find.text('Remoto'), findsOneWidget);
    expect(find.text('Local'), findsNWidgets(2));
  });
}

class _FakeTemplateRepository extends DeviceTemplateRepository {
  @override
  Future<List<DeviceTemplateRecord>> fetchTemplates() async {
    final DeviceTemplate local = getTemplateById('room_climate')!;
    return <DeviceTemplateRecord>[
      DeviceTemplateRecord(
        template: local,
        schemaVersion: 1,
        templateVersion: 4,
        enabled: true,
        description: 'Template remoto de prueba',
        tags: const <String>['test'],
      ),
    ];
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
  }) async {}
}
