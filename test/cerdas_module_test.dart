import 'dart:async';

import 'package:agro_data_control/models/cerdas_models.dart';
import 'package:agro_data_control/services/cerdas_repository.dart';
import 'package:agro_data_control/ui_templates/ui_templates.dart';
import 'package:agro_data_control/widgets/cerdas_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dynamic single-room ingreso escribe con la key de esa sala', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey sala1 = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'plc-sala-1',
    );
    final CerdasContextKey sala2 = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'plc-sala-2',
    );
    final _FakeCerdasRepository repository = _FakeCerdasRepository(
      <CerdasContextKey, int?>{sala1: 20, sala2: 35},
    );
    addTearDown(repository.dispose);

    await _pumpDynamicModule(
      tester,
      repository: repository,
      entries: <CerdasControlEntry>[
        CerdasControlEntry(label: 'Sala 1', contextKey: sala1),
        CerdasControlEntry(label: 'Sala 2', contextKey: sala2),
      ],
    );

    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '1');
    await tester.tap(find.text('Registrar ingreso'));
    await tester.pumpAndSettle();

    expect(repository.lastWrittenKey, sala1);
    expect(repository.counts[sala1], 21);
    expect(repository.counts[sala2], 35);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
  });

  testWidgets('dynamic multi-room mismo device no colisiona por roomId', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey sala1 = CerdasContextKey.dynamic(
      tenantId: 'la-payana',
      siteId: 'roque-perez',
      deviceId: 'plc-maternidad',
      roomId: 'sala-1',
    );
    final CerdasContextKey sala2 = CerdasContextKey.dynamic(
      tenantId: 'la-payana',
      siteId: 'roque-perez',
      deviceId: 'plc-maternidad',
      roomId: 'sala-2',
    );
    final _FakeCerdasRepository repository = _FakeCerdasRepository(
      <CerdasContextKey, int?>{sala1: 20, sala2: 35},
    );
    addTearDown(repository.dispose);

    await _pumpDynamicModule(
      tester,
      tenantId: 'la-payana',
      siteId: 'roque-perez',
      repository: repository,
      entries: <CerdasControlEntry>[
        CerdasControlEntry(label: 'Sala 1', contextKey: sala1),
        CerdasControlEntry(label: 'Sala 2', contextKey: sala2),
      ],
    );

    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '1');
    await tester.tap(find.text('Registrar ingreso'));
    await tester.pumpAndSettle();

    expect(repository.lastWrittenKey, sala1);
    expect(repository.counts[sala1], 21);
    expect(repository.counts[sala2], 35);
  });

  testWidgets('dynamic module distingue null de cero', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey sinDato = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'sin-dato',
    );
    final CerdasContextKey cero = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'cero',
    );
    final _FakeCerdasRepository repository = _FakeCerdasRepository(
      <CerdasContextKey, int?>{cero: 0},
    );
    addTearDown(repository.dispose);

    await _pumpDynamicModule(
      tester,
      repository: repository,
      entries: <CerdasControlEntry>[
        CerdasControlEntry(label: 'Sin dato', contextKey: sinDato),
        CerdasControlEntry(label: 'Cero', contextKey: cero),
      ],
    );

    expect(find.text('Sin datos'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  test('template visibility matches sowCount support', () {
    expect(
      deviceTemplateSupportsCerdasControl(getTemplateById('room_climate')!),
      isTrue,
    );
    expect(
      deviceTemplateSupportsCerdasControl(getTemplateById('laboratory_basic')!),
      isFalse,
    );
    expect(
      deviceTemplateSupportsCerdasControl(
        getTemplateById('disinfection_arch')!,
      ),
      isFalse,
    );
  });

  testWidgets('dynamic row mantiene el stream si no cambia la key', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey sala1 = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'plc-sala-1',
    );
    final CerdasContextKey sala2 = CerdasContextKey.dynamic(
      tenantId: 'the-gene-pig',
      siteId: 'las-heras',
      deviceId: 'plc-sala-2',
    );
    final _FakeCerdasRepository repository = _FakeCerdasRepository(
      <CerdasContextKey, int?>{sala1: 20, sala2: 35},
    );
    addTearDown(repository.dispose);

    await _pumpDynamicModule(
      tester,
      repository: repository,
      entries: <CerdasControlEntry>[
        CerdasControlEntry(label: 'Sala 1', contextKey: sala1),
      ],
    );
    expect(repository.watchPigStatsCalls[sala1], 1);

    await _pumpDynamicModule(
      tester,
      repository: repository,
      entries: <CerdasControlEntry>[
        CerdasControlEntry(label: 'Sala 1 renombrada', contextKey: sala1),
      ],
    );
    expect(repository.watchPigStatsCalls[sala1], 1);

    await _pumpDynamicModule(
      tester,
      repository: repository,
      entries: <CerdasControlEntry>[
        CerdasControlEntry(label: 'Sala 2', contextKey: sala2),
      ],
    );
    expect(repository.watchPigStatsCalls[sala1], 1);
    expect(repository.watchPigStatsCalls[sala2], 1);
  });

  testWidgets('legacy module sigue escribiendo con plcId', (
    WidgetTester tester,
  ) async {
    final CerdasContextKey legacy1 = CerdasContextKey.legacy(
      tenantId: 'the-gene-pig',
      siteId: 'genetica-1',
      plcId: 'munters1',
    );
    final CerdasContextKey legacy2 = CerdasContextKey.legacy(
      tenantId: 'the-gene-pig',
      siteId: 'genetica-1',
      plcId: 'munters2',
    );
    final _FakeCerdasRepository repository = _FakeCerdasRepository(
      <CerdasContextKey, int?>{legacy1: 10, legacy2: 11},
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CerdasModule(
            tenantId: 'the-gene-pig',
            siteId: 'genetica-1',
            plc1Id: 'munters1',
            plc2Id: 'munters2',
            userIdentity: const CerdasUserIdentity(
              uid: 'tester',
              name: 'Tester',
            ),
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '1');
    await tester.tap(find.text('Registrar ingreso'));
    await tester.pumpAndSettle();

    expect(repository.lastWrittenKey, legacy1);
    expect(repository.counts[legacy1], 11);
    expect(repository.counts[legacy2], 11);
  });
}

Future<void> _pumpDynamicModule(
  WidgetTester tester, {
  String tenantId = 'the-gene-pig',
  String siteId = 'las-heras',
  required _FakeCerdasRepository repository,
  required List<CerdasControlEntry> entries,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CerdasDynamicModule(
          tenantId: tenantId,
          siteId: siteId,
          entries: entries,
          userIdentity: const CerdasUserIdentity(uid: 'tester', name: 'Tester'),
          repository: repository,
        ),
      ),
    ),
  );
  await tester.pump();
}

class _FakeCerdasRepository extends CerdasRepository {
  _FakeCerdasRepository(this.counts);

  final Map<CerdasContextKey, int?> counts;
  final Map<CerdasContextKey, StreamController<PigStatsRecord?>> _controllers =
      <CerdasContextKey, StreamController<PigStatsRecord?>>{};
  final Map<CerdasContextKey, int> watchPigStatsCalls =
      <CerdasContextKey, int>{};
  CerdasContextKey? lastWrittenKey;

  @override
  Stream<PigStatsRecord?> watchPigStatsForKey(CerdasContextKey key) {
    watchPigStatsCalls[key] = (watchPigStatsCalls[key] ?? 0) + 1;
    final StreamController<PigStatsRecord?> controller = _controllers
        .putIfAbsent(key, () => StreamController<PigStatsRecord?>.broadcast());
    Future<void>.microtask(() => _emit(key));
    return controller.stream;
  }

  @override
  Stream<List<PigMovementRecord>> watchPigMovementsForKey(
    CerdasContextKey key, {
    int limit = 10,
  }) {
    return const Stream<List<PigMovementRecord>>.empty();
  }

  @override
  Stream<List<PigExitReasonRecord>> watchPigExitReasons({
    required String tenantId,
    required String siteId,
  }) {
    return const Stream<List<PigExitReasonRecord>>.empty();
  }

  @override
  Future<void> addPigMovementForKey(
    CerdasContextKey key, {
    required String type,
    required DateTime date,
    required int quantity,
    String? reasonId,
    String? reasonName,
    required String userId,
    required String userName,
  }) async {
    lastWrittenKey = key;
    final int currentCount = counts[key] ?? 0;
    final int nextCount = type == 'in'
        ? currentCount + quantity
        : currentCount - quantity;
    if (nextCount < 0) {
      throw Exception('Stock insuficiente');
    }
    counts[key] = nextCount;
    _emit(key);
  }

  void _emit(CerdasContextKey key) {
    final StreamController<PigStatsRecord?>? controller = _controllers[key];
    if (controller == null || controller.isClosed) {
      return;
    }
    final int? count = counts[key];
    controller.add(
      count == null
          ? null
          : PigStatsRecord(
              currentCount: count,
              updatedAt: null,
              updatedBy: 'test',
            ),
    );
  }

  void dispose() {
    for (final StreamController<PigStatsRecord?> controller
        in _controllers.values) {
      controller.close();
    }
  }
}
