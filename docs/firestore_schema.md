# Firestore schema

## Esquema vigente

- `tenants/{tenantId}/sites/{siteId}`
- `tenants/{tenantId}/sectors/{sectorId}`
- `tenants/{tenantId}/devices/{deviceId}`

Los documentos Sector y Device se vinculan con un Site mediante el campo
`siteId`.

`enabled` indica que el Site está habilitado administrativamente. No implica
que pueda consultar snapshots.

`provisioningStatus` indica el estado operativo del Site:

- `pending_backend`: estructura creada, backend operativo pendiente.
- `ready`: Site listo para flujo operativo y snapshots.
- `error`: aprovisionamiento o configuración operativa con error.

El alta de tenants nuevos debe crear solamente este modelo estructural:

- un documento Tenant;
- un documento Site inicial;
- uno o mas documentos Sector a nivel tenant;
- uno o mas documentos Device a nivel tenant.

El Site inicial de un tenant nuevo se crea con:

- `enabled: true`
- `provisioningStatus: pending_backend`

No debe usar `backendUrl` ni el endpoint global como fallback operativo.

## Esquema legacy

- `tenants/{tenantId}/sites/{siteId}/plcs/{plcId}`

Se conserva exclusivamente para compatibilidad con tenants existentes.
No debe utilizarse para tenants nuevos ni para nuevas funcionalidades.

Los campos `technicalId`, `backendUrl`, `active`, `displayName`,
`columnLabel` y `sortOrder` pertenecen al soporte legacy o a configuraciones
existentes del dashboard actual. No deben formar parte del flujo de alta de
tenants nuevos.
