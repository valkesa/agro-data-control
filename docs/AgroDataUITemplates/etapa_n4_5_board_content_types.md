# N4.5 — Board Content Types y preparación de N5

## Decisión de evolución

Se agrega `BoardContentLayout` (schemaVersion=2) con `BoardContentItem`:
id, GridPlacement y BoardContentConfig. El type es derivado de la variante
concreta, por lo que un constructor no puede recibir un discriminador contrario
al contenido. BoardContentConfig es sealed y tiene siete variantes tipadas.
No hay Map dinámico de configuración en el dominio ni una clase monolítica con
campos de todos los tipos. Los maps existen únicamente en serialización.

Se eligió un migrador explícito en lugar de alterar la API métrica N3:
`BoardContentLayout.fromLegacy` y lectura de maps schema=1 migran todas las
métricas; `toLegacy` solo admite boards metric-only, sin descartar contenido.
Los fixtures/tests N3 siguen intactos. La nueva abstracción es la entrada prevista
para N5; no se pretende mantener dos renderers nuevos en paralelo.

Los metadatos comunes reutilizan DeviceBoardLayout internamente con items vacíos.
Esto conserva validación de identidad, versiones, título y fechas sin duplicarla.
El catálogo de contenido no conserva items métricos ocultos en ese objeto.
`resolveTitle` sigue showTitle ? titleOverride ?? device.name : null.

## Tipos y configuraciones

- MetricBoardContent: metricKey, cellLayoutPresetId e indicatorKeys inmutables.
  `toMetricItem()` permite consumir los validators y resolver de N3/N4 existentes.
  No duplica MetricDefinition ni cambia el significado de indicadores ordinales.
- ImageBoardContent: sourceType asset/url/firestoreStorageRef/deviceMediaRef,
  sourceRef, fit contain/cover/fill y altText opcional. HTTP(S) exige host y no
  credenciales/espacios. Referencias locales son relativas, sin traversal `..`.
  StorageRef es una ruta de objeto futura, no un SDK ni una descarga.
- LatestEventBoardContent: eventSourceId y fields no vacíos, con keys únicas.
  BoardDataField tiene key, label, format e icon opcional. Formatos: text,
  number, boolean, dateTime y status. Los nombres del Arco están solo en fixtures.
- DataTableBoardContent: dataSourceId, columnas no vacías con keys únicas,
  maxRows (default 20, rango técnico 1..1000), showHeader (default true).
  BoardTableColumn reutiliza BoardDataField y agrega flex positivo 1..100.
  Es proporción relativa, nunca ancho en píxeles. No es TABLA productiva.
- StatusBoardContent: dataSourceId semántico del estado. N5 interpretará el
  resultado del provider; no contiene reglas de negocio ni enum de estados Arco.
- TextBoardContent: texto plano no vacío. Rechaza etiquetas HTML; el renderer N5
  debe dibujarlo como texto, nunca decodificarlo/evaluarlo como markup.
- ChartBoardContent: dataSourceId, chartType line/bar/area y series no vacías
  con keys únicas; BoardChartSeries contiene key y label. Es el contrato base,
  sin motor gráfico, ejes avanzados ni consultas de históricos.

`customWidget` se difiere deliberadamente: ninguna extensión concreta necesita
esa vía de escape en N4.5. Se aplica la condición del prompt de implementarlo
solo si aporta valor real. Se rechaza como unsupported_content_type. Si aparece
una necesidad, N5 podrá agregar un registro explícito con claves conocidas y
config tipada/validada por extensión. No se admiten nombres de clases Dart,
plugins arbitrarios ni blobs sin contrato. El Arco no usa custom widgets.

## Fuentes de datos

Los contenidos no métricos usan dataSourceId/eventSourceId validados como IDs
semánticos: inicio alfanumérico/guion bajo, luego letras/números, punto, dos
puntos, barra, guion o guion bajo. Se prohíben espacios y referencias vacías.
La validación no verifica existencia del provider ni datos reales. Los IDs
no se interpretan como consultas, rutas de Firestore o URLs ejecutables.

N5 recibirá contexto del Device y resolverá los IDs contra providers registrados.
Debe definir contratos de salida por tipo (evento, lista tabular, estado, series),
estados de carga/sin datos/error y formateo de fecha/número. N4.5 no hace
networking, lecturas remotas, listeners, polling o acceso a Storage.

## Serialización y migración

Item schema 2: id, type, placement {x,y,widthCells,heightCells}, content tipado.
El agregado mantiene los campos comunes de N3 con schemaVersion=2. Los enums
se persisten por nombres estables, no índices. Campos desconocidos se rechazan
en board, item, placement, configs y campos/columnas/series anidados.

`fromMap` acepta schema 1 usando el parser N3 estricto y luego migra en memoria;
`toMap` siempre emite schema 2. No hay escritura ni migración productiva.
La vuelta a N3 de un board métrico preserva IDs, posiciones, título, fechas,
layoutVersion, preset e indicadores. Intentar downgrade de un board mixto
lanza non_metric_content. Versiones desconocidas se rechazan explícitamente.

Los parámetros opcionales de constructores tienen defaults, pero el wire exige
los campos no-null emitidos por toMap. Los nullable pueden omitirse (altText,
preset, fechas, título, icon). No se truncan números ni convierten strings a bool.
Las listas y mapas de dominio son inmutables/copias defensivas; toMap devuelve
contenedores independientes. Fechas usan el contrato UTC canónico heredado N3.

## Validación e issues

`BoardContentValidator.validate(board,template,effectiveCatalog,presetCatalog)`
valida metadatos y métricas con N3, y presets métricos con N4. El resto de tipos
no pasa por CellLayoutPreset. Cada configuración valida su propia estructura al
construirse/deserializarse, con LayoutValidationException/ArgumentError.

Todos los items respetan bounds y participan en colisiones mixtas. Se reutiliza
`DeviceBoardLayoutValidator.placementsOverlap` de N3 (rectángulos semiabiertos):
la adyacencia es válida. Cada par se informa una vez; O(n²), sin matriz de celdas.
Los IDs de items son únicos entre todos los tipos. Repetir una metricKey sigue
permitido con IDs/placements distintos. Se agregan issues sin borrar contenido.

Códigos de contenido: unsupported_content_type, invalid_content_config,
data_source_missing, duplicate_field_key, duplicate_column_key,
duplicate_series_key y non_metric_content. Se reutilizan metric_not_found,
indicator_not_available, duplicate_indicator_key, cell_preset_not_found,
cell_span_mismatch, placement_out_of_bounds, placement_collision, etc.
Las fallas estructurales se rechazan al cargar; las incompatibilidades contextuales
se devuelven como lista inmutable. Deserializar nunca sustituye la validación.

## Fixtures locales

El fixture Arco conceptual usa grid_6x7 y Device sintético example-disinfection:
imagen hero 4×4, columna lateral con tres KPIs 2×1 y estado 2×1, último evento
6×1 y tabla de registros 6×2. Se usan las tres métricas realmente disponibles en
N2; el cuarto bloque lateral es estado, sin inventar un KPI de telemetría.

Campos configurados: fecha/hora, patente, tipo, empresa/conductor, estado;
la tabla agrega producto y PPM. Todos viven en reference_content_boards.dart,
no en clases especiales ni branches del núcleo. La imagen referencia `hero`
mediante deviceMediaRef; no necesita un asset físico para validar el contrato.

Sala se obtiene migrando el fixture N3 y sigue metric-only. Ningún modelo hace
selección por tenant/site/device. Se prueban todos los tipos en 6×4, 8×4 y 10×5.

## Brecha 3×1 cerrada

Se agregó default_3x1 al catálogo N4 y a su mapa de defaults usando la misma
función genérica. Su subgrilla es 24×8 y contiene label/value/unit y tres slots.
No se cambió el Laboratorio N3: sus dos spans 3×1 resuelven, validan y producen
contenido semántico con el resolver N4. El catálogo pasa de seis a siete presets;
se actualiza únicamente el conteo esperado del test N4 anterior.

## N5: registro de renderers y persistencia futura

Registro previsto por discriminador (nombres conceptuales, no widgets creados):
metric → MetricBoardRenderer; image → ImageBoardRenderer;
latestEvent → LatestEventBoardRenderer; dataTable → DataTableBoardRenderer;
status → StatusBoardRenderer; text → TextBoardRenderer; chart → ChartBoardRenderer.

Flujo N5: cargar/migrar schema → resolver N1/N2 → validar todo el board → elegir
renderer por type → resolver provider o contenido métrico → presentar. La rama
métrica convierte a N3 y utiliza CellLayoutCatalog/CellContentResolver N4 antes
de resolver valor y formato. Las demás ramas nunca se fuerzan a un preset métrico.
Un tipo futuro debe registrar configuración tipada, validación, wire y renderer.

Se conserva la propuesta tenants/{tenantId}/devices/{deviceId}/ui/board. Antes
de persistencia se requiere habilitar lectores schema 2, políticas de acceso,
versionado y concurrencia; lectores N3 no aceptarán un documento schema 2.
No se actualizan paths/reglas ni se escribe Firestore en N4.5.

## Alcance y verificación

Solo se agregan modelos/tests/documentación y se modifica el catálogo local N4
para 3×1 junto con su expectativa de cantidad. N1–N3, fixtures de Laboratorio,
renderers, TABLERO, TABLA, navegación, backend, PLC, Alertas, Cerdas y Firestore
no cambian. El informe HTML registra format, analyze, tests, build web y la
comparación contra el estado inicial. No hay deploy ni cambios visuales productivos.
