import 'catalog_validation.dart';

/// Semantic subset of legacy IndicatorDefinition. A separate type is necessary
/// because the legacy contract requires a visual position. No position defaults
/// or hidden legacy indicator objects are retained here.
class MetricIndicatorDefinition {
  MetricIndicatorDefinition({
    required this.key,
    required this.sourceField,
    required this.icon,
    required this.condition,
  }) {
    CatalogValidation.key(key, 'key');
    CatalogValidation.source(sourceField);
    CatalogValidation.string(icon, 'icon');
    if (!(condition == null ||
        condition is String ||
        condition is bool ||
        (condition is num && (condition as num).isFinite))) {
      throw ArgumentError.value(
        condition,
        'condition',
        'Expected finite JSON scalar',
      );
    }
  }

  factory MetricIndicatorDefinition.fromMap(Map<String, Object?> map) {
    CatalogValidation.fields(map, {'key', 'sourceField', 'icon', 'condition'});
    if (!map.containsKey('condition')) throw ArgumentError('Missing condition');
    return MetricIndicatorDefinition(
      key: CatalogValidation.string(map['key'], 'key'),
      sourceField: CatalogValidation.string(map['sourceField'], 'sourceField'),
      icon: CatalogValidation.string(map['icon'], 'icon'),
      condition: map['condition'],
    );
  }

  final String key;
  final String sourceField;
  final String icon;
  final Object? condition;

  /// N6.5 admin editor convenience — reconstructs through the validating
  /// constructor.
  MetricIndicatorDefinition copyWith({
    String? key,
    String? sourceField,
    String? icon,
    Object? condition = _unset,
  }) => MetricIndicatorDefinition(
    key: key ?? this.key,
    sourceField: sourceField ?? this.sourceField,
    icon: icon ?? this.icon,
    condition: identical(condition, _unset) ? this.condition : condition,
  );

  static const _unset = Object();

  Map<String, Object?> toMap() => {
    'key': key,
    'sourceField': sourceField,
    'icon': icon,
    'condition': condition,
  };
}
