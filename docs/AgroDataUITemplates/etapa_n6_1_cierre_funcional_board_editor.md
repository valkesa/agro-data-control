# Etapa N6.1 — Cierre funcional del Board Editor

Etapa de robustez, no de features: corrige los cinco hallazgos A1–A5 de la
auditoría posterior a N6 y completa dos vacíos de alcance (config mínima de
`latestEvent`/`dataTable`, selector de `CellLayoutPreset` compatible por
span). Cero persistencia nueva, cero features de producto.

## A1 — Salida con dirty sin confirmación

`BoardEditorPage.build()` ahora envuelve el `Scaffold` en `PopScope(canPop:
!_effectiveDirty, onPopInvokedWithResult: ...)`. Si el pop es interceptado
(`didPop == false`), se llama al mismo `_confirmDiscard()` que ya usaba el
cambio de fixture — un solo diálogo ("¿Descartar cambios?" / Cancelar /
Descartar), sin duplicar lógica entre el botón Atrás del `AppBar` y la
navegación del sistema. `_effectiveDirty` es más amplio que
`controller.dirty`: también es `true` con un draft de alta pendiente
(`_pendingType != null`) o con un error de validación activo, así un alta a
medio completar o un input inválido tampoco se pierde en silencio.

Para poder probar esto en Chrome real se necesitaba una ruta de verdad con
algo para hacer *pop* — `tool/board_preview_main.dart?mode=editor` pasó de
montar `BoardEditorPage` como `home` directo a un `_EditorLauncher` que la
empuja con `Navigator.push`, igual que hace `main.dart` en producción.

## A2 — Controladores de texto persistentes

Los `TextEditingController` de `titleOverride` y de los campos de texto del
item seleccionado (`dataSourceId`, `sourceRef`, texto plano) ahora viven en
`State`, se inicializan una vez y se resincronizan **solo** cuando cambia la
identidad de lo editado — `_syncedSelectedId` guarda el último
`selectedItemId` sincronizado, y `_syncSelectedControllers()` solo
sobreescribe el texto del controller si ese id cambió desde la última vez.
El resultado: escribir sin pulsar Enter sobrevive a cualquier rebuild no
relacionado (cambiar otro control, recalcular issues, etc.), pero
seleccionar un item distinto sí trae el texto de ese nuevo item. Todos los
campos usan `onChanged`, no `onSubmitted`: el título tiene preview inmediato
(`resolveTitle()` recalcula en cada tecla) y cualquier tecleo marca
`_effectiveDirty = true` aunque el valor aún sea inválido.

## A3 — Inputs inválidos sin excepción

Cada mutación que construye un objeto de dominio desde texto libre pasa por
`try { ... } catch (e) { _selectedFieldError = _errorFrom(e); }`
(`_safeUpdateSelected` para el item seleccionado, el mismo patrón para el
draft de alta pendiente). `_errorFrom` distingue `LayoutValidationException`
(usa `issues.first.message`) de `ArgumentError` (usa `.message`) de
cualquier otra excepción (usa `.toString()`), y el mensaje se muestra en
rojo bajo el campo. El texto inválido se conserva tal cual lo escribió el
usuario — no se sanitiza ni se revierte — y el botón "Agregar"/la mutación
correspondiente queda inhabilitada mientras el error esté activo. Ningún
`ArgumentError`/`LayoutValidationException` llega a la capa de widgets.

## A4 — Preview realmente de solo lectura

En vez de intentar que un único widget sirviera para edición y preview
(la causa raíz del hallazgo de auditoría: pending-placement y controles
seguían montados con solo ocultar el debug), `build()` ahora **cambia de
widget** según el modo:

```dart
_controller.editMode ? BoardEditorCanvas(...) : BoardContentRenderer(...)
```

`BoardContentRenderer` es el mismo renderer de solo lectura de N5 — sin
selección, sin overlay fantasma, sin grilla de tap. El selector de
`LayoutTemplate`, el chip Reset, el panel "Items del Board", el panel del
item seleccionado, el panel de alta y el campo `titleOverride` quedan
además condicionados a `if (_controller.editMode)`. El draft de alta
pendiente y el estado de selección no se destruyen al entrar a Preview —
viven en `State`/`BoardEditorController` independientemente del widget
mostrado — así que volver a "Editar" los recupera intactos.

## A5 — Recuperación de items fuera del canvas

Nuevo panel **"Items del Board"**: una fila por cada item del controller
(no solo los que caben en el `LayoutTemplate` vigente), cada una envuelta en
un `InkWell` que llama a `controller.selectItem(id)` — la selección vive en
el controller, nunca depende de que el canvas pueda hacer hit-test sobre esa
celda. Un ícono de advertencia marca las filas cuyo id aparece en los
issues actuales. Además, cada línea del panel de issues que trae `itemId`
es ahora clicable (subrayada, color de acento) y también llama a
`selectItem(issue.itemId)` — "clic issue → seleccionar item" funciona igual
desde ambos paneles. Una vez seleccionado, el item fuera del canvas expone
el mismo panel de edición que cualquier otro (mover, resize, cambiar
preset, eliminar), sin necesitar que vuelva a ser visible primero.

## `latestEvent` / `dataTable` — configuración mínima reutilizable

En vez de un editor completo de `fields`/`columns`, dos mapas estáticos
genéricos (no específicos de Arco) ofrecen configuraciones de referencia:

```dart
final _fieldPresets = <String, List<BoardDataField>>{
  'Simple (1 campo)': [BoardDataField(key: 'value', label: 'Valor')],
  'Evento (fecha + estado)': [
    BoardDataField(key: 'timestamp', label: 'Fecha / hora', format: BoardFieldFormat.dateTime),
    BoardDataField(key: 'state', label: 'Estado', format: BoardFieldFormat.status),
  ],
};
```

(`_columnPresets` es el equivalente envolviendo `BoardTableColumn`, con
`'Simple (1 columna)'` / `'Registro (fecha + estado)'`). Un `ActionChip` por
entrada reemplaza `fields`/`columns` completos preservando `maxRows` y
`showHeader` en el caso de `dataTable`; `eventSourceId`/`dataSourceId` se
edita aparte con el mismo patrón de controller persistente + validación
segura de A2/A3. Ningún archivo del núcleo del editor menciona claves de
negocio de Arco.

## Selector de `CellLayoutPreset` — solo compatibles por span

`_presetDropdownItems({width, height, currentPresetId})` es un helper
compartido por el dropdown del item seleccionado y el del alta pendiente.
Filtra el catálogo a los presets cuyo `(width, height)` coincide con el
span vigente, agrega la opción `(default por span)`, y — si el preset
asignado actualmente **no** está en ese subconjunto — agrega una entrada
diagnóstica extra: `'$nombre — actual, span incompatible'`. Esa entrada
evita el crash de `DropdownButton` (que exige que el valor vigente aparezca
exactamente una vez entre sus items — la misma clase de bug que ya se había
resuelto para el dropdown de `LayoutTemplate`, ver más abajo) sin ocultar el
problema: `cell_span_mismatch` se sigue reportando en el panel de issues
hasta que el usuario elige explícitamente un preset compatible. Cambiar
Ancho/Alto con los steppers **nunca** reasigna el preset automáticamente —
el mismatch queda visible y es una acción deliberada del usuario resolverlo.

### Bug adicional encontrado y corregido: dropdown de `LayoutTemplate`

Al escribir los tests de aceptación de A5 (reducir Sala a `grid_6x1`) se
detectó que seleccionar el fixture Arco lanzaba la misma clase de excepción
de `DropdownButton`: `initialLayoutTemplateCatalog.templates` solo cubre
`grid_6x1`..`grid_6x4`, y Arco usa `grid_6x7`. `_layoutTemplateSelector()`
aplica el mismo patrón de entrada diagnóstica: si el template vigente no
está en el catálogo genérico, se agrega una entrada sintética
`'${nombre} (${id}) — del fixture'` para que el dropdown nunca reciba un
`value` ausente de sus `items`.

## Tests de aceptación

Las reproducciones de la auditoría se convirtieron en 18 tests permanentes
nuevos en `test/board_editor_test.dart` (19 → 37 en total, suite completa
890/890), agrupados exactamente como el prompt lo pide: `A1 — exit
confirmation` (5), `A2 — persistent text controllers` (3), `A3 — invalid
inputs never throw` (2), `A4 — Preview is read-only` (1), `A5 —
out-of-canvas items stay reachable` (2), `latestEvent / dataTable minimal
usable config` (3), `preset selector — span compatible only` (2). Todos
usan la app real (`pushEditor()` empuja `BoardEditorPage` sobre un
Navigator real para poder probar A1) y no mockean el controller ni los
validadores.

## Verificación manual en Chrome

Los 10 pasos del prompt (§17) se probaron contra un build real
(`flutter build web -t tool/board_preview_main.dart`) servido localmente y
manipulado con un script CDP propio (`n6_1_capture.cjs`, sin dependencias
externas): abrir editor → editar título → Atrás (diálogo) → Cancelar →
Atrás → Descartar → reabrir → escribir sin Enter + seleccionar otra card →
Arco → seleccionar card de estado → escribir source inválido → corregir →
configurar `latestEvent`/`dataTable` con los presets reutilizables → volver
a Sala → alta pendiente → Preview (limpio) → volver a Editar → reducir
layout a `grid_6x1` → panel "Items del Board" con ítems fuera de bounds
seleccionables → Reset → asignar preset 2×1 a Humedad → reducir Ancho a 1 →
reabrir el dropdown de preset (entrada diagnóstica "— actual, span
incompatible" visible, sin excepción). Cero errores de consola/excepciones
Flutter durante toda la secuencia (verificado con `Runtime.exceptionThrown`
sobre el mismo socket CDP).

## Cero Firestore / polling — TABLERO intacto

`grep` sobre `lib/board_preview/*.dart` por `Firestore`/`.snapshots()`/
`Timer.periodic`/`StreamSubscription` no devuelve coincidencias de código
(solo dos comentarios doc que dicen explícitamente "no Firestore"). Todo el
estado de N6.1 sigue viviendo en `BoardEditorController`, un `ChangeNotifier`
en memoria — ningún archivo nuevo de N6.1. `lib/main.dart` no cambió desde
la sesión N6 (timestamp sin modificar); TABLERO productivo continúa sobre
el sistema legacy.

## Qué NO se agregó (alcance deliberadamente excluido)

Drag & drop, repositorio/persistencia remota, edición de `Device` real,
editor completo de `CellLayoutPreset`, motor de charts, métricas nuevas.
Esta etapa es exclusivamente robustez sobre lo que N6 ya exponía.
