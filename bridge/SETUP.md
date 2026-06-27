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

El Garmin no dispara de forma fiable los botones de una notificación, así que la
acción desde el reloj va por **Tasker** (en el móvil) + un disparador en el reloj.

1. **Tasker** (Android): crea dos tareas con una sola acción **HTTP Request** cada una:
   - *Aprobar* → `POST` a `https://ntfy.sh/<TOPIC_DEC>` con cuerpo `allow`.
   - *Denegar* → `POST` a `https://ntfy.sh/<TOPIC_DEC>` con cuerpo `deny`.
   (Si te autoalojas con token, añade la cabecera `Authorization: Bearer <token>`.)
2. **Disparador en el reloj**: instala en el Garmin la app Connect IQ **Tasker
   Trigger** (de joaomgcd) y empareja sus disparadores con esas dos tareas de
   Tasker. Mapea, p. ej., dos entradas del menú/atajo del reloj a *Aprobar* y
   *Denegar*. (Los menús exactos varían por versión de la app; la idea: entrada del
   reloj → tarea de Tasker → POST al topic DEC.)
3. **Aviso en la muñeca**: la propia notificación de ntfy ya se refleja en el reloj
   (vibración + texto). Opcional: una tarea de Tasker que reaccione al broadcast de
   ntfy (`io.heckel.ntfy.MESSAGE_RECEIVED`) para vibrar de forma distinta.

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

**Importante (opt-in):** el hook `Stop` se dispara al final de **cada** turno, así
que solo actúa si activas el modo reprompt. Si no, no molesta.

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
3. **Activa/desactiva** cuando vayas a dejar algo corriendo:
   ```bash
   bridge/approver/reprompt.sh on    # … off / status
   ```
4. **Responder**: el push trae botones **Continúa / Tests / Commit** (publican un
   reprompt fijo en el topic REPROMPT). Para **texto libre**, publica cualquier
   mensaje a ese topic desde la app ntfy; ese texto es el reprompt. Desde el
   Garmin, igual que las decisiones: una tarea de Tasker que hace POST del reprompt.

Si respondes, Claude continúa con esa instrucción (`{"decision":"block"}`); si no
respondes en `BRIDGE_REPROMPT_TIMEOUT`, para normal.

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
