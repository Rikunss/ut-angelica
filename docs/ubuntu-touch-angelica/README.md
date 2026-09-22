# Build Ubuntu Touch — Xiaomi Redmi 9C (angelica)

> Panduan build Ubuntu Touch (Halium 10 GSI-port) untuk **Xiaomi Redmi 9C (angelica)**,
> lokal maupun via **GitLab CI / GitHub Actions**.
>
> - Versi Halium : **10.0** (basis Android 10)
> - Metode       : **GSI-port** — hanya build kernel + boot image + device tarball,
>                  *bukan* full tree LineageOS/CM. Rootfs Ubuntu Touch diambil dari OTA UBports.
> - MTK platform : MT6765 (garden/gardenia family)
> - Varian dandelion (Redmi 9A) dibahas di bagian bawah.

## 0. Referensi resmi (WAJIB dibaca dulu)

| Sumber | URL |
|---|---|
| Repo port UBports angelica | https://gitlab.com/ubports/porting/community-ports/android10/xiaomi-redmi-9c/xiaomi-angelica — default branch **`halium-10.0`** |
| Kernel halium-10.0 (MT6765) | https://gitlab.com/ubports/community-ports/android10/xiaomi-redmi-9c/kernel-xiaomi-mt6765 (branch `halium-10.0`) |
| Build tools generik | https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools |
| CI template GSI-port | .../halium-generic-adaptation-build-tools/-/raw/main/gsi-port-ci.yml |
| Dokumentasi porting UBports | https://docs.ubports.com/en/latest/porting/build_and_boot/index.html |

**Repo port ini juga mendukung Redmi 9A (dandelion)** — file `deviceinfo-dandelion`
di-symlink sebagai `deviceinfo` pada job CI-nya.

## 1. Isi repo port

```
xiaomi-angelica/
├── build.sh                      # wrapper → build-tools (clone build/ lalu jalankan ./build/build.sh)
├── deviceinfo                    # param build angelica (lihat bawah)
├── deviceinfo-dandelion          # param build Redmi 9A
├── .gitlab-ci.yml                # include template gsi-port-ci.yml + job angelica/dandelion
├── ramdisk-recovery.img          # ramdisk recovery (blob git biasa, bukan LFS — aman di-mirror ke GitHub)
├── recovery_dtbo_angelica.img
├── recovery_dtbo_dandelion.img
├── ramdisk-recovery-overlay/     # overlay file recovery
└── overlay/
```

`deviceinfo` angelica (ringkas — ini yang menentukan kernel & bootimg):

```bash
deviceinfo_codename="angelica"
deviceinfo_arch="arm"                    # userspace arm
deviceinfo_kernel_arch="aarch64"         # kernel arm64
deviceinfo_halium_version=10
deviceinfo_kernel_source="https://gitlab.com/ubports/community-ports/android10/xiaomi-redmi-9c/kernel-xiaomi-mt6765"
deviceinfo_kernel_source_branch="halium-10.0"
deviceinfo_kernel_defconfig="angelica_halium_defconfig"
deviceinfo_kernel_clang_compile="true"
deviceinfo_bootimg_header_version="2"
deviceinfo_bootimg_partition_size="67108864"
deviceinfo_recovery_dtbo="recovery_dtbo_angelica.img"
deviceinfo_bootimg_append_vbmeta="true"
deviceinfo_kernel_cmdline="bootopt=64S3,32N2,64N2 buildvariant=user systempart=/dev/mapper/system:ro"
# ... offset/pagesize boot img lengkap ada di file deviceinfo repo
```

## 2. Build lokal (referensi — bagaimana CI-nya bekerja)

Prasyarat: Ubuntu 20.04/22.04, git, build tools dasar.

```bash
# 1) clone repo port
git clone https://gitlab.com/ubports/porting/community-ports/android10/xiaomi-redmi-9c/xiaomi-angelica.git
cd xiaomi-angelica

# 2) jalankan build (script akan clone build-tools sendiri)
./build.sh

# hasil build ada di folder ./out (default):
#   device_angelica.tar.xz   (device tarball — overlay/config untuk rootfs)
#   boot.img                 (halium boot image: kernel + DTB + ramdisk)
#   recovery.img             (recovery halium — deviceinfo_has_recovery_partition=true)
#   Module.symvers           (simbol kernel)
#
# TIDAK ada dtbo.img: deviceinfo angelica tidak mendefinisikan deviceinfo_dtbo,
# dan DTB (mt6765/angelica) sudah tertanam di dalam boot.img.
```

Opsi `build.sh` (dari halium-generic-adaptation-build-tools):

```
-b BUILD_DIR   folder workdir (default ./workdir)
-o OUT_DIR     folder output (default ./out)
-c             hanya clone source (tidak build)
-k             hanya build kernel + boot image (skip device tarball)
-m             menuconfig kernel (interactive)
```

> CI resmi UBports memanggil `./build/build.sh` tanpa argumen (pakai default
> `workdir/` dan `out/`). Toolchain clang/gcc + kernel di-clone shallow ke
> `workdir/downloads` dan di-skip bila foldernya sudah ada → bisa di-cache.

## 3. Flashing ke device

> **WAJIB: unlock bootloader dulu** (Mi Unlock Tool), dan boot dulu ke MIUI/HyperOS
> sekali agar data partisi ter-init sebelum flashing.

Struktur partisi angelica: **A/B (dynamic partitions)** → flash pakai `fastbootd`
(fastboot userspace), bukan hanya bootloader mode.

```bash
# masuk fastboot (bootloader)
adb reboot bootloader

# 1) disable verified boot (anti bootloop / anti brick AVB)
fastboot flash vbmeta vbmeta_disabled.img
fastboot flash vbmeta_system vbmeta_disabled.img
fastboot flash vbmeta_vendor vbmeta_disabled.img

# 2) flash boot & recovery
# (angelica tidak menghasilkan dtbo.img — DTB sudah ada di dalam boot.img)
fastboot flash boot out/boot.img
fastboot flash recovery out/recovery.img

# 3) flash system (rootfs UT) — butuh fastbootd
fastboot reboot fastboot          # masuk fastbootd
fastboot delete-logical-partition product   # buat ruang untuk system
fastboot flash system out/system.img

# 4) selesai
fastboot reboot
```

Install Ubuntu Touch secara "resmi" (rootfs devel):
- Setelah `boot.img` + `recovery.img` terflash, gunakan `ubports-installer`
  atau SSH ke recovery untuk `ubuntu-device-flash`.
- Referensi flashing lengkap: https://docs.ubports.com/en/latest/porting/build_and_boot/install_and_boot.html

## 4. Varian dandelion (Redmi 9A)

Repo port yang sama. Pada build lokal:

```bash
ln -sf deviceinfo-dandelion deviceinfo
./build.sh out
```

Hasil: `device_dandelion.tar.xz`, `boot.img`, dst. — kernel yang sama
(kernel-xiaomi-mt6765), hanya defconfig/cmdline yang beda.

## 5. Catatan penting

- `deviceinfo_arch="arm"` tetapi `kernel_arch="aarch64"` → build toolchain 2-arch.
- Boot img header v2 + `append_vbmeta` → pastikan AVB di-disable (flash vbmeta_disabled)
  kalau tidak boot loop.
- Kernel cmdline mengandung `systempart=/dev/mapper/system:ro` → device pakai dynamic
  partitions; flash system wajib via `fastbootd`.
- `vbmeta_disabled.img` bisa dibuat sendiri dengan avbtool:
  `avbtool make_vbmeta_image --flags 3 --padding_size 4096 -o vbmeta_disabled.img`
- Recovery image + device tarball dipakai bersama oleh ubports-installer.
- Jika device hang di logo MI → coba flash ulang vbmeta_disabled via `mtkclient`
  (https://github.com/bkerler/mtkclient) karena MTK BROM bisa akses meski bootloader mati.

## 6. Build via CI

- **GitLab CI** → lihat [`gitlab-ci.md`](gitlab-ci.md) (metode paling gampang, template resmi UBports)
- **GitHub Actions** → lihat [`github-actions.md`](github-actions.md) — workflow-nya sudah ada di repo ini di `.github/workflows/build.yml`
