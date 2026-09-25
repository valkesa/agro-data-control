import 'layout_template.dart';
import 'layout_template_validator.dart';

/// Local-only catalog. No listeners, persistence, device mapping or UI wiring.
class LayoutTemplateCatalog {
  LayoutTemplateCatalog(Iterable<LayoutTemplate> templates)
    : templates = List<LayoutTemplate>.unmodifiable(templates) {
    LayoutTemplateValidator.uniqueIds(this.templates.map((item) => item.id));
  }

  final List<LayoutTemplate> templates;

  LayoutTemplate? byId(String id) {
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }
}

final LayoutTemplateCatalog initialLayoutTemplateCatalog =
    LayoutTemplateCatalog([
      for (var rows = 1; rows <= 4; rows++)
        LayoutTemplate(
          id: 'grid_6x$rows',
          name: '6 × $rows',
          columns: 6,
          rows: rows,
        ),
    ]);
