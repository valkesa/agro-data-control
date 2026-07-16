import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'alert_models.dart';
import 'alert_priority.dart';
import 'whatsapp_alert_recipients.dart';
import 'whatsapp_service.dart';

const Duration defaultNotificationBatchWindow = Duration(seconds: 10);
const Duration defaultWhatsAppSendTimeout = Duration(seconds: 25);

class NotificationBatchKey {
  const NotificationBatchKey({
    required this.tenantId,
    required this.siteId,
    required this.roomId,
  });

  final String tenantId;
  final String siteId;
  final String roomId;

  @override
  bool operator ==(Object other) {
    return other is NotificationBatchKey &&
        other.tenantId == tenantId &&
        other.siteId == siteId &&
        other.roomId == roomId;
  }

  @override
  int get hashCode => Object.hash(tenantId, siteId, roomId);
}

enum PendingNotificationBatchState { open, closing, closed }

class PendingNotificationBatch {
  PendingNotificationBatch({
    required this.batchId,
    required this.key,
    required this.roomNumber,
    required this.muntersId,
    required this.plcLabel,
    required this.createdAt,
    required this.closesAt,
    required Map<AlertType, int> alertOrder,
  }) : alertOrder = Map<AlertType, int>.unmodifiable(alertOrder);

  final String batchId;
  final NotificationBatchKey key;
  final int? roomNumber;
  final String? muntersId;
  final String plcLabel;
  final DateTime createdAt;
  final DateTime closesAt;
  DateTime? closedAt;
  final Map<AlertType, int> alertOrder;
  final Map<AlertInstanceKey, EvaluatedAlert> _alerts =
      <AlertInstanceKey, EvaluatedAlert>{};
  PendingNotificationBatchState state = PendingNotificationBatchState.open;

  String get tenantId => key.tenantId;
  String get siteId => key.siteId;
  String get roomId => key.roomId;

  List<EvaluatedAlert> get alerts {
    final List<EvaluatedAlert> values = _alerts.values.toList(growable: false);
    values.sort(_compareAlerts);
    return List<EvaluatedAlert>.unmodifiable(values);
  }

  int get alertCount => _alerts.length;

  void add(EvaluatedAlert alert) {
    if (state != PendingNotificationBatchState.open) {
      return;
    }
    _alerts[alert.key] = alert;
  }

  void close(DateTime value) {
    closedAt = value.toUtc();
    state = PendingNotificationBatchState.closed;
  }

  int _compareAlerts(EvaluatedAlert a, EvaluatedAlert b) {
    final int orderA = alertOrder[a.type] ?? alertPriorityIndex(a.type) + 1;
    final int orderB = alertOrder[b.type] ?? alertPriorityIndex(b.type) + 1;
    final int orderComparison = orderA.compareTo(orderB);
    if (orderComparison != 0) {
      return orderComparison;
    }
    return alertPriorityIndex(a.type).compareTo(alertPriorityIndex(b.type));
  }
}

abstract class NotificationTimerHandle {
  void cancel();
}

abstract class NotificationBatchScheduler {
  NotificationTimerHandle schedule(Duration delay, void Function() callback);
}

class TimerNotificationBatchScheduler implements NotificationBatchScheduler {
  const TimerNotificationBatchScheduler();

  @override
  NotificationTimerHandle schedule(Duration delay, void Function() callback) {
    return _TimerNotificationHandle(Timer(delay, callback));
  }
}

class _TimerNotificationHandle implements NotificationTimerHandle {
  _TimerNotificationHandle(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

class NotificationBatchManager {
  NotificationBatchManager({
    required this.processor,
    NotificationBatchScheduler scheduler =
        const TimerNotificationBatchScheduler(),
    DateTime Function()? now,
    Duration window = defaultNotificationBatchWindow,
    String Function(DateTime now)? batchIdFactory,
  }) : _scheduler = scheduler,
       _now = now ?? DateTime.now,
       _window = window,
       _batchIdFactory = batchIdFactory ?? generateNotificationBatchId;

  final AlertNotificationProcessor processor;
  final NotificationBatchScheduler _scheduler;
  final DateTime Function() _now;
  final Duration _window;
  final String Function(DateTime now) _batchIdFactory;
  final Map<NotificationBatchKey, PendingNotificationBatch> _batches =
      <NotificationBatchKey, PendingNotificationBatch>{};
  final Map<NotificationBatchKey, NotificationTimerHandle> _timers =
      <NotificationBatchKey, NotificationTimerHandle>{};

  int get openBatchCount => _batches.length;

  int get totalAlertCountPending =>
      _batches.values.fold<int>(0, (int total, PendingNotificationBatch batch) {
        return total + batch.alertCount;
      });

  void addCandidates({
    required String tenantId,
    required String siteId,
    required String roomId,
    required int? roomNumber,
    required String? muntersId,
    String? plcLabel,
    required List<EvaluatedAlert> alerts,
    required Map<AlertType, int> alertOrder,
  }) {
    final List<EvaluatedAlert> candidates = alerts
        .where((EvaluatedAlert alert) => alert.sendWhatsapp)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return;
    }

    final NotificationBatchKey key = NotificationBatchKey(
      tenantId: tenantId,
      siteId: siteId,
      roomId: roomId,
    );
    PendingNotificationBatch? batch = _batches[key];
    if (batch == null || batch.state != PendingNotificationBatchState.open) {
      final DateTime createdAt = _now().toUtc();
      batch = PendingNotificationBatch(
        batchId: _batchIdFactory(createdAt),
        key: key,
        roomNumber: roomNumber,
        muntersId: muntersId,
        plcLabel: _notificationPlcLabel(
          plcLabel: plcLabel,
          roomNumber: roomNumber,
          roomId: roomId,
        ),
        createdAt: createdAt,
        closesAt: createdAt.add(_window),
        alertOrder: alertOrder,
      );
      _batches[key] = batch;
      _timers[key] = _scheduler.schedule(_window, () => flushBatch(key));
      _logNotification(
        'event=notification_batch_opened batchId=${batch.batchId} tenantId=$tenantId siteId=$siteId roomId=$roomId createdAt=${batch.createdAt.toIso8601String()} closesAt=${batch.closesAt.toIso8601String()}',
      );
    }

    for (final EvaluatedAlert alert in candidates) {
      batch.add(alert);
    }
  }

  Future<PendingNotificationBatch?> flushBatch(NotificationBatchKey key) async {
    final PendingNotificationBatch? batch = _batches[key];
    if (batch == null || batch.state != PendingNotificationBatchState.open) {
      return null;
    }
    batch.state = PendingNotificationBatchState.closing;
    _timers.remove(key)?.cancel();
    _batches.remove(key);
    final DateTime closedAt = _now().toUtc();
    batch.close(closedAt);
    _logNotification(
      'event=notification_batch_closed batchId=${batch.batchId} tenantId=${batch.tenantId} siteId=${batch.siteId} roomId=${batch.roomId} alertCount=${batch.alertCount} createdAt=${batch.createdAt.toIso8601String()} closedAt=${closedAt.toIso8601String()} windowDurationMs=${batch.closesAt.difference(batch.createdAt).inMilliseconds}',
    );
    try {
      unawaited(processor.process(batch));
      return batch;
    } catch (error) {
      _logNotification(
        'event=notification_batch_failed batchId=${batch.batchId} errorType=${error.runtimeType} errorMessage=${sanitizeLogValue(error.toString())}',
      );
      return null;
    }
  }

  Future<void> flushAll() async {
    final List<NotificationBatchKey> keys = _batches.keys.toList(
      growable: false,
    );
    for (final NotificationBatchKey key in keys) {
      await flushBatch(key);
    }
  }

  void clearAll() {
    for (final NotificationTimerHandle timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _batches.clear();
  }
}

String _notificationPlcLabel({
  required String? plcLabel,
  required int? roomNumber,
  required String roomId,
}) {
  final String normalized = plcLabel?.trim() ?? '';
  if (normalized.isNotEmpty) {
    return normalized;
  }
  if (roomNumber != null) {
    return 'Sala $roomNumber';
  }
  return roomId;
}

class AlertNotificationFormatter {
  const AlertNotificationFormatter();

  String format(EvaluatedAlert alert) {
    return switch (alert.type) {
      AlertType.muntersDoorOpen => 'Puerta Munters abierta',
      AlertType.roomDoorOpen => 'Puerta de sala abierta',
      AlertType.temperatureInterior =>
        alert.thresholdKind == AlertThresholdKind.minimum
            ? 'Temperatura interior: ${_value(alert.measuredValue)} C (min: ${_value(alert.thresholdValue)} C)'
            : 'Temperatura interior: ${_value(alert.measuredValue)} C (max: ${_value(alert.thresholdValue)} C)',
      AlertType.highTemperatureHeatingActive =>
        'Temperatura interior: ${_value(alert.measuredValue)} C (max: ${_value(alert.thresholdValue)} C)',
      AlertType.lowTemperatureHumidifierActive =>
        'Temperatura interior: ${_value(alert.measuredValue)} C (min: ${_value(alert.thresholdValue)} C)',
      AlertType.highDifferentialPressure =>
        'Presion diferencial: ${_value(alert.measuredValue)} Pa (max: ${_value(alert.thresholdValue)} Pa)',
      AlertType.highHumidity =>
        'Humedad interior: ${_value(alert.measuredValue)} % (max: ${_value(alert.thresholdValue)} %)',
      AlertType.dewPointRisk =>
        'Margen al punto de rocio: ${_value(alert.measuredValue)} C (min: ${_value(alert.thresholdValue)} C)',
    };
  }

  String _value(num? value) {
    if (value == null || !value.isFinite) {
      return 'sin dato';
    }
    final double rounded = (value.toDouble() * 10).roundToDouble() / 10;
    if (rounded == rounded.truncateToDouble()) {
      return rounded.toInt().toString();
    }
    return rounded.toStringAsFixed(1).replaceAll('.', ',');
  }
}

class WhatsAppTemplateMessage {
  const WhatsAppTemplateMessage({
    required this.templateName,
    required this.languageCode,
    required this.bodyParameters,
    required this.partIndex,
    required this.partCount,
  });

  final String templateName;
  final String languageCode;
  final List<String> bodyParameters;
  final int partIndex;
  final int partCount;
}

class BuiltNotificationBatch {
  const BuiltNotificationBatch({
    required this.batchId,
    required this.key,
    required this.messages,
    required this.alertCount,
    required this.createdAt,
    required this.closedAt,
  });

  final String batchId;
  final NotificationBatchKey key;
  final List<WhatsAppTemplateMessage> messages;
  final int alertCount;
  final DateTime createdAt;
  final DateTime closedAt;

  String get templateName =>
      messages.isEmpty ? '' : messages.first.templateName;

  String get languageCode =>
      messages.isEmpty ? '' : messages.first.languageCode;
}

class NotificationBatchBuilder {
  const NotificationBatchBuilder({
    this.templateBuilder = const WhatsAppTemplateBuilder(),
  });

  final WhatsAppTemplateBuilder templateBuilder;

  BuiltNotificationBatch build({
    required PendingNotificationBatch batch,
    required String clientName,
    required String siteName,
  }) {
    final DateTime? closedAt = batch.closedAt;
    if (closedAt == null ||
        batch.state != PendingNotificationBatchState.closed) {
      throw StateError('Notification batch must be closed before building');
    }
    final List<WhatsAppTemplateMessage> messages = templateBuilder.build(
      batch: batch,
      clientName: clientName,
      siteName: siteName,
    );
    return BuiltNotificationBatch(
      batchId: batch.batchId,
      key: batch.key,
      messages: List<WhatsAppTemplateMessage>.unmodifiable(messages),
      alertCount: batch.alertCount,
      createdAt: batch.createdAt,
      closedAt: closedAt,
    );
  }
}

class WhatsAppTemplateBuilder {
  const WhatsAppTemplateBuilder({
    this.singleTemplateName = 'alerts_single_c',
    this.multipleTemplateName = 'alerts_multiple_c',
    this.singleLanguageCode = WhatsAppService.defaultTemplateLanguageCode,
    this.multipleLanguageCode = WhatsAppService.defaultTemplateLanguageCode,
    this.parameterMaxLength = 1024,
    this.formatter = const AlertNotificationFormatter(),
  });

  final String singleTemplateName;
  final String multipleTemplateName;
  final String singleLanguageCode;
  final String multipleLanguageCode;
  final int parameterMaxLength;
  final AlertNotificationFormatter formatter;

  factory WhatsAppTemplateBuilder.fromEnvironment({
    Map<String, String>? environment,
    AlertNotificationFormatter formatter = const AlertNotificationFormatter(),
  }) {
    final Map<String, String> env = environment ?? Platform.environment;
    return WhatsAppTemplateBuilder(
      singleTemplateName: _envValue(
        env,
        'WHATSAPP_ALERT_SINGLE_TEMPLATE_NAME',
        'alerts_single_c',
      ),
      multipleTemplateName: _envValue(
        env,
        'WHATSAPP_ALERT_MULTIPLE_TEMPLATE_NAME',
        'alerts_multiple_c',
      ),
      singleLanguageCode: _envValue(
        env,
        'WHATSAPP_ALERT_SINGLE_TEMPLATE_LANGUAGE',
        WhatsAppService.defaultTemplateLanguageCode,
      ),
      multipleLanguageCode: _envValue(
        env,
        'WHATSAPP_ALERT_MULTIPLE_TEMPLATE_LANGUAGE',
        WhatsAppService.defaultTemplateLanguageCode,
      ),
      parameterMaxLength: _envInt(
        env,
        'WHATSAPP_ALERT_TEMPLATE_PARAMETER_MAX_LENGTH',
        1024,
      ),
      formatter: formatter,
    );
  }

  List<WhatsAppTemplateMessage> build({
    required PendingNotificationBatch batch,
    required String clientName,
    required String siteName,
  }) {
    final String clientSitePlc = '$clientName | $siteName | ${batch.plcLabel}';
    final List<String> alertTexts = batch.alerts
        .map(formatter.format)
        .toList(growable: false);
    if (alertTexts.isEmpty) {
      return const <WhatsAppTemplateMessage>[];
    }
    final List<List<String>> chunks = _chunkAlerts(
      clientSitePlc: clientSitePlc,
      alertTexts: alertTexts,
    );
    return <WhatsAppTemplateMessage>[
      for (int i = 0; i < chunks.length; i += 1)
        _buildPart(
          clientSitePlc: clientSitePlc,
          alertTexts: chunks[i],
          partIndex: i + 1,
          partCount: chunks.length,
        ),
    ];
  }

  WhatsAppTemplateMessage _buildPart({
    required String clientSitePlc,
    required List<String> alertTexts,
    required int partIndex,
    required int partCount,
  }) {
    if (alertTexts.length == 1) {
      final List<String> params = <String>[clientSitePlc, alertTexts[0]];
      _validateParameters(params);
      return WhatsAppTemplateMessage(
        templateName: singleTemplateName,
        languageCode: singleLanguageCode,
        bodyParameters: params,
        partIndex: partIndex,
        partCount: partCount,
      );
    }
    final List<String> lines = distributeAlertLines(alertTexts);
    final List<String> params = <String>[clientSitePlc, ...lines];
    _validateParameters(params);
    return WhatsAppTemplateMessage(
      templateName: multipleTemplateName,
      languageCode: multipleLanguageCode,
      bodyParameters: params,
      partIndex: partIndex,
      partCount: partCount,
    );
  }

  List<List<String>> _chunkAlerts({
    required String clientSitePlc,
    required List<String> alertTexts,
  }) {
    final List<List<String>> chunks = <List<String>>[];
    List<String> current = <String>[];
    for (final String alertText in alertTexts) {
      final List<String> candidate = <String>[...current, alertText];
      final List<String> candidateParameters = _parametersFor(
        clientSitePlc: clientSitePlc,
        alertTexts: candidate,
      );
      if (current.isNotEmpty &&
          candidateParameters.any(
            (String value) => value.length > parameterMaxLength,
          )) {
        chunks.add(current);
        current = <String>[alertText];
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) {
      chunks.add(current);
    }
    return chunks;
  }

  List<String> _parametersFor({
    required String clientSitePlc,
    required List<String> alertTexts,
  }) {
    if (alertTexts.length == 1) {
      return <String>[clientSitePlc, alertTexts[0]];
    }
    return <String>[clientSitePlc, ...distributeAlertLines(alertTexts)];
  }

  void _validateParameters(List<String> parameters) {
    for (final String parameter in parameters) {
      if (parameter.length > parameterMaxLength) {
        throw StateError('WhatsApp template parameter exceeds max length');
      }
    }
  }
}

String _envValue(
  Map<String, String> environment,
  String name,
  String defaultValue,
) {
  final String value = environment[name]?.trim() ?? '';
  return value.isEmpty ? defaultValue : value;
}

int _envInt(Map<String, String> environment, String name, int defaultValue) {
  final String value = environment[name]?.trim() ?? '';
  if (value.isEmpty) {
    return defaultValue;
  }
  return int.tryParse(value) ?? defaultValue;
}

List<String> distributeAlertLines(List<String> alerts) {
  if (alerts.length < 2) {
    throw ArgumentError.value(alerts.length, 'alerts.length', 'Must be >= 2');
  }
  final int lineCount = 2;
  final int base = alerts.length ~/ lineCount;
  int remainder = alerts.length % lineCount;
  int index = 0;
  final List<String> lines = <String>[];
  for (int line = 0; line < lineCount; line += 1) {
    final int take = base + (remainder > 0 ? 1 : 0);
    if (remainder > 0) {
      remainder -= 1;
    }
    if (take == 0) {
      lines.add('-');
      continue;
    }
    lines.add(alerts.skip(index).take(take).join(' - '));
    index += take;
  }
  return lines;
}

class AlertNotificationSender {
  AlertNotificationSender({
    required this.whatsAppService,
    this.sendTimeout = defaultWhatsAppSendTimeout,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final WhatsAppService whatsAppService;
  final Duration sendTimeout;
  final DateTime Function() _now;

  Future<NotificationBatchSendResult> send({
    required BuiltNotificationBatch builtBatch,
    required List<AlertRecipient> recipients,
  }) async {
    final List<AlertRecipient> deduplicatedRecipients =
        deduplicateAlertRecipients(recipients);
    final DateTime sendStartedAt = _now().toUtc();
    final List<NotificationRecipientSendResult> results =
        <NotificationRecipientSendResult>[];
    _logNotification(
      'event=notification_batch_send_started batchId=${builtBatch.batchId} templateName=${builtBatch.templateName} recipientCount=${deduplicatedRecipients.length} sendStartedAt=${sendStartedAt.toIso8601String()}',
    );
    for (final AlertRecipient recipient in deduplicatedRecipients) {
      for (final WhatsAppTemplateMessage message in builtBatch.messages) {
        final DateTime recipientStartedAt = _now().toUtc();
        try {
          final WhatsAppSendResult result = await whatsAppService
              .sendTemplateMessage(
                tenantId: builtBatch.key.tenantId,
                to: recipient.phone,
                templateName: message.templateName,
                languageCode: message.languageCode,
                bodyParameters: message.bodyParameters,
              )
              .timeout(sendTimeout);
          final DateTime recipientFinishedAt = _now().toUtc();
          results.add(
            NotificationRecipientSendResult(
              phoneMasked: maskWhatsAppPhone(recipient.phone),
              success: true,
              messageId: result.messageId,
              statusCode: result.metaStatusCode,
              startedAt: recipientStartedAt,
              finishedAt: recipientFinishedAt,
            ),
          );
        } on TimeoutException {
          final DateTime recipientFinishedAt = _now().toUtc();
          _logNotification(
            'event=notification_recipient_timeout batchId=${builtBatch.batchId} phoneMasked=${maskWhatsAppPhone(recipient.phone)} timeoutMs=${sendTimeout.inMilliseconds}',
          );
          results.add(
            NotificationRecipientSendResult(
              phoneMasked: maskWhatsAppPhone(recipient.phone),
              success: false,
              errorType: NotificationSendErrorType.timeout.name,
              errorMessage: 'WhatsApp send timeout',
              startedAt: recipientStartedAt,
              finishedAt: recipientFinishedAt,
            ),
          );
        } on WhatsAppServiceException catch (error) {
          final DateTime recipientFinishedAt = _now().toUtc();
          final String errorType = classifyWhatsAppException(error).name;
          _logNotification(
            'event=notification_recipient_failed batchId=${builtBatch.batchId} phoneMasked=${maskWhatsAppPhone(recipient.phone)} errorType=$errorType durationMs=${recipientFinishedAt.difference(recipientStartedAt).inMilliseconds}',
          );
          results.add(
            NotificationRecipientSendResult(
              phoneMasked: maskWhatsAppPhone(recipient.phone),
              success: false,
              statusCode: error.metaStatusCode ?? error.statusCode,
              errorType: errorType,
              errorMessage: sanitizeLogValue(
                error.metaErrorMessage ?? error.message,
              ),
              startedAt: recipientStartedAt,
              finishedAt: recipientFinishedAt,
            ),
          );
        } catch (error) {
          final DateTime recipientFinishedAt = _now().toUtc();
          _logNotification(
            'event=notification_recipient_failed batchId=${builtBatch.batchId} phoneMasked=${maskWhatsAppPhone(recipient.phone)} errorType=${NotificationSendErrorType.unknownError.name} durationMs=${recipientFinishedAt.difference(recipientStartedAt).inMilliseconds}',
          );
          results.add(
            NotificationRecipientSendResult(
              phoneMasked: maskWhatsAppPhone(recipient.phone),
              success: false,
              errorType: NotificationSendErrorType.unknownError.name,
              errorMessage: sanitizeLogValue(error.toString()),
              startedAt: recipientStartedAt,
              finishedAt: recipientFinishedAt,
            ),
          );
        }
      }
    }
    final DateTime sentAt = _now().toUtc();
    final int successCount = results.where((r) => r.success).length;
    final int failedCount = results.length - successCount;
    _logNotification(
      'event=notification_batch_sent batchId=${builtBatch.batchId} successCount=$successCount failedCount=$failedCount sendStartedAt=${sendStartedAt.toIso8601String()} sentAt=${sentAt.toIso8601String()} durationMs=${sentAt.difference(sendStartedAt).inMilliseconds}',
    );
    return NotificationBatchSendResult(
      batchId: builtBatch.batchId,
      templateName: builtBatch.templateName,
      recipientCount: deduplicatedRecipients.length,
      successCount: successCount,
      failedCount: failedCount,
      results: List<NotificationRecipientSendResult>.unmodifiable(results),
      sendStartedAt: sendStartedAt,
      sentAt: sentAt,
    );
  }
}

class AlertNotificationProcessor {
  AlertNotificationProcessor({
    required this.recipientsConfig,
    required this.sender,
    required this.clientName,
    required this.siteName,
    this.builder = const NotificationBatchBuilder(),
  });

  final WhatsAppAlertRecipientsConfig recipientsConfig;
  final AlertNotificationSender sender;
  final String clientName;
  final String siteName;
  final NotificationBatchBuilder builder;

  Future<NotificationBatchSendResult> process(
    PendingNotificationBatch batch,
  ) async {
    final List<AlertRecipient> recipients = recipientsConfig.recipientsFor(
      tenantId: batch.tenantId,
      siteId: batch.siteId,
    );
    if (recipients.isEmpty) {
      _logNotification(
        'event=notification_batch_skipped batchId=${batch.batchId} reason=no_recipients',
      );
      final DateTime now = DateTime.now().toUtc();
      return NotificationBatchSendResult(
        batchId: batch.batchId,
        templateName: '',
        recipientCount: 0,
        successCount: 0,
        failedCount: 0,
        results: const <NotificationRecipientSendResult>[],
        sendStartedAt: now,
        sentAt: now,
      );
    }
    final BuiltNotificationBatch builtBatch = builder.build(
      batch: batch,
      clientName: clientName,
      siteName: siteName,
    );
    return sender.send(builtBatch: builtBatch, recipients: recipients);
  }
}

class NotificationBatchSendResult {
  const NotificationBatchSendResult({
    required this.batchId,
    required this.templateName,
    required this.recipientCount,
    required this.successCount,
    required this.failedCount,
    required this.results,
    required this.sendStartedAt,
    required this.sentAt,
  });

  final String batchId;
  final String templateName;
  final int recipientCount;
  final int successCount;
  final int failedCount;
  final List<NotificationRecipientSendResult> results;
  final DateTime sendStartedAt;
  final DateTime sentAt;

  int get durationMs => sentAt.difference(sendStartedAt).inMilliseconds;
}

class NotificationRecipientSendResult {
  const NotificationRecipientSendResult({
    required this.phoneMasked,
    required this.success,
    required this.startedAt,
    required this.finishedAt,
    this.messageId,
    this.statusCode,
    this.errorType,
    this.errorMessage,
  });

  final String phoneMasked;
  final bool success;
  final DateTime startedAt;
  final DateTime finishedAt;
  final String? messageId;
  final int? statusCode;
  final String? errorType;
  final String? errorMessage;

  int get durationMs => finishedAt.difference(startedAt).inMilliseconds;
}

enum NotificationSendErrorType {
  timeout,
  networkError,
  metaHttpError,
  invalidTemplate,
  invalidRecipient,
  unknownError,
}

NotificationSendErrorType classifyWhatsAppException(
  WhatsAppServiceException error,
) {
  return switch (error.kind) {
    WhatsAppErrorKind.timeout => NotificationSendErrorType.timeout,
    WhatsAppErrorKind.http => NotificationSendErrorType.metaHttpError,
    WhatsAppErrorKind.invalidResponse => NotificationSendErrorType.unknownError,
    WhatsAppErrorKind.unexpected => NotificationSendErrorType.unknownError,
  };
}

String generateNotificationBatchId(DateTime now) {
  final DateTime utc = now.toUtc();
  final String date =
      '${utc.year.toString().padLeft(4, '0')}${utc.month.toString().padLeft(2, '0')}${utc.day.toString().padLeft(2, '0')}';
  final String time =
      '${utc.hour.toString().padLeft(2, '0')}${utc.minute.toString().padLeft(2, '0')}${utc.second.toString().padLeft(2, '0')}';
  final int random = Random.secure().nextInt(0x10000);
  return 'NTF-$date-$time-${random.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}

String sanitizeLogValue(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

void _logNotification(String message) {
  stdout.writeln('[notifications] $message');
}
