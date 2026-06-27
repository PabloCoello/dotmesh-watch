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

La app lee la config de **Properties** (`baseUrl`, `decTopic`, `repTopic`, `token`).
El fichero `resources/settings/properties.xml` está **gitignorado**; se versiona solo
`properties.xml.example`. Tu topic real vive en tu copia local, nunca en el repo
(igual que `approver/.env`).

> ⚠️ **Limitación conocida (sideload).** Editar estos valores desde **Garmin Connect
> Mobile → App Settings NO es fiable con una app *sideloadeada*** (no publicada en la
> store): GCM saca el descriptor de settings del servidor de la store, no del reloj, y
> puede **reiniciar el reloj**. Es un *watchdog reset*, no daña nada, pero **no abras
> esa pantalla** en un build sideloadeado. Configura por el fichero local (abajo).

### Build local con tu topic (recomendado al sideloadear)

```bash
cp bridge/watchapp/resources/settings/properties.xml.example \
   bridge/watchapp/resources/settings/properties.xml
$EDITOR bridge/watchapp/resources/settings/properties.xml   # pega decTopic/repTopic
make build-approver
make sideload-approver GARMIN_DIR=/ruta/GARMIN
```

- **baseUrl** — raíz con barra final. Por defecto `https://ntfy.sh/`.
- **decTopic** — tu `BRIDGE_TOPIC_DEC` (el del `.env` del host).
- **repTopic** — tu `BRIDGE_TOPIC_REPROMPT`.
- **token** — vacío en ntfy.sh; solo para self-host con auth.

> El default de una property **solo se aplica si la property aún no existe** en el
> reloj. Si antes abriste los settings en GCM (que pudo crearlas vacías), **borra la
> app y reinstálala** una vez para que el reloj tome los valores nuevos.

Cuando la **publiques en la store** (canal beta), los App Settings de GCM sí
funcionan y configuras desde el móvil sin tocar el build.

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
