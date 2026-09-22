# Build Ubuntu Touch — Xiaomi Redmi 9C (angelica)

> Panduan build Ubuntu Touch (Halium 10 GSI-port) untuk **Xiaomi Redmi 9C (angelica)**,
> lokal maupun via **GitLab CI / GitHub Actions**.
>
> - Versi Halium : **10.0** (basis Android 10)
> - Metode       : **GSI-port** — hanya build kernel + boot image + device tarball,
>                  *bukan* full tree LineageOS/CM. Rootfs Ubuntu Touch diambil dari OTA UBports.
> - MTK platform : MT6765 (garden/gardenia family)
> - Varian dandelion (Redmi 9A) dibahas di bagian bawah.

## Kenapa ini bukan seperti flash ROM Android biasa

Ubuntu Touch (Halium) **bukan** ROM Android dan **tidak** di-flash sebagai zip
lewat TWRP/OrangeFox:

| | Custom ROM Android | Ubuntu Touch (Halium) |
|---|---|---|
| Artefak | zip + `updater-script` | tidak ada zip |
| Yang ditulis | zip diekstrak ke `system` | **image ext4 mentah** ditulis ke blok partisi `system` |
| Boot | kernel + ramdisk ROM | kernel + **initramfs Halium** (hybris-boot) |
| Isi sistem | Android | rootfs Ubuntu + container Android untuk blob vendor |
| AVB | biasanya ditangani ROM | wajib disable `vbmeta` (tidak ada tanda tangan vendor) |

Recovery tidak punya apa pun untuk dieksekusi — UT tidak mengirim
`META-INF/com/google/android/updater-script`. Yang diperlukan adalah menulis
image ke blok partisi, dan itu pekerjaan `fastboot`/`fastbootd`.

Istilah **`flashable`** di CI UBports juga bukan zip: job `devel-flashable`
menghasilkan `system.img` (sparse) + `boot.img` yang di-flash lewat fastboot.

**Custom recovery (OrangeFox/TWRP) tetap berguna** — nandroid backup stock,
wipe, dan baca `pstore`. Dan partisi `recovery` terpisah dari `boot`/`system`,
jadi **kamu tidak wajib mengganti recovery untuk mencoba UT**; `recovery.img`
bikinan kita adalah UBports recovery yang hanya dibutuhkan untuk jalur OTA/install
resmi.

Tapi menulis rootfs **tetap** lewat `fastbootd`, bukan recovery, karena angelica
memakai dynamic partitions: `system` itu logical partition di dalam `super`, dan
recovery berbasis TWRP sering gagal menulis image besar ke logical partition.

> `ubports-installer` **tidak** punya profil untuk angelica/dandelion
> (`ubports/installer-configs/v2/angelica` tidak ada), jadi jalur satu-klik
> memang tidak tersedia — flashing manual adalah satu-satunya cara.

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
├── recovery_dtbo_angelica.img    # TIDAK dipakai tool mana pun (lihat catatan bawah)
├── recovery_dtbo_dandelion.img
├── ramdisk-recovery-overlay/     # overlay file recovery
└── overlay/
```

Catatan `deviceinfo_recovery_dtbo`: setting ini **tidak dibaca** oleh build-tools.
`make-bootimage.sh` memakai variabel `DTBO` lokal yang diisi dari
`deviceinfo_prebuilt_dtbo` atau `$(dirname $OUT)/dtbo.img` — bukan dari
`deviceinfo_recovery_dtbo`.

Sebaliknya, `deviceinfo_dtbo` **dibaca**: karena baris itu ada dan
`deviceinfo_skip_dtbo_partition` tidak di-set, `build.sh` memanggil
`make-dtboimage.sh` dan menghasilkan `partitions/dtbo.img`. Jadi angelica
**punya** `dtbo.img` dan harus di-flash ke partisi `dtbo`.

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
#   device_angelica.tar.xz   (device tarball: system/ + partitions/)
#   device_angelica_usrmerge.tar.xz  (hardlink ke file di atas, nama lama)
#   Module.symvers           (simbol kernel)
#
# boot.img / recovery.img / dtbo.img TIDAK lepas di out/ — ketiganya ada di
# dalam device_angelica.tar.xz sebagai partitions/*.img. Job `devel-flashable`
# UBports yang membongkarnya keluar (system-image-from-ota.sh melakukan
# `cp partitions/* out/`), dan repo ini meniru itu di job rootfs.
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

# 2) flash boot + dtbo (rootfs belum — hemat satu flash besar kalau gagal)
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot reboot

# 3) flash system (rootfs UT) — butuh fastbootd
fastboot reboot fastboot          # masuk fastbootd
fastboot delete-logical-partition product   # buat ruang untuk system
fastboot flash system system.img

# 4) selesai
fastboot reboot
```

Urutan ini sama dengan panduan komunitas untuk Redmi 9A/9C (gist *How to install
Ubuntu Touch on Xiaomi Redmi 9A/9C*), termasuk `fastboot flash dtbo` dan
`delete-logical-partition product`.

**`recovery.img` tidak perlu di-flash** untuk mencoba UT — lihat catatan tentang
OrangeFox di bagian atas dokumen ini.

Install Ubuntu Touch secara "resmi" (rootfs devel):
- Setelah `boot.img` + `recovery.img` terflash, gunakan `ubports-installer`
  atau SSH ke recovery untuk `ubuntu-device-flash`.
- Referensi flashing lengkap: https://docs.ubports.com/en/latest/porting/build_and_boot/install_and_boot.html

## 4. Varian dandelion (Redmi 9A)

Repo port yang sama, hanya `deviceinfo`-nya beda. Pakai script repo ini, jangan
`ln -sf` manual — symlink manual bikin `deviceinfo` tetap nyangkut ke varian lama
waktu dibalik ke angelica:

```bash
DEVICE=dandelion bash scripts/prepare-port.sh
cd port && ./build/build.sh && cd ..

# balik ke angelica
DEVICE=angelica bash scripts/prepare-port.sh
```

Hasil: `out/device_dandelion.tar.xz`, `out/boot.img`, dst. — kernel yang sama
(kernel-xiaomi-mt6765), hanya defconfig/cmdline yang beda.

## 5. Catatan penting

- `deviceinfo_arch="arm"` tetapi `kernel_arch="aarch64"` → build toolchain 2-arch.
  Rootfs-nya karena itu **armhf 32-bit**, dan GSI Halium yang dipakai
  `halium-10.0-arm32`.
- `deviceinfo_dtbo` di-set → `dtbo.img` ikut dibuat dan **harus** di-flash.
  Sebaliknya `deviceinfo_recovery_dtbo` sama sekali tidak dibaca.
- Firmware harus Android 10 (MIUI **12.0.22** untuk 9C); kalau device masih
  Android 11+, flash balik stock A10 dulu (miui.com / xiaomifirmwareupdater).
- Boot img header v2 + `append_vbmeta` → pastikan AVB di-disable (flash vbmeta_disabled)
  kalau tidak boot loop.
- Kernel cmdline mengandung `systempart=/dev/mapper/system:ro` → device pakai dynamic
  partitions; flash system wajib via `fastbootd`.
- `vbmeta_disabled.img` bisa dibuat sendiri dengan avbtool:
  `avbtool make_vbmeta_image --flags 3 --padding_size 4096 -o vbmeta_disabled.img`
- Recovery image + device tarball dipakai bersama oleh ubports-installer.
- Jika device hang di logo MI → coba flash ulang vbmeta_disabled via `mtkclient`
  (https://github.com/bkerler/mtkclient) karena MTK BROM bisa akses meski bootloader mati.

## 6. Kalau gagal boot

Lihat [`debugging.md`](debugging.md) — cara tes bertahap, peta gejala → alat,
dan cara ambil log (`console-ramoops` dari recovery, telnet initramfs Halium,
SSH + `journalctl` dari rootfs).

## 7. Build via CI

- **GitLab CI** → lihat [`gitlab-ci.md`](gitlab-ci.md) (metode paling gampang, template resmi UBports)
- **GitHub Actions** → lihat [`github-actions.md`](github-actions.md) — workflow-nya sudah ada di repo ini di `.github/workflows/build.yml`
