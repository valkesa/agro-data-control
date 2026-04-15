# Backend Adapter

Backend mínimo para leer un Siemens LOGO! por Modbus TCP y publicar snapshots HTTP desde memoria.

## Configuración

El archivo por instalación vive en `backend/config/sites/*.json`.

Campos base:

- `clientName`
- `siteName`
- `plcHost`
- `plcPort`
- `unitId`
- `pollingIntervalMs`
- `timeoutMs`
- `httpHost`
- `httpPort`

Cada unidad (`munters1`, `munters2`) define `signals` con:

- `area`: `holdingRegister`, `inputRegister`, `coil`, `discreteInput`
- `address`
- `dataType`: `bool`, `int`, `double`, `string`
- `wordCount`
- `signed`
- `scale`
- `offset`
- `wordOrder`
- `bitIndex`
- `enumMap`

## Endpoint

`GET /snapshot`

`GET /api/snapshot`

El servidor HTTP responde siempre desde el último snapshot cacheado en memoria.
La lectura al PLC corre en background y conserva el último snapshot válido ante fallos.

Respuesta compatible con el frontend actual:

```json
{
  "plcOnline": true,
  "lastUpdatedAt": "2026-04-01T12:00:00.000Z",
  "clientName": "Cliente Demo",
  "siteName": "Sitio Demo",
  "refreshInProgress": false,
  "status": {
    "plcOnline": true,
    "lastUpdatedAt": "2026-04-01T12:00:00.000Z",
    "clientName": "Cliente Demo",
    "siteName": "Sitio Demo",
    "lastError": null,
    "startedAt": "2026-04-01T11:59:00.000Z",
    "lastPollDurationMs": 120,
    "consecutiveFailures": 0,
    "refreshInProgress": false,
    "hasFreshSnapshot": true
  },
  "munters1": {
    "name": "Munters 1",
    "plcOnline": true,
    "tempInterior": 23.0,
    "humInterior": 61.0
  },
  "munters2": {
    "name": "Munters 2",
    "plcOnline": true
  }
}
```

## Levantar

```bash
dart run backend/bin/plc_snapshot_server.dart --config=backend/config/sites/default.json
```
