import '../device_metric_catalogs/catalog_validation.dart';

/// N6.5.2 — shared primitives for the capability library models
/// ([CapabilityMetricDefinition], [CapabilityIndicatorDefinition],
/// [MetricBinding], [IndicatorBinding]). Deliberately reuses
/// [CatalogValidation]'s primitives (`string`/`key`/`source`/`integer`)
/// instead of duplicating them — only `sourceField`-shaped validation is
/// re-exposed here since bindings are the only place it still applies; a
/// global definition never has one.
abstract final class CapabilityValidation {
  static String string(
    Object? value,
    String field, {
    bool allowEmpty = false,
  }) => CatalogValidation.string(value, field, allowEmpty: allowEmpty);

  static void key(String value, String field) =>
      CatalogValidation.key(value, field);

  static void source(String value) => CatalogValidation.source(value);

  static int integer(Object? value, String field, {int min = 1, int? max}) =>
      CatalogValidation.integer(value, field, min: min, max: max);

  static const maxDecimals = CatalogValidation.maxDecimals;
}
