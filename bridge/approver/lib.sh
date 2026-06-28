# bridge/approver/lib.sh — helpers compartidos del bridge.
#
# Transporte: ntfy ida y vuelta. El host publica la petición en BRIDGE_TOPIC_REQ
# y espera la decisión correlacionada por id en BRIDGE_TOPIC_DEC. Sin puertos
# abiertos en el host. Config por entorno (ver .env.example).
#
# Pensado para ser "sourced" desde los hooks y desde test.sh. El test redefine
# bridge_publish / bridge_wait_decision para probar sin red.

: "${BRIDGE_NTFY_BASE:=https://ntfy.sh}"
: "${BRIDGE_TIMEOUT:=300}"

# Reprompt al terminar (hook Stop). Opt-in por flag: el hook Stop se dispara en
# CADA turno, así que sin el flag bloquearía siempre. Actívalo con `reprompt.sh on`.
: "${BRIDGE_REPROMPT_TIMEOUT:=300}"
: "${BRIDGE_REPROMPT_FLAG:=${XDG_CACHE_HOME:-$HOME/.cache}/dotmesh-bridge/reprompt-on}"

# Reenvío por sesión (opt-in). Solo las sesiones marcadas (su flag existe) escalan
# permisos y disparan el reprompt; las demás pasan de largo. Lo gestionan watch.sh
# y el hook UserPromptSubmit.
: "${BRIDGE_FORWARD_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/dotmesh-bridge}"

# Comandos Bash que SÍ escalan a la muñeca (regex extendida). Lo demás pasa de
# largo sin push: en bypass se ejecuta como siempre. Override/extiende en .env.
: "${BRIDGE_DANGER_REGEX:=rm +-[a-zA-Z]*[rf]|--force|--hard|git +clean +-[a-zA-Z]*f|git +branch +-D|sudo +|dd +if=|mkfs|chmod +-R|chown +-R|(curl|wget) +[^|]*\| *(sh|bash)|npm +publish|shutdown|reboot|poweroff|kubectl +delete|terraform +(apply|destroy)|docker +(rm|rmi|system +prune)}"

bridge_log() { printf 'bridge: %s\n' "$*" >&2; }

# Id de correlación para una petición.
bridge_id() {
  cat /proc/sys/kernel/random/uuid 2>/dev/null || printf '%s-%s' "$(date +%s)" "$RANDOM"
}

# Resumen seguro para el push: nunca contenido de ficheros ni variables.
# $1=tool_name  $2=json de entrada completo
bridge_summary() {
  local tool="$1" input="$2"
  case "$tool" in
    Bash)
      jq -r '.tool_input.command // ""' <<<"$input" | tr '\n' ' ' | cut -c1-200
      ;;
    Write|Edit|MultiEdit|NotebookEdit)
      jq -r '.tool_input.file_path // .tool_input.notebook_path // "?"' <<<"$input"
      ;;
    *)
      printf '%s' "$tool"
      ;;
  esac
}

# ¿La ruta de un Write/Edit es peligrosa? Seguro si es relativa o cuelga del cwd;
# peligroso si es absoluta fuera del cwd o toca rutas sensibles. $1=ruta $2=cwd
bridge_path_dangerous() {
  local path="$1" cwd="$2"
  case "$path" in
    */.ssh/*|*id_rsa*|*/.aws/*|*credential*|/etc/*) return 0 ;;  # sensible
  esac
  # Sin cwd confirmado no podemos dar por "dentro del proyecto" una ruta absoluta.
  if [ -n "$cwd" ]; then
    case "$path" in
      "$cwd"/*|"$cwd") return 1 ;;  # dentro del proyecto -> seguro
    esac
  fi
  case "$path" in
    /*) return 0 ;;   # absoluta fuera del cwd -> escala
    *)  return 1 ;;   # relativa (cuelga del cwd) -> seguro
  esac
}

# ¿Esta llamada a herramienta debe escalar a la muñeca? 0=sí (peligrosa) 1=no.
# $1=tool_name  $2=json de entrada
bridge_is_dangerous() {
  local tool="$1" input="$2" cmd cwd path
  case "$tool" in
    Bash)
      cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
      [[ $cmd =~ $BRIDGE_DANGER_REGEX ]]
      ;;
    Write|Edit|MultiEdit|NotebookEdit)
      cwd=$(jq -r '.cwd // ""' <<<"$input")
      path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
      bridge_path_dangerous "$path" "$cwd"
      ;;
    *) return 0 ;;   # herramienta inesperada en el matcher -> por seguridad, escala
  esac
}

# ¿Está esta sesión vigilada desde la muñeca? El session_id viene del stdin (no
# confiable) -> se sanea para el nombre del flag (evita path traversal).
bridge_sid_safe()     { printf '%s' "$1" | tr -cd 'A-Za-z0-9._-'; }
bridge_forward_flag() { printf '%s/forward-%s' "$BRIDGE_FORWARD_DIR" "$(bridge_sid_safe "$1")"; }
bridge_is_watched() {
  local sid="$1"
  [ -n "$sid" ] || return 1
  [ -e "$(bridge_forward_flag "$sid")" ]
}

# Cabecera Actions de ntfy: dos botones que publican la decisión correlacionada
# en el topic DEC (aprobar/denegar de un toque desde la notificación). $1=id
bridge_actions() {
  local id="$1" url="$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_DEC" auth=""
  [ -n "${BRIDGE_TOKEN:-}" ] && auth=", headers.Authorization='Bearer $BRIDGE_TOKEN'"
  printf "http, Aprobar, %s, method=POST, body='%s allow', clear=true%s; http, Denegar, %s, method=POST, body='%s deny', clear=true%s" \
    "$url" "$id" "$auth" "$url" "$id" "$auth"
}

# Etiqueta legible de la sesión, para X-Title del push y para el cuerpo. Sin 0x1f
# ni saltos. $1=cwd $2=session_id
bridge_session_label() {
  local cwd="$1" sid="$2" base short label
  if [ -n "$cwd" ]; then base=$(basename -- "$cwd"); else base="claude"; fi
  [ -n "$base" ] || base="claude"
  short=$(printf '%s' "$sid" | cut -c1-8)
  if [ -n "$short" ]; then label="$base ($short)"; else label="$base"; fi
  printf '%s' "$label" | tr -d '\037\n'
}

# Cuerpo machine-splittable del push: id␟label␟tool␟summary separados por US
# (0x1f). El reloj lo parte; el summary ya viene sin saltos (bridge_summary).
# $1=id $2=label $3=tool $4=summary
bridge_request_body() {
  local us; us=$(printf '\037')
  printf '%s%s%s%s%s%s%s' "$1" "$us" "$2" "$us" "$3" "$us" "$4"
}

# Publica el push de petición. Cuerpo machine-splittable para el reloj; X-Title
# legible para el móvil. $1=id $2=label $3=tool $4=summary
bridge_publish() {
  local id="$1" label="$2" tool="$3" summary="$4"
  curl -fsS \
    ${BRIDGE_TOKEN:+-H "Authorization: Bearer $BRIDGE_TOKEN"} \
    -H "X-Title: $label" \
    -H "Tags: warning" \
    -H "X-Request-Id: $id" \
    -H "Actions: $(bridge_actions "$id")" \
    --data-binary "$(bridge_request_body "$id" "$label" "$tool" "$summary")" \
    "$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_REQ" >/dev/null
}

# Clasifica un mensaje del topic DEC. $1=id $2=mensaje -> "allow" | "deny" | "".
# Acepta la forma correlacionada ("<id> allow", la usan los botones del push) y
# la pelada ("allow", la usa la tarea estática de Tasker desde el reloj: vale
# con una petición pendiente por par de topics; ver SETUP.md).
bridge_match() {
  case "$2" in
    "$1 allow"|"$1 approve"|allow|approve) printf allow ;;
    "$1 deny"|"$1 reject"|deny|reject)     printf deny  ;;
    *) : ;;
  esac
}

# Espera la decisión del id. Imprime "allow" o "deny"; vacío si timeout.
# $1=id  $2=since (unix ts)
bridge_wait_decision() {
  local id="$1" since="${2:-all}" line ev msg m
  curl -fsS --no-buffer --max-time "$BRIDGE_TIMEOUT" \
    ${BRIDGE_TOKEN:+-H "Authorization: Bearer $BRIDGE_TOKEN"} \
    "$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_DEC/json?since=$since" 2>/dev/null | \
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ev=$(jq -r '.event // empty' <<<"$line" 2>/dev/null) || continue
    [ "$ev" = "message" ] || continue
    msg=$(jq -r '.message // empty' <<<"$line" 2>/dev/null)
    m=$(bridge_match "$id" "$msg")
    [ -n "$m" ] && { echo "$m"; break; }
  done
}

# Emite el JSON de PreToolUse. $1=allow|deny|ask  $2=razón (vacía = sin razón)
bridge_emit() {
  jq -nc --arg d "$1" --arg r "$2" '
    {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d}}
    | if $r == "" then . else .hookSpecificOutput.permissionDecisionReason = $r end
  '
}

# Decisión de reserva cuando el bridge no responde (timeout) o está sin
# configurar. En modos NO interactivos (bypassPermissions, dontAsk) un "ask" de
# hook no abre diálogo y el comando peligroso se ejecutaría igual; un "deny" sí
# se respeta incluso en bypass. Así el fail-safe es seguro en full-auto. En modos
# interactivos delega al terminal con "ask". $1=permission_mode (vacío = ask).
bridge_fallback_decision() {
  case "$1" in
    bypassPermissions|dontAsk) printf deny ;;
    *)                         printf ask  ;;
  esac
}

# Núcleo: lee la entrada de PreToolUse por stdin, decide vía ntfy y emite el JSON.
bridge_decide() {
  local input tool summary id start decision mode cwd session_id label
  input=$(cat)
  session_id=$(jq -r '.session_id // ""' <<<"$input")
  # Opt-in por sesión: solo las sesiones vigiladas escalan; el resto pasa de largo.
  bridge_is_watched "$session_id" || return 0
  tool=$(jq -r '.tool_name // "?"' <<<"$input")
  mode=$(jq -r '.permission_mode // ""' <<<"$input")
  # Solo lo peligroso va a la muñeca; lo seguro pasa de largo (sin push ni
  # bloqueo). En bypass, eso significa que se ejecuta como siempre.
  bridge_is_dangerous "$tool" "$input" || return 0
  summary=$(bridge_summary "$tool" "$input")
  cwd=$(jq -r '.cwd // ""' <<<"$input")
  label=$(bridge_session_label "$cwd" "$session_id")
  id=$(bridge_id)
  start=$(date +%s)
  # Diagnóstico/E2E: el id viaja en el push (X-Request-Id) y hace falta para
  # responder. Lo trazamos por stderr (no afecta a la decisión del hook).
  bridge_log "id=$id tool=$tool → responde \"$id allow|deny\" en ${BRIDGE_TOPIC_DEC:-?}"
  bridge_publish "$id" "$label" "$tool" "$summary"
  decision=$(bridge_wait_decision "$id" "$start" || true)
  case "$decision" in
    allow) bridge_emit allow "" ;;
    deny)  bridge_emit deny  "Denegado desde la muñeca" ;;
    *)
      if [ "$(bridge_fallback_decision "$mode")" = deny ]; then
        bridge_emit deny "Sin respuesta del bridge (timeout) en modo $mode; denegado por seguridad"
      else
        bridge_emit ask "Sin respuesta del bridge (timeout); decide en el terminal"
      fi
      ;;
  esac
}

# ---- Reprompt al terminar una tarea (hook Stop) ----

# Resumen final para el push. El stdin de Stop trae el último mensaje del
# asistente en .last_assistant_message; si falta (versión antigua), cae al parseo
# del transcript. Si ese mensaje acaba con la centinela del skill watch-summary
# (línea "WATCH: ..."), se prefiere esa línea, sin el tag y capada a 200, para que
# el usuario nunca vea "WATCH:". Si no hay centinela, devuelve el texto completo
# (lo recorta el caller). $1 = JSON de entrada del hook Stop.
bridge_last_assistant() {
  local input="$1" raw transcript watch
  raw=$(jq -r '.last_assistant_message // ""' <<<"$input" 2>/dev/null) || true
  if [ -z "$raw" ]; then
    transcript=$(jq -r '.transcript_path // ""' <<<"$input" 2>/dev/null) || true
    if [ -f "$transcript" ]; then
      raw=$(jq -rs '
        [ .[] | select(.type=="assistant")
          | (if (.message.content|type)=="array"
             then ([.message.content[]?|select(.type=="text")|.text]|join("\n"))
             else (.message.content // "") end) ]
        | map(select(. != "")) | last // ""
      ' "$transcript" 2>/dev/null) || true
    fi
  fi
  watch=$(printf '%s\n' "$raw" | grep -E '^[[:space:]]*WATCH:' | tail -n1 || true)
  if [ -n "$watch" ]; then
    watch=${watch#*WATCH:}
    watch=${watch# }
    printf '%s' "$watch" | cut -c1-200
  else
    printf '%s' "$raw"
  fi
}

# Botones de reprompt predefinido (publican texto en el topic REPROMPT). Máx. 3.
bridge_reprompt_actions() {
  local url="$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_REPROMPT" auth=""
  [ -n "${BRIDGE_TOKEN:-}" ] && auth=", headers.Authorization='Bearer $BRIDGE_TOKEN'"
  printf "http, Continúa, %s, method=POST, body='continúa con lo siguiente', clear=true%s; http, Tests, %s, method=POST, body='ejecuta los tests y arregla lo que falle', clear=true%s; http, Commit, %s, method=POST, body='haz commit de los cambios', clear=true%s" \
    "$url" "$auth" "$url" "$auth" "$url" "$auth"
}

# Push de "tarea terminada" con el resumen y los botones de reprompt. $1=resumen
bridge_publish_reprompt() {
  curl -fsS \
    ${BRIDGE_TOKEN:+-H "Authorization: Bearer $BRIDGE_TOKEN"} \
    -H "Title: Claude terminó — ¿siguiente?" \
    -H "Tags: white_check_mark" \
    -H "Actions: $(bridge_reprompt_actions)" \
    -d "$1" \
    "$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_REQ" >/dev/null
}

# Espera un reprompt (cualquier mensaje no vacío) en el topic REPROMPT. $1=since.
bridge_wait_reprompt() {
  local since="${1:-all}" line ev msg
  curl -fsS --no-buffer --max-time "$BRIDGE_REPROMPT_TIMEOUT" \
    ${BRIDGE_TOKEN:+-H "Authorization: Bearer $BRIDGE_TOKEN"} \
    "$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_REPROMPT/json?since=$since" 2>/dev/null | \
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ev=$(jq -r '.event // empty' <<<"$line" 2>/dev/null) || continue
    [ "$ev" = "message" ] || continue
    msg=$(jq -r '.message // empty' <<<"$line" 2>/dev/null)
    [ -n "$msg" ] && { printf '%s' "$msg"; break; }
  done
}

# Emite el JSON del hook Stop para continuar con un reprompt. $1=texto
bridge_emit_continue() {
  jq -nc --arg r "$1" '{decision: "block", reason: $r}'
}

# Núcleo del hook Stop: si el modo reprompt está activo (flag), avisa con el
# resumen y espera un reprompt; si llega, hace continuar a Claude. Si no, calla
# (deja parar). Lee la entrada del hook Stop por stdin.
bridge_reprompt() {
  local input session_id summary text start
  input=$(cat)
  session_id=$(jq -r '.session_id // ""' <<<"$input")
  bridge_is_watched "$session_id" || return 0   # opt-in por sesión: si no, no molesta
  summary=$(bridge_last_assistant "$input" | tr '\n' ' ' | cut -c1-300)
  [ -n "$summary" ] || summary="(tarea terminada)"
  start=$(date +%s)
  bridge_log "reprompt: aviso enviado; espero ${BRIDGE_REPROMPT_TIMEOUT}s en ${BRIDGE_TOPIC_REPROMPT:-?}"
  bridge_publish_reprompt "$summary"
  text=$(bridge_wait_reprompt "$start" || true)
  [ -n "$text" ] && bridge_emit_continue "$text"
  return 0   # sin reprompt = deja parar limpio (no debe salir con error)
}
