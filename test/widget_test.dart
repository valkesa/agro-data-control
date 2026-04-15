import 'package:agro_data_control/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders AgroDataControl dashboard shell', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AgroDataControlApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AgroDataControl'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Munters 1'), findsWidgets);
  });
}
