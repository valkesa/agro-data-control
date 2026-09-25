# Etapa N1 — Geometría independiente

El modelo actual `DeviceTemplate` reúne geometría y contenido. Se conserva en
producción. La arquitectura nueva se agrega en `lib/layout_templates/`, sin
importaciones desde la aplicación, servicios, renderers o catálogo legacy.

## Contratos

- `LayoutTemplate`: geometría externa N columnas × M filas, identidad y nombre
  del layout, versiones, habilitación, fechas y resolución interna por eje.
- `GridPlacement`: origen cero `(x, y)` y span `(widthCells, heightCells)`.
  Valida dimensiones al construir; `validateWithin(layout)` valida pertenencia
  a una grilla concreta. `fitsWithin` permite consultar sin lanzar excepciones.
- `DeviceMetricCatalog` (futuro N2): métricas/capacidades disponibles.
- `DeviceBoardLayout` (futuro N3): selección y ubicación del contenido mediante
  placements; deberá validar todas sus ubicaciones contra el layout referenciado.
- `CellLayoutPreset` (futuro): distribución interna del contenido.

N1 no define solapamientos entre placements: la política corresponderá a N3.
No contiene métricas, sourceField, indicadores, alarmas ni referencias a Device,
Tenant o Site. No crea un renderer ni conecta persistencia.

## Subgrilla y evolución

La resolución inicial centralizada es 8 por eje. Cada template serializa
`internalUnitsPerCellX` y `internalUnitsPerCellY`. Para un placement válido:

```
internalColumns = widthCells * layout.internalUnitsPerCellX
internalRows = heightCells * layout.internalUnitsPerCellY
```

Así, 1×1 → 8×8; 2×1 → 16×8; 1×2 → 8×16; 2×2 → 16×16; 3×2 → 24×16.
Los métodos de cálculo también verifican que el placement entre en el layout.
Los lectores exigen las resoluciones persistidas; un cambio de defaults no
reinterpreta datos guardados. `schemaVersion=1` identifica el contrato soportado;
versiones desconocidas se rechazan. `templateVersion` es un entero positivo para
revisiones del layout. Una resolución distinta puede almacenarse por eje sin
cambiar el esquema; cambiarla para contenido existente requerirá una migración
explícita en etapas posteriores, nunca una reinterpretación silenciosa.

## Catálogo y límites técnicos

`initialLayoutTemplateCatalog` contiene `grid_6x1`, `grid_6x2`, `grid_6x3` y
`grid_6x4`, con nombres `6 × 1` a `6 × 4`. Es inmutable y rechaza IDs duplicados,
incluyendo variantes con espacios alrededor. La búsqueda por ID incluye entradas
deshabilitadas: `enabled` se conserva como dato, sin política de UI en N1.
Las dimensiones son datos: 7×4, 8×4 y 10×5 usan exactamente el mismo contrato.

Se admiten hasta 1024 celdas por eje, 65536 celdas externas en total y 1024
unidades internas por celda/eje. Son protecciones técnicas ante dimensiones
accidentales y futuras asignaciones excesivas en editores/renderers, no presets
ni restricciones de seis columnas. No se materializa ninguna matriz en N1.
Se validan identidad/nombre no vacíos, versiones, dimensiones y spans con
`ArgumentError` también en release (sin depender de asserts).

## Serialización y persistencia futura

`toMap` produce datos compatibles con JSON y fechas UTC ISO-8601 canónicas o
null. `fromMap` exige tipos correctos, campos de versión y resolución; no trunca
decimales ni convierte strings numéricos. Acepta fechas `DateTime` o el formato
canónico emitido por `toMap`; rechaza fechas inválidas. Las fechas son opcionales.
Campos adicionales desconocidos se ignoran; no se preservan al volver a guardar.

Path futuro: `layoutTemplates/{layoutTemplateId}`, global. El futuro adaptador
Firestore convertirá `Timestamp` en la frontera de persistencia y verificará
correspondencia con el ID documental. No se agregan SDKs, repositorios, reglas,
seed remoto ni escrituras de producción en N1.

## Título y separación de vistas

El título de Card pertenece al Device. `LayoutTemplate.name` es únicamente el
nombre del layout dentro del catálogo; **no es el título de Card**.
La futura configuración concreta del Device incluirá `showTitle: bool` y
`titleOverride: String?`. Cuando `showTitle` sea verdadero, se mostrará
`titleOverride ?? device.name`. Estos campos no se implementan en N1.

El layout externo es para el futuro TABLERO. TABLA tendrá configuración propia
de columnas; ambas vistas podrán compartir la identidad `device.name`.
La migración deberá ser explícita en etapas posteriores. Los templates actuales
y ambos renderers siguen usando sus contratos existentes.

## Verificación

`test/layout_templates_test.dart` cubre catálogo, grillas futuras, bordes, spans,
subgrillas, resolución alternativa persistida, round trips de Map/JSON, tipos
inválidos, versiones no soportadas, duplicados y límites técnicos.
El informe HTML de N1 registra los resultados reales de las herramientas.
