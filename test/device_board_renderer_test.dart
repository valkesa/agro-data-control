import 'dart:math' as math;

import 'package:agro_data_control/ui_templates/ui_templates.dart';
import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/models/room_wash_event.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TemplateDataResolver', () {
    const TemplateDataResolver resolver = TemplateDataResolver();

    test('resolves valid sourceField and missing sourceField safely', () {
      expect(resolver.resolveSourceField('tempInterior', _deviceData()), 22.1);
      expect(
        resolver.resolveSourceField('missingField', _deviceData()),
        isNull,
      );
    });

    test('resolves pending fields as null', () {
      expect(
        resolver.resolveSourceField('pending.vehiclesTotal', _deviceData()),
        isNull,
      );
    });

    test('resolves computed dew point delta with shared calculation', () {
      final Object? value = resolver.resolveSourceField(
        'computed.dewPointDelta',
        _deviceData(),
      );
      final double? dewPoint = calculateDewPointC(
        temperatureC: 22.1,
        relativeHumidityPercent: 60,
      );

      expect(
        value,
        closeTo(
          calculateDewPointDeltaC(temperatureC: 22.1, dewPointC: dewPoint)!,
          0.001,
        ),
      );
    });

    test('applies voltageToPercent transform', () {
      final MetricDefinition fan = getTemplateById(
        'room_climate',
      )!.metrics.singleWhere((MetricDefinition metric) => metric.key == 'fan');

      expect(resolver.resolveMetric(fan, _deviceData()), 0.45);
    });
  });

  group('Template value formatting', () {
    test('formats number, percentage, counter, boolean and text', () {
      expect(
        formatTemplateMetricValue(
          _metric(MetricDisplayType.number, decimals: 1),
          19.84,
        ),
        '19.8',
      );
      expect(
        formatTemplateMetricValue(_percentageMetric(decimals: 0), 60),
        '60',
      );
      expect(
        formatTemplateMetricValue(_metric(MetricDisplayType.counter), 1243),
        '1243',
      );
      expect(
        formatTemplateMetricValue(_metric(MetricDisplayType.boolean), true),
        'Activo',
      );
      expect(
        formatTemplateMetricValue(_metric(MetricDisplayType.boolean), false),
        'Inactivo',
      );
      expect(
        formatTemplateMetricValue(_metric(MetricDisplayType.text), 'Sala 1'),
        'Sala 1',
      );
    });

    test(
      'formats percentage scale from metric definition, not value heuristic',
      () {
        expect(formatTemplateMetricValue(_fanMetric(), 0.45), '45');
        expect(
          formatTemplateMetricValue(_percentageMetric(decimals: 0), 60.0),
          '60',
        );
        expect(
          formatTemplateMetricValue(_percentageMetric(decimals: 0), 1.0),
          '1',
        );
        expect(
          formatTemplateMetricValue(_percentageMetric(decimals: 1), 0.5),
          '0.5',
        );
      },
    );
  });

  group('DeviceBoardRenderer', () {
    testWidgets(
      'renders room_climate with 13 ordered slots and declared sizes',
      (WidgetTester tester) async {
        final DeviceTemplate template = getTemplateById('room_climate')!;

        await _pumpRenderer(tester, template: template);

        for (final BoardSlot slot in template.boardSlots) {
          expect(
            find.byKey(Key('device-board-slot-${slot.metricKey}')),
            findsOneWidget,
          );
          expect(
            find.byKey(Key('device-board-slot-position-${slot.position}')),
            findsOneWidget,
          );
        }

        final List<int> renderedPositions = tester.allWidgets
            .map((Widget widget) => widget.key)
            .whereType<Key>()
            .map((Key key) => key.toString())
            .where((String key) => key.contains('device-board-slot-position-'))
            .map(
              (String key) =>
                  int.parse(key.split('position-').last.split("'").first),
            )
            .toList(growable: false);
        expect(
          renderedPositions,
          List<int>.generate(13, (int index) => index + 1),
        );

        final Size temperatureSize = tester.getSize(
          find.byKey(const Key('device-board-slot-tempInterior')),
        );
        final Size humiditySize = tester.getSize(
          find.byKey(const Key('device-board-slot-humedadInterior')),
        );
        final Size deviceNameSize = tester.getSize(
          find.byKey(const Key('device-board-slot-puertaSala')),
        );
        expect(temperatureSize.width, greaterThan(humiditySize.width));
        expect(humiditySize.width, greaterThan(deviceNameSize.width));
      },
    );

    testWidgets(
      'card titles share the exact same TextStyle across every preset',
      (WidgetTester tester) async {
        Future<TextStyle> titleStyleFor(
          DeviceTemplate template,
          String title,
        ) async {
          await _pumpRenderer(tester, template: template, title: title);
          final Text titleWidget = tester.widget<Text>(find.text(title));
          return titleWidget.style!;
        }

        final TextStyle sala1 = await titleStyleFor(
          getTemplateById('room_climate')!,
          'Sala1',
        );
        final TextStyle sala2 = await titleStyleFor(
          getTemplateById('room_climate')!,
          'Sala2',
        );
        final TextStyle lab = await titleStyleFor(
          getTemplateById('laboratory_basic')!,
          'Lab',
        );
        final TextStyle arco = await titleStyleFor(
          getTemplateById('disinfection_arch')!,
          'Arco Desf',
        );

        for (final TextStyle style in <TextStyle>[sala2, lab, arco]) {
          expect(style.fontSize, sala1.fontSize);
          expect(style.fontWeight, sala1.fontWeight);
          expect(style.height, sala1.height);
          expect(style.color, sala1.color);
        }
      },
    );

    testWidgets('large preset keeps slots 6 to 13 square and equal', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        width: 430,
      );

      final Size firstMini = tester.getSize(
        find.byKey(const Key('device-board-slot-position-6')),
      );
      expect(firstMini.width, firstMini.height);
      for (int position = 7; position <= 13; position++) {
        final Size size = tester.getSize(
          find.byKey(Key('device-board-slot-position-$position')),
        );
        expect(size.width, firstMini.width);
        expect(size.height, firstMini.height);
      }
    });

    testWidgets('large preset geometry is mathematically derived', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        width: 430,
      );

      final Rect large = tester.getRect(
        find.byKey(const Key('device-board-slot-position-1')),
      );
      final Rect medium2 = tester.getRect(
        find.byKey(const Key('device-board-slot-position-2')),
      );
      final Rect medium3 = tester.getRect(
        find.byKey(const Key('device-board-slot-position-3')),
      );
      final Rect medium4 = tester.getRect(
        find.byKey(const Key('device-board-slot-position-4')),
      );
      final Rect mini6 = tester.getRect(
        find.byKey(const Key('device-board-slot-position-6')),
      );
      final Rect mini13 = tester.getRect(
        find.byKey(const Key('device-board-slot-position-13')),
      );
      final double horizontalGap = medium3.left - medium2.right;
      final double verticalGap = medium4.top - medium2.bottom;

      expect(large.width, medium2.width * 2 + horizontalGap);
      expect(large.height, medium2.height * 2 + verticalGap);
      expect(large.height, 124);
      expect(mini6.width, mini6.height);
      expect(mini6.height, medium2.height);
      expect(medium2.left, large.left);
      expect(medium3.right, large.right);
      expect(
        mini13.bottom - mini6.top,
        large.height +
            verticalGap +
            medium2.height +
            verticalGap +
            medium2.height,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('medium values keep secondary visual hierarchy', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        width: 430,
      );

      final List<String> slotKeys = <String>[
        'humedadInterior',
        'dewPointDelta',
        'tempExterior',
        'humedadExterior',
      ];
      final List<double?> fontSizes = <double?>[
        for (final String slotKey in slotKeys)
          tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byKey(Key('device-board-slot-$slotKey')),
                  matching: find.byType(Text),
                ),
              )
              .map((Text text) => text.style?.fontSize ?? 0)
              .reduce(math.max),
      ];

      expect(fontSizes.toSet(), <double>{28});
      for (final String slotKey in slotKeys) {
        final Size size = tester.getSize(
          find.byKey(Key('device-board-slot-$slotKey')),
        );
        expect(size.height, 59);
      }
    });

    testWidgets('small labels for NH3 and CO2 are centered', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        width: 430,
      );

      for (final ({String slotKey, String label}) item
          in <({String slotKey, String label})>[
            (slotKey: 'nh3', label: 'NH3'),
            (slotKey: 'co2', label: 'CO2'),
          ]) {
        final Rect slotRect = tester.getRect(
          find.byKey(Key('device-board-slot-${item.slotKey}')),
        );
        final Rect labelRect = tester.getRect(find.text(item.label));
        expect(
          (labelRect.center.dx - slotRect.center.dx).abs(),
          lessThanOrEqualTo(2),
        );
      }
    });

    testWidgets('water minibox shows only a centered icon', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        width: 430,
      );

      final Finder waterSlot = find.byKey(const Key('device-board-slot-agua'));
      final Finder waterIcon = find.descendant(
        of: waterSlot,
        matching: find.byIcon(Icons.local_drink_outlined),
      );
      final Rect slotRect = tester.getRect(waterSlot);
      final Rect iconRect = tester.getRect(waterIcon);

      expect(find.text('Agua'), findsNothing);
      expect(waterIcon, findsOneWidget);
      expect(
        (iconRect.center.dx - slotRect.center.dx).abs(),
        lessThanOrEqualTo(2),
      );
    });

    testWidgets('minibox icon is centered above value, especially fan', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        width: 430,
      );

      final Finder fanSlot = find.byKey(const Key('device-board-slot-fan'));
      final Finder fanIcon = find.byKey(const Key('device-board-animated-fan'));
      final Rect slotRect = tester.getRect(fanSlot);
      final Rect iconRect = tester.getRect(fanIcon);
      final Rect valueRect = tester.getRect(find.text('45'));

      expect(
        (iconRect.center.dx - slotRect.center.dx).abs(),
        lessThanOrEqualTo(1.5),
      );
      expect(iconRect.top, greaterThan(slotRect.top));
      expect(iconRect.bottom, lessThan(valueRect.top));
      expect(iconRect.width, greaterThanOrEqualTo(22));
    });

    testWidgets('large preset keeps the legacy topology on desktop', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        width: 430,
      );

      final Offset p1 = _slotTopLeft(tester, 1);
      final Offset p2 = _slotTopLeft(tester, 2);
      final Offset p3 = _slotTopLeft(tester, 3);
      final Offset p6 = _slotTopLeft(tester, 6);
      final Offset p7 = _slotTopLeft(tester, 7);
      final Offset p8 = _slotTopLeft(tester, 8);
      final Offset p12 = _slotTopLeft(tester, 12);
      final Offset p13 = _slotTopLeft(tester, 13);

      expect(
        find.byKey(const Key('device-board-large-layout')),
        findsOneWidget,
      );
      expect(p2.dy, greaterThan(p1.dy));
      expect(p3.dy, p2.dy);
      expect(p3.dx, greaterThan(p2.dx));
      expect(p6.dx, greaterThan(p1.dx));
      expect(p7.dy, p6.dy);
      expect(p7.dx, greaterThan(p6.dx));
      expect(p8.dy, greaterThan(p6.dy));
      expect(p12.dx, p6.dx);
      expect(p13.dx, p7.dx);
    });

    testWidgets('large preset does not reflow into a long column on mobile', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        width: 320,
      );

      final Size layoutSize = tester.getSize(
        find.byKey(const Key('device-board-large-layout')),
      );
      final Offset p1 = _slotTopLeft(tester, 1);
      final Offset p6 = _slotTopLeft(tester, 6);
      final Offset p13 = _slotTopLeft(tester, 13);

      expect(tester.takeException(), isNull);
      expect(layoutSize.width, greaterThanOrEqualTo(330));
      expect(layoutSize.height, lessThanOrEqualTo(330));
      expect(p6.dx, greaterThan(p1.dx));
      expect(p13.dy, greaterThan(p6.dy));
      expect(find.text('22.1'), findsOneWidget);
    });

    testWidgets('visual device name uses title instead of technical id', (
      WidgetTester tester,
    ) async {
      final Map<String, Object?> data = _deviceData()
        ..['name'] = 'plc-genetica-sala1';

      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: data,
        title: 'Sala1',
      );

      expect(find.text('Sala1'), findsWidgets);
      expect(find.text('plc-genetica-sala1'), findsNothing);
    });

    testWidgets('renders source values, transforms and pending placeholders', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(tester, template: getTemplateById('room_climate')!);

      expect(find.text('Sala 1'), findsWidgets);
      expect(find.text('22.1'), findsOneWidget);
      expect(find.text('18.0'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
      expect(find.text(templateNoDataLabel), findsNWidgets(3));
      expect(find.text('42'), findsNothing);
    });

    testWidgets('renders sow count from currentCount instead of peso', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: _deviceData()..['currentCount'] = 42,
      );

      expect(
        find.byKey(const Key('device-board-slot-sowCount')),
        findsOneWidget,
      );
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Peso'), findsNothing);
      expect(find.text('Cerdas'), findsNothing);
      expect(
        find.byKey(const Key('device-board-custom-pig-icon')),
        findsOneWidget,
      );
    });

    testWidgets('MetricStatusBehavior none keeps valid values neutral', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(tester, template: getTemplateById('room_climate')!);

      final Text fanValue = tester.widget<Text>(find.text('45'));
      expect(fanValue.style?.color, const Color(0xFFE5E7EB));
    });

    test('fan uses exact legacy stepped durations', () {
      expect(
        fanSpinDurationForPercent(null),
        const Duration(milliseconds: 650),
      );
      expect(fanSpinDurationForPercent(0), const Duration(milliseconds: 1500));
      expect(
        fanSpinDurationForPercent(0.25),
        const Duration(milliseconds: 1500),
      );
      expect(fanSpinDurationForPercent(0.5), const Duration(milliseconds: 650));
      expect(
        fanSpinDurationForPercent(0.75),
        const Duration(milliseconds: 250),
      );
      expect(fanSpinDurationForPercent(1), const Duration(milliseconds: 250));
    });

    testWidgets('value and unit share visual color by status behavior', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(tester, template: getTemplateById('room_climate')!);
      _expectSlotValueAndUnitColor(
        tester,
        slotKey: 'tempInterior',
        value: '22.1',
        unit: '°C',
        color: const Color(0xFF22C55E),
      );

      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: _deviceData()..['humInterior'] = 90.0,
      );
      _expectSlotValueAndUnitColor(
        tester,
        slotKey: 'humedadInterior',
        value: '90',
        unit: '%',
        color: const Color(0xFFFACC15),
      );

      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: _deviceData()..['presionDiferencial'] = 80.0,
      );
      _expectSlotValueAndUnitColor(
        tester,
        slotKey: 'presion',
        value: '80',
        unit: 'Pa',
        color: const Color(0xFFEF4444),
      );

      await _pumpRenderer(tester, template: getTemplateById('room_climate')!);
      _expectSlotValueAndUnitColor(
        tester,
        slotKey: 'fan',
        value: '45',
        unit: '%',
        color: const Color(0xFFE5E7EB),
      );
    });

    testWidgets('alarmState colors normal, warning, alarm and null correctly', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(tester, template: getTemplateById('room_climate')!);
      expect(
        tester.widget<Text>(find.text('22.1')).style?.color,
        const Color(0xFF22C55E),
      );

      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: _deviceData()..['humInterior'] = 90.0,
      );
      expect(
        tester.widget<Text>(find.text('90')).style?.color,
        const Color(0xFFFACC15),
      );

      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: _deviceData()..['tempInterior'] = 40.0,
      );
      expect(
        tester.widget<Text>(find.text('40.0')).style?.color,
        const Color(0xFFEF4444),
      );

      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: _deviceData()..['tempInterior'] = null,
      );
      final Text noData = tester.widget<Text>(
        find.text(templateNoDataLabel).first,
      );
      expect(noData.style?.color, const Color(0xFF94A3B8));
    });

    testWidgets(
      'renders boolean values with visual state labels, not true/false',
      (WidgetTester tester) async {
        await _pumpRenderer(tester, template: _booleanTemplate());

        expect(find.text('Activo'), findsOneWidget);
        expect(find.text('Inactivo'), findsOneWidget);
        expect(find.text('true'), findsNothing);
        expect(find.text('false'), findsNothing);
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        expect(find.byIcon(Icons.cancel), findsOneWidget);
      },
    );

    testWidgets('renders active and inactive indicators structurally', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(tester, template: getTemplateById('room_climate')!);

      expect(
        find.byKey(const Key('device-board-indicator-calefaccionEtapa1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('device-board-indicator-calefaccionEtapa2')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('device-board-indicator-state-calefaccionEtapa1-active'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('device-board-indicator-state-calefaccionEtapa2-inactive'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('device-board-indicator-state-humidificacion-inactive'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      final double indicatorX = tester
          .getTopLeft(
            find.byKey(const Key('device-board-indicator-calefaccionEtapa1')),
          )
          .dx;
      final double valueX = tester.getTopLeft(find.text('22.1')).dx;
      expect(indicatorX, lessThan(valueX));
    });

    testWidgets('flame, fan and dew point use animated visual widgets', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(tester, template: getTemplateById('room_climate')!);

      expect(
        find.byKey(const Key('device-board-indicator-calefaccionEtapa1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('device-board-animated-fan')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('device-board-animated-dew-point')),
        findsOneWidget,
      );
    });

    testWidgets('cooling indicator turns active from bombaHumidificador', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: _deviceData()..['bombaHumidificador'] = true,
      );

      expect(
        find.byKey(const Key('device-board-indicator-humidificacion')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('device-board-indicator-state-humidificacion-active'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('doors use alarm colors and no boolean cross', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: _deviceData()
          ..['salaAbierta'] = false
          ..['munterAbierto'] = false,
      );

      final Text closedDoor = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('device-board-slot-puertaSala')),
          matching: find.text('Sala'),
        ),
      );
      expect(closedDoor.style?.color, const Color(0xFF22C55E));
      expect(find.byIcon(Icons.cancel), findsNothing);

      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: _deviceData()..['salaAbierta'] = true,
      );
      final Text openDoor = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('device-board-slot-puertaSala')),
          matching: find.text('Sala'),
        ),
      );
      expect(openDoor.style?.color, const Color(0xFFEF4444));
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets('NH3 and CO2 use textual identifier without icon', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(tester, template: getTemplateById('room_climate')!);

      expect(
        find.descendant(
          of: find.byKey(const Key('device-board-slot-nh3')),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('device-board-slot-co2')),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
      expect(find.text('NH3'), findsOneWidget);
      expect(find.text('CO2'), findsOneWidget);
    });

    testWidgets('header dots reflect PLC and backend state', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        title: 'Sala1',
        data: _deviceData()
          ..['plcRunning'] = true
          ..['backendOnline'] = true,
        showSnapshotPulse: true,
      );

      expect(find.byKey(const Key('device-board-header')), findsOneWidget);
      expect(find.byKey(const Key('device-board-dot-plc')), findsOneWidget);
      expect(find.byKey(const Key('device-board-dot-backend')), findsOneWidget);
      expect(find.text('Sala1'), findsWidgets);

      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        title: 'Sala1',
        data: _deviceData()..['plcRunning'] = false,
        snapshotStale: true,
      );

      expect(find.byKey(const Key('device-board-dot-backend')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('supports multiple leftOfValue indicators', (
      WidgetTester tester,
    ) async {
      final Map<String, Object?> data = _deviceData()..['resistencia2'] = true;

      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: data,
      );

      expect(
        find.byKey(const Key('device-board-indicator-calefaccionEtapa1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('device-board-indicator-calefaccionEtapa2')),
        findsOneWidget,
      );
    });

    testWidgets(
      'keeps two heating indicators dimmed when both stages are off',
      (WidgetTester tester) async {
        final Map<String, Object?> data = _deviceData()
          ..['resistencia1'] = false
          ..['resistencia2'] = false;

        await _pumpRenderer(
          tester,
          template: getTemplateById('room_climate')!,
          data: data,
        );

        expect(
          find.byKey(const Key('device-board-indicator-calefaccionEtapa1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('device-board-indicator-calefaccionEtapa2')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const Key(
              'device-board-indicator-state-calefaccionEtapa1-inactive',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const Key(
              'device-board-indicator-state-calefaccionEtapa2-inactive',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('22.1'), findsOneWidget);
      },
    );

    testWidgets('sensor failure hides measured value behind error tooltip', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: _deviceData()..['tempInterior'] = -51.0,
      );

      expect(
        find.byKey(const Key('device-board-sensor-failure')),
        findsOneWidget,
      );
      expect(find.text('-51.0'), findsNothing);
      final Tooltip tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const Key('device-board-sensor-failure')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Falla sensor (cod. -51)');
    });

    testWidgets('recent wash keeps high humidity as warning instead of alarm', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: TemplateDataContext(
          source: _muntersData(
            humInterior: 96,
            recentRoomWashEvent: RoomWashEvent(
              tenantId: 'tenant',
              roomId: 'room',
              roomNumber: 1,
              muntersId: 'munters1',
              washedAt: DateTime.now().subtract(const Duration(minutes: 15)),
              createdByUid: 'uid',
              createdByName: 'Operador',
              source: RoomWashEvent.operatorSource,
            ),
          ),
        ),
      );

      expect(
        tester.widget<Text>(find.text('96')).style?.color,
        const Color(0xFFFACC15),
      );
    });

    testWidgets('high humidity without recent wash remains alarm', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('room_climate')!,
        data: TemplateDataContext(source: _muntersData(humInterior: 96)),
      );

      expect(
        tester.widget<Text>(find.text('96')).style?.color,
        const Color(0xFFEF4444),
      );
    });

    testWidgets('unknown icons and null data degrade safely', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(tester, template: _unknownIconTemplate());

      expect(find.byIcon(Icons.device_unknown_outlined), findsOneWidget);
      expect(find.text(templateNoDataLabel), findsOneWidget);
    });

    testWidgets('unknown metric references do not break the whole card', (
      WidgetTester tester,
    ) async {
      final DeviceTemplate template = _unknownIconTemplate();
      template.boardSlots.add(
        BoardSlot(
          metricKey: 'missingMetric',
          position: 2,
          size: BoardSlotSize.small,
          visible: true,
        ),
      );

      await _pumpRenderer(tester, template: template);

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Unknown metric'), findsWidgets);
    });

    testWidgets('medium and compact presets render structurally', (
      WidgetTester tester,
    ) async {
      await _pumpRenderer(
        tester,
        template: getTemplateById('laboratory_basic')!,
      );
      expect(find.text('Laboratorio básico'), findsOneWidget);
      expect(
        find.byKey(const Key('device-board-slot-tempInterior')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('device-board-slot-labPending')),
        findsOneWidget,
      );

      await _pumpRenderer(
        tester,
        template: getTemplateById('disinfection_arch')!,
      );
      expect(find.text('Arco de desinfección'), findsOneWidget);
      expect(
        find.byKey(const Key('device-board-slot-vehiclesDisinfectedDaily')),
        findsOneWidget,
      );
    });

    testWidgets(
      'laboratory compact preset lays out three medium boxes horizontally',
      (WidgetTester tester) async {
        await _pumpRenderer(
          tester,
          template: getTemplateById('laboratory_basic')!,
          width: 390,
        );

        final Rect temp = tester.getRect(
          find.byKey(const Key('device-board-slot-tempInterior')),
        );
        final Rect humidity = tester.getRect(
          find.byKey(const Key('device-board-slot-humedadInterior')),
        );
        final Rect pending = tester.getRect(
          find.byKey(const Key('device-board-slot-labPending')),
        );

        expect(temp.top, humidity.top);
        expect(humidity.top, pending.top);
        expect(humidity.left, greaterThan(temp.right));
        expect(pending.left, greaterThan(humidity.right));
        expect(temp.size, humidity.size);
        expect(humidity.size, pending.size);
        expect(temp.size, const Size(126, 59));
        expect(find.text('Pendiente'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'disinfection arch compact preset lays out three real medium boxes horizontally',
      (WidgetTester tester) async {
        await _pumpRenderer(
          tester,
          template: getTemplateById('disinfection_arch')!,
          width: 390,
        );

        final Rect disinfected = tester.getRect(
          find.byKey(const Key('device-board-slot-vehiclesDisinfectedDaily')),
        );
        final Rect total = tester.getRect(
          find.byKey(const Key('device-board-slot-vehiclesTotalDaily')),
        );
        final Rect level = tester.getRect(
          find.byKey(const Key('device-board-slot-disinfectantLevel')),
        );

        expect(disinfected.top, total.top);
        expect(total.top, level.top);
        expect(total.left, greaterThan(disinfected.right));
        expect(level.left, greaterThan(total.right));
        expect(disinfected.size, const Size(126, 59));
        expect(total.size, disinfected.size);
        expect(level.size, disinfected.size);
        expect(find.text(templateNoDataLabel), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'real Gene Pig Arco device resolves and renders disinfection_arch, not room_climate',
      (WidgetTester tester) async {
        const DeviceTemplateResolver resolver = DeviceTemplateResolver();
        final AgroDevice arco = AgroDevice(
          id: 'plc-genetica-arcodesinf',
          tenantId: 'the-gene-pig',
          siteId: 'las-heras',
          name: 'Arco Desf',
          type: 'environment_single_room',
          model: 'Logo 8',
          description: '',
          enabled: true,
          createdAt: null,
          updatedAt: null,
        );

        final DeviceTemplate? template = resolver.templateForDevice(arco);
        expect(template?.id, 'disinfection_arch');

        await _pumpRenderer(tester, template: template!, width: 390);

        expect(find.text('Desinfectados/dia'), findsOneWidget);
        expect(find.text('Vehiculos/dia'), findsOneWidget);
        expect(find.text('Nivel'), findsOneWidget);

        expect(find.textContaining('Temperatura interior'), findsNothing);
        expect(find.textContaining('HR int'), findsNothing);
        expect(find.textContaining('Delta PR'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

Future<void> _pumpRenderer(
  WidgetTester tester, {
  required DeviceTemplate template,
  Object? data,
  String? title,
  double? width,
  bool showSnapshotPulse = false,
  bool snapshotStale = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: DeviceBoardRenderer(
                template: template,
                deviceData: data ?? _deviceData(),
                title: title,
                showSnapshotPulse: showSnapshotPulse,
                snapshotStale: snapshotStale,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectSlotValueAndUnitColor(
  WidgetTester tester, {
  required String slotKey,
  required String value,
  required String unit,
  required Color color,
}) {
  final Finder slot = find.byKey(Key('device-board-slot-$slotKey'));
  final Text valueText = tester.widget<Text>(
    find.descendant(of: slot, matching: find.text(value)),
  );
  final Text unitText = tester.widget<Text>(
    find.descendant(of: slot, matching: find.text(unit)),
  );
  expect(valueText.style?.color, color);
  expect(unitText.style?.color, color);
}

Offset _slotTopLeft(WidgetTester tester, int position) {
  return tester.getTopLeft(
    find.byKey(Key('device-board-slot-position-$position')),
  );
}

Map<String, Object?> _deviceData() {
  return <String, Object?>{
    'name': 'Sala 1',
    'historyPlcId': 'munters1',
    'tempInterior': 22.1,
    'humInterior': 60.0,
    'tempExterior': 18.0,
    'humExterior': 70.0,
    'tensionSalidaVentiladores': 450.0,
    'presionDiferencial': 14.0,
    'nh3': 11.0,
    'salaAbierta': true,
    'munterAbierto': false,
    'resistencia1': true,
    'resistencia2': false,
    'bombaHumidificador': false,
    'currentCount': null,
  };
}

MuntersModel _muntersData({
  double humInterior = 60,
  RoomWashEvent? recentRoomWashEvent,
}) {
  return MuntersModel(
    name: 'Sala 1',
    historyPlcId: 'munters1',
    recentRoomWashEvent: recentRoomWashEvent,
    tempInterior: 22.1,
    tempIngresoSala: null,
    humInterior: humInterior,
    tempExterior: 18,
    humExterior: 70,
    tensionSalidaVentiladores: 450,
    bombaHumidificador: false,
    fanQ5: false,
    fanQ6: false,
    fanQ7: false,
    fanQ8: false,
    fanQ9: false,
    fanQ10: false,
    resistencia1: true,
    resistencia2: false,
    alarmaGeneral: false,
    fallaRed: false,
    nivelAguaAlarma: false,
    fallaTermicaBomba: false,
    eventosSinAgua: 0,
    horasMunter: 0,
    horasFiltroF9: 0,
    horasFiltroG4: 0,
    horasPolifosfato: 0,
    salaAbierta: false,
    aperturasSala: 0,
    munterAbierto: false,
    aperturasMunter: 0,
    cantidadApagadas: 0,
    estadoEquipo: 'RUN',
  );
}

MetricDefinition _metric(MetricDisplayType displayType, {int decimals = 0}) {
  return MetricDefinition(
    key: 'metric',
    label: 'Metric',
    unit: displayType == MetricDisplayType.percentage ? '%' : '',
    icon: 'unknown',
    sourceField: 'value',
    displayType: displayType,
    decimals: decimals,
  );
}

MetricDefinition _percentageMetric({required int decimals}) {
  return MetricDefinition(
    key: 'humidity',
    label: 'Humidity',
    unit: '%',
    icon: 'humidity',
    sourceField: 'humidity',
    displayType: MetricDisplayType.percentage,
    decimals: decimals,
  );
}

MetricDefinition _fanMetric() {
  return MetricDefinition(
    key: 'fan',
    label: 'Fan',
    unit: '%',
    icon: 'fan',
    sourceField: 'tensionSalidaVentiladores',
    displayType: MetricDisplayType.percentage,
    decimals: 0,
    transform: MetricTransform.voltageToPercent,
  );
}

DeviceTemplate _unknownIconTemplate() {
  return DeviceTemplate(
    id: 'unknown_icon',
    name: 'Unknown metric',
    boardPreset: BoardPreset.compact,
    metrics: <MetricDefinition>[
      MetricDefinition(
        key: 'unknownMetric',
        label: 'Unknown metric',
        unit: '',
        icon: 'missingIcon',
        sourceField: 'missingValue',
        displayType: MetricDisplayType.text,
        decimals: 0,
      ),
    ],
    boardSlots: <BoardSlot>[
      BoardSlot(
        metricKey: 'unknownMetric',
        position: 1,
        size: BoardSlotSize.small,
        visible: true,
      ),
    ],
    tableSection: 'Test',
  );
}

DeviceTemplate _booleanTemplate() {
  return DeviceTemplate(
    id: 'boolean_template',
    name: 'Boolean template',
    boardPreset: BoardPreset.compact,
    metrics: <MetricDefinition>[
      MetricDefinition(
        key: 'activeDoor',
        label: 'Puerta activa',
        unit: '',
        icon: 'unknown',
        sourceField: 'salaAbierta',
        displayType: MetricDisplayType.boolean,
        decimals: 0,
      ),
      MetricDefinition(
        key: 'inactiveDoor',
        label: 'Puerta inactiva',
        unit: '',
        icon: 'unknown',
        sourceField: 'munterAbierto',
        displayType: MetricDisplayType.boolean,
        decimals: 0,
      ),
    ],
    boardSlots: <BoardSlot>[
      BoardSlot(
        metricKey: 'activeDoor',
        position: 1,
        size: BoardSlotSize.medium,
        visible: true,
      ),
      BoardSlot(
        metricKey: 'inactiveDoor',
        position: 2,
        size: BoardSlotSize.medium,
        visible: true,
      ),
    ],
    tableSection: 'Test',
  );
}
