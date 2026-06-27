#!/usr/bin/env bash
# Activa/desactiva el modo reprompt del hook Stop (un flag file que lee el hook).
# Uso: reprompt.sh on | off | status
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
. "$DIR/lib.sh"

flag="$BRIDGE_REPROMPT_FLAG"
case "${1:-status}" in
  on)     mkdir -p "$(dirname "$flag")"; : > "$flag"; echo "reprompt ON  ($flag)" ;;
  off)    rm -f "$flag"; echo "reprompt OFF" ;;
  status) [ -e "$flag" ] && echo "reprompt ON" || echo "reprompt OFF" ;;
  *)      echo "uso: reprompt.sh on|off|status" >&2; exit 2 ;;
esac
