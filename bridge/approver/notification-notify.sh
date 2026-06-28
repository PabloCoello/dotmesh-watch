#!/usr/bin/env bash
# Hook Notification: refleja avisos del arnés al reloj (solo aviso; Notification no
# puede responder). Registrar DOS veces, con matcher y argumento por tipo:
#   matcher "idle_prompt"       -> notification-notify.sh idle_prompt
#   matcher "permission_prompt" -> notification-notify.sh permission_prompt
# idle_prompt se suprime en sesiones vigiladas (el reprompt del hook Stop ya avisa;
# de-dup). permission_prompt siempre avisa. Ver SETUP.md.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
. "$DIR/lib.sh"

# Sin transporte configurado: nada que reflejar.
[ -n "${BRIDGE_TOPIC_REQ:-}" ] || exit 0

bridge_notify "${1:-}"
