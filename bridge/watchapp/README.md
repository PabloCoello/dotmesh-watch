# bridge/watchapp — approver nativo (Connect IQ)

App Connect IQ para **decidir desde la muñeca** sin Tasker ni apps de pago: un menú
con *Aprobar/Denegar* y los tres reprompts que **publica en ntfy** directamente con
`makeWebRequest`. Es una **segunda app** del repo (GUID propio, `type="watch-app"`),
independiente de la esfera; la esfera no se toca.

## Por qué nativo

El reloj sale a Internet por el móvil (tether BLE de Garmin Connect), así que el
propio reloj puede hacer el POST — no hace falta el puente Tasker. Esto sustituye al
artefacto de [`../tasker/`](../tasker/), que queda como alternativa legada para quien
ya use Tasker.

## Cómo publica en ntfy

`makeWebRequest` solo manda cuerpo JSON o form-urlencoded, no texto plano. ntfy
admite **publish-as-JSON**: `POST` al raíz con `{"topic": …, "message": …}`. Así que
la app pega a la **base** (raíz, p. ej. `https://ntfy.sh/`) con ese JSON, y ntfy lo
publica en el topic. Los mensajes son los mismos que manda el host (`../approver/lib.sh`):
`allow` / `deny` al topic DEC, y `continúa con lo siguiente` / `ejecuta los tests y
arregla lo que falle` / `haz commit de los cambios` al topic REP.

## Build

Comparte device (`epix2pro47mm`) y `developer_key.der` con la esfera:

```bash
make build-approver                       # compila bin/dotmesh-approver.prg
make sim-approver                         # simulador
make sideload-approver GARMIN_DIR=/ruta/GARMIN   # al reloj
```

## Configurar (sin secretos en el repo)

Los topics y el token van en los **App Settings** (Garmin Connect Mobile → la app →
Configuración), no en el código:

- **Base ntfy** — raíz con barra final. Por defecto `https://ntfy.sh/`.
- **Topic DEC** — tu `BRIDGE_TOPIC_DEC` (el del `.env` del host).
- **Topic REP** — tu `BRIDGE_TOPIC_REPROMPT`.
- **Token** — vacío en ntfy.sh; solo para self-host con auth.

En el simulador se ponen en *Settings → Edit Persistent Storage / App Settings*.

## Uso

Abre **approver** en el reloj → elige *Aprobar/Denegar* (permiso) o *Continúa/Tests/
Commit* (reprompt) → publica y muestra «Enviado». El aviso de que hay algo que
decidir llega por la notificación de ntfy reflejada en la muñeca.

## Pendiente (v2)

- Mostrar en la app el texto de lo que está pendiente (leer el NDJSON de `/json` de
  ntfy, que el parser JSON de CIQ no traga directo).
- Icono propio (ahora reusa el de la esfera).
- Acceso más rápido (glance/atajo) en vez de abrir la app.
- Vibración propia al llegar una petición.
