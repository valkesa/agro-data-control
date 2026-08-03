import 'package:agro_data_control/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders login screen when no user is authenticated',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const AgroDataControlApp());
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Ingresar'), findsWidgets);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Continuar con Google'), findsOneWidget);
    },
    // Requires Firebase Auth/Core platform channels in widget tests.
    skip: true,
  );
}
