#!/usr/bin/env bash
# Hook UserPromptSubmit: gestiona el opt-in del reloj por sesión.
#  - "/watch on|off|status" (o "watch ...") conmuta la vigilancia de ESTA sesión
#    y descarta el prompt (no consume turno).
#  - Cualquier otro prompt: registra el session_id activo (para watch.sh).
# Registrar como hook UserPromptSubmit (sin matcher). La inyección de contexto
# para sesiones vigiladas la añade B4.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
. "$DIR/lib.sh"

input=$(cat)
session_id=$(jq -r '.session_id // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
prompt=$(jq -r '.prompt // ""' <<<"$input")

bridge_record_session "$session_id" "$cwd"

if cmd=$(bridge_watch_parse "$prompt"); then
  state=$(bridge_watch_set "$cmd" "$session_id")
  bridge_emit_block "bridge: vigilancia del reloj $state para esta sesión"
fi
