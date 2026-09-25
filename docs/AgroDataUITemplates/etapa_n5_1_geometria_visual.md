# N5.1 · Geometría visual

El nuevo preview usa `BoardRenderConfig(designWidth: 840)`. Es configuración de runtime,
no un campo persistido de N1. Para cada layout: `cellSize = designWidth / columns`;
el alto y el ancho de cada celda son iguales. Se eliminó `cellAspectRatio`.

El renderer calcula `scale = min(1, availableWidth / designWidth)`, centra un canvas
lógico de ancho fijo y lo dibuja mediante un único `FittedBox(scaleDown)`. Se escala
la composición completa, incluido el título. En desktop no se amplía. No hay scroll
horizontal; se conserva el scroll vertical de la página.

Las cards decoran el canvas desde una capa de fondo: sus bordes y separaciones no
restan unidades al contenido. Las métricas usan una única medida de unidad interna:
`min(width / internalColumns, height / internalRows)`. Con N1 8×8 por celda, la
subgrilla ocupa exactamente el canvas lógico. Si N1 configura densidades distintas
por eje, se centra la subgrilla conservando sus unidades cuadradas.

## Presets de esquema 2

Cada elemento agrega `visibility: visible | hidden` y
`sizeRole: xs | sm | md | lg | xl | xxl`. Son campos obligatorios en JSON v2.
La lectura de v1 migra en memoria a v2: todos los elementos visibles y roles
semánticos equivalentes según tipo/fontRole. Se conservan posiciones, versión del
preset, fechas y referencias. No hay escritura automática a ningún repositorio.
El constructor nuevo y la serialización usan esquema 2; versiones futuras y
campos desconocidos se rechazan.

Los elementos ocultos no se dibujan, pero siguen reservando sus placements y slots
ordinales en la validación: ocultar slot 0 no desplaza las keys de slots 1 y 2.
Los tamaños efectivos viven en `BoardRenderConfig.elementSize` y son múltiplos de
la unidad interna: xs 0.6, sm 0.75, md 1, lg 1.5, xl 2, xxl 3. Para 6 columnas,
840 de ancho y densidad 8, cada unidad mide 17.5 lógicos. No hay píxeles persistidos.

`MetricBoardRenderer` resuelve contenido y aplica placements, visibilidad,
alineación, tamaño y estilo. `fontRole` distingue la jerarquía cromática;
`sizeRole` controla el tamaño. `weight` y `maxLines` se respetan. Texto de una línea
reduce su tamaño si no entra; texto multilineal dispone del ancho del placement
para envolver y luego se ajusta a su caja. Iconos e indicadores usan la misma escala.
No hay ramas de composición por métrica, device, tenant ni span.

## Catálogo revisado

Los siete presets iniciales pasan a `presetVersion: 2`.
- 1×1: label superior, valor xl, unidad separada y slots compactos a la derecha.
- 2×1 y 3×1: valor xxl con mayor alto útil; unidad a su derecha en otra región.
- 1×2: valor xl y slots separados verticalmente.
- 2×2: label md, valor xxl y unidad inferior; tres slots agrupados a la derecha.
- icon_value 1×1 y 2×1: región propia de icono junto al label y tamaño md.

Sala principal utiliza el mismo default_2x2 genérico. Arco conserva el contrato de
contenido y todos sus spans (4×4, 2×1, 6×1, 6×2). Laboratorio conserva dos cards 3×1.
El modo grilla muestra designWidth, cellSize y scale. Se mantienen los selectores,
la comparación con legacy y la restricción owner del preview.

## Validación

`board_geometry_test.dart` cubre las cinco proporciones externas, unidades internas
cuadradas, transformación física en 1440/1100/390, centrado, configuración runtime,
visibilidad y roles para los cinco tipos de elemento, alineaciones, estilos,
migración v1, lectura estricta v2 y ausencia de ramas de negocio.
Se actualizaron las expectativas geométricas de N5 y de versión de N4.

Resultados y capturas de Chrome: `no_git/informes_de_codigo/informe_etapa_n5_1_geometria_visual.html`.
TABLERO productivo y el backend permanecen sin cambios de esta etapa. No se agregan
lecturas Firestore, polling, persistencia ni asignaciones reales.
