#!/usr/bin/env bash
# Test local del hook de aprobación: prueba parseo y mapeo decisión→JSON con el
# transporte simulado (sin red). Verde = exit 0.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"

# --- Dobles de prueba: anulan el transporte real tras el source ---
US=$(printf '\037')
FAKE_DECISION=""
PUBLISHED_BODY=""
# Captura el cuerpo REAL (machine-splittable) que publicaría el host.
bridge_publish()       { PUBLISHED_BODY="$(bridge_request_body "$1" "$2" "$3" "$4")"; }
bridge_wait_decision() { printf '%s' "$FAKE_DECISION"; } # decisión inyectada

# Reenvío por sesión: dir de flags aislado y una sesión de prueba vigilada.
BRIDGE_FORWARD_DIR=$(mktemp -d)
TEST_SID=test-session
: > "$BRIDGE_FORWARD_DIR/forward-$TEST_SID"

fails=0
check() { # $1=etiqueta $2=esperado $3=obtenido
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s — esperado [%s] obtenido [%s]\n' "$1" "$2" "$3"; fails=$((fails+1))
  fi
}

decide_with() { # $1=decisión simulada $2=json de entrada -> imprime permissionDecision (vacío si pasa de largo)
  FAKE_DECISION="$1"
  printf '%s' "$2" | jq -c --arg s "$TEST_SID" '. + {session_id:$s}' | bridge_decide | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

# Solo entradas PELIGROSAS llegan a la decisión.
check "allow"        allow "$(decide_with allow '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}')"
check "deny"         deny  "$(decide_with deny  '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}')"
check "timeout→ask"  ask   "$(decide_with ''    '{"tool_name":"Write","tool_input":{"file_path":"/etc/hosts"}}')"

# Fail-safe por modo de permisos: un "ask" de hook NO frena en bypass, así que en
# timeout/misconfig se deniega en modos no interactivos; en interactivos, "ask".
check "fallback bypass→deny"  deny "$(bridge_fallback_decision bypassPermissions)"
check "fallback dontAsk→deny" deny "$(bridge_fallback_decision dontAsk)"
check "fallback default→ask"  ask  "$(bridge_fallback_decision default)"
check "fallback vacío→ask"    ask  "$(bridge_fallback_decision '')"
check "timeout bypass→deny" deny "$(decide_with '' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"},"permission_mode":"bypassPermissions"}')"
check "timeout default→ask" ask  "$(decide_with '' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"},"permission_mode":"default"}')"

# Lo SEGURO pasa de largo: sin salida, sin push.
PUBLISHED_BODY="(sin tocar)"
safe_out=$(decide_with allow '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
[ -z "$safe_out" ] && [ "$PUBLISHED_BODY" = "(sin tocar)" ] \
  && printf 'ok   comando seguro pasa de largo\n' \
  || { printf 'FAIL comando seguro no pasó de largo (out=[%s] body=[%s])\n' "$safe_out" "$PUBLISHED_BODY"; fails=$((fails+1)); }

# Reenvío por sesión (B1): una sesión NO vigilada no escala ni con comando peligroso.
unwatched_out=$( FAKE_DECISION=allow; printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"},"session_id":"no-vigilada"}' | bridge_decide | jq -r '.hookSpecificOutput.permissionDecision // empty' )
[ -z "$unwatched_out" ] \
  && printf 'ok   sesión no vigilada pasa de largo\n' \
  || { printf 'FAIL no vigilada escaló (out=[%s])\n' "$unwatched_out"; fails=$((fails+1)); }
check "is_watched vigilada"    si "$(bridge_is_watched "$TEST_SID" && echo si || echo no)"
check "is_watched no vigilada" no "$(bridge_is_watched no-vigilada && echo si || echo no)"
check "is_watched vacío"       no "$(bridge_is_watched '' && echo si || echo no)"
case "$(bridge_sid_safe '../../etc/passwd')" in */*) printf 'FAIL sid_safe deja slashes\n'; fails=$((fails+1)) ;; *) printf 'ok   sid_safe sin slashes\n' ;; esac

# El clasificador de peligro.
is_dangerous() { bridge_is_dangerous "$1" "$2" && echo si || echo no; }
check "peligro: rm -rf"      si "$(is_dangerous Bash '{"tool_input":{"command":"rm -rf build"}}')"
check "peligro: --force"     si "$(is_dangerous Bash '{"tool_input":{"command":"git push --force"}}')"
check "peligro: sudo"        si "$(is_dangerous Bash '{"tool_input":{"command":"sudo apt update"}}')"
check "seguro: git status"   no "$(is_dangerous Bash '{"tool_input":{"command":"git status"}}')"
check "seguro: ls"           no "$(is_dangerous Bash '{"tool_input":{"command":"ls -la"}}')"
check "Write en cwd seguro"  no "$(is_dangerous Write '{"cwd":"/home/p/proj","tool_input":{"file_path":"/home/p/proj/a.txt"}}')"
check "Write fuera escala"   si "$(is_dangerous Write '{"cwd":"/home/p/proj","tool_input":{"file_path":"/etc/hosts"}}')"
check "Write .ssh escala"    si "$(is_dangerous Edit  '{"cwd":"/home/p/proj","tool_input":{"file_path":"/home/p/.ssh/config"}}')"

# La razón aparece al denegar y no al permitir.
reason_deny=$(FAKE_DECISION=deny; printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"},"session_id":"test-session"}' | bridge_decide | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
[ -n "$reason_deny" ] && printf 'ok   deny lleva razón\n' || { printf 'FAIL deny sin razón\n'; fails=$((fails+1)); }

# El resumen de Write NO filtra contenido: solo la ruta.
# (here-string, no pipe: el pipe correría bridge_decide en un subshell y
#  PUBLISHED_BODY no subiría al shell padre).
FAKE_DECISION=allow
bridge_decide >/dev/null <<<'{"tool_name":"Write","tool_input":{"file_path":"/secreto.txt","content":"CLAVE-SUPERSECRETA"},"session_id":"test-session"}'
case "$PUBLISHED_BODY" in
  *CLAVE-SUPERSECRETA*) printf 'FAIL el push filtró contenido del fichero\n'; fails=$((fails+1)) ;;
esac
check "Write solo publica la ruta" "/secreto.txt" "${PUBLISHED_BODY##*$US}"

# El resumen de Bash recorta a 200 caracteres (el summary es el último campo).
FAKE_DECISION=allow
long="sudo $(printf 'a%.0s' {1..400})"
bridge_decide >/dev/null <<<"{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$long\"},\"session_id\":\"test-session\"}"
sumf="${PUBLISHED_BODY##*$US}"
[ "${#sumf}" -le 200 ] && printf 'ok   Bash recorta a ≤200\n' || { printf 'FAIL Bash no recorta (%s)\n' "${#sumf}"; fails=$((fails+1)); }

# Cuerpo machine-splittable (D1): id␟label␟tool␟summary y etiqueta de sesión.
body=$(bridge_request_body ID123 "miproj (deadbeef)" Write /secreto.txt)
check "request_body id primero" ID123 "${body%%$US*}"
nseps=$(printf '%s' "$body" | tr -cd "$US" | wc -c | tr -d ' ')
check "request_body 3 separadores" 3 "$nseps"
case "$body" in *"$US"*) printf 'ok   request_body lleva separador US\n' ;; *) printf 'FAIL request_body sin separador\n'; fails=$((fails+1)) ;; esac
b2=$(bridge_request_body X Y Bash 'rm -rf build')
case "$b2" in *CLAVE*) printf 'FAIL request_body filtró contenido\n'; fails=$((fails+1)) ;; *) printf 'ok   request_body sin fuga\n' ;; esac
check "session_label base+sid" "proj (1234abcd)" "$(bridge_session_label /home/p/proj 1234abcd5678)"
check "session_label sin cwd"  "claude"          "$(bridge_session_label '' '')"

# Matching de decisiones: correlacionado por id y pelado; basura no casa.
check "match <id> allow" allow "$(bridge_match abc 'abc allow')"
check "match <id> deny"  deny  "$(bridge_match abc 'abc deny')"
check "match allow pelado" allow "$(bridge_match abc allow)"
check "match deny pelado"  deny  "$(bridge_match abc deny)"
check "match otro id"      ""    "$(bridge_match abc 'xyz allow')"
check "match basura"       ""    "$(bridge_match abc 'lolnope')"

# bridge_actions: cabecera con ambos botones, decisión correlacionada y topic DEC.
BRIDGE_NTFY_BASE=https://ntfy.sh BRIDGE_TOPIC_DEC=dec123 BRIDGE_TOKEN="" acts=$(bridge_actions ABC)
case "$acts" in
  *Aprobar*Denegar*) printf 'ok   actions: ambos botones\n' ;;
  *) printf 'FAIL actions sin botones [%s]\n' "$acts"; fails=$((fails+1)) ;;
esac
case "$acts" in
  *dec123*"ABC allow"*"ABC deny"*) printf 'ok   actions: id+topic correctos\n' ;;
  *) printf 'FAIL actions mal formada [%s]\n' "$acts"; fails=$((fails+1)) ;;
esac
# Con token, la cabecera incluye Authorization; sin token, no.
acts_tok=$(BRIDGE_NTFY_BASE=https://ntfy.sh BRIDGE_TOPIC_DEC=dec123 BRIDGE_TOKEN=secreto bridge_actions ABC)
case "$acts_tok" in *Bearer*secreto*) printf 'ok   actions: token cuando hay\n' ;; *) printf 'FAIL actions sin token\n'; fails=$((fails+1)) ;; esac
case "$acts" in *Authorization*) printf 'FAIL actions con auth sin token\n'; fails=$((fails+1)) ;; *) printf 'ok   actions: sin auth si no hay token\n' ;; esac

# ---- Hook Stop (reprompt) ----
check "continue decision" block    "$(bridge_emit_continue 'haz X' | jq -r .decision)"
check "continue reason"   'haz X'  "$(bridge_emit_continue 'haz X' | jq -r .reason)"

ra=$(BRIDGE_NTFY_BASE=https://ntfy.sh BRIDGE_TOPIC_REPROMPT=rep1 BRIDGE_TOKEN="" bridge_reprompt_actions)
case "$ra" in
  *Continúa*Tests*Commit*rep1*) printf 'ok   reprompt: 3 botones + topic\n' ;;
  *) printf 'FAIL reprompt actions [%s]\n' "$ra"; fails=$((fails+1)) ;;
esac

# Resumen final: bridge_last_assistant recibe el JSON de stdin de Stop.
# Vía directa: usa .last_assistant_message si viene.
check "last assistant directo" "directo" "$(bridge_last_assistant '{"last_assistant_message":"directo"}')"
# Vía fallback: sin el campo, parsea el último assistant del transcript.
tf=$(mktemp)
printf '%s\n' \
  '{"type":"user","message":{"content":"hola"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"primero"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"resumen final"}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","content":"x"}]}}' > "$tf"
check "last assistant fallback" "resumen final" "$(bridge_last_assistant "$(jq -nc --arg t "$tf" '{transcript_path:$t}')")"
rm -f "$tf"

# Centinela WATCH: del skill watch-summary — se prefiere, sin el tag y capada a 200.
check "watch centinela" "OK lib.sh · Tests" \
  "$(bridge_last_assistant '{"last_assistant_message":"respuesta larga normal\nWATCH: OK lib.sh · Tests"}')"
case "$(bridge_last_assistant '{"last_assistant_message":"x\nWATCH: OK y"}')" in
  *WATCH:*) printf 'FAIL centinela filtró el tag WATCH:\n'; fails=$((fails+1)) ;;
  *)        printf 'ok   centinela sin tag WATCH:\n' ;;
esac
check "sin centinela→texto" "respuesta sin marca" \
  "$(bridge_last_assistant '{"last_assistant_message":"respuesta sin marca"}')"
longw="WATCH: $(printf 'b%.0s' {1..400})"
out_w=$(bridge_last_assistant "$(jq -nc --arg m "$longw" '{last_assistant_message:$m}')")
[ "${#out_w}" -le 200 ] && printf 'ok   centinela capa a <=200\n' || { printf 'FAIL centinela no capa (%s)\n' "${#out_w}"; fails=$((fails+1)); }
check "centinela última gana" "segunda" \
  "$(bridge_last_assistant '{"last_assistant_message":"WATCH: primera\nWATCH: segunda"}')"

# bridge_reprompt: opt-in POR SESIÓN (vigilada). Transporte simulado.
bridge_publish_reprompt() { :; }
REPROMPT_TEXT=""
bridge_wait_reprompt() { printf '%s' "$REPROMPT_TEXT"; }
BRIDGE_TOPIC_REPROMPT=rep1
WATCHED_IN=$(jq -nc --arg s "$TEST_SID" '{transcript_path:"",session_id:$s}')
UNWATCHED_IN='{"transcript_path":"","session_id":"no-vigilada"}'

REPROMPT_TEXT="ejecuta los tests"
check "reprompt vigilada+texto→block" block "$(bridge_reprompt <<<"$WATCHED_IN" | jq -r '.decision // empty')"

REPROMPT_TEXT=""   # vigilada pero sin respuesta -> para
out_to=$(bridge_reprompt <<<"$WATCHED_IN")
[ -z "$out_to" ] && printf 'ok   reprompt vigilada+timeout→para\n' || { printf 'FAIL reprompt timeout emitió [%s]\n' "$out_to"; fails=$((fails+1)); }

REPROMPT_TEXT="lo que sea"   # sesión no vigilada -> no molesta
out_off=$(bridge_reprompt <<<"$UNWATCHED_IN")
[ -z "$out_off" ] && printf 'ok   reprompt no vigilada→no molesta\n' || { printf 'FAIL reprompt no vigilada emitió [%s]\n' "$out_off"; fails=$((fails+1)); }

# ---- Toggle por sesión (B2) ----
check "watch_parse /watch on"  on     "$(bridge_watch_parse '/watch on')"
check "watch_parse watch off"  off    "$(bridge_watch_parse 'watch off')"
check "watch_parse /watch"     status "$(bridge_watch_parse '/watch')"
check "watch_parse watch"      status "$(bridge_watch_parse 'watch')"
check "watch_parse status"     status "$(bridge_watch_parse '/watch status')"
bridge_watch_parse 'arregla el watch' && { printf 'FAIL watch_parse casó frase libre\n'; fails=$((fails+1)); } || printf 'ok   watch_parse ignora frase libre\n'
bridge_watch_parse 'watcher on'       && { printf 'FAIL watch_parse casó watcher\n'; fails=$((fails+1)); } || printf 'ok   watch_parse ignora watcher\n'

SID2=sesion-b2
check "watch_set on"        on  "$(bridge_watch_set on "$SID2")"
check "is_watched tras on"  si  "$(bridge_is_watched "$SID2" && echo si || echo no)"
check "watch_set status"    on  "$(bridge_watch_set status "$SID2")"
check "watch_set off"       off "$(bridge_watch_set off "$SID2")"
check "is_watched tras off" no  "$(bridge_is_watched "$SID2" && echo si || echo no)"
bridge_watch_set on '' && { printf 'FAIL watch_set aceptó sid vacío\n'; fails=$((fails+1)); } || printf 'ok   watch_set rechaza sid vacío\n'

bridge_record_session sid-xyz /tmp/proj-b2
check "last_session por cwd" sid-xyz "$(bridge_last_session /tmp/proj-b2)"
check "last_session global"  sid-xyz "$(bridge_last_session '')"

check "emit_block decision" block  "$(bridge_emit_block 'x'    | jq -r .decision)"
check "emit_block reason"   'hola' "$(bridge_emit_block 'hola' | jq -r .reason)"

echo "---"
if [ "$fails" -eq 0 ]; then echo "todos los tests OK"; else echo "$fails test(s) fallidos"; exit 1; fi
