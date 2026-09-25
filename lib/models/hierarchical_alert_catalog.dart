// Etapa B5 — catálogo de alertas jerárquicas.
//
// Este archivo es una réplica deliberada, campo por campo, de
// `backend/lib/src/alert_configuration_contracts.dart` (Etapa B2) y de
// `backend/lib/src/alert_priority.dart` (`AlertMetadataRegistry`, fuente
// real de `order`). El paquete Flutter (`agro_data_control`) y el paquete
// backend (`agro_data_control_backend`) son paquetes pub independientes —
// el backend no declara `flutter` como SDK y el frontend no depende del
// paquete del backend — así que no hay forma de importar los contratos
// reales sin acoplar un cliente Flutter a un paquete de servidor con
// dependencias de Modbus/JWT. Ver Etapa B5 informe, sección "Duplicación de
// contratos" para la decisión completa.
//
// Mantenimiento (Etapa B5.1 §11): si el backend agrega/quita una alerta, o
// cambia `order`/`scopeCapability`/`supportsWhatsappDelay`/thresholds para
// alguna, este archivo debe actualizarse a mano en el mismo cambio — no hay
// forma automática de detectar el drift sin acoplar los paquetes. El test
// `hierarchical_alert_catalog_test.dart` fija los 9 `order` esperados
// explícitamente por número (no por posición de lista), así que un drift
// futuro entre este archivo y `AlertMetadataRegistry.all` se manifestaría
// ahí como un valor incorrecto, no como un test que deja de compilar.

enum AlertConfigScope { tenant, site, device, room }

enum AlertScopeCapability { device, room, deviceOrRoom }

enum AlertConfigOrigin { catalogDefault, tenant, site, device, room, legacy }

enum AlertThresholdKind { none, minimum, maximum, range, minimumMargin }

class AlertDefinition {
  const AlertDefinition({
    required this.id,
    required this.label,
    required this.order,
    required this.scopeCapability,
    required this.thresholdKind,
    required this.supportsVisual,
    required this.supportsWhatsapp,
    required this.supportsWhatsappDelay,
    this.supportsSensorFailureMinimum = false,
    this.thresholdLinks = const <String, String>{},
  });

  final String id;
  final String label;

  /// Orden de catálogo real — réplica exacta de
  /// `AlertMetadataRegistry.all[...].order` en
  /// `backend/lib/src/alert_priority.dart` (Etapa B2), NO un índice de
  /// lista Flutter ni un valor inventado (Etapa B5.1 §7-8). Es el fallback
  /// que usa el resolver cuando ningún nivel (tenant/site/device/room ni
  /// legacy) define un `order` propio para esta alerta.
  final int order;
  final AlertScopeCapability scopeCapability;
  final AlertThresholdKind thresholdKind;
  final bool supportsVisual;
  final bool supportsWhatsapp;
  final bool supportsWhatsappDelay;
  final bool supportsSensorFailureMinimum;

  /// Campos de `thresholds` de ESTA alerta que en realidad son un espejo de
  /// otra alerta, no un valor propio configurable — clave: nombre del
  /// campo (`'max'`, `'min'`, `'sensorFailureMin'`); valor: `id` de la
  /// alerta de la que se toma el valor efectivo.
  ///
  /// Pedido explícito del usuario (2026-09-08):
  ///   - `high_temperature_heating_active.max` refleja
  ///     `temperature_interior.max` — nunca un valor propio.
  ///   - `low_temperature_humidifier_active.min` refleja
  ///     `temperature_interior.min` — nunca un valor propio.
  ///   - `temperature_interior.sensorFailureMin` refleja el umbral propio
  ///     de `sensor_failure` — esa card pasa a ser la única fuente de
  ///     verdad de ese número.
  ///
  /// La UI (`AlertConfigCard`) muestra estos campos en modo solo lectura,
  /// con un hint indicando de qué alerta viene el valor — nunca permite
  /// editarlos desde la card donde aparecen como link.
  final Map<String, String> thresholdLinks;

  /// Campos de `thresholds` que esta alerta realmente usa — la UI no debe
  /// mostrar campos que no correspondan (Etapa B5 §13). Incluye tanto los
  /// propios (editables) como los de `thresholdLinks` (solo lectura).
  Set<String> get applicableThresholdFields {
    return <String>{
      if (thresholdKind == AlertThresholdKind.minimum ||
          thresholdKind == AlertThresholdKind.range)
        'min',
      if (thresholdKind == AlertThresholdKind.maximum ||
          thresholdKind == AlertThresholdKind.range)
        'max',
      if (thresholdKind == AlertThresholdKind.minimumMargin) 'margin',
      if (supportsSensorFailureMinimum) 'sensorFailureMin',
      ...thresholdLinks.keys,
    };
  }
}

class AlertDefinitionCatalog {
  const AlertDefinitionCatalog._();

  static const List<AlertDefinition> definitions = <AlertDefinition>[
    AlertDefinition(
      id: 'munters_door_open',
      label: 'Puerta Munters abierta',
      order: 1,
      scopeCapability: AlertScopeCapability.deviceOrRoom,
      thresholdKind: AlertThresholdKind.none,
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: true,
    ),
    AlertDefinition(
      id: 'room_door_open',
      label: 'Puerta de sala abierta',
      order: 2,
      scopeCapability: AlertScopeCapability.room,
      thresholdKind: AlertThresholdKind.none,
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: true,
    ),
    AlertDefinition(
      id: 'sensor_failure',
      label: 'Falla sensor Temp. Interior',
      order: 3,
      scopeCapability: AlertScopeCapability.deviceOrRoom,
      // Antes tenía además `thresholdKind: minimum`, lo que mostraba dos
      // campos ("Mínimo" y "Mínimo falla sensor") con el mismo número esta
      // alerta es la única dueña real de ese umbral.
      thresholdKind: AlertThresholdKind.none,
      supportsSensorFailureMinimum: true,
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
    ),
    AlertDefinition(
      id: 'temperature_interior',
      label: 'Temperatura interior',
      order: 4,
      scopeCapability: AlertScopeCapability.room,
      thresholdKind: AlertThresholdKind.range,
      supportsSensorFailureMinimum: true,
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
      thresholdLinks: <String, String>{'sensorFailureMin': 'sensor_failure'},
    ),
    AlertDefinition(
      id: 'high_temperature_heating_active',
      label: 'Temperatura alta con calefaccion activa',
      order: 5,
      scopeCapability: AlertScopeCapability.deviceOrRoom,
      // Ya no tiene `max` propio editable: siempre fue, de hecho, el mismo
      // campo compartido que temperature_interior en el modelo legacy.
      thresholdKind: AlertThresholdKind.none,
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
      thresholdLinks: <String, String>{'max': 'temperature_interior'},
    ),
    AlertDefinition(
      id: 'low_temperature_humidifier_active',
      label: 'Temperatura baja con bomba humidificadora activa',
      order: 6,
      scopeCapability: AlertScopeCapability.deviceOrRoom,
      thresholdKind: AlertThresholdKind.none,
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
      thresholdLinks: <String, String>{'min': 'temperature_interior'},
    ),
    AlertDefinition(
      id: 'high_differential_pressure',
      label: 'Presion diferencial alta',
      order: 7,
      scopeCapability: AlertScopeCapability.deviceOrRoom,
      thresholdKind: AlertThresholdKind.maximum,
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
    ),
    AlertDefinition(
      id: 'high_humidity',
      // Pasa a cubrir ambos sentidos (antes solo evaluaba humedad alta) —
      // ver HighHumidityEvaluator en el backend. El `id` no cambia (evita
      // tocar claves ya guardadas), solo el label y el rango de umbrales.
      label: 'Humedad interior',
      order: 8,
      scopeCapability: AlertScopeCapability.room,
      thresholdKind: AlertThresholdKind.range,
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
    ),
    AlertDefinition(
      id: 'dew_point_risk',
      label: 'Riesgo por punto de rocio',
      order: 9,
      scopeCapability: AlertScopeCapability.room,
      thresholdKind: AlertThresholdKind.minimumMargin,
      supportsVisual: true,
      supportsWhatsapp: true,
      supportsWhatsappDelay: false,
    ),
  ];

  static AlertDefinition byId(String id) {
    for (final AlertDefinition definition in definitions) {
      if (definition.id == id) {
        return definition;
      }
    }
    throw StateError('Missing alert definition for $id');
  }

  /// Etapa B5 §8: mientras las capabilities de B2.5 no estén conectadas
  /// productivamente, el fallback documentado es mostrar el catálogo
  /// completo para cualquier scope — no hardcodear un subconjunto distinto
  /// por tipo de Device. Cuando B6 conecte capabilities reales, este método
  /// es el único punto que hay que tocar para filtrar por
  /// `scopeCapability`/tipo de Device.
  static List<AlertDefinition> applicableFor({
    required AlertConfigScope scope,
    bool deviceHasRooms = false,
  }) {
    return definitions;
  }
}
