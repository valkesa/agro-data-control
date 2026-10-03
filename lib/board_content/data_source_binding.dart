import '../device_board_layouts/board_parsing.dart';

/// Etapa DataSourceBinding 1 — what a single Board item's
/// [MetricBoardContent] renders (`item.metricKey`, the semantic/render
/// identity) is deliberately kept separate from *where its value comes
/// from*. This is that "where": a real Tenant/Site/Device plus the metric
/// key to read on it.
///
/// Deliberately thin — no `sourceField`, no PLC address, no Modbus
/// register, no backend path. Those live on the technical ingestion side;
/// this binding only answers "qué métrica semántica de qué Device quiero
/// consumir", nothing about how that Device's backend produces it.
///
/// Lives only on the concrete, applied Board (inside a [MetricBoardContent]
/// item of a `DeviceBoardLayout`/[BoardContentLayout]) — never on a
/// BoardPreset, which stays reusable/generic across tenants by design.
/// `null` here is the normal, non-error state for any item that hasn't
/// been wired to a real source yet (including every item on a document
/// written before this stage — absence of `dataSource` in the persisted
/// map is not a legacy-document-shaped special case, it's just "no
/// binding").
///
/// [metricKey] here is intentionally a separate field from the owning
/// item's own `metricKey`, not a shared/derived value: they usually match,
/// but nothing in this stage forces that — an item could alias or override
/// which concrete metric it reads without changing what it semantically
/// renders as.
class DataSourceBinding {
  const DataSourceBinding({
    required this.tenantId,
    required this.siteId,
    required this.deviceId,
    required this.metricKey,
  });

  factory DataSourceBinding.fromMap(Map<String, Object?> map) {
    BoardParsing.fields(map, {'tenantId', 'siteId', 'deviceId', 'metricKey'});
    return DataSourceBinding(
      tenantId: BoardParsing.string(map['tenantId'], 'tenantId'),
      siteId: BoardParsing.string(map['siteId'], 'siteId'),
      deviceId: BoardParsing.string(map['deviceId'], 'deviceId'),
      metricKey: BoardParsing.string(map['metricKey'], 'metricKey'),
    );
  }

  final String tenantId;
  final String siteId;
  final String deviceId;
  final String metricKey;

  Map<String, Object?> toMap() => {
    'tenantId': tenantId,
    'siteId': siteId,
    'deviceId': deviceId,
    'metricKey': metricKey,
  };

  @override
  bool operator ==(Object other) =>
      other is DataSourceBinding &&
      other.tenantId == tenantId &&
      other.siteId == siteId &&
      other.deviceId == deviceId &&
      other.metricKey == metricKey;

  @override
  int get hashCode => Object.hash(tenantId, siteId, deviceId, metricKey);

  @override
  String toString() =>
      'DataSourceBinding($tenantId/$siteId/$deviceId · $metricKey)';
}
