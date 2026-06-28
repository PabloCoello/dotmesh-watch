# bridge — guía de instalación (Claude + Android + Garmin)

Montaje de extremo a extremo del bridge de aprobación: un permiso de Claude Code
se convierte en un push que apruebas/deniegas desde el móvil o el Garmin. Cuatro
pasos: **ntfy → host (Claude) → móvil → reloj**.

## Cómo encaja

```
Claude (tool-use) ──PreToolUse hook (host)──┐ publica en topic REQ (+ botones)
   ▲                                          ▼
   │ allow/deny                         móvil (app ntfy / Garmin) ── pulsas ──┐
   └──── el hook lee la decisión ◀── topic DEC ◀───────────────────────────────┘
```

- **Botón en la notificación** (móvil): publica `"<id> allow|deny"` en el topic DEC.
- **Desde el Garmin**: Tasker publica un `allow`/`deny` "pelado" en el topic DEC
  (vale con una petición pendiente cada vez; ver "Multi-sesión").

---

## Paso 1 — ntfy (transporte)

Dos topics: uno para peticiones (REQ) y otro para decisiones (DEC).

```bash
echo "REQ: dotmesh-claude-req-$(openssl rand -hex 12)"
echo "DEC: dotmesh-claude-dec-$(openssl rand -hex 12)"
```

> **Seguridad en ntfy.sh (plan gratis):** los topics son públicos *por nombre*; no
> hay control de acceso real. **El nombre aleatorio ES el secreto** — trátalos como
> contraseñas y no los compartas. El `BRIDGE_TOKEN` solo aporta autenticación si
> reservas los topics (de pago) o **te autoalojas** ntfy (recomendado a futuro,
> idealmente tras Tailscale). Sin reserva/self-host, deja `BRIDGE_TOKEN` vacío.

---

## Paso 2 — Host (Claude Code)

Requisitos: `curl` y `jq`.

1. **Config**:
   ```bash
   cd dotmesh-watch
   cp bridge/approver/.env.example bridge/approver/.env
   $EDITOR bridge/approver/.env     # pega los topics; BRIDGE_TOKEN solo si aplica
   ```
2. **Registra el hook** en tu `settings.json` de Claude Code. Apunta al script por
   ruta absoluta y limita el matcher a lo que muta:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash|Write|Edit|MultiEdit|NotebookEdit",
           "hooks": [
             { "type": "command",
               "command": "/home/problemas/Documentos/GitHub/dotmesh-watch/bridge/approver/pretooluse-approve.sh",
               "timeout": 300 }
           ]
         }
       ]
     }
   }
   ```
   > **Ojo en esta máquina:** tu `~/.claude/settings.json` lo gestiona el paquete
   > `claude/` de dotmesh (stow). Edítalo en `dotmesh/claude/.claude/settings.json`
   > y `make restow`, **o** usa un `.claude/settings.json` por proyecto. No edites el
   > symlink a mano.
3. **Smoke test** (sin móvil): ver Paso 5.

---

## Paso 3 — Móvil (Android, app ntfy)

1. Instala **ntfy** (Play Store / F-Droid).
2. **Suscríbete al topic REQ**: botón **+** → escribe solo el **nombre** del topic
   (el valor de `BRIDGE_TOPIC_REQ`, sin `https://ntfy.sh/`); deja el servidor por
   defecto. **DEC no hace falta suscribirlo** — ahí *se envían* las decisiones (los
   botones hacen POST y el host escucha); suscríbelo solo para depurar.
   Si te autoalojas o reservas, configura el servidor y el token en la app.
3. Cuando Claude pida permiso, llega una notificación con dos botones, **Aprobar**
   y **Denegar**: un toque y listo. Eso publica la decisión en el topic DEC y el
   hook se libera. (Esto ya te sirve sin reloj.)

---

## Paso 4 — Garmin (decidir desde la muñeca)

La vía recomendada es el **approver nativo** ([`watchapp/`](watchapp/)): una app Connect
IQ que lee el topic REQ y publica la decisión sin Tasker ni apps de pago. En sus
*Properties*, **`reqTopic` es tu `BRIDGE_TOPIC_REQ`** (de donde lee lo pendiente) y
**`decTopic` tu `BRIDGE_TOPIC_DEC`** (donde manda el `"<id> allow|deny"`). Cuidado con no
confundir `reqTopic` (peticiones) con `repTopic` (reprompt del hook `Stop`, otro topic
distinto). Su instalación y configuración están en
[`watchapp/README.md`](watchapp/README.md).

La alternativa **legada** por **Tasker** (móvil) + un disparador en el reloj sigue aquí
para quien ya la use; el Garmin no dispara de forma fiable los botones de una
notificación.

1. **Tasker** (Android): crea dos tareas con una sola acción **HTTP Request** cada una:
   - *Aprobar* → `POST` a `https://ntfy.sh/<TOPIC_DEC>` con cuerpo `allow`.
   - *Denegar* → `POST` a `https://ntfy.sh/<TOPIC_DEC>` con cuerpo `deny`.
   (Si te autoalojas con token, añade la cabecera `Authorization: Bearer <token>`.)
2. **Disparador en el reloj**: instala en el Garmin la app Connect IQ **Tasker
   Trigger** (de joaomgcd) y empareja sus disparadores con esas dos tareas de
   Tasker. Mapea, p. ej., dos entradas del menú/atajo del reloj a *Aprobar* y
   *Denegar*. (Los menús exactos varían por versión de la app; la idea: entrada del
   reloj → tarea de Tasker → POST al topic DEC.)

### Aviso en la muñeca

Para enterarte de que hay algo que decidir hay tres opciones, de menos a más esfuerzo:

1. **Notificación de ntfy reflejada** (recomendado en v2): si el móvil tiene la app ntfy
   suscrita al topic REQ, su notificación se refleja en el reloj con vibración y texto.
   No requiere nada en el reloj y funciona con el approver nativo.
2. **`Attention.vibrate` en primer plano**: el approver puede vibrar al detectar una
   petición, pero solo mientras la app está abierta (Connect IQ no deja vibrar en
   segundo plano a una watch-app). Útil si dejas el approver en pantalla; no sirve como
   aviso pasivo. Pendiente de implementar.
3. **App compañera Android** (no recomendado en v2): una app/servicio propio que
   reaccione al broadcast de ntfy (`io.heckel.ntfy.MESSAGE_RECEIVED`) y empuje un aviso
   propio. Es lo que hacía la tarea de Tasker; aporta poco frente a la opción 1 y añade
   una pieza más que mantener.

---

## Paso 5 — Verificar

**A) El hook, aislado (sin móvil):**
```bash
# en una terminal: lanza el hook; imprime "id=..." por stderr y se queda esperando
echo '{"tool_name":"Bash","tool_input":{"command":"echo hola"}}' \
  | bridge/approver/pretooluse-approve.sh

# en otra terminal: responde (carga el .env para tener topic/token)
set -a; . bridge/approver/.env; set +a
curl ${BRIDGE_TOKEN:+-H "Authorization: Bearer $BRIDGE_TOKEN"} \
  -d "<id> allow" "$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_DEC"
# -> el hook emite {"hookSpecificOutput":{...,"permissionDecision":"allow"}} y sale
```

**B) E2E real (riesgo #1 — trabajas en bypass):** arranca Claude en bypass y pídele
un `Bash` **inocuo** (`ls`, `echo`). Debe llegarte el push y tu decisión debe mandar.
Usa algo inofensivo: si por lo que sea la base no frena, el comando se ejecutaría.

---

## Aviso al terminar + reprompt desde la muñeca (hook Stop)

Recibe un push con el resumen final cuando Claude acaba, y respóndele desde el
reloj para que continúe.

**Importante (opt-in por sesión):** el hook `Stop` se dispara al final de **cada**
turno, así que solo actúa en sesiones **vigiladas**. Marcas una sesión con
`/watch on` (mismo flag que el reenvío de permisos); el resto no molesta.

1. **Topic de vuelta**: genera `BRIDGE_TOPIC_REPROMPT`
   (`dotmesh-claude-rep-$(openssl rand -hex 12)`) y ponlo en `.env`.
2. **Registra el hook `Stop`** en `settings.json` (sin matcher):
   ```json
   { "hooks": { "Stop": [ { "hooks": [
     { "type": "command",
       "command": "/home/problemas/Documentos/GitHub/dotmesh-watch/bridge/approver/stop-reprompt.sh",
       "timeout": 320 } ] } ] } }
   ```
   (Pon `timeout` mayor que `BRIDGE_REPROMPT_TIMEOUT`.)
3. **Registra el hook `UserPromptSubmit`** (sin matcher) para que `/watch` funcione:
   ```json
   { "hooks": { "UserPromptSubmit": [ { "hooks": [
     { "type": "command",
       "command": "/home/problemas/Documentos/GitHub/dotmesh-watch/bridge/approver/userpromptsubmit-watch.sh" } ] } ] } }
   ```
4. **Vigila la sesión** que vayas a dejar corriendo: escribe `/watch on` en la
   propia conversación (`/watch off` para dejar de reenviar; `/watch` muestra el
   estado). Desde el terminal, `bridge/approver/watch.sh on|off` como respaldo.
   `reprompt.sh` queda como shim deprecado que delega en `watch.sh`.
5. **Responder**: el push trae botones **Continúa / Tests / Commit** (publican un
   reprompt fijo en el topic REPROMPT). Para **texto libre**, publica cualquier
   mensaje a ese topic desde la app ntfy; ese texto es el reprompt. Desde el
   Garmin, igual que las decisiones: una tarea de Tasker que hace POST del reprompt.

Si respondes, Claude continúa con esa instrucción (`{"decision":"block"}`); si no
respondes en `BRIDGE_REPROMPT_TIMEOUT`, para normal.

## Reflejar preguntas y avisos del arnés (hooks AskUserQuestion y Notification)

Dos hooks más que llevan al reloj lo que pasa en la conversación sin que tengas que
mirar la pantalla. El de preguntas es opt-in por sesión (solo en sesiones vigiladas);
el de avisos no (ver el detalle de cada uno abajo).

**Preguntas del arnés (`AskUserQuestion`).** Cuando Claude te pregunta con su menú,
el hook `pretooluse-ask.sh` refleja la pregunta y sus opciones al reloj. Por defecto
es **solo aviso** (E4): la respondes en el terminal como siempre. Regístralo con su
matcher (separado del de aprobación, que trataría mal esta herramienta):

```json
{ "hooks": { "PreToolUse": [ {
  "matcher": "AskUserQuestion",
  "hooks": [ { "type": "command",
    "command": "/home/problemas/Documentos/GitHub/dotmesh-watch/bridge/approver/pretooluse-ask.sh",
    "timeout": 310 } ] } ] } }
```

Responder desde la muñeca (E3) es **opt-in extra**: pon `BRIDGE_ANSWER_QUESTIONS=1`
en `.env`. Solo cubre menús de **una sola** pregunta y **sin** multiSelect; el resto
cae al aviso. El push lleva las opciones numeradas; respondes publicando en el topic
DEC `"<id> <n>"` (índice) o `"<id> <label>"`, igual que un allow/deny. Si no
respondes en `BRIDGE_TIMEOUT`, la pregunta sigue viva en el terminal.

> **Antes de activar E3:** falta confirmar en vivo que el arnés acepta la respuesta
> one-shot en una TUI interactiva (no `claude -p`). El spike está en
> `.ai/tmp/spike-ask/` (`RUNBOOK.md`). Hasta tener ese GO, deja
> `BRIDGE_ANSWER_QUESTIONS=0`: el aviso (E4) funciona igual.

**Avisos (`Notification`).** El hook `notification-notify.sh` refleja los avisos del
arnés (inactividad y permiso). No puede responder; es solo aviso. Regístralo **dos
veces**, una por matcher, pasando el tipo como argumento:

```json
{ "hooks": { "Notification": [
  { "matcher": "idle_prompt",
    "hooks": [ { "type": "command",
      "command": "/home/problemas/Documentos/GitHub/dotmesh-watch/bridge/approver/notification-notify.sh idle_prompt" } ] },
  { "matcher": "permission_prompt",
    "hooks": [ { "type": "command",
      "command": "/home/problemas/Documentos/GitHub/dotmesh-watch/bridge/approver/notification-notify.sh permission_prompt" } ] }
] } }
```

`idle_prompt` se **suprime en sesiones vigiladas** (el push del reprompt del hook
`Stop` ya avisa de que Claude espera; así no llega por duplicado). `permission_prompt`
avisa siempre, aunque en `bypassPermissions` casi nunca se dispara.

**Fallo por error de API (`StopFailure`).** El hook `stopfailure-notify.sh` avisa
cuando un turno muere por un error de API (rate limit, sobrecarga, error de
servidor...). El hook `Stop` **no** dispara en ese caso, ni tampoco en la
interrupción manual (Esc). Es solo aviso: un único push, sin botones ni espera.
Regístralo **sin matcher** (captura cualquier tipo de error):

```json
{ "hooks": { "StopFailure": [
  { "hooks": [ { "type": "command",
    "command": "/home/problemas/Documentos/GitHub/dotmesh-watch/bridge/approver/stopfailure-notify.sh" } ] }
] } }
```

Avisa **siempre** que haya transporte, esté o no vigilada la sesión (un fallo
conviene saberlo). Eso sí, el **nombre del proyecto** solo viaja en sesiones
vigiladas; las demás reciben un aviso genérico, para no filtrar metadatos de las que
optaste por no espejar.

## Qué escala a la muñeca (y qué no)

El hook **no** manda push por cada Bash/Write/Edit — eso sería insoportable en
bypass. Solo escala lo que parece peligroso; el resto pasa de largo (en bypass se
ejecuta como siempre, sin aviso):

- **Bash**: solo si el comando casa con `BRIDGE_DANGER_REGEX` (por defecto: `rm`
  con `-r`/`-f`, `--force`, `--hard`, `git clean -f`, `branch -D`, `sudo`, `dd if=`,
  `mkfs`, `chmod`/`chown -R`, `curl`/`wget` a `sh`/`bash`, `npm publish`, `shutdown`/
  `reboot`, `kubectl delete`, `terraform apply|destroy`, `docker rm|rmi|prune`).
- **Write/Edit/MultiEdit/NotebookEdit**: solo si la ruta cae **fuera del proyecto**
  (`cwd`) o toca algo sensible (`.ssh`, `id_rsa`, `.aws`, `credential`, `/etc`).
  Editar ficheros dentro del repo no avisa.

Para afinar, define `BRIDGE_DANGER_REGEX` en `.env` (sustituye al valor por
defecto, así que incluye lo que quieras conservar).

## Multi-sesión y seguridad

- El `allow`/`deny` **pelado** (el que manda el reloj) casa con *la* petición
  pendiente. Con **varias sesiones** de Claude compartiendo los mismos topics
  podrías aprobar la que no es. Solución: un **par de topics por sesión/equipo**, o
  usa solo los botones del push (que llevan el `id` correlacionado).
- **Fail-safe**: ante config ausente o timeout, el hook devuelve `ask` (decides en
  el terminal), nunca un `allow` mudo.
- El push **no** lleva contenido de ficheros: `Bash` → comando recortado; `Write`/
  `Edit` → solo la ruta.
- `bridge/approver/.env` está en `.gitignore`. No lo commitees.
