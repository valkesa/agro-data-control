# N4 — CellLayoutPreset: composición de celdas métricas

## Modelos y semántica

`CellLayoutPreset`: id, name, widthCells, heightCells, schemaVersion=1,
presetVersion positivo, enabled, elements inmutables y fechas opcionales.
No contiene métricas concretas, valores actuales, fuentes de datos, identidad
de negocio o ubicación externa. No duplica internalColumns/internalRows.

`CellLayoutElement`: id, type, InternalGridPlacement, indicatorSlot opcional,
horizontalAlignment, verticalAlignment y textStyle opcionales.
El type cumple el papel de sourceRef semántico, sin strings arbitrarios:
label → MetricDefinition.label; unit → unit; icon → icon; value → pendiente de
resolución N5; indicator → indicatorKeys[indicatorSlot] del item N3.
No se admite sourceRef de negocio ni se copia un asset específico.

Tipos N4: label, value, unit, icon, indicator. Se permiten repeticiones de todos
los tipos si sus IDs son distintos, sin colisión; no se presupone una composición
única. Los tipos están serializados por nombre estable, nunca ordinal de enum.
Agregar tipos futuros requerirá extender el enum, su semántica y resolver;
los nombres actuales se conservarán. Los lectores antiguos rechazan tipos
no soportados explícitamente, sin reinterpretarlos. Se prueba extensibilidad
mediante un preset futuro 3×2 y una métrica energyConsumption, sin branches por Device.

Alineaciones: horizontal start/center/end; vertical top/center/bottom.
null significa heredar la política del renderer futuro, sin offsets.
CellTextStyle: fontRole label/primaryValue/unit/secondary; weight
normal/medium/bold; maxLines positivo. No admite píxeles. El estilo de texto
solo aplica a label/value/unit. Los presets iniciales usan alineación center.

## Geometría y resolución N1

InternalGridPlacement tiene x/y no negativos, widthUnits/heightUnits positivos.
Sus bounds se comprueban contra el span del preset y la resolución del
LayoutTemplate entregado. Se reutilizan los cálculos GridPlacement N1, sin
copiar el número 8 en fórmulas N4. El catálogo inicial usa la constante central
de N1 al construir sus coordenadas, y persiste solo esas coordenadas.

1×1 → 8×8; 2×1 → 16×8; 1×2 → 8×16; 2×2 → 16×16; 3×2 → 24×16.
Una resolución por eje distinta se respeta al validar. No se escalan las
coordenadas automáticamente: una grilla menor puede invalidar un preset;
una mayor puede dejar espacio libre. La integración futura deberá fijar el
contexto N1 o versionar/migrar los presets al cambiar resolución.

`CellLayoutValidator.overlaps` compara rectángulos semiabiertos en unidades
internas; colisión parcial, total o contención es inválida. Bordes y esquinas
adyacentes son válidos. `collisions` compara cada par una vez: O(n²) en tiempo,
sin matriz de ocupación; hasta O(n²) issues en el peor caso. Se ofrece como
función central reutilizable para esta primitiva, sin convertir unidades
internas en celdas externas limitadas por N1.

## Slots y compatibilidad con N3

Los indicatorSlot son enteros únicos, contiguos desde cero. Solo type indicator
puede declararlos y todo indicator debe tener uno. Esto evita huecos que harían
incorrecta una validación basada únicamente en cantidad de slots.
N3 selecciona keys; N4 nunca nombra calefacción, humedad u otro indicador de
negocio en el preset. Más keys que slots: inválido. Menos keys: slots vacíos,
sin corrimiento ni reordenamiento. La repetición visual de un mismo slot no se
admite en N4; requeriría un contrato futuro explícito.

`CellLayoutValidator.validate(preset,item,template)` comprueba coincidencia de
ID explícito, span, enabled, bounds externos, bounds internos, colisiones y
capacidad de slots. IDs, tipos, versiones y topología de slots ya se validan
al construir los modelos inmutables. Devuelve issues inmutables del contrato
LayoutValidationIssue N3. Las referencias de un issue interno identifican IDs
de elementos; los issues de compatibilidad identifican el item N3.

Códigos principales: cell_preset_mismatch, cell_preset_disabled,
cell_span_mismatch, placement_out_of_bounds, preset_out_of_bounds,
internal_out_of_bounds, internal_collision, insufficient_indicator_slots.
La estructura usa LayoutValidationException/ArgumentError y los helpers
estrictos de N3 para tipos, campos desconocidos y fechas; no modifica N3.

N3 debe validarse primero contra su catálogo efectivo. N4 no recibe el catálogo
completo y no reemplaza la verificación semántica de keys/indicadores N3.
Deserializar no prueba compatibilidad contextual; siempre validar antes de usar.

## Catálogo y defaults

Catálogo local inmutable de seis presets:

- default_1x1, default_2x1, default_1x2, default_2x2.
- icon_value_1x1, icon_value_2x1.

Todos tienen label, value, unit y tres slots a la derecha. Las variantes agregan
el icono a la izquierda del label. El valor usa el área central y unit la franja
inferior; los rectángulos no se superponen. No son presets de temperatura,
laboratorio ni Arco. CellLayoutCatalog valida IDs únicos y el mapa inmutable
de defaults: cada entrada debe corresponder a un preset existente, habilitado
y del span indicado.

`resolve(item)`: si hay ID explícito, buscarlo exactamente; si es null, buscar
default por widthCells×heightCells. No se elige por metricKey ni se hace fallback
silencioso para un ID desconocido o span sin default. Se lanza cell_preset_not_found.
Un preset explícito encontrado aún debe validarse: el lookup no certifica compatibilidad.

El fixture de Laboratorio N3 usa 3×1, fuera del catálogo inicial mínimo N4.
Queda sin default deliberadamente y no se modifica ese fixture; se deberá
agregar un preset 3×1 antes de integrarlo en N5. Es extensibilidad por datos,
no una limitación del modelo ni una selección por Device.

## Resolver puro

CellContentResolver.resolve(metric,item,preset,template:...) valida identidad
de métrica y compatibilidad geométrica antes de resolver. El contexto N1 se
agrega como argumento requerido para no producir contenido con bounds inválidos.
Produce List<ResolvedCellElement> inmutable con definición visual, text,
iconRef, indicatorKey y valuePending. El valor real queda pendiente, sin
placeholder inventado de telemetría. Un slot sobrante tiene indicatorKey=null
y emptyIndicator=true. No lee snapshots, Firestore, imágenes ni widgets.
Ante incompatibilidad lanza el primer issue; la UI futura puede usar primero
el validator para mostrar la lista completa.

## Serialización y persistencia

Preset, elemento, placement y estilo tienen toMap/fromMap compatibles con JSON.
Schema/version viven en el agregado preset; los hijos siguen ese contrato.
Campos requeridos exigen tipos exactos, enums por nombre soportado; no hay
coerciones numéricas. Campos desconocidos se rechazan en todos los niveles.
Fechas son opcionales, DateTime o ISO-8601 UTC canónico; toMap emite UTC o null.
Los campos opcionales de elemento pueden omitirse. No se guardan valores derivados.

Path global futuro: cellLayoutPresets/{presetId}. Describe composición visual
reutilizable, no contenido tenant-scoped. Sin repositorios, SDKs, reglas,
listeners, semillas remotas, escrituras ni deploy en N4.

## N4.5, N5 y UI N7/N8

N4 es solo composición de celdas métricas. image, table, latestEvent y chart no
son CellElementType. N4.5 deberá modelarlos como tipos de contenido de Board
con contratos propios. La futura variante métrica de DeviceBoardLayoutItem
podrá conservar la referencia a este preset sin cambiar su significado.

N5 resolverá valores/formato desde N2 y dibujará las unidades proporcionalmente.
N7/N8 podrán filtrar presets habilitados por span, mostrar preview con contenido
semántico, visualizar subgrilla y editar placements con drag/drop. Cada cambio
se validará contra límites y colisiones antes de aceptarse. No se implementó
ninguna de esas UIs ni un renderer productivo en N4.

## Compatibilidad

Solo archivos nuevos. Sin cambios N1–N3, TABLERO, TABLA, renderers, navegación,
backend, PLC, Alertas, Cerdas ni Firestore. El informe HTML registra los tests,
análisis, build web y comprobación de archivos contra el estado inicial.
