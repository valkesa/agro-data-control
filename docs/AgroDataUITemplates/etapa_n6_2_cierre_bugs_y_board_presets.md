# Etapa N6.2 — Cierre definitivo de bugs + separación BoardPreset

Dos objetivos independientes: (A) cerrar R1–R5, los hallazgos de la
auditoría posterior a N6.1; (B) introducir `BoardPreset` como concepto
explícito, separado de `LayoutTemplate`/`DeviceMetricCatalog`/futuro
`DeviceBoardLayout`, con una UI mínima para crear/duplicar/editar presets.
Sin Firestore, sin Tenant/Site/Device real, sin drag & drop.

## R1 — drafts por item

Antes, solo el item *actualmente seleccionado* podía tener un error de
validación visible; cambiar de selección con un error activo lo perdía en
silencio. Ahora `_BoardEditorPageState` mantiene `Map<String, _ItemDraft>
_itemDrafts`: `_syncSelectedControllers()` guarda el texto+error del item
saliente en el mapa *solo si tenía un error activo* (si no, se borra
cualquier entrada obsoleta), y al seleccionar un item restaura su draft si
existe. `_effectiveDirty` ahora también es `true` si `_itemDrafts` no está
vacío — un error parqueado en un item que no es el seleccionado igual
bloquea la salida silenciosa (Back sigue mostrando "¿Descartar cambios?").
El panel "Items del Board" marca con ⚠ tanto los items con issues del
validador como los que tienen un draft parqueado.

## R2 — layout actual del fixture, una sola colección

`effectiveLayoutTemplates(current)` (en `board_editor_controller.dart`) es
ahora la única fuente que tanto los `items` del dropdown como su callback
`onChanged` consultan — antes el dropdown insertaba una entrada sintética
"del fixture" pero el callback seguía resolviendo contra la lista genérica
de 4 templates, una asimetría que funcionaba por casualidad. Además,
`BoardEditorController.setLayoutTemplate()` ahora es un no-op real si
`next.id == _template.id`: no marca dirty, no reconstruye nada, no dispara
`notifyListeners()`. Seleccionar el layout ya vigente (grid_6x7 de Arco)
deja de ser una operación con efectos secundarios.

## R3 — Reset limpia todo el estado efímero

`_resetEphemeralState()` ahora también limpia `_itemDrafts` (R1) y
restaura los controllers compartidos del formulario de alta
(`_sourceRefController`, `_dataSourceController`, `_textController`) a sus
valores por defecto (`'hero'`, `'device.status'`, `'Nota'`). Antes esos tres
controllers —reutilizados entre los 7 tipos de contenido posibles en el
alta— conservaban cualquier texto tipeado para un tipo cancelado y podían
reaparecer al iniciar un alta distinta. `_startAdding()` aplica el mismo
reseteo por tipo, así que ni siquiera hace falta un Reset completo para que
un alta nueva empiece limpia.

## R4 — Preview realmente minimal

N6.1 ya hacía que Preview usara `BoardContentRenderer` en vez de
`BoardEditorCanvas`, pero seguía mostrando el switch "Mostrar título" (solo
deshabilitado) y el panel de issues completo. R4 endurece esto: `_titleSection()`
y `_issuesPanel()` ahora están condicionados a `_controller.editMode` — en
Preview no aparecen. Para no perder el diagnóstico cuando hace falta, se
agregó un ícono nuevo en el `AppBar` (`editor-debug-toggle`, un
`Icons.bug_report` apagado por default) que revela el panel de issues
también en Preview sin traer de vuelta ningún control de edición. Lo único
visible en Preview por default es: navegación general (AppBar + chips de
"Casos demo", que no son controles de edición), el selector Editar/Preview,
y el board final.

## R5 — Duplicate Keys en colisiones múltiples

**Causa exacta:** `BoardContentValidator` emite un `LayoutValidationIssue`
`placement_collision` por cada *par* de items solapados —si un item 2×2 se
mueve sobre dos vecinos a la vez, emite dos issues con el mismo `itemId`
(el item movido) y distinto `relatedItemId`. El panel de issues construía
la `Key` de cada fila como `'editor-issue-${issue.code}-${issue.itemId}'`
— sin `relatedItemId`, ambos issues generaban la misma `Key` dentro del
mismo `Column`, y Flutter's element reconciliation exige claves únicas
entre hermanos: la segunda fila con la clave repetida disparaba la
excepción "Multiple widgets used the same key" en pleno build (la
"Duplicate keys found" del reporte). El canvas en sí nunca tuvo el
problema — `BoardEditorCanvas` ya usa `ValueKey('edit-placement-${item.id}')`,
una clave por item real, nunca por issue: la regla "1 item → 1 nodo
visual" ya estaba respetada ahí.

**Corrección:** la clave de cada fila del panel de issues ahora incluye
`relatedItemId`: `'editor-issue-${code}-${itemId}-${relatedItemId ?? "_"}'`.
Cada par de colisión es emitido una sola vez por el validador (el doble
`for` que lo genera solo recorre `a < b`), así que la clave es única por
construcción — sin necesitar un índice de lista como respaldo.

## Separación conceptual — `BoardPreset`

Cuatro conceptos ahora formalizados y sin solaparse:

| Concepto | Qué es | Qué NO tiene |
|---|---|---|
| `LayoutTemplate` | Geometría externa pura (`grid_6x1`, `grid_8x4`, …) | Métricas, contenido, tenant, device |
| `DeviceMetricCatalog` | Qué métricas/capacidades tiene un Device | Posiciones, geometría |
| `BoardPreset` (nuevo) | Config reutilizable de arranque: `layoutTemplateId` + `items[]` + `required`/`optionalMetricKeys` | `tenantId`/`siteId`/`deviceId` — ningún campo de identidad de Device |
| `DeviceBoardLayout` (futuro) | Config concreta de un Device real, potencialmente iniciada desde un `BoardPreset` | — |

`BoardPreset` (`lib/board_presets/board_preset.dart`) es una clase de datos
inmutable: `id`, `name`, `description`, `layoutTemplateId` (string, nunca el
objeto — se resuelve bajo demanda), `showTitleDefault`, `items` (copia
inmutable de `BoardContentItem`), `requiredMetricKeys`/`optionalMetricKeys`
(declarativos — sin validar contra ningún catálogo real todavía, per §11:
"al aplicar a un Device futuro se validará... no conectar esa aplicación
todavía"), `schemaVersion`, `presetVersion`. `copyWith` siempre reconstruye
la lista de `items` desde cero — la independencia estructural entre un
preset y su copia no depende de que nadie recuerde "clonar bien", es
estructural en el constructor.

### `BoardPresetCatalog` — catálogo local

`BoardPresetCatalog` (`ChangeNotifier`, en memoria, sin Firestore) expone
`create()`, `duplicate()`, `rename()`, `updateContent()`. Un único
`sharedBoardPresetCatalog` de módulo mantiene el estado entre la lista y
cualquier editor empujado desde ella durante la sesión. La semilla inicial
migra el **contenido visual** de los tres fixtures demo (Sala/Laboratorio/
Arco) a tres `BoardPreset` reales ("Sala clima estándar", "Laboratorio
estándar", "Arco estándar") — decisión documentada explícitamente: los
`items`/`template` se copian una única vez en la construcción del catálogo;
a partir de ahí un `BoardPreset` nunca vuelve a leer
`preview_board_data.dart`, y los fixtures demo siguen existiendo sin
cambios como el playground de solo-geometría de N6/N6.1 (`board_editor_page.dart`
sigue teniendo su propio flujo `_fixtureIndex`/`previewBoardFixtures`,
completamente separado del flujo `presetId`/`presetCatalog`).

`resolveLayoutTemplateId(id)` reconstruye cualquier `LayoutTemplate` a
partir de su id siguiendo la convención `grid_<columnas>x<filas>` que ya
usaba todo el codebase — cubre tanto los 4 templates genéricos como
cualquier geometría de fixture (`grid_6x7`) o dinámica (`grid_8x4`) sin
necesitar una lista adicional de "templates conocidos".

### Catálogo de métricas de referencia

En modo preset no existe un Device real del cual leer un
`DeviceMetricCatalog`. En vez de fabricar uno nuevo, `referenceMetricCatalog`
reexpone (relabeled, nunca renombrando su contenido) el catálogo N2 ya
existente `environment_room_v1` ("Capacidades ambientales") — el mismo que
ya usa el fixture Sala, reutilizando `MetricDefinition`s reales y
validadas en vez de inventar métricas nuevas para la ocasión.

## Modo editor: `BoardEditorMode.preset`

`BoardEditorController` gana un segundo camino de construcción,
`BoardEditorController.forPreset({preset, catalog})`, junto al existente
`BoardEditorController({initial: fixture})` — ninguno de los dos duplica al
otro; ambos comparten exactamente la misma lógica de mutación
(`addItem`/`moveSelectedTo`/`resizeSelected`/etc.), solo difiere cómo se
inicializa y a qué se resetea. `BoardEditorPage` gana `presetId`/
`presetCatalog` opcionales (validados juntos vía `assert`); cuando están
presentes:

- El encabezado muestra "BOARD PRESET EDITOR / Preset: {nombre} / Layout:
  {cols}x{rows}" en vez de "Sala · demo" (§13 — nunca ambiguo con un
  Device real).
- Los chips "Casos demo" no se renderizan (no tiene sentido elegir un
  fixture mientras se edita un preset).
- Cada cambio del controller (`_onControllerChanged`) commitea en vivo a
  `BoardPresetCatalog.updateContent()` — editar *es* guardar, siempre en
  memoria, sin paso de publicación separado.
- `catalog` para el editor de contenido (metricKey, indicators) es
  `referenceMetricCatalog`, no el catálogo de ningún fixture.

`BoardEditorMode` declara también `device` para la etapa futura (§12); N6.2
no lo construye en ningún lado — es una preparación explícita, no una
implementación parcial.

## UI de BoardPreset

`BoardPresetsPage` (owner-only): lista cada preset con nombre, descripción,
id, layout, cantidad de items, `requiredMetricKeys`/`optionalMetricKeys` y
tres acciones. "Nuevo preset" abre un diálogo con nombre/descripción y
steppers de columnas/filas (soporta cualquier geometría, no solo las 4
genéricas — cubre el caso de prueba 8×4 del prompt); al confirmar crea el
preset vacío y navega directo a su editor. "Duplicar" llama a
`catalog.duplicate(id)` (nuevo id, mismo contenido inicial, sin compartir
listas). "Renombrar" edita nombre/descripción sin tocar el id técnico.

## Tests

18 tests nuevos/actualizados en `board_editor_test.dart` (37→47): 3 de R1,
1 de R2, 1 de R3, 1 de R4, 1 de R5, y 3 de integración del modo preset del
editor (abre contra un `BoardPreset`, commitea contenido en vivo,
independencia de duplicado sobrevive al flujo completo del editor). 13
tests nuevos en `board_preset_test.dart` (modelo + catálogo: sin
tenant/site/device, resolución de templates fixture-only y dinámicos,
create/duplicate/independencia/rename). 4 tests nuevos en
`board_presets_page_test.dart` (acceso owner-only, crear "Maternidad
estándar" + agregar métrica, duplicar + editar duplicado sin tocar el
original, renombrar preservando id) — matching directo con los pasos 10–14
del Chrome manual del prompt. Suite completa: 917/917.

## Verificación manual en Chrome

Los 14 pasos del prompt (§17) se probaron contra un build real
(`flutter build web -t tool/board_preview_main.dart`) con dos scripts CDP
propios sin dependencias (`n6_2_capture.cjs` para los pasos 1–9 del editor,
`n6_2_capture_presets.cjs` para los pasos 10–14 de BoardPresets). Cero
excepciones Flutter, cero errores de consola de la app durante toda la
secuencia (verificado con `Runtime.exceptionThrown` sobre el mismo socket
CDP en ambos scripts).

## Cero Firestore / polling — TABLERO intacto

`grep` sobre `lib/board_presets/*.dart` y `lib/board_preview/*.dart` por
`Firestore`/`.snapshots()`/`Timer.periodic`/`StreamSubscription` no
devuelve coincidencias de código (solo comentarios doc que dicen
explícitamente "no Firestore"). `lib/main.dart` solo gana un `enum` value,
un `case` y un botón "Board Presets" con el mismo guard owner-only que ya
usan "Board Editor"/"Board Preview" — ningún archivo de N1–N5.2 fue
modificado. TABLERO productivo sigue sobre el sistema legacy.

## Nota de comportamiento (no un bug de R1–R5)

En modo preset, cada mutación aplicada se commitea en vivo al catálogo —
pero el flag `dirty` del controller sigue siendo genérico ("hubo alguna
mutación en esta sesión de edición"), así que el diálogo "¿Descartar
cambios?" puede aparecer al salir incluso cuando el contenido ya está
guardado en `BoardPresetCatalog`. No es incorrecto (sigue protegiendo
drafts/errores realmente no aplicados, que es lo que R1/A1 exigen), pero es
una imprecisión de redacción que vale la pena revisar en una etapa futura
si se distingue "guardado en el preset" de "dirty" de verdad.

## Qué NO se agregó (§19)

Firestore, selector real de Tenant/Site/Device, persistencia remota,
migración productiva, drag & drop, asignación de preset a un Device,
switch productivo. `BoardEditorMode.device` queda declarado, sin
implementación — trabajo explícito para una etapa posterior.
