# Cierre final de históricos ambientales C1–C7

Implementado el 25/09/2026. Complementa y reemplaza las garantías de recuperación del cierre H1–H7. No cambia UI, Templates, reglas, configuraciones de sitios ni el histórico legacy.

## Persistencia y recuperación

`DeviceEnvironmentHistoryService` serializa los snapshots. Cada transición local se aplica sin `await`, se escribe a un temporal con `flush: true` y se publica mediante rename. Solo después puede enviarse a Firestore.

- Cierre horario: retira `currentHour`, agrega el resumen a pending y hace fold del diario una sola vez por `periodId`, en un único checkpoint.
- Cierre diario: retira `dailyAccumulator` y agrega `pendingDaily` en un único checkpoint.
- La confirmación de Firestore retira un pendiente mediante otra transición durable. Si esa transición falla, el pendiente permanece; reintentar conserva ID, contenido y `createdAt`.
- `dailyAccumulator.hoursIncluded` contiene los IDs incorporados, no un contador. El diario no lee horarios de Firestore.
- El checkpoint guarda el último slot aceptado/procesado. Slots repetidos o anteriores no se vuelven a acumular.

### Fallo del filesystem

`durabilityDegraded` es observable. Una transición cuyo checkpoint falla se revierte en memoria; el checkpoint anterior queda vigente y se detienen escrituras remotas. Los nuevos snapshots no se aceptan como muestras durables mientras persista el fallo. En el siguiente ciclo se intenta persistir nuevamente el estado vigente; si funciona, se reanuda el proceso. No se promete conservar mediciones nuevas que nunca pudieron guardarse durante una falla de disco.

Un write confirmado remotamente seguido de fallo local de retiro puede repetirse: entrega al menos una vez con documento idempotente. Se asume un único escritor por identidad sobre filesystem local persistente. No se implementó coordinación entre procesos ni tolerancia a destrucción del disco.

## Validación de Site

Estados: `unverified`, `temporarilyUnavailable`, `verified`, `mismatch`.

1. Cargar y validar checkpoint local, sin enviar pendientes.
2. Consultar `tenants/{tenant}/devices/{device}` para comprobar `siteId` real.
3. Solo `verified` permite reintentos/escrituras.
4. Un error o Device inexistente conserva el estado local y reintenta validación en el próximo poll; un mismatch bloquea esa instancia.
5. Normalizar la hora anterior y continuar muestreando, sujeto a durabilidad.

La verificación exitosa se conserva durante la instancia; una reasignación de Device a otro Site requiere reiniciar/reconfigurar el writer. No hay watcher nuevo.

Las cuatro APIs de lectura siempre filtran por tenant/device/site configurados. `expectedSiteId`, si se utiliza, agrega una restricción y no permite ampliar el scope. El repositorio también rechaza escrituras con identidad distinta a la configuración.

## Checkpoint v3

La ruta codifica individualmente en base64url, sin padding, los valores efectivos de proyecto, database, tenant, site y device, separados por puntos. Se utiliza el mismo proyecto efectivo que el repositorio (incluido fallback `FIRESTORE_PROJECT_ID`).

El JSON contiene versión 3, identidad completa, `currentHour`, `dailyAccumulator`, `lastSampleSlot`, `pendingHourlyPeriods` y `pendingDailyPeriods`. Los pendientes llevan también proyecto/database. Se validan campos obligatorios, tipos, versión, identidad interna, timestamps, límites de períodos, estadísticas y unicidad de IDs.

JSON inválido, schema desconocido, datos incompletos o identidad contradictoria se rechazan como unidad y se conservan como `.rejected.<timestamp>`; no se envía su contenido. Si no se puede preservar ese archivo, no se avanza. Los archivos de versiones anteriores tienen otro nombre/formato y no se convierten automáticamente. Antes de una futura activación sobre una instalación con estado v2, deben drenarse con su escritor previo o recuperarse mediante una migración explícita revisada. No hubo deploy en esta etapa.

## Fechas y lecturas

- Períodos e IDs en ART/UTC−3; timestamps remotos UTC.
- Acumuladores y slots locales usan fechas UTC que representan el reloj ART, evitando dependencia del TZ del host.
- Rango semiabierto `[fromUtc, toUtc)` sobre `periodStartUtc`.
- La enumeración de IDs convierte ambos límites a ART antes de recorrer fechas.
- Rango vacío: vacío; invertido: error; exactamente 31 días: válido; más de 31 días: error explícito.
- `sampleCount=0` conserva avg/min/max null.

## Costos y convivencia

Operación continua sin reintentos: 24 writes horarios + 1 diario por Device/día, cero lecturas para reconstruir el diario. Un read de Site al verificar inicialmente y lecturas adicionales si hace falta reintentar esa verificación. No hay writes remotos por cada muestra. El diario se publica en el primer ciclo posterior al cambio de fecha, no con un timer de medianoche.

Con 30 días: 750 writes/Device; 7.500 para 10 Devices; 75.000 para 100. Reintentos y consultas se contabilizan aparte. El legacy continúa alimentando `tenants/{t}/sites/{s}/plcs/{p}/metrics/temperature/...`; el nuevo servicio escribe `tenants/{t}/devices/{d}/historyHourly|historyDaily/...` y sigue siendo el futuro origen principal cuando migren sus consumidores. No se retira legacy automáticamente.

## Pruebas

Desde `backend/`:

```sh
dart test/device_environment_history_service_test.dart
dart test/device_environment_history_final_test.dart
dart test/device_environment_history_manual_verification_test.dart
```

La integración admite `FIRESTORE_EMULATOR_JAR=/ruta/cloud-firestore-emulator.jar` para usar un JAR local; de lo contrario usa Firebase CLI. Arranca un emulador aislado y lo detiene al terminar. No necesita credenciales productivas. El caso final verifica contra REST real: Site ausente→verified, pending+mismatch, restart con promedio diario exacto, rango UTC/ART, scope de las cuatro lecturas e idempotencia.

Desde raíz:

```sh
dart analyze backend
dart test/historicos_temperatura_humedad_firestore_rules_emulator_test.dart
flutter test
```

El informe HTML contiene las evidencias y la matriz de puntos de reinicio A–G.
