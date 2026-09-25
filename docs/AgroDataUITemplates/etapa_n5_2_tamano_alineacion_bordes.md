# N5.2 · Tamaño natural, alineación y bordes

`BoardRenderConfig.baseCellSize` reemplaza `designWidth` como configuración de runtime.
El valor elegido es 68 tras comparar capturas de 64, 68, 72 y 76 con legacy.

- Ancho natural = columnas × baseCellSize.
- Alto natural de la grilla = filas × baseCellSize (sin título/debug).
- Escala = min(1, ancho disponible / ancho natural).
- Un solo FittedBox(scaleDown), anclado topLeft, escala toda la composición.
- El wrapper de la página también se alinea a la izquierda.

Sala 6×4 mide 408×272 en desktop; Laboratorio 6×1, 408×68; Arco 6×7, 408×476.
La unidad N1 8×8 mide 8,5×8,5 antes de escalar. En viewport 390, el contenido
ofrece 358 y la escala es 358/408 = 0,87745. No existe una segunda escala mobile.

La comparación usa el área ocupada por cards legacy (aprox. 390×255), no el
contenedor legacy completo que se extiende por la página. El tamaño 68 aproxima
ese footprint y mejora ligeramente la lectura frente a 64. 72 y 76 agregan
superficie con poca ganancia en rótulos pequeños. Los labels/unidades de los
presets N5.1 siguen siendo pequeños: esta etapa no modifica sus roles ni placements.
En angosto, el nuevo entra completo; legacy conserva su scroll horizontal existente.

`BoardPreviewCard` centraliza fondo, recorte, borde y hover para los siete tipos.
`BoardCardTokens.boardCardBorder` usa #536074 y `boardCardBorderHover` #8190A5,
con espesor lógico 1. El borde se pinta en primer plano, visible también sobre
imágenes opacas. El recorte y el gutter no deflaten los constraints del contenido.
No se incorporó selección ni estado de alarma nuevo; los estados semánticos existentes
conservan sus colores internos. Los tokens pertenecen al preview, no a legacy.

El debug muestra baseCellSize, naturalBoardWidth y scale. El entrypoint de desarrollo
acepta `cell` y `compare` en query para reproducir las comparaciones, sin nueva ruta
productiva. Los controles existentes y el guard owner se conservan.

Pruebas: geometría externa/interna, múltiples cantidades de columnas, tamaño natural,
escala y anclaje izquierdo real de la página, token normal y hover en los siete tipos,
sin cambios de tamaño al pasar el mouse. Se mantienen los tests de presets N5.1.

Informe y evidencia: `no_git/informes_de_codigo/informe_etapa_n5_2_tamano_alineacion_bordes.html`.
Sin cambios de esta etapa en presets, renderer métrico, main.dart, legacy, backend,
Firestore, streams o polling. No se realizó despliegue ni switch de TABLERO.
