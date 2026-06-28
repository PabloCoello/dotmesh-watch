#!/usr/bin/env bash
# Hook StopFailure: avisa al reloj cuando el turno termina por un error de API
# (rate_limit, overloaded, server_error, ...). El hook Stop NO dispara en ese caso,
# ni en la interrupción manual (Esc). Es SOLO efecto: el arnés ignora el stdout y el
# código de salida -> un único push, sin botones ni espera. No usa el opt-in por
# sesión: un fallo siempre conviene saberlo.
# Registrar como hook "StopFailure" (sin matcher = cualquier error de API).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
. "$DIR/lib.sh"

# Sin transporte configurado: nada que avisar.
[ -n "${BRIDGE_TOPIC_REQ:-}" ] || exit 0

bridge_failure
