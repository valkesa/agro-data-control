class LayoutValidationIssue {
  const LayoutValidationIssue({
    required this.code,
    required this.message,
    this.itemId,
    this.metricKey,
    this.relatedItemId,
  });
  final String code;
  final String message;
  final String? itemId;
  final String? metricKey;
  final String? relatedItemId;
}

/// Structural errors at construction/deserialization retain machine-readable codes.
class LayoutValidationException extends ArgumentError {
  LayoutValidationException(LayoutValidationIssue issue)
    : issues = List.unmodifiable([issue]),
      super(issue.message);
  final List<LayoutValidationIssue> issues;
}
