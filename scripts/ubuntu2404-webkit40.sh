#!/usr/bin/env bash
#
# Provisiona webkit2gtk-4.0 (mundo libsoup2) en Ubuntu 24.04 para que arranque
# el Connect IQ SDK Manager, que se enlaza contra la 4.0 ya retirada de noble.
#
# Cómo: añade jammy como fuente de apt PINEADA por debajo de noble (prioridad
# 100 < 500), instala solo las libs 4.0 y sus dependencias jammy-only, y RETIRA
# la fuente al terminar (trap EXIT). No cambia ninguna otra versión del sistema.
#
# Nota: el atajo de symlink 4.0 -> 4.1 NO vale; mezcla libsoup2 y libsoup3 en el
# mismo proceso y el SDK Manager aborta al arrancar.
#
# Reversible: las libs quedan instaladas y coexisten con libsoup3. Para quitarlas:
#   sudo apt remove libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18
#
# Uso:  sudo bash scripts/ubuntu2404-webkit40.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Ejecuta con sudo: sudo bash $0" >&2
  exit 1
fi

. /etc/os-release
if [ "${VERSION_ID:-}" != "24.04" ]; then
  echo "Pensado para Ubuntu 24.04 (detectado: ${PRETTY_NAME:-desconocido})." >&2
  echo "En otras versiones revisa a mano la disponibilidad de webkit2gtk-4.0." >&2
  exit 1
fi

LIST=/etc/apt/sources.list.d/jammy-ciq.list
PIN=/etc/apt/preferences.d/99-jammy-ciq

cleanup() {
  rm -f "$LIST" "$PIN"
  apt-get update -qq || true
  echo "Fuente jammy retirada; apt vuelve a ser solo noble."
}
trap cleanup EXIT

cat > "$PIN" <<'EOF'
# jammy solo como ultimo recurso: nunca por encima de noble.
Package: *
Pin: release n=jammy
Pin-Priority: 100
EOF

cat > "$LIST" <<'EOF'
deb http://archive.ubuntu.com/ubuntu jammy main universe
deb http://security.ubuntu.com/ubuntu jammy-security main universe
EOF

echo "Actualizando indices (con jammy pineado por debajo de noble)..."
apt-get update -qq

echo "Instalando webkit2gtk-4.0 y sus dependencias jammy-only..."
apt-get install -y --no-install-recommends \
  libwebkit2gtk-4.0-37 \
  libjavascriptcoregtk-4.0-18

if [ -e /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so.37 ]; then
  echo
  echo "OK  webkit2gtk-4.0 instalado."
  echo "Ahora lanza el SDK Manager con:  ciq-sdkmanager"
else
  echo "Algo fallo: no aparece libwebkit2gtk-4.0.so.37." >&2
  exit 1
fi
