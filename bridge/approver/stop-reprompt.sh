#!/usr/bin/env bash
# Hook Stop: al terminar Claude, avisa con el resumen final y permite repromptear
# desde la muñeca. OPT-IN: el hook Stop se dispara en CADA turno, así que solo
# actúa si el modo reprompt está activo (flag). Actívalo/desactívalo con:
#   bridge/approver/reprompt.sh on|off
# Registrar en settings.json como hook "Stop" (sin matcher).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
. "$DIR/lib.sh"

# Sin transporte configurado: deja parar sin tocar nada.
if [ -z "${BRIDGE_TOPIC_REQ:-}" ] || [ -z "${BRIDGE_TOPIC_REPROMPT:-}" ]; then
  exit 0
fi

bridge_reprompt
