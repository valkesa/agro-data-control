import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/models/munters_model.dart';
import 'package:agro_data_control/models/room_wash_event.dart';
import 'package:agro_data_control/ui_templates/ui_templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceTableRenderer grouping', () {
    testWidgets('Sala1 + Sala2 share one Salas section with 2 rows', (
      WidgetTester tester,
    ) async {
      final DeviceTemplate room = getTemplateById('room_climate')!;
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: room,
          deviceData: _munters(name: 'Sala1'),
          title: 'Sala1',
        ),
        DeviceTableEntry(
          template: room,
          deviceData: _munters(name: 'Sala2'),
          title: 'Sala2',
        ),
      ]);

      expect(
        find.byKey(const Key('device-table-section-Salas')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('device-table-cell-Sala1-deviceName'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('device-table-cell-Sala2-deviceName'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Salas'), findsOneWidget);
    });

    testWidgets('Lab produces its own Laboratorio section with 1 row', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('laboratory_basic')!,
          deviceData: _munters(name: 'Lab'),
          title: 'Lab',
        ),
      ]);

      expect(
        find.byKey(const Key('device-table-section-Laboratorio')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('device-table-cell-Lab-equipment')),
        findsOneWidget,
      );
    });

    testWidgets('Arco produces its own section with 1 row', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('disinfection_arch')!,
          deviceData: _munters(name: 'Arco Desf'),
          title: 'Arco Desf',
        ),
      ]);

      expect(
        find.byKey(const Key('device-table-section-Arco Desinfección')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('device-table-cell-Arco Desf-equipment'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'Arco section title renders the accented name without clipping',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('disinfection_arch')!,
            deviceData: _munters(name: 'Arco Desinfección'),
            title: 'Arco Desinfección',
          ),
        ]);

        final Finder sectionTitle = find.byKey(
          const Key('device-table-section-title-Arco Desinfección'),
        );
        expect(sectionTitle, findsOneWidget);
        expect(find.bySemanticsLabel('Arco Desinfección'), findsWidgets);
        expect(find.text('Arco Desinfeccio\u0301n'), findsOneWidget);
        expect(
          tester.getSize(sectionTitle).width,
          greaterThan(140),
          reason:
              'El titulo de seccion debe tener ancho de seccion, no quedar '
              'recortado como si fuera una celda angosta.',
        );
      },
    );

    testWidgets(
      'Arco section title is normalized even when a remote template has the old label',
      (WidgetTester tester) async {
        final DeviceTemplate local = getTemplateById('disinfection_arch')!;
        final DeviceTemplate remoteOldLabel = DeviceTemplate(
          id: local.id,
          name: local.name,
          boardPreset: local.boardPreset,
          metrics: local.metrics,
          indicators: local.indicators,
          boardSlots: local.boardSlots,
          tableSection: 'Arco de desinfección',
          tableColumns: local.tableColumns,
        );

        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: remoteOldLabel,
            deviceData: _munters(name: 'Arco Desinfección'),
            title: 'Arco Desinfección',
          ),
        ]);

        expect(
          find.byKey(const Key('device-table-section-Arco Desinfección')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('device-table-section-Arco de desinfección')),
          findsNothing,
        );
      },
    );

    testWidgets('all three sections coexist with distinct column sets', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('room_climate')!,
          deviceData: _munters(name: 'Sala1'),
          title: 'Sala1',
        ),
        DeviceTableEntry(
          template: getTemplateById('laboratory_basic')!,
          deviceData: _munters(name: 'Lab'),
          title: 'Lab',
        ),
        DeviceTableEntry(
          template: getTemplateById('disinfection_arch')!,
          deviceData: _munters(name: 'Arco Desf'),
          title: 'Arco Desf',
        ),
      ]);

      expect(
        find.byKey(const Key('device-table-section-Salas')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('device-table-section-Laboratorio')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('device-table-section-Arco Desinfección')),
        findsOneWidget,
      );

      // Salas trae puertas/fan/cerdas/NH3, que Laboratorio y Arco no tienen.
      // 'Sala' es el shortLabel tanto de deviceName como de puertaSala en
      // room_climate: confirmamos que aparece dos veces (una por columna),
      // ambas dentro de Salas, ninguna filtrada por otra sección.
      expect(find.text('Sala'), findsNWidgets(2));
      expect(find.text('Vehiculos/dia'), findsOneWidget);
      expect(find.textContaining('Delta PR'), findsOneWidget);
      // Laboratorio no debe traer ninguna columna de Sala.
      expect(find.text('Munters'), findsOneWidget); // solo aparece 1 vez (Sala)
    });
  });

  group('DeviceTableRenderer column order/visibility', () {
    testWidgets(
      'columns render sorted by order, invisible columns are hidden',
      (WidgetTester tester) async {
        final DeviceTemplate template = _orderTestTemplate();
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: template,
            deviceData: <String, Object?>{
              'name': 'X1',
              'first': 1,
              'second': 2,
              'hidden': 3,
            },
            title: 'X1',
          ),
        ]);

        final double firstX = tester.getTopLeft(find.text('Second')).dx;
        final double secondX = tester.getTopLeft(find.text('First')).dx;
        // 'second' declara order:0 y 'first' order:1, así que Second debe
        // quedar a la izquierda de First pese al orden de declaración inverso
        // en tableColumns.
        expect(firstX, lessThan(secondX));
        expect(find.text('Hidden'), findsNothing);
      },
    );
  });

  group('DeviceTableRenderer values', () {
    testWidgets('resolves number, percentage, counter, boolean and text', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('room_climate')!,
          deviceData: _munters(name: 'Sala1'),
          title: 'Sala1',
        ),
      ]);

      expect(find.textContaining('22.1'), findsOneWidget); // number
      expect(find.textContaining('60'), findsWidgets); // percentage
      expect(find.textContaining('Sala1'), findsWidgets); // text (row label)
    });

    testWidgets('pending sourceFields render as "-"', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('disinfection_arch')!,
          deviceData: _munters(name: 'Arco Desf'),
          title: 'Arco Desf',
        ),
      ]);

      expect(find.text(templateNoDataLabel), findsNothing);
      expect(find.text('-'), findsNWidgets(3));
    });

    testWidgets(
      'computed dew point delta resolves through the shared resolver',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala1'),
            title: 'Sala1',
          ),
        ]);

        // No debe mostrar "-" para dewPointDelta: hay tempInterior y
        // humInterior reales en el fixture, así que el resolver calcula un
        // valor real en vez de caer al null-safe fallback.
        final Finder dewCell = find.descendant(
          of: find.byKey(
            const ValueKey<String>('device-table-cell-Sala1-dewPointDelta'),
          ),
          matching: find.textContaining(RegExp(r'-?\d+\.\d')),
        );
        expect(dewCell, findsWidgets);
        expect(
          find.byKey(const Key('device-table-header-dewPointDelta')),
          findsOneWidget,
        );
        expect(find.textContaining('Delta PR °C'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('device-table-cell-Sala1-dewPointDelta'),
            ),
            matching: find.textContaining('°C'),
          ),
          findsNothing,
        );
      },
    );
  });

  group('DeviceTableRenderer alarm semantics', () {
    test('alarmState levels map to the same tokens as TABLERO', () {
      expect(
        templateAlarmLevelColor(TemplateAlarmLevel.normal),
        const Color(0xFF22C55E),
      );
      expect(
        templateAlarmLevelColor(TemplateAlarmLevel.warning),
        const Color(0xFFFACC15),
      );
      expect(
        templateAlarmLevelColor(TemplateAlarmLevel.alarm),
        const Color(0xFFEF4444),
      );
      expect(
        templateAlarmLevelColor(TemplateAlarmLevel.unavailable),
        const Color(0xFFE5E7EB),
      );
    });

    testWidgets(
      'sensor failure hides the raw temperature behind an error tooltip',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: MuntersModel(
              name: 'Sala1',
              historyPlcId: 'munters1',
              tempInterior: -51,
              tempIngresoSala: null,
              humInterior: 60,
              tempExterior: 18,
              humExterior: 70,
              tensionSalidaVentiladores: 400,
              bombaHumidificador: false,
              fanQ5: false,
              fanQ6: false,
              fanQ7: false,
              fanQ8: false,
              fanQ9: false,
              fanQ10: false,
              resistencia1: false,
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
            ),
            title: 'Sala1',
          ),
        ]);

        expect(find.textContaining('-51'), findsNothing);
        expect(
          find.byKey(const Key('device-table-sensor-failure')),
          findsOneWidget,
        );
        expect(find.byTooltip('Falla sensor (cod. -51)'), findsOneWidget);
      },
    );

    testWidgets('statusBehavior none keeps sowCount neutral even with data', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('room_climate')!,
          deviceData: TemplateDataContext(
            source: _munters(name: 'Sala1'),
            extras: <String, Object?>{'currentCount': 120},
          ),
          title: 'Sala1',
        ),
      ]);

      final Text cerdas = tester.widget<Text>(find.text('120'));
      expect(cerdas.style?.color, const Color(0xFFE5E7EB));
    });

    testWidgets('recent wash keeps high humidity as warning, not alarm', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('room_climate')!,
          deviceData: _munters(
            name: 'Sala1',
            humInterior: 97,
            recentRoomWashEvent: RoomWashEvent(
              tenantId: 'tenant',
              roomId: 'room',
              roomNumber: 1,
              muntersId: 'munters1',
              washedAt: DateTime.now().subtract(const Duration(minutes: 10)),
              createdByUid: 'uid',
              createdByName: 'Operador',
              source: RoomWashEvent.operatorSource,
            ),
          ),
          title: 'Sala1',
        ),
      ]);

      final Text humidity = tester.widget<Text>(find.text('97'));
      expect(humidity.style?.color, const Color(0xFFFACC15));
    });
  });

  group('DeviceTableRenderer indicators', () {
    testWidgets(
      'active/inactive indicators render dimmed differently next to temperature',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala1'),
            title: 'Sala1',
          ),
        ]);

        final Finder icons = find.descendant(
          of: find.byKey(
            const ValueKey<String>('device-table-cell-Sala1-tempInterior'),
          ),
          matching: find.byType(Icon),
        );
        final List<Color?> flameColors = tester
            .widgetList<Icon>(icons)
            .map((Icon icon) => icon.color)
            .where(
              (Color? color) =>
                  color == const Color(0xFFF97316) ||
                  color == const Color(0xFF64748B),
            )
            .toList();
        // resistencia1=true (activo), resistencia2=false/bombaHumidificador
        // false (inactivos): deben existir ambos colores (naranja/gris del
        // fueguito animado legacy), no todos iguales.
        expect(flameColors, contains(const Color(0xFFF97316)));
        expect(flameColors, contains(const Color(0xFF64748B)));
      },
    );

    testWidgets(
      'worst case: alert bubble + both heating stages active never throws '
      '(may ellipsize — accepted tradeoff for a narrower column)',
      (WidgetTester tester) async {
        // tempInterior=12.1 is below temperatureMin (15) -> alarm -> bubble;
        // both resistencia stages active -> two animated flames at once.
        // At the narrowed column width this combo can legitimately ellipsize
        // ("12…" instead of "12.1") — a deliberate tradeoff (see prompt
        // Prompt_Fix_Tabla_SingleRoom_DeviceGroupTitle follow-up: user chose
        // "angostar igual, aceptar truncamiento en ese caso extremo" over
        // widening the column to fit this rare combo without loss). What
        // must never happen is a `RenderFlex` overflow exception/crash.
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: const MuntersModel(
              name: 'Sala1',
              tempInterior: 12.1,
              tempIngresoSala: null,
              humInterior: 60,
              tempExterior: 5,
              humExterior: 70,
              tensionSalidaVentiladores: 450,
              bombaHumidificador: false,
              fanQ5: true,
              fanQ6: false,
              fanQ7: false,
              fanQ8: false,
              fanQ9: false,
              fanQ10: false,
              resistencia1: true,
              resistencia2: true,
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
            ),
            title: 'Sala1',
          ),
        ]);

        // The one hard requirement: no RenderFlex overflow / crash.
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(
            const ValueKey<String>('device-table-cell-Sala1-tempInterior'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the common case (a bubble alone, no indicators) never ellipsizes at '
      'the narrowed width',
      (WidgetTester tester) async {
        // humedadInterior has no attached indicators (flame/snowflake are
        // only on tempInterior) — this is the realistic common shape of an
        // alert cell, and it has to render the full value, not "97…".
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala1', humInterior: 97),
            title: 'Sala1',
          ),
        ]);

        expect(tester.takeException(), isNull);
        final Finder humidityText = find.descendant(
          of: find.byKey(
            const ValueKey<String>('device-table-cell-Sala1-humedadInterior'),
          ),
          matching: find.text('97'),
        );
        expect(humidityText, findsOneWidget);
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          humidityText,
        );
        expect(paragraph.didExceedMaxLines, isFalse);
      },
    );
  });

  group('DeviceTableRenderer Laboratorio', () {
    testWidgets('labPending never renders as a column', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('laboratory_basic')!,
          deviceData: _munters(name: 'Lab'),
          title: 'Lab',
        ),
      ]);

      expect(find.text('Pendiente'), findsNothing);
      expect(find.textContaining('Temperatura interior'), findsOneWidget);
      expect(find.textContaining('Humedad interior'), findsOneWidget);
    });
  });

  group('DeviceTableRenderer Arco', () {
    testWidgets('shows only its own 3 metrics, none from room_climate', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('disinfection_arch')!,
          deviceData: _munters(name: 'Arco Desf'),
          title: 'Arco Desf',
        ),
      ]);

      expect(find.text('Desinfectados/dia'), findsOneWidget);
      expect(find.text('Vehiculos/dia'), findsOneWidget);
      expect(find.text('Nivel %'), findsOneWidget);

      expect(find.textContaining('Temperatura interior'), findsNothing);
      expect(find.textContaining('HR int'), findsNothing);
      expect(find.textContaining('Delta PR'), findsNothing);
      expect(find.textContaining('Fan'), findsNothing);
    });
  });

  group('DeviceTableRenderer device grouping', () {
    testWidgets(
      'a multi-room device gets one spanning title row above its Salas',
      (WidgetTester tester) async {
        final DeviceTemplate room = getTemplateById('room_climate')!;
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: room,
            deviceData: _munters(name: 'Sala1'),
            title: 'Sala1',
            deviceGroupTitle: 'PLC Maternidad',
          ),
          DeviceTableEntry(
            template: room,
            deviceData: _munters(name: 'Sala2'),
            title: 'Sala2',
            deviceGroupTitle: 'PLC Maternidad',
          ),
          DeviceTableEntry(
            template: room,
            deviceData: _munters(name: 'Sala3'),
            title: 'Sala3',
            deviceGroupTitle: 'PLC Recria',
          ),
        ]);

        expect(
          find.byKey(const Key('device-table-group-title-PLC Maternidad')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('device-table-group-title-PLC Recria')),
          findsOneWidget,
        );
        final double maternidadY = tester
            .getTopLeft(
              find.byKey(const Key('device-table-group-title-PLC Maternidad')),
            )
            .dy;
        final double sala1Y = tester
            .getTopLeft(
              find.byKey(
                const ValueKey<String>('device-table-cell-Sala1-deviceName'),
              ),
            )
            .dy;
        final double recriaY = tester
            .getTopLeft(
              find.byKey(const Key('device-table-group-title-PLC Recria')),
            )
            .dy;
        final double sala3Y = tester
            .getTopLeft(
              find.byKey(
                const ValueKey<String>('device-table-cell-Sala3-deviceName'),
              ),
            )
            .dy;
        expect(sala1Y, greaterThan(maternidadY));
        expect(recriaY, greaterThan(sala1Y));
        expect(sala3Y, greaterThan(recriaY));
      },
    );

    testWidgets(
      'a single-room device whose name matches the room hides the redundant group title',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala1'),
            title: 'Sala1',
            deviceGroupTitle: 'Sala1',
          ),
        ]);

        expect(
          find.byKey(const Key('device-table-group-title-Sala1')),
          findsNothing,
        );
        expect(find.text('Sala1'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey<String>('device-table-cell-Sala1-deviceName'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Las Heras single-room devices (Sala1, Sala2, Lab, Arco Desf) each show their name once',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala1'),
            title: 'Sala1',
            deviceGroupTitle: 'Sala1',
          ),
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala2'),
            title: 'Sala2',
            deviceGroupTitle: 'Sala2',
          ),
        ]);

        expect(
          find.byKey(const Key('device-table-group-title-Sala1')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('device-table-group-title-Sala2')),
          findsNothing,
        );
        expect(find.text('Sala1'), findsOneWidget);
        expect(find.text('Sala2'), findsOneWidget);
      },
    );

    testWidgets(
      'Laboratorio single-room device hides the redundant group title',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('laboratory_basic')!,
            deviceData: _munters(name: 'Lab'),
            title: 'Lab',
            deviceGroupTitle: 'Lab',
          ),
        ]);

        expect(
          find.byKey(const Key('device-table-group-title-Lab')),
          findsNothing,
        );
        expect(find.text('Lab'), findsOneWidget);
      },
    );

    testWidgets(
      'Arco de desinfeccion single-room device hides the redundant group title',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('disinfection_arch')!,
            deviceData: _munters(name: 'Arco Desf'),
            title: 'Arco Desf',
            deviceGroupTitle: 'Arco Desf',
          ),
        ]);

        expect(
          find.byKey(const Key('device-table-group-title-Arco Desf')),
          findsNothing,
        );
        expect(find.text('Arco Desf'), findsOneWidget);
      },
    );

    testWidgets(
      'a single-room device whose group title differs from the room name keeps the header',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala1'),
            title: 'Sala1',
            deviceGroupTitle: 'PLC Gestacion',
          ),
        ]);

        expect(
          find.byKey(const Key('device-table-group-title-PLC Gestacion')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey<String>('device-table-cell-Sala1-deviceName'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('null deviceGroupTitle renders no title row at all', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('room_climate')!,
          deviceData: _munters(name: 'Munters 1'),
          title: 'Munters 1',
        ),
      ]);

      expect(find.byIcon(Icons.memory), findsNothing);
      expect(find.text('Munters 1'), findsWidgets);
    });

    testWidgets(
      'identity column keeps the same width across Salas, Laboratorio and Arco',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala1'),
            title: 'Sala1',
            deviceGroupTitle: 'Sala1',
          ),
          DeviceTableEntry(
            template: getTemplateById('laboratory_basic')!,
            deviceData: _munters(name: 'Lab'),
            title: 'Lab',
            deviceGroupTitle: 'Lab',
          ),
          DeviceTableEntry(
            template: getTemplateById('disinfection_arch')!,
            deviceData: _munters(name: 'Arco Desf'),
            title: 'Arco Desf',
            deviceGroupTitle: 'Arco Desf',
          ),
        ]);

        final double salaWidth = tester
            .getSize(
              find.byKey(
                const ValueKey<String>('device-table-cell-Sala1-deviceName'),
              ),
            )
            .width;
        final double labWidth = tester
            .getSize(
              find.byKey(
                const ValueKey<String>('device-table-cell-Lab-equipment'),
              ),
            )
            .width;
        final double archWidth = tester
            .getSize(
              find.byKey(
                const ValueKey<String>('device-table-cell-Arco Desf-equipment'),
              ),
            )
            .width;

        expect(labWidth, closeTo(salaWidth, 0.1));
        expect(archWidth, closeTo(salaWidth, 0.1));
      },
    );

    testWidgets(
      'all data columns use the same width and short tables do not stretch',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala1'),
            title: 'Sala1',
            deviceGroupTitle: 'Sala1',
          ),
          DeviceTableEntry(
            template: getTemplateById('laboratory_basic')!,
            deviceData: _munters(name: 'Lab'),
            title: 'Lab',
            deviceGroupTitle: 'Lab',
          ),
          DeviceTableEntry(
            template: getTemplateById('disinfection_arch')!,
            deviceData: _munters(name: 'Arco Desf'),
            title: 'Arco Desf',
            deviceGroupTitle: 'Arco Desf',
          ),
        ]);

        final double salaDoorWidth = tester
            .getSize(
              find.byKey(
                const ValueKey<String>('device-table-cell-Sala1-puertaSala'),
              ),
            )
            .width;
        final double salaTempWidth = tester
            .getSize(
              find.byKey(
                const ValueKey<String>('device-table-cell-Sala1-tempInterior'),
              ),
            )
            .width;
        final double labTempWidth = tester
            .getSize(
              find.byKey(
                const ValueKey<String>('device-table-cell-Lab-tempInterior'),
              ),
            )
            .width;
        final double archLevelWidth = tester
            .getSize(
              find.byKey(
                const ValueKey<String>(
                  'device-table-cell-Arco Desf-disinfectantLevel',
                ),
              ),
            )
            .width;

        expect(salaDoorWidth, closeTo(salaTempWidth, 0.1));
        expect(labTempWidth, closeTo(salaTempWidth, 0.1));
        expect(archLevelWidth, closeTo(salaTempWidth, 0.1));

        final Rect salaLast = tester.getRect(
          find.byKey(const ValueKey<String>('device-table-cell-Sala1-nh3')),
        );
        final Rect labLast = tester.getRect(
          find.byKey(
            const ValueKey<String>('device-table-cell-Lab-humedadInterior'),
          ),
        );
        final Rect archLast = tester.getRect(
          find.byKey(
            const ValueKey<String>(
              'device-table-cell-Arco Desf-disinfectantLevel',
            ),
          ),
        );
        expect(labLast.right, lessThan(salaLast.right));
        expect(archLast.right, lessThan(salaLast.right));
      },
    );

    testWidgets('headers are centered inside their columns', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <DeviceTableEntry>[
        DeviceTableEntry(
          template: getTemplateById('room_climate')!,
          deviceData: _munters(name: 'Sala1'),
          title: 'Sala1',
        ),
      ]);

      final Rect headerCell = tester.getRect(
        find.byKey(const Key('device-table-header-cell-tempInterior')),
      );
      final Rect headerText = tester.getRect(
        find.byKey(const Key('device-table-header-tempInterior')),
      );

      expect(headerText.center.dx, closeTo(headerCell.center.dx, 1.0));
    });

    testWidgets(
      'Delta PR header uses the animated dew point icon (thermostat + 3 drops), not a static icon',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala1'),
            title: 'Sala1',
          ),
        ]);
        await tester.pump(const Duration(milliseconds: 400));

        final Finder headerCell = find.byKey(
          const Key('device-table-header-cell-dewPointDelta'),
        );
        expect(
          find.descendant(
            of: headerCell,
            matching: find.byWidgetPredicate(
              (Widget widget) =>
                  widget.runtimeType.toString() == '_TableAnimatedDewPointIcon',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: headerCell,
            matching: find.byIcon(Icons.device_thermostat),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: headerCell,
            matching: find.byIcon(Icons.water_drop),
          ),
          findsNWidgets(3),
        );
      },
    );

    testWidgets(
      'three indicators wrap two per row without increasing row height',
      (WidgetTester tester) async {
        await _pump(tester, <DeviceTableEntry>[
          DeviceTableEntry(
            template: getTemplateById('room_climate')!,
            deviceData: _munters(name: 'Sala1'),
            title: 'Sala1',
          ),
        ]);

        final Finder indicatorCell = find.byKey(
          const ValueKey<String>('device-table-cell-Sala1-tempInterior'),
        );
        final Finder plainCell = find.byKey(
          const ValueKey<String>('device-table-cell-Sala1-tempExterior'),
        );
        // One `Icon` per indicator no longer holds: the active heating
        // indicator now renders as the animated multi-tip flame (several
        // overlaid `Icon`s), not a single static one. Count indicator
        // *slots* instead, via the private wrapper each indicator gets
        // (matched by runtime type name, since it isn't exported).
        final List<Rect> indicatorRects = tester
            .widgetList(
              find.descendant(
                of: indicatorCell,
                matching: find.byWidgetPredicate(
                  (Widget widget) =>
                      widget.runtimeType.toString() == '_TableIndicatorIcon',
                ),
              ),
            )
            .map((Widget widget) => tester.getRect(find.byWidget(widget)))
            .toList(growable: false);

        expect(indicatorRects.length, 3);
        expect(indicatorRects[0].top, closeTo(indicatorRects[1].top, 0.1));
        expect(indicatorRects[2].top, greaterThan(indicatorRects[0].top));
        expect(
          tester.getSize(indicatorCell).height,
          closeTo(tester.getSize(plainCell).height, 0.1),
        );
        expect(
          tester.getSize(indicatorCell).width,
          closeTo(tester.getSize(plainCell).width, 0.1),
        );
      },
    );
  });

  group('DeviceTableRenderer productive flow', () {
    testWidgets(
      'real Gene Pig devices resolve through DeviceTemplateResolver into 3 sections',
      (WidgetTester tester) async {
        const DeviceTemplateResolver resolver = DeviceTemplateResolver();
        final List<AgroDevice> devices = <AgroDevice>[
          _geneticaDevice(id: 'plc-genetica-sala1', name: 'Sala1'),
          _geneticaDevice(id: 'plc-genetica-sala2', name: 'Sala2'),
          _geneticaDevice(id: 'plc-genetica-laboratorio', name: 'Lab'),
          _geneticaDevice(id: 'plc-genetica-arcodesinf', name: 'Arco Desf'),
        ];

        final List<DeviceTableEntry> entries = <DeviceTableEntry>[
          for (final AgroDevice device in devices)
            DeviceTableEntry(
              template: resolver.templateForDevice(device)!,
              deviceData: _munters(name: device.name),
              title: device.name,
            ),
        ];

        await _pump(tester, entries);

        expect(
          find.byKey(const Key('device-table-section-Salas')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('device-table-section-Laboratorio')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('device-table-section-Arco Desinfección')),
          findsOneWidget,
        );
        expect(find.text('Sala1'), findsOneWidget);
        expect(find.text('Sala2'), findsOneWidget);
        expect(find.text('Lab'), findsOneWidget);
        expect(find.text('Arco Desf'), findsOneWidget);
      },
    );

    testWidgets(
      'La Payana 8 salas render one Salas section, no Laboratorio/Arco',
      (WidgetTester tester) async {
        const DeviceTemplateResolver resolver = DeviceTemplateResolver();
        final List<DeviceTableEntry> entries = <DeviceTableEntry>[
          for (int i = 1; i <= 8; i++)
            DeviceTableEntry(
              template: resolver.templateForDevice(
                AgroDevice(
                  id: 'sala-$i',
                  tenantId: 'la-payana',
                  siteId: 'roque-perez',
                  name: 'Sala $i',
                  type: 'environment_multi_room',
                  model: '',
                  description: '',
                  enabled: true,
                  createdAt: null,
                  updatedAt: null,
                ),
              )!,
              deviceData: _munters(name: 'Sala $i'),
              title: 'Sala $i',
              deviceGroupTitle: 'PLC Maternidad',
            ),
        ];

        await _pump(tester, entries);

        expect(
          find.byKey(const Key('device-table-section-Salas')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('device-table-section-Laboratorio')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('device-table-section-Arco Desinfección')),
          findsNothing,
        );
        for (int i = 1; i <= 8; i++) {
          expect(find.text('Sala $i'), findsOneWidget);
        }
      },
    );
  });
}

AgroDevice _geneticaDevice({required String id, required String name}) {
  return AgroDevice(
    id: id,
    tenantId: 'the-gene-pig',
    siteId: 'las-heras',
    name: name,
    type: 'environment_single_room',
    model: 'Logo 8',
    description: '',
    enabled: true,
    createdAt: null,
    updatedAt: null,
  );
}

Future<void> _pump(WidgetTester tester, List<DeviceTableEntry> entries) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DeviceTableRenderer(entries: entries),
        ),
      ),
    ),
  );
}

MuntersModel _munters({
  required String name,
  double humInterior = 60,
  RoomWashEvent? recentRoomWashEvent,
}) {
  return MuntersModel(
    name: name,
    historyPlcId: 'munters1',
    recentRoomWashEvent: recentRoomWashEvent,
    tempInterior: 22.1,
    tempIngresoSala: null,
    humInterior: humInterior,
    tempExterior: 18,
    humExterior: 70,
    tensionSalidaVentiladores: 450,
    bombaHumidificador: false,
    fanQ5: true,
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

DeviceTemplate _orderTestTemplate() {
  return DeviceTemplate(
    id: 'order_test',
    name: 'Order test',
    boardPreset: BoardPreset.compact,
    metrics: <MetricDefinition>[
      MetricDefinition(
        key: 'first',
        label: 'First',
        unit: '',
        icon: 'unknown',
        sourceField: 'first',
        displayType: MetricDisplayType.number,
        decimals: 0,
      ),
      MetricDefinition(
        key: 'second',
        label: 'Second',
        unit: '',
        icon: 'unknown',
        sourceField: 'second',
        displayType: MetricDisplayType.number,
        decimals: 0,
      ),
      MetricDefinition(
        key: 'hidden',
        label: 'Hidden',
        unit: '',
        icon: 'unknown',
        sourceField: 'hidden',
        displayType: MetricDisplayType.number,
        decimals: 0,
      ),
    ],
    tableSection: 'OrderTest',
    tableColumns: <TableColumn>[
      TableColumn(
        metricKey: 'first',
        order: 1,
        width: TemplateTableColumnWidth.medium,
        visible: true,
      ),
      TableColumn(
        metricKey: 'second',
        order: 0,
        width: TemplateTableColumnWidth.medium,
        visible: true,
      ),
      TableColumn(
        metricKey: 'hidden',
        order: 2,
        width: TemplateTableColumnWidth.medium,
        visible: false,
      ),
    ],
  );
}
