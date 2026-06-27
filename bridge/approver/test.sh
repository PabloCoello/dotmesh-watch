#!/usr/bin/env bash
# Test local del hook de aprobación: prueba parseo y mapeo decisión→JSON con el
# transporte simulado (sin red). Verde = exit 0.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"

# --- Dobles de prueba: anulan el transporte real tras el source ---
FAKE_DECISION=""
PUBLISHED_BODY=""
bridge_publish()       { PUBLISHED_BODY="$3"; }          # captura el cuerpo del push
bridge_wait_decision() { printf '%s' "$FAKE_DECISION"; } # decisión inyectada

fails=0
check() { # $1=etiqueta $2=esperado $3=obtenido
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s — esperado [%s] obtenido [%s]\n' "$1" "$2" "$3"; fails=$((fails+1))
  fi
}

decide_with() { # $1=decisión simulada $2=json de entrada -> imprime permissionDecision
  FAKE_DECISION="$1"
  printf '%s' "$2" | bridge_decide | jq -r '.hookSpecificOutput.permissionDecision'
}

check "allow"        allow "$(decide_with allow '{"tool_name":"Bash","tool_input":{"command":"git status"}}')"
check "deny"         deny  "$(decide_with deny  '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}')"
check "timeout→ask"  ask   "$(decide_with ''    '{"tool_name":"Write","tool_input":{"file_path":"/etc/hosts"}}')"

# La razón aparece al denegar y no al permitir.
reason_deny=$(FAKE_DECISION=deny; printf '%s' '{"tool_name":"Bash","tool_input":{"command":"x"}}' | bridge_decide | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
[ -n "$reason_deny" ] && printf 'ok   deny lleva razón\n' || { printf 'FAIL deny sin razón\n'; fails=$((fails+1)); }

# El resumen de Write NO filtra contenido: solo la ruta.
# (here-string, no pipe: el pipe correría bridge_decide en un subshell y
#  PUBLISHED_BODY no subiría al shell padre).
FAKE_DECISION=allow
bridge_decide >/dev/null <<<'{"tool_name":"Write","tool_input":{"file_path":"/secreto.txt","content":"CLAVE-SUPERSECRETA"}}'
case "$PUBLISHED_BODY" in
  *CLAVE-SUPERSECRETA*) printf 'FAIL el push filtró contenido del fichero\n'; fails=$((fails+1)) ;;
  /secreto.txt)         printf 'ok   Write solo publica la ruta\n' ;;
  *)                    printf 'FAIL resumen Write inesperado [%s]\n' "$PUBLISHED_BODY"; fails=$((fails+1)) ;;
esac

# El resumen de Bash recorta a 200 caracteres.
FAKE_DECISION=allow
long=$(printf 'a%.0s' {1..400})
bridge_decide >/dev/null <<<"{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$long\"}}"
[ "${#PUBLISHED_BODY}" -le 200 ] && printf 'ok   Bash recorta a ≤200\n' || { printf 'FAIL Bash no recorta (%s)\n' "${#PUBLISHED_BODY}"; fails=$((fails+1)); }

echo "---"
if [ "$fails" -eq 0 ]; then echo "todos los tests OK"; else echo "$fails test(s) fallidos"; exit 1; fi
