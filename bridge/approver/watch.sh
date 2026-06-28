#!/usr/bin/env bash
# Respaldo de terminal para conmutar la vigilancia del reloj de una sesión.
# Uso: watch.sh on|off|status [session_id]
# Sin session_id usa el más reciente registrado para este cwd (heurístico: con
# varias sesiones en el mismo cwd puede no ser la que crees; "/watch" dentro de la
# sesión es determinista y preferible).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
. "$DIR/lib.sh"

action="${1:-status}"
sid="${2:-$(bridge_last_session "$PWD")}"
if [ -z "$sid" ]; then
  echo "watch: no hay sesión registrada; pasa el session_id como 2.º argumento" >&2
  exit 2
fi
state=$(bridge_watch_set "$action" "$sid")
echo "watch: sesión ${sid} -> ${state}"
