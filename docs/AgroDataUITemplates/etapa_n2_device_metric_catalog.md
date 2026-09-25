# Etapa N2 — DeviceMetricCatalog

## Decisión y auditoría

Se usa un catálogo reutilizable con `id`, `name`, `schemaVersion`,
`catalogVersion`, `List<MetricDefinition>`, indicadores semánticos y asociaciones
por key. No contiene identidad de un Device concreto ni referencias a N1.
`name` identifica el catálogo de capacidades, nunca una Card.

`MetricDefinition` ya era independiente de `DeviceTemplate`: se reutiliza sin
modificaciones, junto con sus enums de displayType, transform y statusBehavior.
Se conservan key, label, shortLabel, unit, icon, sourceField,
valueLabelSourceField, displayType, decimals, transform y statusBehavior.
No se crea una definición paralela de métrica, un resolver nuevo ni otra lógica
de formato. `TemplateDataResolver` y el formatter existente aceptan las métricas
del nuevo catálogo directamente; esto se prueba sin conectar la UI productiva.

El `IndicatorDefinition` actual requiere `position`. Para no alterar producción,
`MetricIndicatorDefinition` contiene únicamente su subconjunto semántico:
key, sourceField, icon y condition (escalar JSON finito o null). La duplicación
de esos cuatro campos es deliberada: el tipo legacy no puede reutilizarse sin
introducir geometría o modificar un contrato productivo. No se retiene un
objeto legacy escondido dentro del indicador nuevo.

## Disponibilidad y asociaciones

La pertenencia a `metrics` significa capacidad declarada disponible; no implica
que hoy exista un valor de telemetría ni que deba mostrarse. `pending.*` puede
declarar una capacidad pendiente y seguirá sin producir valor. No hay campo
visible, posición, tamaño u orden visual. El orden de la lista no es un contrato
de presentación. No se agrega `required`: los datos actuales no justifican una
obligatoriedad contractual y no debe inferirse de la visibilidad legacy.

`availableIndicators` asocia metricKey → lista de indicatorKeys. Los indicadores
deben existir en `indicators`. Una misma capacidad puede ofrecer varios; la
futura celda elegirá cuáles mostrar y dónde. Se permite un indicador definido
sin asociaciones. Una asociación ausente o vacía no ofrece indicadores.

Las listas, el mapa y sus listas internas son inmutables y copiados al construir.
`toMap` devuelve contenedores nuevos que no permiten mutar el catálogo.

## Personalización por Device

`withOverrides` produce un catálogo efectivo local:

- `upserts`: definiciones completas; reemplazan por key o agregan keys nuevas.
- `removedKeys`: quita capacidades y sus asociaciones. No cambia visibilidad.
- `indicatorUpserts`: agrega o reemplaza indicadores semánticos por key.
- `indicatorAssociations`: reemplaza la asociación completa de cada métrica;
  una lista vacía elimina sus indicadores disponibles.

Se rechazan keys duplicadas en el delta, bajas inexistentes, altas/bajas
contradictorias y referencias inválidas. La base nunca se modifica. El resultado
conserva id y versión de la base como procedencia; **no debe guardarse sobre el
catálogo global**. La persistencia del binding y del delta por Device queda
diferida. No se agrega deviceId/tenantId/siteId al catálogo para representar esa
relación. No hay inferencias por nombres de Devices o layouts.

## Fuentes: contrato real

Se conserva `sourceField`, sin Firestore ni renderer en el modelo. Se admiten
aliases planos (tempInterior, currentCount) y rutas de identificadores separadas
por puntos, incluyendo snapshot.*, manual.*, computed.* y pending.*. Los segmentos
usan letras ASCII o guion bajo al inicio y letras, números o guion bajo después.
No hay una whitelist de nombres de métricas o prefijos. Se rechazan segmentos
vacíos, barras y espacios; es la gramática defensiva de N2, compatible con todas
las fuentes extraídas actualmente. El resolver legacy acepta strings más amplios;
N2 no modifica ese comportamiento productivo.

En `TemplateDataResolver`, una clave con puntos es una búsqueda literal, no
traversal de mapas anidados. Los datos snapshot/manual/computed arbitrarios se
pueden entregar como claves completas en `TemplateDataContext.extras` o un Map.
N2 no crea conectores a esos orígenes ni un motor de fórmulas.
`computed.dewPointDelta` mantiene su cálculo existente: dewPoint − temperature.
`pending.*` siempre devuelve null, incluso si extras contiene un valor.
El fan conserva voltageToPercent (450 → 0.45) y formato porcentual (45).

## Extracción local temporal

`reference_metric_catalogs.dart` es la única frontera que importa el catálogo
legacy. El núcleo puede existir sin esa frontera. Se reutilizan los objetos
MetricDefinition actuales, copiando únicamente las listas contenedoras.
Nunca se leen ni copian boardSlots, tableColumns, boardPreset o tableSection.

| Catálogo N2 | Origen legacy | Métricas | Exclusiones |
| --- | --- | ---: | --- |
| environment_room_v1 | room_climate | 13 | deviceName, plcId: identidad |
| laboratory_v1 | laboratory_basic | 2 | equipment: identidad; labPending: relleno visual |
| disinfection_arch_v1 | disinfection_arch | 3 | equipment: identidad |

Las keys reales se preservan (por ejemplo tempInterior y sowCount), sin renombrar
telemetría ni migrar Cerdas. No se inventa presión para el laboratorio: no existe
en sus métricas actuales. Los pending específicos de CO2, agua y desinfección
se conservan porque representan capacidades con nombre, a diferencia del
placeholder genérico del laboratorio.

La asociación semántica explícita de tempInterior a calefaccionEtapa1,
calefaccionEtapa2 y humidificacion se tomó de la auditoría. No se deriva de
posiciones o visibilidad al ejecutar. Se proyectan los indicadores sin position.
Estos tres catálogos son referencias de capacidades, **no templates visuales**.

## Serialización y validación

`toMap`/`fromMap` son compatibles con JSON. Schema 1 soportado; catalogVersion
positivo. La representación persistida exige todos los campos del catálogo y
los campos de métrica emitidos por toMap, salvo los dos strings opcionales.
Se rechazan tipos incorrectos, enum/transform desconocidos, keys/labels vacíos,
keys repetidas, fuentes mal formadas, referencias rotas y decimales fuera de
0..20 (contrato técnico del formatter toStringAsFixed).

La frontera N2 reutiliza el constructor de MetricDefinition y sus lectores de
enums; no usa coerciones permisivas del parser legacy. Los campos desconocidos
se rechazan también en métricas e indicadores. Así no se aceptan silenciosamente
campos de geometría, visibilidad o identidad. Esta política estricta difiere de
la tolerancia a campos extra de N1; extensiones de N2 requieren evolucionar el
contrato de forma explícita. La validación se ejecuta también en release.

Persistencia futura propuesta:

```
metricCatalogs/{catalogId}                  # catálogo global reutilizable
tenants/{tenantId}/devices/{deviceId}       # binding futuro conceptual
  metricCatalogId
  metricOverrides                         # delta, nunca la base sobrescrita
```

Antes de conectar se deberá adaptar el binding al path real de Devices y definir
cómo se fija/migra catalogVersion. N2 no agrega repositorios, reglas, seed remoto,
listeners, UI de edición ni escrituras.

## Consumo futuro en N3

```
DeviceMetricCatalog + LayoutTemplate → DeviceBoardLayout

DeviceBoardLayoutItem {          // conceptual; no implementado
  metricKey: "tempInterior",
  placement: GridPlacement(...),
  cellLayoutPresetId: "..."
}
```

N3 resolverá el catálogo efectivo del Device, verificará metricKey con
metricByKey, verificará indicadores elegidos contra availableIndicators y
validará el placement contra el LayoutTemplate N1. Allí se guardarán selección,
posición, tamaño, visibilidad y referencias a CellLayoutPreset. Cambios de
capacidad deberán revalidar los layouts concretos.

El título sigue siendo `device.name`, con showTitle y titleOverride futuros en
la configuración concreta: `titleOverride ?? device.name`. No pertenece a N1
ni N2. TABLA tendrá selección/columnas propias, sin imponerle el layout externo.

## Compatibilidad y verificación

N2 se agrega en archivos nuevos, sin imports desde el entrypoint, renderers o
servicios productivos. La dependencia temporal es N2 → catálogo legacy, no a la
inversa. N1 y el comportamiento actual conviven sin migración. No se cambian
backend, PLC, Alertas, Cerdas ni Firestore. Los tests comprueban el grafo de
imports del núcleo, extracción por identidad de objeto, fuentes, override,
inmutabilidad y round trips. El informe HTML registra los resultados finales
de format, analyze, suite de Flutter y build web.
