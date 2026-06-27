#!/usr/bin/env bash
# Hook PreToolUse: escala la aprobación de una herramienta a la muñeca vía ntfy.
# Registrar en settings.json con matcher Bash|Write|Edit|MultiEdit|NotebookEdit.
# Claude Code pasa la entrada por stdin y lee la decisión por stdout (exit 0).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
. "$DIR/lib.sh"

# Fail-safe: sin transporte configurado, delega al terminal (nunca allow mudo).
if [ -z "${BRIDGE_TOPIC_REQ:-}" ] || [ -z "${BRIDGE_TOPIC_DEC:-}" ]; then
  bridge_emit ask "bridge sin configurar (.env); decide en el terminal"
  exit 0
fi

bridge_decide
