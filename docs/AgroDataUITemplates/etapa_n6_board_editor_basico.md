# Etapa N6 — Board Editor básico + ajuste de gap

## Ajuste previo: gap entre Cards

`BoardRenderConfig.cardGap` reemplaza la constante fija `BoardCardTokens.gutter`
(antes 3 lógicos) como fuente única del espacio entre celdas adyacentes.
Se compararon visualmente 3 (actual), 2 y 1 sobre Sala en Chrome
(`n6_gap_candidate_3/2/1.png`): con 1 las Cards ya empiezan a sentirse
apretadas para un dashboard permanente; con 3 no hay reducción. Se eligió
**2**, la reducción mínima que compacta el conjunto sin acercarlo a "pegado".
`baseCellSize`, la geometría cuadrada, `naturalBoardWidth` y los bordes de
N5.2 no cambiaron.

## Arquitectura del editor

`BoardEditorController` (`ChangeNotifier`) mantiene una copia editable en
memoria de un `PreviewBoardFixture`: `LayoutTemplate`, `List<BoardContentItem>`,
`showTitle`/`titleOverride`. Cada mutación reconstruye objetos inmutables de
N3/N4.5 (nunca los muta in place) y expone `board` (el `BoardContentLayout`
vigente) e `issues(presets)`, que delega en `BoardContentValidator.validate`
sin reimplementar ninguna regla. `reset()` vuelve al fixture pristino
(`_active`, la referencia estática nunca tocada); `applyFixture()` cambia de
Sala/Laboratorio/Arco.

La geometría se extrajo de `BoardContentRenderer` (N5.2) a un widget
compartido, `BoardCanvasLayout`: ancho natural fijo, `FittedBox(scaleDown)`,
anclaje `topLeft`, celdas cuadradas. `BoardEditorCanvas` construye su Stack
sobre ese mismo widget — el editor **no tiene una geometría paralela**.
Añade: una grilla de `GestureDetector` transparentes por celda (debajo de las
Cards, así una celda ocupada siempre prioriza seleccionar su Card), selección
resaltada y placeholder de diagnóstico (⚠) para cualquier item cuyo id
aparezca en `issues` — evita que `MetricBoardRenderer`/`CellContentResolver`
(que lanzan excepción ante geometría inválida, correcto para el preview de
solo lectura) tumben la página mientras se edita un estado transitoriamente
inválido.

`BoardEditorPage` arma los paneles: selector de fixture + Reset, selector de
`LayoutTemplate` (genérico, `initialLayoutTemplateCatalog.templates`, sin
branches por id), título (`showTitle`/`titleOverride` con preview inmediato
de `resolveTitle`), el canvas, el panel de issues (verde si vacío, naranja
con el código+mensaje de cada uno si no), el panel del item seleccionado
(mover con flechas o clic, resize con steppers, editor de metricKey/preset/
indicators o campo mínimo según tipo, eliminar con confirmación) y el panel
de alta (7 tipos, posición x/y y span por steppers o tocando una celda vacía
del canvas, con overlay fantasma antes de confirmar).

## Reutilización de validadores

Ninguna regla de negocio se reimplementó. `BoardEditorController.issues()`
llama a `BoardContentValidator.validate` (que a su vez usa
`DeviceBoardLayoutValidator`/`CellLayoutValidator` de N3/N4 sin cambios). El
editor solo decide **qué hacer con los issues** (mostrarlos, no bloquear el
guardado salvo un caso: exceso de indicator slots al agregar, que se
bloquea localmente comparando `indicatorKeys.length` contra
`preset.indicatorSlotCount` — un dato ya validado, no una regla nueva).

Mover/redimensionar/agregar nunca pre-verifican colisión o bounds: el cambio
se aplica siempre y el panel de issues refleja el estado real, igual que el
resto de la arquitectura N1-N5 ("no perder cambios silenciosamente").
Confirmado con Sala: mover Temperatura sobre Humedad produce
`placement_collision` visible y dos Cards con el placeholder rojo, sin
crashear ni perder el resto del board (`n6_editor_sala_move.png`).

## Selección de preset — por qué lista todos, no solo los compatibles

La primera versión filtraba el dropdown de preset por el span **actual** del
item; al redimensionar, el preset ya asignado podía quedar fuera de esa
lista filtrada y Flutter lanza una excepción (`DropdownButton` exige que el
valor actual aparezca exactamente una vez entre sus items). Se corrigió
listando **todos** los presets habilitados, marcando "(span distinto)" en
los que no calzan con el span vigente — el mismatch sigue reportándose por
`cell_span_mismatch` en el panel de issues, no se oculta.

## Alcance de datos de tipos no métricos

Para `latestEvent`/`dataTable` se usa un field/columna mínima genérica
(`key: 'value', label: 'Valor'`) al agregar, en vez de un editor completo de
fields/columnas — explícitamente permitido por el prompt. `image`/`status`/
`text`/`chart` tienen formularios mínimos fieles a sus contratos N4.5
(sourceType/fit, dataSourceId, texto plano, chartType+serie). Ninguno
hardcodea nombres de campos de negocio del Arco.

## Sala, Laboratorio, Arco

Los tres fixtures reales de N4.5 (no copias) se editan con las mismas
herramientas genéricas: Sala (13 items, `grid_6x4`), Laboratorio (dos 3×1 en
`grid_6x1`, sin excepción para ese span), Arco (`image`+3 `metric`+`status`+
`latestEvent`+`dataTable` en `grid_6x7`) — capturas en
`n6_editor_laboratorio.png`/`n6_editor_arco.png`. Ningún archivo del núcleo
(`board_editor_*.dart`) menciona Sala/Laboratorio/Arco.

## No persistencia

Todo el estado vive en `BoardEditorController` (memoria del widget). No se
agregó repositorio, `StreamBuilder`, `Timer`, listener ni escritura a
Firestore — confirmado por grep sobre `lib/board_preview/*.dart`. `main.dart`
solo gana la ruta owner-only "Board Editor" (mismo bloque `if (userRole ==
UserAppRole.owner)` que ya usan "Board Preview"/"Templates UI"); ningún
archivo de N1-N5.2 fue modificado, confirmado por timestamp y por
`n6_changed_files.json`.

## Recomendaciones para la siguiente etapa

1. Definir persistencia real (¿`tenants/{tenantId}/devices/{deviceId}/ui/board`
   propuesto desde N4.5?) y un migrador explícito borrador-local → Firestore.
2. Editor completo de `fields`/`columns` para `latestEvent`/`dataTable` en
   vez del campo mínimo genérico actual.
3. Drag & drop real sobre el canvas (hoy: clic-para-reposicionar + flechas),
   posible en N7 reutilizando la misma `BoardCanvasLayout`.
4. Editor de `CellLayoutPreset` en sí (hoy solo se selecciona, no se edita).
5. Persistir el ancho/alto elegidos en el selector de LayoutTemplate como
   parte de un futuro `DeviceBoardLayout` real, no solo del fixture en memoria.
