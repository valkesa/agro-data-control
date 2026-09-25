# Etapa N3 — DeviceBoardLayout

## Contrato y responsabilidades

`lib/device_board_layouts/` agrega configuración local independiente de widgets.
`DeviceBoardLayout` contiene deviceId, layoutTemplateId, showTitle, titleOverride,
schemaVersion (1), layoutVersion (positivo), items, createdAt y updatedAt opcionales.
No copia columns/rows ni el nombre del Device. `resolveTitle(deviceName)` devuelve
null si showTitle es false y, en caso contrario, titleOverride ?? deviceName.
Un override vacío o de solo espacios es inválido aun con showTitle=false.

`DeviceBoardLayoutItem` contiene id, metricKey, GridPlacement de N1,
cellLayoutPresetId opcional e indicatorKeys. No duplica ningún campo de formato,
fuente o significado de MetricDefinition. Usa celdas externas, nunca píxeles.
Las listas son copias inmutables; toMap devuelve contenedores independientes.
Una misma métrica puede aparecer varias veces, con IDs distintos y sin colisión.
Un layout sin items es válido como configuración vacía.

## Validación obligatoria antes de consumir

Hay dos niveles explícitos:

1. Constructores/fromMap validan estructura: tipos, IDs no vacíos, versión,
   título, preset opcional y primitivas geométricas N1.
2. `DeviceBoardLayoutValidator.validate(board, template, effectiveCatalog)`
   devuelve una lista inmutable de issues. Una lista vacía indica validez.
   Comprueba referencia de template, habilitación, métricas, bounds, IDs únicos,
   indicadores disponibles para esa métrica, duplicados de indicadores y colisiones.

El parser puede cargar un borrador semánticamente inválido para diagnosticarlo.
**La deserialización no autoriza renderizar o persistir: siempre validar contra
N1 y el catálogo efectivo N2 antes de usar la configuración.** No se borran,
reacomodan ni reparan items automáticamente. Si cambian capacidades o dimensiones,
volver a validar. N2 no contiene deviceId: quien resuelva el binding futuro debe
entregar el catálogo efectivo del Device correcto y verificar el deviceId del doc.

Las versiones y el título ya son invariantes de los modelos inmutables al llegar
al validator. El template N1 y catálogo N2 también validan sus propias versiones.
El layout no fija revisiones de sus dependencias; se valida contra las entregadas.
Antes de persistencia productiva deberá definirse una política de revisión/migración.

## Issues

`LayoutValidationIssue`: code, message, itemId?, metricKey?, relatedItemId?.
Los códigos semánticos son metric_not_found, placement_out_of_bounds,
placement_collision, indicator_not_available, duplicate_indicator_key,
duplicate_item_id, layout_template_mismatch y layout_template_disabled.
relatedItemId identifica al segundo participante de una colisión.

Errores estructurales N3 lanzan `LayoutValidationException extends ArgumentError`
con una lista inmutable issues: unsupported_schema_version, invalid_layout_version,
invalid_title_override, unknown_field e invalid_string/integer/boolean/list/map/date.
Las dimensiones estructurales inválidas de GridPlacement conservan los
ArgumentError de N1. No se sustituyó ni duplicó su validación.

## Colisiones y subgrilla

La función central `placementsOverlap(a,b)` usa rectángulos semiabiertos:

```
a.x < b.x + b.widthCells && b.x < a.x + a.widthCells &&
a.y < b.y + b.heightCells && b.y < a.y + a.heightCells
```

Bordes y esquinas adyacentes son válidos. `collisions(items)` compara cada par
una sola vez: O(n²) en tiempo, sin materializar una matriz por celda. La memoria
para issues depende de los pares en conflicto (hasta O(n²)); la geometría de cada
comparación usa espacio constante. Es apropiado para configuraciones de cards;
un editor futuro de gran escala podrá optimizarlo sin cambiar el contrato.
No existen ramas por tenant, Device o cantidad de columnas.

Los métodos internalColumns(template) e internalRows(template) delegan en N1:
span × internalUnitsPerCellX/Y. No se serializan los resultados. 1×1 → 8×8;
2×1 → 16×8; 1×2 → 8×16; 2×2 → 16×16; 3×2 → 24×16. Se respeta también una
resolución persistida distinta por eje. N1 valida bounds durante el cálculo.

## Indicadores y N4

indicatorKeys selecciona solo indicadores presentes en
catalog.availableIndicators[metricKey], sin repetidos. No guarda posiciones.
cellLayoutPresetId es una referencia opaca, opcional y no vacía si existe.
N3 no verifica que ese preset exista: el catálogo se definirá en N4. null
significará un default compatible con el span; N3 no inventa ese default.

N4 deberá resolver presets, validar compatibilidad con la subgrilla derivada y
asignar composición/posiciones internas. No se implementan editor, drag & drop,
resize, presets de tamaño rígidos ni un nuevo renderer en N3. TABLA continúa
con configuración propia; estos items no la gobiernan.

## Serialización

Map/JSON versionados. Campos desconocidos se rechazan en board, item y placement,
incluyendo campos legacy de métricas, tabla, geometría redundante y deviceName.
Enteros y bool requieren tipos exactos, sin coerción ni truncamiento. Campos de
versión, identidad, items, showTitle, placement e indicatorKeys son requeridos
en el wire. Fechas, titleOverride y cellLayoutPresetId pueden omitirse o ser null.
Fechas se emiten como UTC ISO-8601 canónico; se aceptan ese formato y DateTime.
Se rechazan fechas normalizadas inválidas, locales sin zona o valores arbitrarios.

## Persistencia futura auditada

El código actual confirma Devices en `tenants/{tenantId}/devices/{deviceId}`:
`lib/firebase/firestore_paths.dart:100` define deviceDoc y
`lib/services/agro_device_service.dart:123` lo usa. El site es contexto del Device,
no un segmento entre tenant y devices en ese path.

Recomendación: `tenants/{tenantId}/devices/{deviceId}/ui/board` (documento board
en subcolección ui). Antes de conectar, verificar deviceId contra el padre,
resolver catálogo efectivo desde el Device, validar todo y definir reglas de
acceso/versiones y concurrencia. El tenant procede del contexto de persistencia;
no se duplica en el modelo. No se agregaron rutas, reglas, repositorios, seed ni
escrituras Firestore. La auditoría es del código local, sin lectura de producción.

## Referencias locales

`referenceBoardLayouts` combina explícitamente las tres piezas, usando IDs
sintéticos example-room, example-laboratory y example-disinfection:

- Sala: grid_6x4 + environment_room_v1. 13 items; temperatura principal 2×2,
  puertas 1×1, otras capacidades 2×1 o 1×1; tres indicadores de temperatura.
- Laboratorio: grid_6x1 + laboratory_v1. Temperatura y humedad 3×1 cada una.
- Arco: grid_6x1 + disinfection_arch_v1. Vehículos desinfectados, vehículos
  totales y nivel desinfectante 2×1 cada uno.

Los nombres Sala/Laboratorio/Arco son etiquetas del fixture, no títulos guardados
ni reglas del modelo. Todos usan preset null, showTitle=true y titleOverride=null.
Son ejemplos de expresividad, sin asignación automática a Devices productivos.

## Verificación y compatibilidad

El test nuevo cubre round trip, inmutabilidad, límites, rectángulos adyacentes,
colisión parcial/total/contención, todos los pares, grillas 6×4/8×4/10×5,
indicadores, referencias, cambios de catálogo, títulos, versiones, subgrillas,
campos inválidos y referencias locales. El informe HTML registra los resultados
reales de format/analyze/flutter test/flutter build web.

Solo se agregan archivos N3. Sin imports desde UI, cambios de N1/N2, navegación,
TABLERO, TABLA, renderers, backend, PLC, Alertas, Cerdas o Firestore; sin deploy.
