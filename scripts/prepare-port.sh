#!/usr/bin/env bash
#
# Menyiapkan source build Ubuntu Touch (Halium 10 GSI-port).
#
# Hasil: folder $PORT_DIR berisi repo port UBports + folder $PORT_DIR/build
# (halium-generic-adaptation-build-tools), siap dipakai lewat ./build/build.sh
# dari dalam folder tersebut.
#
# Semua variabel bisa di-override lewat environment.
set -euo pipefail

PORT_DIR="${PORT_DIR:-port}"
DEVICE="${DEVICE:-angelica}"
PORT_REPO="${PORT_REPO:-https://gitlab.com/ubports/porting/community-ports/android10/xiaomi-redmi-9c/xiaomi-angelica.git}"
PORT_BRANCH="${PORT_BRANCH:-halium-10.0}"
TOOLS_REPO="${TOOLS_REPO:-https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools.git}"
TOOLS_BRANCH="${TOOLS_BRANCH:-main}"
OVERRIDES_DIR="${OVERRIDES_DIR:-overrides}"

log() { printf '\n==> %s\n' "$*"; }

log "Clone repo port $PORT_REPO (branch $PORT_BRANCH)"
if [ -d "$PORT_DIR/.git" ]; then
  echo "    $PORT_DIR sudah ada, dilewati"
else
  git clone --depth 1 -b "$PORT_BRANCH" "$PORT_REPO" "$PORT_DIR"
fi

# Kembalikan deviceinfo ke versi asli repo port dulu. Tanpa ini, ganti-ganti
# varian device (dandelion -> angelica) akan meninggalkan deviceinfo varian lama.
git -C "$PORT_DIR" checkout -- deviceinfo 2>/dev/null || true

# Overlay kustomisasi lokal (opsional). Diterapkan sebelum pemilihan varian
# deviceinfo, supaya varian yang dipilih selalu menang.
if [ -d "$OVERRIDES_DIR" ]; then
  target="$(cd "$PORT_DIR" && pwd)"
  entries="$(cd "$OVERRIDES_DIR" && find . -mindepth 1 -maxdepth 1 ! -name 'README.md')"
  if [ -n "$entries" ]; then
    log "Terapkan overrides dari $OVERRIDES_DIR ke $PORT_DIR"
    (
      cd "$OVERRIDES_DIR"
      find . -mindepth 1 -maxdepth 1 ! -name 'README.md' -exec cp -a {} "$target"/ \;
    )
  fi
fi

if [ "$DEVICE" != "angelica" ]; then
  log "Pakai varian deviceinfo: $DEVICE"
  ln -sf "deviceinfo-$DEVICE" "$PORT_DIR/deviceinfo"
fi

log "Clone generic build tools (branch $TOOLS_BRANCH)"
if [ -d "$PORT_DIR/build" ]; then
  echo "    $PORT_DIR/build sudah ada, dilewati"
else
  git clone --depth 1 -b "$TOOLS_BRANCH" "$TOOLS_REPO" "$PORT_DIR/build"
fi

[ -f "$PORT_DIR/deviceinfo" ] || {
  echo "ERROR: $PORT_DIR/deviceinfo tidak ada" >&2
  exit 1
}

log "Siap dibuild"
(
  # shellcheck disable=SC1091
  cd "$PORT_DIR" && source ./deviceinfo
  echo "    device          : $deviceinfo_name ($deviceinfo_codename)"
  echo "    halium version  : $deviceinfo_halium_version"
  echo "    kernel source   : $deviceinfo_kernel_source (branch $deviceinfo_kernel_source_branch)"
  echo "    kernel defconfig: $deviceinfo_kernel_defconfig"
)
