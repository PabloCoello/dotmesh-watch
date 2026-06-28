#!/usr/bin/env bash
# Hook PreToolUse: escala la aprobación de una herramienta a la muñeca vía ntfy.
# Registrar en settings.json con matcher Bash|Write|Edit|MultiEdit|NotebookEdit.
# Claude Code pasa la entrada por stdin y lee la decisión por stdout (exit 0).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
. "$DIR/lib.sh"

# Lee la entrada una sola vez: la necesitamos aquí (modo de permisos) y la
# reinyectamos a bridge_decide, que hace su propio `cat`.
INPUT=$(cat)

# Fail-safe: sin transporte configurado, no delegamos a un "ask" mudo —un "ask"
# de hook no frena en bypass—; denegamos según el modo de la sesión.
if [ -z "${BRIDGE_TOPIC_REQ:-}" ] || [ -z "${BRIDGE_TOPIC_DEC:-}" ]; then
  mode=$(jq -r '.permission_mode // ""' <<<"$INPUT")
  if [ "$(bridge_fallback_decision "$mode")" = deny ]; then
    bridge_emit deny "bridge sin configurar (.env) en modo $mode; denegado por seguridad"
  else
    bridge_emit ask "bridge sin configurar (.env); decide en el terminal"
  fi
  exit 0
fi

printf '%s' "$INPUT" | bridge_decide
