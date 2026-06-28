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

# Reprompt al terminar (hook Stop): cuántos segundos espera tu reprompt. El opt-in
# del Stop es por sesión (vigilada), igual que el reenvío de permisos (ver abajo).
: "${BRIDGE_REPROMPT_TIMEOUT:=300}"

# Reenvío por sesión (opt-in). Solo las sesiones marcadas (su flag existe) escalan
# permisos y disparan el reprompt; las demás pasan de largo. Lo gestionan watch.sh
# y el hook UserPromptSubmit.
: "${BRIDGE_FORWARD_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/dotmesh-bridge}"

# Contexto inyectado en sesiones vigiladas (hook UserPromptSubmit): pide cerrar el
# turno final con la centinela del skill watch-summary, para que el resumen quepa
# en el reloj. Override en .env si quieres afinar el texto.
: "${BRIDGE_WATCH_CONTEXT:=Esta sesión se refleja en el reloj (bridge dotmesh-watch). Termina SIEMPRE el turno final con una única línea, la última del mensaje, con el formato exacto: WATCH: <ESTADO> <asunto> · <siguiente-acción>. ESTADO es uno de OK/FALLO/BLOQUEADO/ESPERA, en castellano, sin markdown, <=160 caracteres; mapea la siguiente-acción a Continúa/Tests/Commit cuando encaje. Detalle en la skill watch-summary.}"

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

# ¿El prompt es el comando de toggle? Imprime on|off|status y devuelve 0 si casa
# ("/watch [on|off|status]" o sin barra; sin argumento = status); si no, return 1.
bridge_watch_parse() {
  local p="$1" arg
  if [[ "$p" =~ ^[[:space:]]*/?watch([[:space:]]+(on|off|status))?[[:space:]]*$ ]]; then
    arg="${BASH_REMATCH[2]}"
    printf '%s' "${arg:-status}"
    return 0
  fi
  return 1
}

# Activa/desactiva/consulta la vigilancia de una sesión. $1=on|off|status $2=sid.
# Imprime el estado resultante (on|off); devuelve 2 si falta el sid.
bridge_watch_set() {
  local action="$1" sid="$2" flag
  [ -n "$sid" ] || return 2
  flag=$(bridge_forward_flag "$sid")
  case "$action" in
    on)  mkdir -p "$BRIDGE_FORWARD_DIR"; : > "$flag"; printf 'on' ;;
    off) rm -f "$flag"; printf 'off' ;;
    *)   bridge_is_watched "$sid" && printf 'on' || printf 'off' ;;
  esac
}

# Registra el session_id activo (global y por cwd) para que watch.sh pueda
# togglear desde el terminal sin conocerlo. $1=sid $2=cwd
bridge_record_session() {
  local sid="$1" cwd="$2" h
  [ -n "$sid" ] || return 0
  mkdir -p "$BRIDGE_FORWARD_DIR"
  printf '%s' "$sid" > "$BRIDGE_FORWARD_DIR/last-session"
  [ -n "$cwd" ] || return 0
  h=$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)
  printf '%s' "$sid" > "$BRIDGE_FORWARD_DIR/last-session-$h"
}

# session_id más reciente registrado: por cwd si se pasa, si no el global. $1=cwd
bridge_last_session() {
  local cwd="$1" h f="$BRIDGE_FORWARD_DIR/last-session"
  if [ -n "$cwd" ]; then
    h=$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)
    [ -f "$BRIDGE_FORWARD_DIR/last-session-$h" ] && f="$BRIDGE_FORWARD_DIR/last-session-$h"
  fi
  [ -f "$f" ] && cat "$f" || true
}

# Emite el JSON de UserPromptSubmit que descarta el prompt y muestra un motivo,
# para que "/watch ..." no consuma un turno. $1=motivo
bridge_emit_block() {
  jq -nc --arg r "$1" '{decision: "block", reason: $r}'
}

# Inyecta additionalContext en UserPromptSubmit (texto extra para el modelo, sin
# bloquear el prompt). $1=texto
bridge_emit_context() {
  jq -nc --arg c "$1" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
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

# Núcleo del hook Stop: si la sesión está vigilada, avisa con el resumen y espera
# un reprompt; si llega, hace continuar a Claude. Si no, calla (deja parar). Lee
# la entrada del hook Stop por stdin.
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

# ---- Preguntas del arnés (hook PreToolUse matcher AskUserQuestion) ----
#
# Dos modos sobre el mismo hook (pretooluse-ask.sh):
#  - E4 (por defecto): refleja la pregunta al reloj como AVISO y NO responde; tú
#    sigues respondiendo en el terminal (stdout vacío -> la tool procede normal).
#  - E3 (opt-in extra, BRIDGE_ANSWER_QUESTIONS=1): intenta RESPONDER desde la
#    muñeca una pregunta única y no-multiSelect; si no es respondible o hay
#    timeout, cae al mirror read-only. La forma de updatedInput.answers
#    ({pregunta: label}) se confirmó en el spike E1; habilitar E3 en producción
#    exige antes el GO del spike E2 (TUI interactiva). Ver SETUP.md.

# Resumen seguro de la(s) pregunta(s) para el push: header + question + labels de
# las opciones. Son textos del modelo (no contenido de ficheros), pero igual se
# limpian US/saltos y se recorta. $1=JSON de entrada del hook.
bridge_question_summary() {
  # jq -j (sin salto final): así una entrada vacía da "" y no " ", y el fallback
  # "(pregunta sin texto)" de bridge_mirror_question se activa de verdad.
  jq -j '
    [ .tool_input.questions[]?
      | ((.header // "") as $h | (.question // "") as $q
         | if $h != "" and $q != "" then $h + ": " + $q
           elif $q != "" then $q else $h end)
        + ( [.options[]?.label]
            | if length > 0 then "  [" + join(" · ") + "]" else "" end )
    ] | join(" / ")
  ' <<<"$1" 2>/dev/null | tr '\037\n' '  ' | cut -c1-300
}

# Refleja la pregunta al reloj como aviso (E4): X-Title fijo, SIN Actions y SIN
# cuerpo machine-splittable (el parser del reloj ignora líneas sin US -> no
# ensucia el picker de decisiones). Read-only: no emite stdout. $1=input.
bridge_mirror_question() {
  local summary; summary=$(bridge_question_summary "$1")
  [ -n "$summary" ] || summary="(pregunta sin texto)"
  curl -fsS \
    ${BRIDGE_TOKEN:+-H "Authorization: Bearer $BRIDGE_TOKEN"} \
    -H "X-Title: Claude pregunta" \
    -H "Tags: speech_balloon" \
    -d "$summary" \
    "$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_REQ" >/dev/null || return 0   # best-effort
}

# ¿Es una pregunta respondible desde la muñeca (E3 v1)? Solo una pregunta y sin
# multiSelect; lo demás cae al mirror read-only (E4). $1=input -> 0=sí 1=no.
bridge_question_answerable() {
  local ok
  ok=$(jq -r '
    (.tool_input.questions // []) as $qs
    | if ($qs | length) == 1
         and (($qs[0].multiSelect // false) | not)
         and (($qs[0].question // null) | type) == "string"
         and (($qs[0].options // null) | type) == "array"
         and (($qs[0].options | length) >= 1)
      then "1" else "0" end
  ' <<<"$1" 2>/dev/null) || return 1
  [ "$ok" = 1 ]
}

# Cuerpo del push de una pregunta respondible: enunciado, opciones numeradas y la
# instrucción de respuesta correlacionada. $1=id $2=input.
bridge_question_prompt() {
  jq -r --arg id "$1" '
    .tool_input.questions[0] as $q
    | ( ($q.header // "") as $h
        | (if $h != "" then $h + " — " else "" end) + ($q.question // "") ),
      ( [ $q.options | to_entries[] | "  \(.key + 1)) \(.value.label)" ] | .[] ),
      ( "Responde: \"" + $id + " <n>\"" )
  ' <<<"$2" 2>/dev/null
}

# Publica la pregunta respondible al reloj (E3). X-Request-Id para correlacionar;
# SIN Actions (la respuesta llega por texto en DEC: "<id> <n|label>"). Los botones
# del reloj para opciones llegan con la app CIQ (M4). $1=id $2=label $3=input.
bridge_publish_question() {
  local id="$1" label="$2" input="$3"
  curl -fsS \
    ${BRIDGE_TOKEN:+-H "Authorization: Bearer $BRIDGE_TOKEN"} \
    -H "X-Title: $label — Claude pregunta" \
    -H "Tags: speech_balloon" \
    -H "X-Request-Id: $id" \
    -d "$(bridge_question_prompt "$id" "$input" | tr -d '\037')" \
    "$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_REQ" >/dev/null || return 0   # best-effort
}

# Mapea un mensaje del topic DEC a la label elegida. Acepta "<id> <n>" (índice
# 1-based) o "<id> <label>" (case-insensitive). $1=id $2=mensaje $3=input ->
# imprime la label o vacío.
bridge_match_answer() {
  local id="$1" msg="$2" input="$3" rest
  case "$msg" in
    "$id "*) rest=${msg#"$id" } ;;
    *) return 0 ;;
  esac
  # Índice 1-based: exige [1-9][0-9]* para descartar "0" (que en jq sería
  # options[-1] = la última opción) y los ceros a la izquierda (que --argjson
  # rechazaría). Un "0" cae a la rama de label y, al no casar, devuelve vacío.
  if printf '%s' "$rest" | grep -qE '^[1-9][0-9]*$'; then
    jq -r --argjson k "$rest" '.tool_input.questions[0].options[$k - 1].label // ""' <<<"$input" 2>/dev/null
    return 0
  fi
  jq -r --arg a "$rest" '
    [ .tool_input.questions[0].options[]?.label
      | select((ascii_downcase) == ($a | ascii_downcase)) ] | first // ""
  ' <<<"$input" 2>/dev/null
}

# Espera la respuesta correlacionada del id en DEC. Imprime la label elegida;
# vacío si timeout. $1=id $2=since (unix ts) $3=input.
bridge_wait_answer() {
  local id="$1" since="${2:-all}" input="$3" line ev msg label
  curl -fsS --no-buffer --max-time "$BRIDGE_TIMEOUT" \
    ${BRIDGE_TOKEN:+-H "Authorization: Bearer $BRIDGE_TOKEN"} \
    "$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_DEC/json?since=$since" 2>/dev/null | \
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ev=$(jq -r '.event // empty' <<<"$line" 2>/dev/null) || continue
    [ "$ev" = "message" ] || continue
    msg=$(jq -r '.message // empty' <<<"$line" 2>/dev/null)
    label=$(bridge_match_answer "$id" "$msg" "$input")
    [ -n "$label" ] && { printf '%s' "$label"; break; }
  done
}

# Construye el updatedInput de la respuesta: tool_input + answers como mapa
# {pregunta: label} (forma confirmada en E1). $1=input $2=label elegida.
bridge_answer_input() {
  jq -c --arg a "$2" '.tool_input + { answers: { (.tool_input.questions[0].question): $a } }' <<<"$1" 2>/dev/null
}

# Emite el JSON de PreToolUse que responde la pregunta (allow + updatedInput).
# $1=updatedInput (JSON).
bridge_emit_answer() {
  jq -nc --argjson ui "$1" '
    {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput: $ui}}
  '
}

# Núcleo del hook AskUserQuestion. Opt-in por sesión. Con BRIDGE_ANSWER_QUESTIONS=1
# y DEC configurado y pregunta respondible: publica, espera y responde (E3);
# si no, refleja read-only (E4). $1=JSON de entrada del hook.
bridge_ask() {
  local input="$1" session_id cwd label id start choice ui
  session_id=$(jq -r '.session_id // ""' <<<"$input")
  bridge_is_watched "$session_id" || return 0   # opt-in por sesión
  if [ "${BRIDGE_ANSWER_QUESTIONS:-0}" = 1 ] && [ -n "${BRIDGE_TOPIC_DEC:-}" ] \
     && bridge_question_answerable "$input"; then
    cwd=$(jq -r '.cwd // ""' <<<"$input")
    label=$(bridge_session_label "$cwd" "$session_id")
    id=$(bridge_id)
    start=$(date +%s)
    bridge_log "pregunta id=$id → responde \"$id <n>\" en ${BRIDGE_TOPIC_DEC:-?}"
    bridge_publish_question "$id" "$label" "$input"
    choice=$(bridge_wait_answer "$id" "$start" "$input" || true)
    if [ -n "$choice" ]; then
      ui=$(bridge_answer_input "$input" "$choice")
      bridge_emit_answer "$ui"
    fi
    return 0   # timeout/sin elección -> sin stdout: la pregunta sigue en el terminal
  fi
  bridge_mirror_question "$input"   # E4: aviso read-only
  return 0
}

# ---- Avisos del arnés (hook Notification) ----

# Publica un aviso simple al reloj (E5): .message del payload, X-Title según el
# tipo, SIN Actions (Notification es solo efecto, no puede responder).
# $1=título $2=mensaje.
bridge_publish_notification() {
  local title="$1" message="$2"
  [ -n "$message" ] || return 0
  curl -fsS \
    ${BRIDGE_TOKEN:+-H "Authorization: Bearer $BRIDGE_TOKEN"} \
    -H "X-Title: $title" \
    -H "Tags: bell" \
    -d "$message" \
    "$BRIDGE_NTFY_BASE/$BRIDGE_TOPIC_REQ" >/dev/null || return 0   # best-effort
}

# Núcleo del hook Notification. $1=kind (idle_prompt|permission_prompt|otro). Lee
# el payload por stdin. de-dup: idle_prompt se SUPRIME en sesiones vigiladas
# (el push del reprompt del hook Stop ya cubre ese caso); permission_prompt
# siempre avisa (es un bloqueo de permiso, conviene saberlo).
bridge_notify() {
  local kind="${1:-}" input session_id message title
  input=$(cat)
  message=$(jq -r '.message // ""' <<<"$input" 2>/dev/null)
  [ -n "$message" ] || return 0
  session_id=$(jq -r '.session_id // ""' <<<"$input" 2>/dev/null)
  case "$kind" in
    idle_prompt)
      bridge_is_watched "$session_id" && return 0   # de-dup con el reprompt de Stop
      title="Claude en espera" ;;
    permission_prompt) title="Claude pide permiso" ;;
    *)                 title="Claude" ;;
  esac
  bridge_publish_notification "$title" "$message"
}
