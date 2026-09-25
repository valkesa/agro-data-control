# Etapa N6.3 — Editor visual de CellLayoutPreset + UX lateral del Board Editor

Dos entregables independientes: (A) un editor visual para la composición
interna de un `CellLayoutPreset` (label/value/unit/icon/indicator slots
dentro de la subgrilla de N1, nunca píxeles); (B) una UX de panel lateral
para el Board Editor en desktop (`[Board][Seleccionado][Agregar]`), sin
tocar la geometría real del renderer. Sin Firestore, sin Device real, sin
Tenant/Site/Device selector, sin drag & drop.

## Arquitectura: `CellLayoutCanvas` compartido

El renderer real (`MetricBoardRenderer.build()`, en
`board_item_renderers.dart`) construía su propia geometría de elementos
internos con un método privado `_element(...)` de ~90 líneas. Ese código se
extrajo tal cual a un widget público nuevo, `CellLayoutCanvas`
(`lib/board_preview/cell_layout_canvas.dart`), que ahora consume tanto el
renderer real como el editor nuevo — el mismo patrón que `BoardCanvasLayout`
ya usaba entre `BoardContentRenderer`/`BoardEditorCanvas` desde N6. El
widget acepta `resolved: List<ResolvedCellElement>?` XOR
`rawElements: List<CellLayoutElement>?` (mutuamente excluyentes, con
`assert`): el primero es el modo de producción (contenido totalmente
resuelto); el segundo es un modo "geometría cruda" nuevo, sin dependencia de
datos, que dibuja cada elemento como una etiqueta de tipo + icono genérico —
necesario para que el editor pueda mostrar un estado inválido a mitad de
edición sin crashear (ver más abajo). `MetricBoardRenderer.build()` quedó
reducido a resolver contenido y delegar en `CellLayoutCanvas`; no hay
segunda implementación de geometría en ningún lado del código.

Un detalle de compatibilidad: la clave de cada elemento de texto se
preservó exactamente en su formato legacy
(`'metric-$itemIdForKeys-${e.type.name}'`) en vez de migrarla a un formato
basado en el id del elemento, porque `test/board_geometry_test.dart` la
hardcodea. Cambiarla habría sido una regresión cosmética sin ningún
beneficio funcional.

## `CellLayoutPresetCatalog`: catálogo local en memoria

`lib/cell_layout_presets/cell_layout_preset_catalog.dart` es un
`ChangeNotifier` que envuelve una lista mutable de `CellLayoutPreset`,
sembrada desde los 7 presets de `initialCellLayoutCatalog` (N4). Expone
`create`/`duplicate`/`rename`/`update`/`delete`, todo en memoria — ningún
método toca Firestore. `duplicate(id)` construye una copia bajo un id nuevo
reusando la lista de `elements` original: como el constructor de
`CellLayoutPreset` ya congela esa lista en una copia inmutable (invariante
de N4), ninguna edición posterior a la copia puede alcanzar el original —
se verificó explícitamente con un test que edita la copia y confirma que
`widthUnits` del original no cambia. `delete` exige un callback
`isReferenced(id)` provisto por el llamador (el catálogo deliberadamente no
sabe nada de `Board`/`BoardPreset`) y lo bloquea si retorna `true`. Un
singleton a nivel de módulo, `sharedCellLayoutPresetCatalog`, es el que usa
el Board Editor en producción, para que un diseño creado o editado en el
editor (empujado con `Navigator.push`) sea visible al volver — el
`CellLayoutCatalog get _presets` del Board Editor reconstruye un snapshot
fresco desde `sharedCellLayoutPresetCatalog.presets` en cada acceso, en vez
de usar el catálogo estático viejo.

## El editor visual (`CellLayoutEditorPage`)

`lib/cell_layout_presets/cell_layout_editor_page.dart` es la pieza central
de N6.3. Se abre desde el Board Editor (`_openCellLayoutEditor`, en
`board_editor_page.dart`) con el preset actualmente asignado al item
seleccionado (o el default por span si no hay ninguno). Todo el estado de
edición vive en `_elements` (una `List<CellLayoutElement>` mutable local);
"Guardar" es lo único que empuja ese estado al catálogo compartido.

**Selección y movimiento.** Tocar un elemento en la subgrilla lo selecciona
(borde cian). El panel de propiedades ofrece 4 flechas (arriba/abajo/
izquierda/derecha, cada una mueve 1 unidad interna) más un `FilterChip`
"Mover con clic": activado, el próximo tap sobre una celda interna
reposiciona el elemento seleccionado a esa celda (reutilizando el mismo
patrón de "Mover con clic" que el Board Editor ya tenía a nivel de items).

**Resize, alineación, sizeRole, visibilidad.** Steppers discretos de
ancho/alto (`cell-editor-width-±`/`cell-editor-height-±`), dropdowns de
alineación horizontal/vertical (`CellHorizontalAlignment`/
`CellVerticalAlignment`, el enum de N5.2), un dropdown de `sizeRole`
(`CellSizeRole`) y un switch de visibilidad. Ocultar un elemento
(`CellVisibility.hidden`) no lo borra de `_elements` — sigue existiendo,
solo deja de tener representación visual en el canvas — un test dedicado
confirma que alternar el switch dos veces hace desaparecer y reaparecer el
elemento sin perder su configuración.

**Propiedades por tipo (§13).** Para `value`/`label`/`unit` aparece además
una sección "Texto" con peso de fuente (`CellFontWeight`) y máximo de
líneas. Para `indicator` aparece el número de slot ordinal (solo lectura,
lo gestiona la sección de abajo, nunca se edita a mano).

**Indicator slots dinámicos.** Un panel separado (`cell-editor-
indicator-slots-panel`) muestra la cuenta actual y dos botones: "Agregar
slot" añade un `CellLayoutElement` tipo `indicator` con
`indicatorSlot: nextSlot` (el largo actual de la lista de indicadores,
preservando contigüidad 0..n-1); "Quitar último slot" retira el de mayor
`indicatorSlot`, nunca uno arbitrario — así la lista nunca queda con huecos
ordinales. Un preset recién creado con "Crear desde default" ya trae 3
slots (la misma composición de los presets semilla), así que el primer
click de "Agregar slot" lleva a 4, no a 1.

**Sin crashear, permitir reparar (§9).** La validación de bounds/colisión
reusa `CellLayoutValidator.collisions`/`fitsWithin` (N4) directamente —
nunca se reimplementó nada. Cuando el estado actual tiene algún elemento
inválido, `_canvasPanel()` no intenta resolver contenido real: pasa
`rawElements` a `CellLayoutCanvas` en vez de `resolved`, así que el canvas
sigue siendo interactivo (se puede seguir seleccionando/moviendo elementos
para reparar) aunque la composición sea momentáneamente inválida. Un panel
rojo (`cell-editor-issues`) lista cada issue con su mensaje. Nunca se
lanza una excepción hacia la UI: `CellContentResolver.resolve` solo se
llama dentro de un `try/catch` con fallback a `rawElements`. Un test
dedicado (`'a collision shows an error visually and never crashes, and can
be repaired'`) mueve un elemento hasta colisionar, confirma que no hay
excepción y que aparece el mensaje `internal_collision`, y después revierte
el movimiento y confirma que el panel de issues desaparece.

**Preview con métrica demo (§15).** El canvas usa siempre la misma métrica
de referencia — "Temperatura interior · 24.6 · °C", con una leyenda visible
que aclara que no pertenece a un Device real — nunca datos reales ni un
renderer paralelo: es literalmente `CellLayoutCanvas`, el mismo widget que
usa `MetricBoardRenderer` en producción.

**No modificar presets globales por accidente (§3).** Al abrir un preset
que es semilla global (`catalog.isSeedGlobal`) o que el llamador marca como
referenciado (`isReferenced`), el header muestra una advertencia con dos
botones: "Duplicar diseño de celda" (crea la copia y pasa a editarla
directamente) y "Editar igual" (permite editar el original, solo si el
usuario lo confirma explícitamente). El botón "Guardar" queda deshabilitado
mientras no se haya elegido una de las dos opciones.

Un bug real se encontró y corrigió durante esta etapa: `_save()`, `_reset()`
y el cálculo de `isGlobal` del header usaban `widget.presetId` — el id con
el que se **abrió** la página — en vez de `_pristine.id` — el id
**actualmente activo** (que cambia a la copia después de "Duplicar diseño
de celda"). El efecto práctico: guardar después de duplicar escribía sobre
el preset global original (silenciosamente, vía `CellLayoutPresetCatalog
._replace`, que hace no-op si el id no existe pero SÍ existe para los 7
presets semilla) y además revertía `_pristine` de vuelta al original,
haciendo que "Volver al Board" devolviera el id equivocado — exactamente la
falla que el prompt marca como criterio de "no hecho" ("editar una copia
modifica el original"). Se detectó con el test de integración de extremo a
extremo (duplicar → mover → guardar → volver al Board → verificar
`cellLayoutPresetId` en el item real), no con los tests unitarios de la
página sola, que nunca ejercitan el ciclo completo con un preset semilla.
Corregido apuntando los tres sitios a `_pristine.id`.

## Nomenclatura (§19)

"Preset" a secas nunca refiere ambigüamente a dos conceptos distintos:
`BoardPreset` se nombra siempre "Preset de tablero" y `CellLayoutPreset`
siempre "Diseño de celda", tanto en el Board Editor (`'Preset de tablero:
...'` en el header de modo BoardPreset, ya eran así desde N6.2) como en el
editor nuevo (título "Diseño de celda", botón "Duplicar diseño de celda",
etc). Los tests que verificaban la cadena vieja `'Preset: Maternidad
estándar'` se actualizaron a `'Preset de tablero: Maternidad estándar'`.

## Helpers de UI: imágenes y catálogos de referencia (§20/§21)

El editor de `ImageBoardContent` (antes un simple `TextField` de
`sourceRef`) ahora tiene: un dropdown de `sourceType` con etiquetas humanas
(`imageSourceTypeLabel`), un label dinámico para `sourceRef` según el tipo
elegido (`imageSourceRefLabel` — por ejemplo "URL" vs "Ruta de asset") y un
texto explicativo del comportamiento de `fit` (`imageFitHelp`). En modo
BoardPreset, el editor de contenido `metric` agrega dos textos de ayuda
nuevos: uno arriba del dropdown de `metricKey` ("Catálogo de métricas de
referencia" + disclaimer de que es un catálogo de referencia, no el
catálogo real del Device) y otro arriba de la lista de indicadores
("Indicadores disponibles para esta métrica" + explicación). Ninguno de los
dos aparece en modo Board normal — son específicos del contexto
BoardPreset, que es donde la ambigüedad "esto es de referencia, no datos
reales" importa.

## UX lateral del Board Editor (§16/§17/§18)

En desktop (`LayoutBuilder` con breakpoint en 900px), el body pasa de una
columna única a un `Row`: el board a la izquierda (`flex` variable) y un
panel lateral fijo de 380px a la derecha (`editor-side-panel`), con 3
chips de tab (`editor-side-tab-board/selected/add`) que muestran
exactamente uno de "Items del Board", el panel del item seleccionado o el
formulario de alta — nunca dos a la vez. Por debajo de 900px, el mismo
contenido se apila en `Column` (board arriba, panel debajo) — layout
`editor-layout-narrow`. La geometría del renderer del board en sí (`
BoardEditorCanvas`) no se tocó en absoluto; solo cambia qué hay alrededor.

Seleccionar un item en el board cambia automáticamente el tab activo a
"Seleccionado" (rastreado con `_lastAutoTabSelectedId` para no repetir el
salto en cada rebuild); "Reset" deliberadamente NO fuerza ningún cambio de
tab — deja al usuario donde estaba, solo limpia el estado efímero
subyacente (igual que R3 de N6.2).

Achicar el panel a 380px (y, en el header de ancho completo, probar un
viewport realmente angosto como 500px) expuso una clase entera de bugs de
overflow en `DropdownButton`/`Row` que nunca se habían disparado con el
layout de ~1200px de ancho de antes. Se corrigieron sistemáticamente ~7
sitios distintos con el patrón `Expanded` + `isExpanded: true` +
`TextOverflow.ellipsis` (o `SizedBox(width: double.infinity)` para
dropdowns fuera de un `Row`), incluyendo el selector de `LayoutTemplate`
del header, que solo se manifestaba en el viewport angosto de los tests
nuevos, no en desktop.

## Bug real encontrado en N4.5 (no es N6.3, pero N6.3 lo expuso)

`BoardContentValidator.validate()` (N4.5) delega en
`CellLayoutValidator.validate()` para cada item de tipo `metric`, y hasta
ahora reenviaba sus issues sin retocar el `itemId`. El problema:
`internal_collision`/`internal_out_of_bounds` llevan como `itemId`/
`relatedItemId` el id del **elemento de celda** (`'value'`, `'unit'`,
`'indicator-2'`, ...) — nunca el id del item real del board, porque N4 no
tiene ningún concepto de "board". Mientras nadie podía crear un
`CellLayoutPreset` genuinamente roto, esta rama nunca se ejercitaba. N6.3
sí puede crear uno (moviendo elementos hasta colisionar y guardando así) y
aplicarlo a un item real, lo que expuso dos síntomas a la vez: (a) el board
real lanzaba `LayoutValidationException` sin capturar dentro de
`MetricBoardRenderer` (el id que traía el issue no coincidía con ningún
item real, así que el path de reparación del Board Editor no lo detectaba
como perteneciente a ese item); (b) el panel de issues del Board Editor
podía generar claves duplicadas si dos items distintos tenían el mismo
`itemId` de elemento roto (por ejemplo `'value'` en dos presets distintos).
La rama vecina, `catch (LayoutValidationException)` en la misma función,
YA hacía el remapeo correcto (`itemId: item.id`) — la omisión estaba solo
en el camino feliz (sin excepción), una asimetría que delata que fue un
descuido, no una decisión. Se corrigió reetiquetando cada issue devuelto:
si `issue.itemId` no coincide con el id del item de métrica, se reemplaza
por el id real del item del board y el id de elemento original se preserva
en el texto del mensaje (`'... (value ↔ unit)'`). Se endureció además la
clave del panel de issues del Board Editor con un índice de lista
(`'editor-issue-$i-...'`) para unicidad incondicional, independiente de
cualquier colisión de ids futura. Verificado con `dart analyze` limpio y
`test/board_content_test.dart` (39/39) sin cambios de comportamiento.

## Tests

- `test/cell_layout_editor_smoke_test.dart` (2): render + selección básica.
- `test/cell_layout_preset_catalog_test.dart` (8): semilla, create, duplicate
  + independencia estructural, rename, update (bump de versión),
  `availableForSpan`, delete bloqueado/permitido, unicidad de ids.
- `test/cell_layout_editor_page_test.dart` (12): gate de edición directa
  para preset global, duplicar cambia a edición directa, preset local edita
  directo, mover con flechas, resize, colisión (mostrar + reparar sin
  crash), resize fuera de bounds, alineación, sizeRole, visibilidad,
  agregar/quitar indicator slot, confirmación de descarte al volver atrás
  con cambios sin guardar.
- `test/board_editor_test.dart`: ~36 tests existentes ajustados a la
  semántica de un solo tab activo a la vez (se agregaron helpers
  `openAgregarTab`/`openBoardTab`); 6 tests nuevos de UX lateral (layout
  desktop/narrow, tabs mutuamente exclusivos, auto-switch al seleccionar,
  "Mover con clic" dentro del panel); 1 test de integración extremo a
  extremo ("Editar diseño" abre el editor, duplicar, mover, guardar, volver
  al Board, y el item real queda con el nuevo `cellLayoutPresetId`) — este
  último fue el que expuso tanto el bug de `_pristine.id` como el bug de
  N4.5 descriptos arriba; 1 test más de integración con modo BoardPreset
  (§10 de §30 — "integración con Preset de tablero"): crea un
  `BoardPreset`, agrega un item métrico, lo selecciona y abre su editor de
  diseño de celda desde ahí, confirmando que `_openCellLayoutEditor`/
  `_metricEditor` son el mismo código compartido que en modo fixture (sin
  ningún `if (_presetMode)` especial) y que por lo tanto ya funcionaban en
  ambos modos sin cambios adicionales.
- `test/board_presets_page_test.dart`: 2 sitios ajustados a la navegación
  por tabs; nomenclatura "Preset de tablero" actualizada.

Suite completa: 946 tests, 0 fallas (1 skip preexistente no relacionado).

## Verificación manual en Chrome

Se agregó temporalmente una ruta de depuración (`?mode=editor` →
`BoardEditorPage(isOwner: true)` directo, sin login) a `lib/main.dart`
únicamente para poder navegar con CDP sin flujo de autenticación; se
revirtió por completo antes del build final (confirmado con `git diff` —
sin rastro). Con esa ruta y un servidor local sirviendo `build/web`, se
recorrieron los 20 pasos del prompt vía Chrome headless + CDP: seleccionar
un item 2×1 con preset global, abrir el editor, ver el gate de "Duplicar
diseño de celda", duplicar, mover el elemento `value` (con flechas y con
"Mover con clic"), ver una colisión real renderizada de forma segura (modo
crudo, sin crash) y repararla, agregar/quitar un indicator slot, guardar,
volver al Board y confirmar que el item real quedó apuntando al nuevo
diseño duplicado; por separado, cambiar un item 1×1 al preset "Icono y
valor 1×1", abrir su editor, duplicar y mover el elemento `icon`; y
finalmente recargar en un viewport de 480px para confirmar el layout
apilado (board arriba, panel de tabs debajo) sin overflow. Se capturaron 8
screenshots (más una de bonus mostrando la colisión/reparación en vivo).

## Exclusiones confirmadas (§28)

Sin Firestore (`grep` de `cloud_firestore`/`FirebaseFirestore` en todos los
archivos nuevos: ningún resultado), sin Device real (la única métrica que
alimenta el editor es la demo fija "Temperatura interior"), sin selector de
Tenant/Site/Device, sin drag & drop (todo el movimiento es por flechas o
por "Mover con clic", nunca gestos de arrastre), sin persistencia remota
(`CellLayoutPresetCatalog` es puramente en memoria, se pierde al recargar),
sin switch productivo tocado (`lib/main.dart` termina esta etapa
bit-a-bit idéntico a como empezó, salvo cambios preexistentes no
relacionados con N6.3 de otra tarea en curso).
