class TemplateDataContext {
  const TemplateDataContext({required this.source, this.extras = const {}});

  final Object? source;
  final Map<String, Object?> extras;
}
