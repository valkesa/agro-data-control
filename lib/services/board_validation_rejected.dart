import '../device_board_layouts/layout_validation_issue.dart';

/// N7.1.1 §6 (finding A3) — thrown by [DeviceBoardConfigRepository.saveLayout]
/// (and, once applied preset content is validated too,
/// [DeviceBoardConfigRepository.applyPreset]) when the layout it was asked
/// to persist still has at least one blocking [LayoutValidationIssue] — the
/// second, server-side-of-the-call defense §6 asks for ("no confiar solo en
/// el botón"). The Board Editor's own Guardar button already gates on the
/// same [BoardContentValidator.validate] call (see
/// `board_editor_page.dart`'s `_deviceBoardHasBlockingIssues`), so this
/// should be unreachable through normal UI use — it exists specifically to
/// reject a caller that bypasses that button (a stale draft, a future
/// programmatic caller, a test) rather than silently persisting invalid
/// content.
class BoardValidationRejected implements Exception {
  const BoardValidationRejected(this.issues);

  final List<LayoutValidationIssue> issues;

  @override
  String toString() =>
      'BoardValidationRejected(${issues.map((i) => i.code).join(', ')})';
}
