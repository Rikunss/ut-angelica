#!/usr/bin/env bash
#
# Merakit rootfs Ubuntu Touch siap-flash dari device tarball hasil build.
#
# Ini jalur yang sama dengan job "devel-flashable" di CI UBports:
#   1. prepare-fake-ota.sh  -> paket device tarball + rootfs UBports + tarball
#                              device-generic Halium jadi OTA "palsu"
#   2. system-image-from-ota.sh -> unzip OTA itu jadi image rootfs
#
# Hasil di $PORT_DIR/out: system.img (sparse, siap fastboot) dan ubuntu.img.zst.
#
# Release rootfs mengikuti default prepare-fake-ota.sh upstream
# (deviceinfo_ubuntu_touch_release, saat ini 24.04-2.x). Bisa diubah lewat
# overrides/deviceinfo — lihat overrides/README.md.
set -euo pipefail

PORT_DIR="${PORT_DIR:-port}"
cd "$PORT_DIR"

# shellcheck disable=SC1091
DEVICE="$(. ./deviceinfo && echo "$deviceinfo_codename")"
echo "==> Device: $DEVICE"

rm -rf ota
mkdir -p out

echo "==> Bungkus device tarball jadi OTA"
./build/prepare-fake-ota.sh "out/device_${DEVICE}.tar.xz" ota

echo "==> Rakit image rootfs"
./build/system-image-from-ota.sh ota/ubuntu_command out

# system-image-from-ota.sh menghasilkan rootfs.img (ext4 raw) + system.img (sparse).
# Ikuti penamaan artefak CI UBports: rootfs.img -> ubuntu.img -> ubuntu.img.zst
mv out/rootfs.img out/ubuntu.img
zstd --ultra -22 -T0 out/ubuntu.img
rm -f out/ubuntu.img

ls -lh out
