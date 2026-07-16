import 'dart:async';

import 'package:agro_data_control_backend/src/alert_models.dart';
import 'package:agro_data_control_backend/src/alert_notifications.dart';
import 'package:agro_data_control_backend/src/alert_priority.dart';
import 'package:agro_data_control_backend/src/whatsapp_alert_recipients.dart';
import 'package:agro_data_control_backend/src/whatsapp_service.dart';

Future<void> main() async {
  _testFormatter();
  _testTemplateDistribution();
  _testTemplateBuilderSingleAndMultiple();
  _testTemplateBuilderFromEnvironment();
  await _testBatching();
  await _testSender();
}

void _testFormatter() {
  const AlertNotificationFormatter formatter = AlertNotificationFormatter();
  _expect(
    formatter.format(
          _alert(
            AlertType.highTemperatureHeatingActive,
            measured: 32.34,
            threshold: 30,
          ),
        ) ==
        'Temperatura interior: 32,3 C (max: 30 C)',
    'formats temperature with comma decimal',
  );
  _expect(
    formatter.format(
          _alert(AlertType.dewPointRisk, measured: 0.84, threshold: 1),
        ) ==
        'Margen al punto de rocio: 0,8 C (min: 1 C)',
    'formats dew point margin',
  );
  _expect(
    formatter.format(_alert(AlertType.muntersDoorOpen)) ==
        'Puerta Munters abierta',
    'formats munters door',
  );
}

void _testTemplateDistribution() {
  _expect(distributeAlertLines(_alerts(2)).join('|') == 'A1|A2', '2 alerts');
  _expect(
    distributeAlertLines(_alerts(3)).join('|') == 'A1 - A2|A3',
    '3 alerts',
  );
  _expect(
    distributeAlertLines(_alerts(4)).join('|') == 'A1 - A2|A3 - A4',
    '4 alerts',
  );
  _expect(
    distributeAlertLines(_alerts(5)).join('|') == 'A1 - A2 - A3|A4 - A5',
    '5 alerts',
  );
  _expect(
    distributeAlertLines(_alerts(6)).join('|') == 'A1 - A2 - A3|A4 - A5 - A6',
    '6 alerts',
  );
}

void _testTemplateBuilderSingleAndMultiple() {
  const WhatsAppTemplateBuilder builder = WhatsAppTemplateBuilder();
  final AlertRecipient recipient = _recipient();
  final PendingNotificationBatch single = _batch(
    alerts: <EvaluatedAlert>[
      _alert(
        AlertType.highTemperatureHeatingActive,
        measured: 31,
        threshold: 30,
      ),
    ],
  );
  final WhatsAppTemplateMessage singleMessage = builder
      .build(
        batch: single,
        clientName: recipient.displayClientName,
        siteName: recipient.displaySiteName,
      )
      .single;
  _expect(
    singleMessage.templateName == 'alerts_single_c',
    'single template name',
  );
  _expect(singleMessage.languageCode == 'es_AR', 'single language code');
  _expect(
    singleMessage.bodyParameters.length == 2 &&
        singleMessage.bodyParameters[0] ==
            'The Good Pig | Sitio principal | Sala 1' &&
        singleMessage.bodyParameters[1] ==
            'Temperatura interior: 31 C (max: 30 C)',
    'single variables',
  );

  final PendingNotificationBatch multiple = _batch(
    alerts: <EvaluatedAlert>[
      _alert(AlertType.highHumidity, measured: 98, threshold: 95),
      _alert(AlertType.highDifferentialPressure, measured: 280, threshold: 250),
    ],
  );
  final WhatsAppTemplateMessage multipleMessage = builder
      .build(
        batch: multiple,
        clientName: recipient.displayClientName,
        siteName: recipient.displaySiteName,
      )
      .single;
  _expect(
    multipleMessage.templateName == 'alerts_multiple_c',
    'multiple template name',
  );
  _expect(multipleMessage.bodyParameters.length == 3, 'multiple variables');
  _expect(
    multipleMessage.bodyParameters[0] ==
        'The Good Pig | Sitio principal | Sala 1',
    'multiple context variable',
  );
  _expect(
    multipleMessage.bodyParameters[1] ==
            'Presion diferencial: 280 Pa (max: 250 Pa)' &&
        multipleMessage.bodyParameters[2] ==
            'Humedad interior: 98 % (max: 95 %)',
    'multiple alert variables',
  );
}

void _testTemplateBuilderFromEnvironment() {
  final WhatsAppTemplateBuilder builder =
      WhatsAppTemplateBuilder.fromEnvironment(
        environment: const <String, String>{
          'WHATSAPP_ALERT_SINGLE_TEMPLATE_NAME': 'custom_single',
          'WHATSAPP_ALERT_MULTIPLE_TEMPLATE_NAME': 'custom_multiple',
          'WHATSAPP_ALERT_SINGLE_TEMPLATE_LANGUAGE': 'es',
          'WHATSAPP_ALERT_MULTIPLE_TEMPLATE_LANGUAGE': 'es_419',
        },
      );
  final AlertRecipient recipient = _recipient();
  final WhatsAppTemplateMessage singleMessage = builder
      .build(
        batch: _batch(
          alerts: <EvaluatedAlert>[_alert(AlertType.muntersDoorOpen)],
        ),
        clientName: recipient.displayClientName,
        siteName: recipient.displaySiteName,
      )
      .single;
  _expect(singleMessage.templateName == 'custom_single', 'env single template');
  _expect(singleMessage.languageCode == 'es', 'env single language');

  final WhatsAppTemplateMessage multipleMessage = builder
      .build(
        batch: _batch(
          alerts: <EvaluatedAlert>[
            _alert(AlertType.muntersDoorOpen),
            _alert(AlertType.roomDoorOpen),
          ],
        ),
        clientName: recipient.displayClientName,
        siteName: recipient.displaySiteName,
      )
      .single;
  _expect(
    multipleMessage.templateName == 'custom_multiple',
    'env multiple template',
  );
  _expect(multipleMessage.languageCode == 'es_419', 'env multiple language');
}

Future<void> _testBatching() async {
  final _FakeScheduler scheduler = _FakeScheduler();
  final _FakeNotificationProcessor processor = _FakeNotificationProcessor();
  final NotificationBatchManager manager = NotificationBatchManager(
    processor: processor,
    scheduler: scheduler,
    now: () => DateTime.utc(2026, 7, 12, 9),
    batchIdFactory: (_) => 'NTF-20260712-090000-TEST',
  );

  manager.addCandidates(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    roomNumber: 1,
    muntersId: 'munters1',
    alerts: <EvaluatedAlert>[_alert(AlertType.muntersDoorOpen)],
    alertOrder: _order(),
  );
  _expect(manager.openBatchCount == 1, 'first activated opens batch');
  _expect(scheduler.handles.length == 1, 'one timer created');

  manager.addCandidates(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_1',
    roomNumber: 1,
    muntersId: 'munters1',
    alerts: <EvaluatedAlert>[
      _alert(
        AlertType.highTemperatureHeatingActive,
        measured: 31,
        threshold: 30,
      ),
      _alert(
        AlertType.highTemperatureHeatingActive,
        measured: 31,
        threshold: 30,
      ),
    ],
    alertOrder: _order(),
  );
  _expect(scheduler.handles.length == 1, 'timer does not restart');
  _expect(manager.totalAlertCountPending == 2, 'deduplicates repeated alert');

  scheduler.handles.single.fire();
  await Future<void>.delayed(Duration.zero);
  _expect(manager.openBatchCount == 0, 'batch closes');
  _expect(processor.processed.length == 1, 'batch processed once');
  scheduler.handles.single.fire();
  await Future<void>.delayed(Duration.zero);
  _expect(
    processor.processed.length == 1,
    'double callback does not process twice',
  );

  manager.addCandidates(
    tenantId: 'tenant-a',
    siteId: 'site-a',
    roomId: 'room_2',
    roomNumber: 2,
    muntersId: 'munters2',
    alerts: <EvaluatedAlert>[_alert(AlertType.roomDoorOpen, roomId: 'room_2')],
    alertOrder: _order(),
  );
  manager.addCandidates(
    tenantId: 'tenant-a',
    siteId: 'site-b',
    roomId: 'room_2',
    roomNumber: 2,
    muntersId: 'munters2',
    alerts: <EvaluatedAlert>[
      _alert(AlertType.roomDoorOpen, siteId: 'site-b', roomId: 'room_2'),
    ],
    alertOrder: _order(),
  );
  _expect(manager.openBatchCount == 2, 'sites create independent batches');
  manager.clearAll();
  _expect(manager.openBatchCount == 0, 'clearAll clears batches');
  _expect(
    scheduler.handles
            .where((_FakeTimerHandle handle) => handle.cancelled)
            .length >=
        2,
    'clearAll cancels timers',
  );
}

Future<void> _testSender() async {
  final _FakeWhatsAppService whatsApp = _FakeWhatsAppService();
  final AlertNotificationProcessor processor = AlertNotificationProcessor(
    recipientsConfig: const WhatsAppAlertRecipientsConfig(),
    sender: AlertNotificationSender(whatsAppService: whatsApp),
    clientName: 'The Good Pig',
    siteName: 'Sitio principal',
  );
  final PendingNotificationBatch batch = _batch(
    tenantId: 'the_good_pig',
    siteId: 'main_site',
    alerts: <EvaluatedAlert>[_alert(AlertType.muntersDoorOpen)],
  )..close(DateTime.utc(2026, 7, 12, 9, 0, 10));
  final NotificationBatchSendResult result = await processor.process(batch);
  _expect(result.successCount == 2, 'configured recipients succeed');
  _expect(
    whatsApp.calls.first.templateName == 'alerts_single_c',
    'sender uses single template',
  );
  _expect(whatsApp.calls.first.languageCode == 'es_AR', 'sender uses es_AR');

  final PendingNotificationBatch globalOnlyBatch = _batch(
    tenantId: 'missing',
    siteId: 'missing',
    alerts: <EvaluatedAlert>[_alert(AlertType.muntersDoorOpen)],
  )..close(DateTime.utc(2026, 7, 12, 9, 0, 10));
  final NotificationBatchSendResult globalOnly = await processor.process(
    globalOnlyBatch,
  );
  _expect(globalOnly.recipientCount == 2, 'global recipients handle any site');
  _expect(
    whatsApp.calls.length == 4,
    'global-only batch sends one additional message per global recipient',
  );

  final _FakeWhatsAppService timeoutWhatsApp = _FakeWhatsAppService(
    neverComplete: true,
  );
  final AlertNotificationProcessor timeoutProcessor =
      AlertNotificationProcessor(
        recipientsConfig: const WhatsAppAlertRecipientsConfig(),
        sender: AlertNotificationSender(
          whatsAppService: timeoutWhatsApp,
          sendTimeout: Duration.zero,
        ),
        clientName: 'The Good Pig',
        siteName: 'Sitio principal',
      );
  final PendingNotificationBatch timeoutBatch = _batch(
    tenantId: 'the_good_pig',
    siteId: 'main_site',
    alerts: <EvaluatedAlert>[_alert(AlertType.muntersDoorOpen)],
  )..close(DateTime.utc(2026, 7, 12, 9, 0, 10));
  final NotificationBatchSendResult timeoutResult = await timeoutProcessor
      .process(timeoutBatch);
  _expect(timeoutResult.failedCount == 2, 'timeout fails recipients');
  _expect(
    timeoutResult.results.every(
      (NotificationRecipientSendResult result) =>
          result.errorType == NotificationSendErrorType.timeout.name,
    ),
    'timeout classified',
  );
}

List<String> _alerts(int count) {
  return <String>[for (int i = 1; i <= count; i += 1) 'A$i'];
}

PendingNotificationBatch _batch({
  String tenantId = 'tenant-a',
  String siteId = 'site-a',
  List<EvaluatedAlert>? alerts,
}) {
  final PendingNotificationBatch batch = PendingNotificationBatch(
    batchId: 'NTF-20260712-090000-TEST',
    key: NotificationBatchKey(
      tenantId: tenantId,
      siteId: siteId,
      roomId: 'room_1',
    ),
    roomNumber: 1,
    muntersId: 'munters1',
    plcLabel: 'Sala 1',
    createdAt: DateTime.utc(2026, 7, 12, 9),
    closesAt: DateTime.utc(2026, 7, 12, 9, 0, 10),
    alertOrder: _order(),
  );
  for (final EvaluatedAlert alert in alerts ?? <EvaluatedAlert>[]) {
    batch.add(alert);
  }
  return batch;
}

EvaluatedAlert _alert(
  AlertType type, {
  String tenantId = 'tenant-a',
  String siteId = 'site-a',
  String roomId = 'room_1',
  num? measured,
  num? threshold,
}) {
  return EvaluatedAlert(
    key: AlertInstanceKey(
      tenantId: tenantId,
      siteId: siteId,
      roomId: roomId,
      roomNumber: 1,
      muntersId: 'munters1',
      alertType: type,
    ),
    type: type,
    isActive: true,
    sendWhatsapp: true,
    measuredValue: measured,
    thresholdValue: threshold,
    thresholdKind: AlertThresholdKind.maximum,
    unit: '',
    evaluatedAt: DateTime.utc(2026, 7, 12, 9),
  );
}

Map<AlertType, int> _order() {
  return <AlertType, int>{
    for (final AlertType type in alertPriorityOrder)
      type: alertPriorityIndex(type) + 1,
  };
}

AlertRecipient _recipient() {
  return const AlertRecipient(
    scope: AlertRecipientScope.tenantSite,
    tenantId: 'the_good_pig',
    siteId: 'main_site',
    clientName: 'The Good Pig',
    siteName: 'Sitio principal',
    contactName: 'Gerardo',
    phone: '5491138267368',
  );
}

class _FakeScheduler implements NotificationBatchScheduler {
  final List<_FakeTimerHandle> handles = <_FakeTimerHandle>[];

  @override
  NotificationTimerHandle schedule(Duration delay, void Function() callback) {
    final _FakeTimerHandle handle = _FakeTimerHandle(callback);
    handles.add(handle);
    return handle;
  }
}

class _FakeTimerHandle implements NotificationTimerHandle {
  _FakeTimerHandle(this.callback);

  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (!cancelled) {
      callback();
    }
  }

  @override
  void cancel() {
    cancelled = true;
  }
}

class _FakeNotificationProcessor extends AlertNotificationProcessor {
  _FakeNotificationProcessor()
    : super(
        recipientsConfig: const WhatsAppAlertRecipientsConfig(),
        sender: AlertNotificationSender(
          whatsAppService: _FakeWhatsAppService(),
        ),
        clientName: 'The Good Pig',
        siteName: 'Sitio principal',
      );

  final List<PendingNotificationBatch> processed = <PendingNotificationBatch>[];

  @override
  Future<NotificationBatchSendResult> process(
    PendingNotificationBatch batch,
  ) async {
    processed.add(batch);
    return NotificationBatchSendResult(
      batchId: batch.batchId,
      templateName: 'test',
      recipientCount: 1,
      successCount: 1,
      failedCount: 0,
      results: <NotificationRecipientSendResult>[
        NotificationRecipientSendResult(
          phoneMasked: '********7368',
          success: true,
          startedAt: batch.closedAt ?? batch.createdAt,
          finishedAt: batch.closedAt ?? batch.closesAt,
        ),
      ],
      sendStartedAt: batch.closedAt ?? batch.createdAt,
      sentAt: batch.closedAt ?? batch.closesAt,
    );
  }
}

class _FakeWhatsAppService extends WhatsAppService {
  _FakeWhatsAppService({this.neverComplete = false})
    : super(environment: const <String, String>{});

  final bool neverComplete;

  final List<_WhatsAppCall> calls = <_WhatsAppCall>[];

  @override
  Future<WhatsAppSendResult> sendTemplateMessage({
    required String tenantId,
    required String to,
    String? message,
    String? templateName,
    String? languageCode,
    List<String>? bodyParameters,
  }) async {
    if (neverComplete) {
      return Completer<WhatsAppSendResult>().future;
    }
    calls.add(
      _WhatsAppCall(
        templateName: templateName ?? '',
        languageCode: languageCode ?? '',
        bodyParameters: bodyParameters ?? const <String>[],
      ),
    );
    return WhatsAppSendResult(
      messageId: 'wamid.test',
      raw: const <String, Object?>{},
      mode: 'template',
      fallbackUsed: false,
      metaStatusCode: 200,
      templateName: templateName,
      languageCode: languageCode,
    );
  }
}

class _WhatsAppCall {
  const _WhatsAppCall({
    required this.templateName,
    required this.languageCode,
    required this.bodyParameters,
  });

  final String templateName;
  final String languageCode;
  final List<String> bodyParameters;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Failed expectation: $description');
  }
}
