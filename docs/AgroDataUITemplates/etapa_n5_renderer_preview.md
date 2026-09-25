# N5 — Renderer paralelo y Board Preview

## Acceso y alcance

La app normal ofrece Configuración → Administración → Board Preview solo para
owner. El botón está dentro del bloque de permisos owner existente; el handler
vuelve a comprobar el rol y BoardPreviewPage deniega acceso si isOwner=false.
No se agrega una ruta pública ni un flag que cambie TABLERO. El nuevo renderer
se utiliza únicamente en preview. No hay deploy ni migración de Devices.

Para desarrollo existe `tool/board_preview_main.dart`, entrypoint separado que
no inicializa Firebase ni autentica usuarios. Renderiza únicamente fixtures
sintéticos. No se selecciona desde main.dart. Sirve para verificar Chrome y
capturas sin entrar con una cuenta real; no es un bypass de autenticación de la app.

## Arquitectura

BoardContentRenderer valida BoardContentLayout con N1/N2/N3/N4/N4.5 antes de
calcular la geometría. boardRendererRegistry es un mapa inmutable type → builder:
MetricBoardRenderer, ImageBoardRenderer, LatestEventBoardRenderer,
DataTableBoardRenderer, StatusBoardRenderer, TextBoardRenderer y ChartBoardRenderer.
Cada clase es responsable de su tipo. Los renderers no consultan deviceId o tenant
ni seleccionan tamaños/assets por métrica. El selector y la comparación viven
solo en la pantalla de fixtures.

Grilla externa: cellWidth = ancho disponible / template.columns;
cellHeight = cellWidth / cellAspectRatio (default 1.35, parámetro de runtime).
Posición = (x × cellWidth, y × cellHeight); tamaño = span × tamaño de celda.
No se persisten píxeles. LayoutBuilder/Stack/Positioned traducen las unidades
lógicas al tamaño real. Padding/bordes son tokens locales de presentación,
no geometría persistida. Se prueban 6×4, 6×7, 8×4 y 10×5.

## Métricas y subgrilla

La rama métrica convierte el contenido schema 2 al item métrico N3, resuelve el
preset explícito/default con N4 y usa CellContentResolver. La subgrilla se deriva
del span/resolución N1, incluyendo 3×1 → 24×8; no se usa layout legacy.
Cada InternalGridPlacement se traduce proporcionalmente al área interna de la Card.

TemplateDataResolver, MetricDefinition, transforms, formatter e iconografía son
los existentes. Se muestran label/value/unit/icon según el preset, alineaciones,
roles de fuente, peso y maxLines. FittedBox reduce contenido para caber, sin
posiciones o tamaños particulares por metricKey. Los presets default actuales
no declaran icon; los presets icon_value sí y están cubiertos por tests.

Indicators: la key seleccionada se resuelve por índice de slot; se obtiene su
valor desde el contexto sintético y se compara con condition. Activo usa acento
ámbar, inactivo gris, con tooltip. Slots sin key quedan vacíos y no desplazan
contenido. Configuraciones incompatibles se detienen antes de renderizar.
No se implementan nuevas alarmas, acciones ni animaciones de negocio.

## Datos locales y renderers no métricos

PreviewBoardDataProvider recibe un contexto de métricas, un mapa de fuentes y
un mapa de imágenes ImageProvider. Se comparte por board; no hay lecturas por
celda, listeners, Timer, polling ni persistencia. Los datos fijos están claramente
identificados como sintéticos. La lectura real de producción no forma parte de N5.

Se conserva la semántica pending.* del resolver: CO2/agua y los tres KPIs del Arco
muestran Sin datos. No se inventan mediciones para capacidades todavía pendientes.
Sala usa temperatura 24.6, humedad 64%, fan 45%, presión 28 Pa, puertas y otros
valores sintéticos. Laboratorio usa las dos métricas 3×1 del fixture existente.

Imagen: contain/cover/fill se traducen a BoxFit. Las referencias, incluso URLs,
se resuelven exclusivamente desde media local. Si no hay imagen se muestra un
placeholder genérico con altText; si la decodificación falla se muestra diagnóstico.
No se descarga una imagen por URL ni se agrega Firebase Storage. El Arco usa
el placeholder permitido por el prompt, no una fotografía de producto.

LatestEvent dibuja fields configurados desde un Map del provider, con label,
icon opcional y formato. DataTable dibuja columnas por flex, respeta showHeader y
maxRows y permite scroll vertical dentro de la Card. No es la TABLA global.
Fechas sintéticas se formatean dd/MM HH:mm; booleanos Sí/No; otros tipos usan
su representación textual. No se agrega un sistema de localización/formato avanzado.

Status usa PreviewStatus(value,label,severity) y colores del lenguaje visual
actual: ok verde, warning ámbar, critical rojo, neutral gris. Text muestra texto
plano, sin HTML. Chart reconoce tipo y series, pero presenta un placeholder
funcional: motor gráfico y providers de históricos quedan para una etapa posterior.

## Pantalla y comparación

La pantalla indica NUEVO RENDERER — PREVIEW, permite cambiar Sala/Laboratorio/Arco
sin reiniciar y muestra Mostrar grilla apagado por default. Al activarlo dibuja
límites externos, IDs/spans y subgrillas métricas. Comparar actual, disponible
para Sala, agrega abajo el DeviceBoardRenderer existente con los mismos datos
sintéticos. Esa llamada está solo en preview; no cambia TABLERO normal.

Colores de superficie/borde, radios, fuente e iconos siguen la app actual. La
comparación muestra que la nueva distribución responde a spans explícitos y
reserva espacios para slots, mientras legacy conserva sus proporciones propias.
No se buscó paridad pixel-perfect ni se copiaron sus estructuras rígidas.

En móvil se conserva la grilla lógica, por lo que algunos textos quedan pequeños;
no se reordenan items ni se convierten columnas automáticamente. La tabla
embebida tiene scroll vertical. Una UI móvil más adaptada requeriría decisiones
posteriores sobre layouts; las capturas documentan esta limitación de N5.

## Errores

Los issues del validator se presentan en PreviewDiagnostic antes de dibujar
geometría inválida. Se cubren metric_not_found, cell_preset_not_found,
placement_collision, placement_out_of_bounds e indicator_not_available.
La frontera BoardContentRenderer.fromMap captura tipos desconocidos, estructura
y versiones inválidas; muestra unsupported_content_type u otro issue heredado.
Fuentes locales inexistentes o con forma incorrecta muestran data_source_missing
por contenido. Imagen ausente usa placeholder explícito; no hace lectura remota.
Chart no exige fuente real porque su implementación N5 es solo placeholder.

## Prueba manual

1. Abrir la app compilada con estos cambios e ingresar como owner.
2. Abrir Configuración y, en Administración, Board Preview.
3. Elegir Sala y verificar temperatura, humedad, fan, presión, puertas e indicadores.
4. Activar Comparar actual para contrastar con legacy usando datos sintéticos.
5. Elegir Laboratorio y comprobar las dos celdas 3×1.
6. Elegir Arco y revisar hero, métricas sin datos pendientes, estado, evento y tabla.
7. Activar/desactivar Mostrar grilla y cambiar el ancho de la ventana.
8. Guardar screenshots para revisión visual antes de avanzar.

Alternativa local de desarrollo, sin login ni Firebase:

```
flutter run -d chrome -t tool/board_preview_main.dart
```

El build de desarrollo usado para capturas está servido en http://127.0.0.1:8097/.
Los parámetros fixture=0/1/2 y grid=1 existen solamente en ese entrypoint de
prueba; no cambian la navegación de la app normal. El servidor es temporal.

## Verificación técnica y Chrome

Los 30 widget tests N5 cubren grillas/spans, título, métricas/iconos/slots,
3×1, tres fits de imagen, evento configurable, tabla/header/maxRows/flex,
severidades, texto/chart, errores, fixtures a 320/1100 y guard de owner/selector/debug.
El informe registra la suite completa, análisis, build web normal y build preview.

Chrome headless con perfil temporal verificó escritorio, móvil y grilla debug;
se guardaron capturas y n5_chrome_validation.json con texto, excepciones y URLs.
Se observaron recursos locales y fuentes de Google; no hubo solicitudes de datos
Firestore, backend ni polling del preview. No se afirma cero tráfico de recursos.
El flujo de login real/rol owner se verificó por integración de código y test
de guard; la sesión de Chrome usó el entrypoint sintético, sin cuenta productiva.

## Archivos existentes y producción

Solo main.dart cambia respecto del estado inicial: import, acción y acceso
owner-only a preview. Los módulos N1–N4.5, servicios, polling, renderers actuales,
TABLERO y TABLA mantienen sus archivos intactos. La suite existente de regresión
continúa pasando. El menú agrega una opción visible para owner, pero no reemplaza
el renderer de la vista normal. No hubo deploy, escritura Firestore o cambio backend.
