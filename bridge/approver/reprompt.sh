#!/usr/bin/env bash
# DEPRECADO. El opt-in del reprompt es ahora POR SESIÓN y está unificado con el
# reenvío de permisos: una misma sesión "vigilada" escala permisos y dispara el
# reprompt. Usa "/watch on|off" dentro de la sesión (hook UserPromptSubmit) o
# watch.sh desde el terminal. Este shim delega en watch.sh por compatibilidad.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "reprompt.sh está deprecado; usa /watch o watch.sh (opt-in por sesión)." >&2
exec "$DIR/watch.sh" "$@"
