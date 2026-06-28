#!/usr/bin/env bash
# Hook PreToolUse matcher AskUserQuestion. Por defecto (E4) refleja la pregunta al
# reloj como aviso y NO responde: sigues respondiendo en el terminal (stdout vacío
# -> la tool procede por el flujo normal). Con BRIDGE_ANSWER_QUESTIONS=1 (E3)
# intenta responder desde la muñeca una pregunta única/no-multiSelect; si no es
# respondible o hay timeout, cae al mirror read-only.
#
# Separado de pretooluse-approve.sh a propósito: aquel solo emite allow/deny/ask y
# trataría mal AskUserQuestion. Registrar con matcher AskUserQuestion.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
. "$DIR/lib.sh"

INPUT=$(cat)

# Sin transporte configurado: nada que reflejar; deja que el terminal pregunte.
[ -n "${BRIDGE_TOPIC_REQ:-}" ] || exit 0

bridge_ask "$INPUT"
