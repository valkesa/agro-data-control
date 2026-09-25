# Etapa N6.4.1 — Ajustes del Editor de Diseño de celda

Implementado y validado el 17 de septiembre de 2026 sobre N6.4.

- C1: las superficies de los elementos se resuelven por encima de la grilla de movimiento. Clicar un elemento ocupado lo selecciona y mantiene el modo activo; clicar una celda libre mueve el seleccionado, sujeto a las validaciones existentes.
- C2: `CellLayoutCanvas.editorMode` habilita contornos de todos los elementos, incluidos slots vacíos y elementos ocultos. Tokens centralizados en `cell_editor_tokens.dart`: borde normal #33465E, seleccionado #63D3FA, oculto #243247. Seleccionado: 2 px; normal: 1 px. Elementos ocultos con opacidad 0,35, seleccionables. Runtime/preview no activa estos contornos.
- C3: `MetricBoardContent.labelOverride` y `unitOverride`, opcionales, con serialización compatible, validación de tipos y `copyWith`. Vacío o espacios restaura el fallback. Los campos se actualizan con `onChanged`, sin Enter, y conservan sus valores al cambiar selección o editar/duplicar diseños. La definición compartida de la métrica y el preset no almacenan estos textos. La unidad usa `unitOverride ?? metric.unit`, también sin datos.
- C4: el ajuste interno con FittedBox se reemplaza por ClipRect + OverflowBox alineado. Se conserva el tamaño semántico y se recorta dentro del footprint. Multilínea conserva maxLines y el ancho disponible. Editor y renderer comparten el canvas. La escala global del Board permanece intacta.

## Validación

- Formato: 9 archivos, 0 cambios pendientes.
- Análisis: 0 errores, 0 warnings, 14 infos en archivos ajenos a esta etapa.
- Pruebas focalizadas: 40 aprobadas. Se agregaron 9 pruebas y se actualizaron dos expectativas anteriores incompatibles con los nuevos requisitos.
- Suite completa final: 989 aprobadas y 1 omitida.
- Build web principal y build de preview: exitosos.
- Chrome real mediante CDP: selección ocupada, movimiento libre, contornos, overrides inmediatos y conservados, clipping XXL/hero/icono y viewport de 390 px. Siete capturas y ninguna excepción registrada.

No se conectó Firestore ni persistencia remota, no hubo deploy y no se modificó el TABLERO productivo en esta etapa. Se preservó el trabajo preexistente del repositorio. Los presets con slots pequeños ahora pueden recortar contenido que antes se reducía automáticamente; ampliar el footprint o elegir otro tamaño es la corrección explícita de diseño.

Informe y evidencia: `no_git/informes_de_codigo/informe_etapa_n6_4_1_ajustes_editor_diseno_celda.html` y `evidencia_n6_4_1/`.
