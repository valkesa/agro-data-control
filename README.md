# agro_data_control

Frontend Flutter + backend adapter Modbus TCP para Siemens LOGO!.

## Diagnóstico actual

- La UI consume un snapshot HTTP por `PLC_API_URL`.
- Hoy no existe un backend dentro de este repo que publique `/snapshot`.
- Tampoco hay configuración versionada para `--dart-define=PLC_API_URL=...` en desarrollo o producción.
- Si `PLC_API_URL` no se define, el frontend cae en placeholders.

## Backend

Se agregó un backend mínimo en [`backend/README.md`](/Users/jerry/APPS/valke-apps/agro_data_control/backend/README.md).

Levantar con:

```bash
dart run backend/bin/plc_snapshot_server.dart --config=backend/config/sites/default.json
```

Endpoints:

- `GET /snapshot`
- `GET /health`

## Frontend

Apuntar la app al backend con `PLC_API_URL`.

Desarrollo web:

```bash
flutter run -d chrome --dart-define=PLC_API_URL=http://localhost:8080/snapshot
```

Build web:

```bash
flutter build web --dart-define=PLC_API_URL=http://localhost:8080/snapshot
```

## JSON esperado por la app

```json
{
  "plcOnline": true,
  "lastUpdatedAt": "2026-04-01T12:00:00.000Z",
  "munters1": {
    "name": "Munters 1",
    "plcOnline": true,
    "tempInterior": 23.0,
    "humInterior": 61.0,
    "tempExterior": 29.0,
    "humExterior": 48.0,
    "presionDiferencial": 12.0,
    "fanGroup1": 0.7,
    "fanGroup2": 0.65,
    "tensionSalidaVentiladores": 7.1,
    "fanQ5": true,
    "fanQ6": true,
    "fanQ7": false,
    "fanQ8": true,
    "fanQ9": false,
    "fanQ10": false,
    "fanQ11": null,
    "bombaHumidificador": true,
    "resistencia1": false,
    "resistencia2": false,
    "alarmaGeneral": false,
    "fallaRed": false,
    "nivelAguaAlarma": null,
    "eventosSinAgua": null,
    "horasMunter": null,
    "horasPanelHumidificador": null,
    "horasFiltroF9": null,
    "horasFiltroG4": null,
    "horasPolifosfato": null,
    "salaAbierta": false,
    "aperturasSala": null,
    "munterAbierto": false,
    "aperturasMunter": null,
    "cantidadApagadas": null,
    "estadoEquipo": "En marcha"
  },
  "munters2": {
    "name": "Munters 2",
    "plcOnline": true
  }
}
```
