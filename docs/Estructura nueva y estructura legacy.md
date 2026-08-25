# AgroData Control — Resumen de continuidad
## Etapas 4 y 5 — Gestión de Devices, Rooms, integridad de snapshot, despliegue y normalización
Fecha de consolidación: 2026-08-24

Este archivo está pensado para ser subido en un nuevo chat y usado como contexto operativo. Resume lo implementado, las decisiones tomadas, el estado de producción y el próximo paso.

---

# 1. Punto de partida antes de Etapa 4

AgroData ya había evolucionado desde el esquema legacy hacia un modelo estructural moderno basado en:

- Tenant
- Site
- Sector
- Device
- Room

El esquema moderno relevante es:

- `tenants/{tenantId}`
- `tenants/{tenantId}/sites/{siteId}`
- `tenants/{tenantId}/sectors/{sectorId}`
- `tenants/{tenantId}/devices/{deviceId}`
- `tenants/{tenantId}/devices/{deviceId}/rooms/{roomId}`

El esquema legacy sigue existiendo para los PLC históricos de The Gene Pig:

- `tenants/{tenantId}/sites/{siteId}/plcs/{plcId}`

Decisión importante:
**los PLC legacy de The Gene Pig no se migran**. `genetica-1` puede seguir siendo un Site legacy en sus propios campos, pero puede contener nuevos Sectores y Devices del modelo moderno.

---

# 2. ETAPA 4 — Gestión de Devices y Rooms

## 2.1 Gestión de Devices desde la UI

Se agregó a `TenantManagementPage` una sección **Devices** dentro de cada Site.

Desde Gestión de clientes, un `owner` puede:

- crear Devices;
- editar Devices;
- habilitar/deshabilitar Devices;
- asociarlos a uno o más Sectores;
- administrar sus Rooms;
- hacerlo también dentro de un Site legacy como `the-gene-pig / genetica-1`.

Se corrigió una restricción previa: que un Site sea legacy solo impide editar los campos propios históricos del Site; **no impide agregar Sectores o Devices nuevos dentro de ese Site**.

## 2.2 Catálogo funcional de tipos de Device

Se creó:

`lib/models/agro_device_type_catalog.dart`

Se definieron solo dos tipos funcionales reales:

### `environment_single_room`
Label:
`Ambiente — una sola sala`

Comportamiento:
- no utiliza subcolección de Rooms para representar unidades;
- utiliza la `snapshotUnitKey` propia del Device.

### `environment_multi_room`
Label:
`Ambiente — multisala`

Comportamiento:
- utiliza múltiples Rooms;
- cada Room tiene su propia `snapshotUnitKey`;
- es el modelo correspondiente a PLC Maternidad de La Payana.

No se agregaron tipos especulativos.

El campo `model` continúa separado de `type`. Por ejemplo, un PLC puede tener modelo físico Siemens S7-1200, pero su tipo funcional puede ser `environment_multi_room`.

Los tipos históricos no catalogados pueden seguir leyéndose sin romper la App, pero no son seleccionables para nuevas altas.

## 2.3 Relación Device ↔ Sector

Se agregó al modelo `AgroDevice`:

`sectorIds: List<String>`

Un Device puede asociarse a uno o varios Sectores del mismo Site.

Los servicios validan que:

- los Sectores existan;
- pertenezcan al mismo Site que el Device.

Esta validación se realiza a nivel de servicio. Firestore Rules solo validan que `sectorIds` sea una lista; no verifican referencialmente cada Sector.

Esto se aceptó porque la administración estructural continúa siendo **owner-only**.

## 2.4 Rooms

Se incorporó gestión real de Rooms desde la UI:

- crear;
- editar;
- habilitar/deshabilitar;
- definir `sortOrder`;
- definir `snapshotUnitKey`.

Las Rooms se cargan **solo cuando el administrador expande un Device**.

No se cargan al abrir el Tenant.

Objetivo: minimizar lecturas Firestore.

## 2.5 Alta atómica Device + Rooms

Se creó:

`lib/services/agro_device_provisioning_service.dart`

con:

`createDeviceWithRooms()`

La creación de un Device multisala y todas sus Rooms se realiza mediante un único `WriteBatch`.

Resultado:

- o se crea todo;
- o no se crea nada.

No pueden quedar Devices parcialmente creados si falla alguna Room.

## 2.6 Firestore Rules de Etapa 4

Se agregó `sectorIds` al allowlist de creación/actualización de Devices.

Se mantiene:

- administración estructural owner-only;
- sin delete físico;
- IDs y relaciones estructurales protegidos según las reglas existentes.

---

# 3. ETAPA 4.1 — Integridad de snapshotUnitKey

Se detectó un problema conceptual importante:

Etapa 4 originalmente podía detectar claves duplicadas dentro de un Device, pero la resolución del snapshot ocurre a nivel de todo el Site mediante `unitsByKey`.

Por lo tanto, una misma `snapshotUnitKey` repetida en dos Devices distintos del mismo Site podía provocar una asociación ambigua.

## 3.1 Regla definitiva

Dentro del mismo:

`tenant + site`

cada `snapshotUnitKey` no vacía debe ser única.

La unicidad incluye:

- `snapshotUnitKey` propia de Devices sin Rooms;
- `snapshotUnitKey` de Rooms de Devices multisala.

La comparación:

- aplica `trim()`;
- es case-sensitive;
- no transforma a minúsculas;
- `null` o vacío no participan de la unicidad.

Ejemplo:

- `Sala-1`
- `sala-1`

son técnicamente distintas, aunque la auditoría puede marcarlas como sospechosas.

## 3.2 Servicio centralizado

Se creó:

`lib/services/snapshot_unit_key_service.dart`

Incluye:

- índice `snapshotUnitKey → propietario`;
- auditoría pura;
- `SnapshotUnitKeyValidator`.

La validación se usa en:

- `AgroDeviceService.create()`
- `AgroDeviceService.update()`
- `AgroDeviceRoomService.create()`
- `AgroDeviceRoomService.update()`
- `AgroDeviceProvisioningService.createDeviceWithRooms()`

La lógica no está duplicada en cada servicio.

## 3.3 Alcance de lecturas

La validación de unicidad se ejecuta **solo cuando el administrador guarda**.

Costo máximo aproximado:

- 1 query de Devices del Site;
- hasta N queries de Rooms, una por Device.

No se ejecuta:

- al renderizar;
- al abrir un diálogo;
- en el dashboard;
- en polling;
- mediante listeners.

No se creó una colección índice denormalizada.

## 3.4 Concurrencia

La validación es previa a la escritura, por lo que existe una ventana de carrera teórica si dos administradores escriben exactamente al mismo tiempo.

No se implementó un índice transaccional global.

Se aceptó porque:

- la gestión es owner-only;
- la frecuencia es muy baja;
- normalmente hay un único administrador actuando;
- existe herramienta de auditoría posterior.

## 3.5 Auditoría de claves

Se implementó una función pura para detectar:

- duplicados exactos;
- claves vacías explícitas;
- espacios iniciales/finales;
- diferencias solo de mayúsculas/minúsculas.

No corre automáticamente contra producción.

## 3.6 Indicadores administrativos

Se agregó información visual basada únicamente en metadata.

Para Device de una sola sala sin clave:

`Pendiente de vincular al snapshot`

Para multisala:

`N de M rooms vinculadas al snapshot`

No consulta al backend.

Se corrigió un bug para evitar mostrar falsamente “snapshot incompleto” en tipos históricos/no catalogados.

---

# 4. Estado de La Payana detectado en Etapa 4/4.1

Tenant:
`la-payana`

Site:
`roque-perez`

Sector:
`maternidad`

Device:
`plc-maternidad`

Antes de Etapa 5B tenía:

- `type: "unknown"`
- `sectorIds`: ausente
- `siteId: "roque-perez"`
- `enabled: true`

Rooms:

- `sala-1` a `sala-8`
- `sortOrder`: 0 a 7
- `snapshotUnitKey`:
  - `plc-maternidad__sala-1`
  - ...
  - `plc-maternidad__sala-8`
- todas habilitadas.

La auditoría confirmó:

- sin claves duplicadas;
- sin espacios;
- sin colisiones de mayúsculas/minúsculas;
- estructura compatible exactamente con `environment_multi_room`.

---

# 5. ETAPA 5A — Deploy a producción y smoke test

## 5.1 Commit previo

Todo lo acumulado de Etapas 1–4.1 estaba inicialmente sin commit.

Antes de desplegar se creó:

`246dc23`

Mensaje:

`Estandarización de gestión de tenants/sites/sectores/devices (Etapas 1-4.1)`

Esto dejó un punto claro de rollback.

## 5.2 Validaciones pre-deploy

Se verificó:

- `dart format`
- `flutter analyze`
- `flutter test`
- tests backend
- dry-run de Firestore Rules
- `flutter build web --release`

Resultado previo al deploy:

- Flutter: 223/223 tests
- backend: 8/8
- build release correcto.

## 5.3 Firestore Rules desplegadas

Proyecto:

`agro-data-control`

Se desplegaron las reglas acumuladas.

Cambios principales:

- edición restringida de Tenant por owner;
- `sectorIds` permitido en Devices.

No se implementó unicidad global de `snapshotUnitKey` en reglas.

## 5.4 Frontend desplegado

Hosting:

`agro-data-control.web.app`

Se desplegó la UI nueva de Gestión de clientes.

No se modificó el backend.

## 5.5 Tenant QA

Se creó un Tenant controlado:

`qa-structural-test`

Contenía inicialmente:

- Site `qa-site`
- Sector `qa-sector`
- Device `qa-device`
- Rooms `qa-room-1`, `qa-room-2`

Durante el smoke test manual se agregaron también:

- Site `qb_site`
- Sector `qa_sector2`
- Room `qa_room3`

El propósito fue probar la UI real contra Firestore y Firestore Rules.

## 5.6 Smoke test manual

El smoke test fue realizado manualmente desde la aplicación con un usuario `owner`.

Resultado informado:
**todo salió correctamente**.

Se validó en producción:

- Gestión de clientes accesible;
- edición de Tenant;
- edición de Site;
- `provisioningStatus` preservado;
- creación/edición de Sector;
- Device y Rooms;
- rechazo correcto de `snapshotUnitKey` duplicada;
- alta correcta con clave libre;
- ausencia de regresiones visibles.

Esto es importante: las pruebas realizadas previamente mediante service account no probaban Firestore Rules, porque Admin/REST con credenciales IAM las ignora. El smoke test desde la App autenticada sí validó el flujo real del owner.

---

# 6. ETAPA 5B — Limpieza QA y normalización de La Payana

## 6.1 Limpieza lógica del QA

No se borró ningún documento.

Se deshabilitó todo el entorno QA:

Tenant:
- `qa-structural-test` → `active: false`

Sites:
- `qa-site` → `enabled: false`
- `qb_site` → `enabled: false`

Sectores:
- `qa-sector` → `enabled: false`
- `qa_sector2` → `enabled: false`

Device:
- `qa-device` → `enabled: false`

Rooms:
- `qa-room-1` → `enabled: false`
- `qa-room-2` → `enabled: false`
- `qa_room3` → `enabled: false`

Las entidades siguen físicamente en Firestore y pueden reutilizarse en futuros smoke tests.

## 6.2 Normalización controlada de La Payana

Se decidió no hacer editable `type` desde la UI, porque debe quedar conceptualmente fijo después de crear el Device.

Para normalizar el Device histórico se creó una herramienta puntual.

Archivos:

- `lib/services/la_payana_normalization.dart`
- `tool/normalize_la_payana_device.dart`
- tests correspondientes.

El script está hardcodeado exclusivamente a:

- tenant: `la-payana`
- site: `roque-perez`
- sector: `maternidad`
- device: `plc-maternidad`

No es una herramienta genérica de migración.

## 6.3 Cambio aplicado

El Device pasó de:

`type: "unknown"`

a:

`type: "environment_multi_room"`

Y se agregó:

`sectorIds: ["maternidad"]`

No se modificó ningún otro dato funcional.

Solo se actualizó también `updatedAt`.

## 6.4 Protecciones del script

Antes de escribir, valida:

- existencia de Tenant/Site/Sector/Device;
- Site correcto;
- Sector correcto;
- type permitido;
- sectorIds compatible;
- exactamente 8 Rooms;
- existencia de `sala-1` a `sala-8`;
- todas con `snapshotUnitKey`;
- ausencia de duplicados.

La escritura utiliza actualización parcial.

## 6.5 Idempotencia

Commit:

`53b2a33`

Mensaje:

`chore: normalize La Payana device metadata (Etapa 5B)`

El script se ejecutó dos veces:

1. primera ejecución → aplicó normalización;
2. segunda ejecución → detectó estado correcto y realizó `sin cambios`.

Idempotencia comprobada.

## 6.6 Verificación de Rooms

Las 8 Rooms fueron comparadas antes/después.

Permanecieron idénticas en:

- IDs;
- names;
- enabled;
- sortOrder;
- snapshotUnitKey;
- createdAt.

No se creó ni eliminó ninguna Room.

## 6.7 Tests finales

Luego de Etapa 5B:

- Flutter: 241/241 tests (+1 skip preexistente)
- backend: 8/8
- sin modificaciones funcionales al backend.

---

# 7. Estado actual de producción

## The Gene Pig

Tenant:
`the-gene-pig`

Site:
`genetica-1`

Estado:

- Site histórico/legacy;
- PLC históricos siguen bajo `/plcs/`;
- `munters1` y `munters2` intactos;
- visibles como Sala 1 / Sala 2 en la aplicación;
- **no se migran**;
- `tenants/the-gene-pig/devices` continúa sin el nuevo PLC real al cierre de Etapa 5B.

Importante:
aunque `genetica-1` sea legacy, **puede recibir nuevos Sectores y Devices modernos**.

## La Payana

Tenant:
`la-payana`

Site:
`roque-perez`

Sector:
`maternidad`

Device:
`plc-maternidad`

Estado final:

- `type: environment_multi_room`
- `sectorIds: ["maternidad"]`
- `siteId: roque-perez`
- `enabled: true`
- 8 Rooms
- 8 claves de snapshot únicas
- sin cambios en Rooms.

## QA

`qa-structural-test` y todas sus entidades permanecen en Firestore pero deshabilitadas.

---

# 8. Arquitectura operativa que quedó definida

La administración estructural ya puede hacerse desde AgroData Monitor.

Para un Device de un tipo funcional ya soportado, el objetivo es que **no haga falta programar una nueva UI ni crear documentos manualmente**.

Flujo esperado:

1. Crear/seleccionar Tenant.
2. Crear/seleccionar Site.
3. Crear Sectores necesarios.
4. Crear Device.
5. Elegir tipo funcional.
6. Asociar Sectores.
7. Crear Rooms si corresponde.
8. Definir `snapshotUnitKey` según contrato real del backend.
9. Vincular el backend.
10. Pasar el Site a estado operativo cuando corresponda.

La creación estructural y la integración física/backend son dos fases distintas.

---

# 9. Próximo paso — Etapa 5C

La Etapa 5C **no es inicialmente una gran implementación de código**.

El siguiente objetivo es incorporar el nuevo PLC real de The Gene Pig utilizando la infraestructura administrativa ya creada.

Primero hay que definir los datos reales:

- Site: probablemente `genetica-1`;
- nombre visible del Device;
- `deviceId`;
- modelo físico del PLC;
- protocolo/familia;
- tipo funcional:
  - `environment_single_room`, o
  - `environment_multi_room`;
- Sectores que cubre;
- cantidad de salas/ambientes;
- nombres de Rooms;
- variables disponibles por sala;
- `snapshotUnitKey` definitivas;
- endpoint/backend que entregará ese Device.

Después:

### Fase estructural
La realiza el usuario desde:

`Configuración → Gestión de clientes`

creando Sector/Device/Rooms.

### Fase backend
Puede requerir nuevos prompts para CODEX dependiendo del PLC físico y protocolo.

El backend moderno debe producir el snapshot correspondiente utilizando exactamente las claves configuradas.

No asumir que el nuevo PLC usa la misma integración que La Payana hasta conocer modelo/protocolo real.

---

# 10. Restricciones que deben preservarse

En próximos desarrollos:

1. No migrar los PLC legacy de The Gene Pig.
2. No volver a usar `/sites/{site}/plcs/{plc}` para nuevos Devices.
3. Nuevos Devices usan el modelo moderno.
4. Un Site legacy puede contener Devices modernos.
5. `snapshotUnitKey` debe ser única dentro del Site.
6. No convertir automáticamente las claves a minúsculas.
7. Rooms se cargan bajo demanda en administración.
8. Evitar listeners/polling innecesarios.
9. Administración estructural continúa owner-only salvo decisión explícita futura.
10. No realizar deletes físicos; usar enabled/active.
11. `type` es funcional, no el modelo físico del PLC.
12. `type` no debe modificarse libremente después del alta.
13. La relación Device↔Sector se guarda en `device.sectorIds`.
14. No llamar “Backend offline” a un Site que todavía está `pending_backend`.
15. La integración backend debe respetar el contrato exacto de `snapshotUnitKey`.

---

# 11. Archivos/clases especialmente relevantes

Frontend/modelos/servicios:

- `lib/pages/tenant_management_page.dart`
- `lib/models/agro_device.dart`
- `lib/models/agro_device_type_catalog.dart`
- `lib/services/agro_device_service.dart`
- `lib/services/agro_device_room_service.dart`
- `lib/services/agro_device_provisioning_service.dart`
- `lib/services/snapshot_unit_key_service.dart`
- `lib/services/la_payana_normalization.dart`

Herramienta puntual:

- `tool/normalize_la_payana_device.dart`

Seguridad:

- `firestore.rules`

Commits relevantes:

- `246dc23` — Etapas 1–4.1 + administración estructural desplegada.
- `53b2a33` — normalización de metadata de La Payana.

---

# 12. Estado al abrir el próximo chat

La gestión estructural moderna está implementada, desplegada y validada en producción.

No hay que volver a diseñar Gestión de clientes.

No hay que volver a discutir si los nuevos PLC deben cargarse por código: **se cargan desde la UI cuando el tipo funcional ya está soportado**.

La siguiente conversación debería comenzar con:

> “Estamos en la Etapa 5C. Quiero incorporar el nuevo PLC real de The Gene Pig usando el modelo moderno. Los PLC históricos Sala 1/Sala 2 continúan legacy. Primero definamos el PLC, los Sectores, Rooms y el contrato de snapshot; después vemos si el backend moderno necesita adaptación.”

Ese es el punto exacto de continuidad.
