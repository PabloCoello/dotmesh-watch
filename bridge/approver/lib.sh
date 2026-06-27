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

# Cabecera Actions de ntfy: dos botones que publican la decisión correlacionada
# en el topic DEC (aprobar/denegar de un toque desde la notificación). $1=id
bridge_actions() {
  local id="$1" url="$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_DEC" auth=""
  [ -n "${BRIDGE_TOKEN:-}" ] && auth=", headers.Authorization='Bearer $BRIDGE_TOKEN'"
  printf "http, Aprobar, %s, method=POST, body='%s allow', clear=true%s; http, Denegar, %s, method=POST, body='%s deny', clear=true%s" \
    "$url" "$id" "$auth" "$url" "$id" "$auth"
}

# Publica el push de petición. $1=id $2=título $3=cuerpo
bridge_publish() {
  local id="$1" title="$2" body="$3"
  curl -fsS \
    ${BRIDGE_TOKEN:+-H "Authorization: Bearer $BRIDGE_TOKEN"} \
    -H "Title: $title" \
    -H "Tags: warning" \
    -H "X-Request-Id: $id" \
    -H "Actions: $(bridge_actions "$id")" \
    -d "$body" \
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

# Núcleo: lee la entrada de PreToolUse por stdin, decide vía ntfy y emite el JSON.
bridge_decide() {
  local input tool summary id start decision
  input=$(cat)
  tool=$(jq -r '.tool_name // "?"' <<<"$input")
  # Solo lo peligroso va a la muñeca; lo seguro pasa de largo (sin push ni
  # bloqueo). En bypass, eso significa que se ejecuta como siempre.
  bridge_is_dangerous "$tool" "$input" || return 0
  summary=$(bridge_summary "$tool" "$input")
  id=$(bridge_id)
  start=$(date +%s)
  # Diagnóstico/E2E: el id viaja en el push (X-Request-Id) y hace falta para
  # responder. Lo trazamos por stderr (no afecta a la decisión del hook).
  bridge_log "id=$id tool=$tool → responde \"$id allow|deny\" en ${BRIDGE_TOPIC_DEC:-?}"
  bridge_publish "$id" "Claude: aprobar $tool" "$summary"
  decision=$(bridge_wait_decision "$id" "$start" || true)
  case "$decision" in
    allow) bridge_emit allow "" ;;
    deny)  bridge_emit deny  "Denegado desde la muñeca" ;;
    *)     bridge_emit ask   "Sin respuesta del bridge (timeout); decide en el terminal" ;;
  esac
}

# ---- Reprompt al terminar una tarea (hook Stop) ----

# Último mensaje de texto del asistente en el transcript (el resumen final).
bridge_last_assistant() {
  local transcript="$1"
  [ -f "$transcript" ] || return 0
  jq -rs '
    [ .[] | select(.type=="assistant")
      | (if (.message.content|type)=="array"
         then ([.message.content[]?|select(.type=="text")|.text]|join("\n"))
         else (.message.content // "") end) ]
    | map(select(. != "")) | last // ""
  ' "$transcript" 2>/dev/null || true
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
  local input transcript summary text start
  input=$(cat)
  [ -e "${BRIDGE_REPROMPT_FLAG}" ] || return 0   # opt-in: sin flag, no molesta
  transcript=$(jq -r '.transcript_path // ""' <<<"$input")
  summary=$(bridge_last_assistant "$transcript" | tr '\n' ' ' | cut -c1-300)
  [ -n "$summary" ] || summary="(tarea terminada)"
  start=$(date +%s)
  bridge_log "reprompt: aviso enviado; espero ${BRIDGE_REPROMPT_TIMEOUT}s en ${BRIDGE_TOPIC_REPROMPT:-?}"
  bridge_publish_reprompt "$summary"
  text=$(bridge_wait_reprompt "$start" || true)
  [ -n "$text" ] && bridge_emit_continue "$text"
  return 0   # sin reprompt = deja parar limpio (no debe salir con error)
}
