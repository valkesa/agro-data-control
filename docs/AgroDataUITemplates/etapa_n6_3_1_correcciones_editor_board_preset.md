# Etapa N6.3.1 — Correcciones del Editor de BoardPreset

Etapa corta de corrección sobre dos problemas funcionales encontrados en
prueba manual del editor de `BoardPreset` (N6.2/N6.3): B1, agrandar una
métrica a un span válido podía dejarla sin `CellLayoutPreset`; B2, no se
podía eliminar un `BoardContentItem` seleccionado. Sin Firestore, sin
Tenant/Site/Device real — la persistencia real sigue reservada para una
etapa futura.

## B1 — causa exacta de `cell_preset_not_found`

`CellLayoutCatalog.resolve()` (N4) resolvía `(default por span)`
(`cellLayoutPresetId == null`) consultando únicamente
`defaultForSpan(width, height)` — un `Map<String, String>` sembrado a mano
con solo 5 combinaciones: `1x1`, `2x1`, `1x2`, `2x2`, `3x1`. Cualquier otro
span válido (por ejemplo `4x2`, tras agrandar `temperature-main` desde su
`2x2` original) hacía que `defaultForSpan` devolviera `null`, y `resolve()`
fallaba con `BoardParsing.fail('cell_preset_not_found', ...)` — una
excepción no capturada en el camino de renderizado real
(`MetricBoardRenderer.build()` llamaba a `resolve()` sin ningún
`try/catch`), dejando al usuario "en un estado sin renderer" exactamente
como describe el prompt.

## Resolución genérica por span — sin tabla hardcodeada

`buildDefaultCellLayoutElements(width, height)` (N4/N6.3) ya era una
función completamente genérica — nunca dependía de una lista fija de spans,
solo de `width`/`height` para calcular la subgrilla interna
(`columns = width × 8`, `rows = height × 8`) y distribuir label/value/unit/
icon/indicator slots proporcionalmente. Los 5 presets "semilla" del catálogo
inicial simplemente la invocan con 5 combinaciones curadas a mano; nunca fue
una limitación real de la función.

`lib/cell_layout_presets/cell_layout_catalog.dart` gana una función pública
nueva:

```dart
CellLayoutPreset resolveDefaultCellLayoutForSpan(int width, int height) =>
    CellLayoutPreset(
      id: 'auto_default_${width}x$height',
      name: 'Default automático $width × $height',
      widthCells: width,
      heightCells: height,
      elements: buildDefaultCellLayoutElements(width, height),
    );
```

Un `CellLayoutPreset` efímero, nunca agregado a ningún catálogo por esta
función — coherente con "no persistir este default generado
automáticamente salvo acción explícita del usuario" (§3). `resolve()` ahora
lo usa como fallback:

```dart
CellLayoutPreset resolve(DeviceBoardLayoutItem item) {
  if (item.cellLayoutPresetId == null) {
    return defaultForSpan(item.placement.widthCells, item.placement.heightCells) ??
        resolveDefaultCellLayoutForSpan(
          item.placement.widthCells,
          item.placement.heightCells,
        );
  }
  final result = byId(item.cellLayoutPresetId!);
  if (result == null) BoardParsing.fail('cell_preset_not_found', ...);
  return result;
}
```

Un `defaultForSpan` sembrado sigue teniendo prioridad cuando existe (se
mantiene curado/hand-tuned para los 5 spans más comunes); todo lo demás cae
al fallback genérico. Importante: esto solo aplica al camino
`(default por span)`. Un `cellLayoutPresetId` **explícito** que ya no
resuelve sigue fallando exactamente igual que antes — nunca se "repara"
silenciosamente un error real de configuración.

Se probó con 6 spans distintos (`1x1`, `2x1`, `2x2`, `3x1`, `4x2`, `5x3`),
incluyendo dos (`4x2`, `5x3`) que nunca tuvieron una entrada sembrada, y en
los 6 casos `CellLayoutValidator.validate` devuelve cero issues — confirma
que la geometría generada es válida (sin colisiones internas, dentro de
bounds) para cualquier span, no solo para los ya conocidos.

## Defensa en profundidad: el renderer real nunca vuelve a crashear

Aun con la resolución genérica, `CellContentResolver.resolve()` puede
fallar por otras razones (`cell_span_mismatch` con un preset explícito
incompatible, `internal_collision`, etc.) — y `MetricBoardRenderer.build()`
llamaba a `c.presets.resolve(item)` y `CellContentResolver.resolve(...)`
sin ningún `try/catch`, a diferencia de `BoardEditorCanvas` (que ya
protegía cada card con un placeholder cuando el item está en
`invalidIds`) y de `ImageBoardRenderer` (que ya usa `PreviewDiagnostic`
para un `sourceRef` sin imagen). Se corrigió el mismo patrón en
`MetricBoardRenderer`:

```dart
try {
  final preset = c.presets.resolve(item);
  final resolved = CellContentResolver.resolve(metric, item, preset, template: c.template);
  return CellLayoutCanvas(...);
} on LayoutValidationException catch (error) {
  return PreviewDiagnostic(
    issues: [for (final issue in error.issues)
      LayoutValidationIssue(code: issue.code, message: issue.message, itemId: item.id)],
  );
}
```

Esto cierra la clase completa de "renderer real crashea por una
composición de celda inválida", no solo el caso puntual de B1 — el mismo
mecanismo seguro ("no crashear, permitir reparar") que N6.3 ya había
construido para el editor de diseño de celda, ahora también cubre el
renderer de producción/preview.

## "Crear diseño desde este default" (§5)

Nuevo botón (`editor-create-design-from-default`) en el panel del item
seleccionado, visible solo cuando `content.cellLayoutPresetId == null`.
Materializa el default genérico en un `CellLayoutPreset` real vía
`sharedCellLayoutPresetCatalog.create(name: ..., width: ..., height: ...)`
(la misma composición, ahora persistida en el catálogo local) y abre
directamente el editor visual sobre él — nunca detrás del gate de
"Duplicar diseño de celda" (§3), porque un preset recién creado no está
referenciado por nada todavía. El ícono lápiz existente
(`editor-open-cell-layout-editor`) también se corrigió: antes, si no había
un default sembrado para el span, el click no hacía nada (`if (presetId ==
null) return;`); ahora cae al mismo flujo de "crear desde default" en vez
de un click muerto.

Un detalle de implementación: `_openCellLayoutEditor`'s `onApplied` antes
solo se invocaba si `resultId != presetId` — una optimización razonable
para el flujo de "editar un preset ya asignado" (si no cambió, no hace
falta reaplicar), pero rota para "crear desde default": el preset recién
creado nunca estuvo asignado al item, así que `resultId == presetId` es el
caso normal de éxito, no un no-op a saltear. Se relajó a "aplicar cualquier
resultado no nulo" — sigue siendo idempotente en el caso viejo, y ahora
también correcto en el nuevo.

## B2 — causa investigada, no reproducida tal cual

El botón "Eliminar elemento" (`editor-delete`, con su diálogo de
confirmación `¿Eliminar "..." del board?` / Cancelar / Eliminar) ya estaba
implementado de forma completa y sin condiciones de deshabilitado en el
código base de partida: `onPressed: _confirmDelete` nunca es `null`,
`_confirmDelete()` abre el diálogo, y confirmar llama a
`_controller.removeSelected()`, que filtra el item de `_items` y limpia
`selectedItemId`. Un test de reproducción exhaustivo contra el escenario
exacto descripto en el prompt (`Sala clima estándar` → `temperature-main` →
resize `2×2` → `4×2` → Eliminar → confirmar) no reprodujo ningún bloqueo:
el diálogo se abre, confirmar elimina el item, sin excepciones.

La hipótesis más plausible, dado que B1 y B2 se reportaron en la misma
sesión de prueba manual: al estar `temperature-main` en el estado roto de
B1 (`cell_preset_not_found` sin capturar), el renderer real crasheaba en
ese card específico — un estado visualmente roto que, en un navegador real
(a diferencia del sandbox de test), puede leerse como "la UI dejó de
responder" incluso si técnicamente el botón de eliminar seguía
funcionando en su propio subárbol de widgets. La corrección de B1 (arriba)
elimina esa causa raíz por completo. Independientemente de si esa era la
causa literal, se blindó el flujo con la batería completa de tests que
pide el prompt (§17) para dejarlo verificado end-to-end y evitar cualquier
regresión futura.

## Política para `requiredMetricKeys` (§11)

`BoardPreset.requiredMetricKeys`/`optionalMetricKeys` nunca bloqueaban la
eliminación (no había ningún guard que los consultara) — la novedad de
esta etapa es agregar la advertencia explícita que pide el prompt, sin
tocar el flujo de eliminación en sí. `_confirmDelete()` calcula, antes de
eliminar, si el item es de tipo `metric` y su `metricKey` está en
`requiredMetricKeys` del preset actual; si es así, tras eliminar (nunca
antes, nunca bloqueando) muestra un `SnackBar`:

```text
Esta métrica sigue declarada como requerida por el preset.
```

Verificado en Chrome real contra "Sala clima estándar" (que declara
`tempInterior`/`humInterior` como requeridos): eliminar `temperature-main`
dispara la advertencia y el item desaparece igual — nunca bloqueado.

## Tests

- `test/cell_layout_default_span_test.dart` (nuevo, 5 tests):
  `resolveDefaultCellLayoutForSpan` para un span nunca sembrado; validación
  sin issues para 6 spans distintos (prueba que no es tabla hardcodeada);
  `CellLayoutCatalog.resolve` cae al fallback para un span no soportado; un
  default sembrado sigue teniendo prioridad; un id explícito pero
  inexistente sigue fallando.
- `test/board_editor_test.dart`, grupo `N6.3.1 — B1` (3 tests): resize
  `2×2→4×2` de un item con default sembrado a uno sin sembrar nunca produce
  `cell_preset_not_found`; lo mismo repetido contra 3 spans más
  (`3×1`/`4×2`/`5×3`); "Crear diseño desde este default" produce un preset
  real, directamente editable (sin gate de duplicar), y el item queda
  apuntando a él tras "Volver al Board".
- `test/board_editor_test.dart`, grupo `N6.3.1 — B2` (7 tests): eliminar un
  metric con confirmación; cancelar deja el item intacto; la selección
  queda limpia tras eliminar; eliminar funciona para `image`/`status`/
  `dataTable` (parametrizado); eliminar un item con `placement_collision`
  activo revalida el board a cero issues; eliminar no borra la métrica del
  `DeviceMetricCatalog`; eliminar una métrica `required` muestra la
  advertencia sin bloquear.
- `test/cell_layout_preset_test.dart`: la aserción preexistente que
  esperaba `cell_preset_not_found` para un span sin default sembrado se
  actualizó para verificar el nuevo comportamiento correcto (la aserción
  vieja literalmente probaba el bug que esta etapa corrige).

Suite completa: 962 tests, 0 fallas (1 skip preexistente no relacionado).

## Verificación manual en Chrome

Se agregó temporalmente una ruta de depuración (`?mode=editor` →
`BoardEditorPage` directo sobre `preset-sala-clima-estandar` vía
`sharedBoardPresetCatalog`, sin login) a `lib/main.dart`; revertida por
completo antes del build final (confirmado con `git diff`). Con un
servidor local sirviendo `build/web`, se recorrieron los 15 pasos del
prompt §18: abrir "Sala clima estándar" → seleccionar Temperatura interior
→ confirmar `(default por span)` → agrandar `2×2→4×2` → confirmar que
sigue renderizando sin `cell_preset_not_found` (solo aparece el
`placement_collision` geométrico esperado, por invadir celdas vecinas) →
"Crear diseño desde este default" abre el editor directo, sin gate →
"Volver al Board" y confirmar que el dropdown ya no dice
"(default por span)" → seleccionar Temperatura → Eliminar elemento →
Cancelar (el item permanece) → repetir y confirmar (desaparece del board y
de "Items del Board", selección queda limpia, aparece la advertencia de
métrica requerida) → confirmar que la métrica sigue ofrecida en "Agregar"
→ repetir eliminación con un item que tiene una colisión activa (el board
revalida a cero issues). Cero excepciones Flutter en ninguna corrida.

## Exclusiones confirmadas (§19)

Sin Firestore (`grep` de `cloud_firestore`/`FirebaseFirestore` sobre los 3
archivos de `lib/` tocados: cero coincidencias), sin botón "Guardar"
persistente nuevo (el editor de preset sigue commiteando en memoria, igual
que desde N6.2), sin Tenant/Site/Device real, sin drag & drop, sin
migración productiva, sin tocar el switch de TABLERO —
`lib/main.dart` termina la etapa bit-a-bit idéntico a como empezó (salvo
cambios preexistentes de otra tarea en curso, ajenos a N6.3.1).
