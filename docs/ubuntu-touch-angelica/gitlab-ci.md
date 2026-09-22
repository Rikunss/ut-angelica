# Build via GitLab CI — angelica (Redmi 9C)

Metode **paling gampang & resmi**: repo port UBports angelica sudah punya
`.gitlab-ci.yml` yang meng-include template CI generik UBports
(`halium-generic-adaptation-build-tools/gsi-port-ci.yml`).

Template ini otomatis menghasilkan 3 job:

| Job | Output | Keterangan |
|---|---|---|
| `build` | `out/device_angelica.tar.xz`, `out/boot.img`, `out/recovery.img` | build kernel + boot image + device tarball |
| `devel-flashable` | `out/ubuntu.img.zst` + `out/system.img` + boot.img | rootfs siap flash |
| `flashable` | — | **dinonaktifkan** di repo port (`rules: when: never`) |

> Tidak ada `dtbo.img`: deviceinfo angelica tidak mendefinisikan `deviceinfo_dtbo`.
> Job `flashable` juga mati karena ambil rootfs dari channel OTA resmi, dan
> angelica bukan device resmi UBports — jadi satu-satunya jalur rootfs adalah
> `devel-flashable`.

## 1. Fork / import repo

**Cara termudah:** fork langsung di GitLab:

```
https://gitlab.com/ubports/porting/community-ports/android10/xiaomi-redmi-9c/xiaomi-angelica
→ klik "Fork"
```

Atau kalau ingin repo di akun sendiri: *New project → Import project →
Repository by URL*, isi:

```
https://gitlab.com/ubports/porting/community-ports/android10/xiaomi-redmi-9c/xiaomi-angelica.git
```

> Repo ini **tidak memakai Git LFS** (tidak ada `.gitattributes`), jadi proses
> import/mirror tidak akan rusak.

## 2. CI-nya sudah jalan otomatis

`.gitlab-ci.yml` (branch `halium-10.0`) meng-`include` template generik, lalu
menimpa beberapa hal:

```yaml
include:
  - https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools/-/raw/main/gsi-port-ci.yml

image: ubuntu:20.04   # repo port menimpa image template (22.04 → 20.04)
tags: [ubports]       # hapus baris ini kalau fork kamu jalan di shared runner

# job bawaan template dimatikan, lalu di-alias per device
build:
  rules:
    - when: never
flashable:
  rules:
    - when: never
devel-flashable:
  rules:
    - when: never

build-angelica:
  extends: build
  rules:
    - if: $CI_PIPELINE_SOURCE == "push"
build-dandelion:
  extends: build
  before_script:
    - ln -sf deviceinfo-dandelion deviceinfo
  rules:
    - if: $CI_PIPELINE_SOURCE == "push"
devel-flashable-angelica:
  extends: [devel-flashable]
  needs: [build-angelica]
  rules:
    - if: $CI_PIPELINE_SOURCE == "push"
devel-flashable-dandelion:
  extends: [devel-flashable]
  needs: [build-dandelion]
  before_script:
    - ln -sf deviceinfo-dandelion deviceinfo
  rules:
    - if: $CI_PIPELINE_SOURCE == "push"
```

Setiap `git push`, pipeline otomatis jalan. Tunggu sampai `build-angelica` hijau
(kernel MT6765 di-compile dengan clang, ±20–40 menit).

> **Catatan runner:** repo port memakai `image: ubuntu:20.04` dan
> `tags: [ubports]`. Tag itu hanya menunjuk runner milik UBports — kalau fork
> kamu harus jalan di shared runner publik GitLab, hapus baris `tags: [ubports]`.
> GitLab shared runner menjalankan image `ubuntu:20.04` (docker) tanpa masalah.

## 3. Ambil artefak

Setelah pipeline sukses:

- **`build` job** → *Job artifacts → Browse* →
  `out/device_angelica.tar.xz`, `out/boot.img`, `out/recovery.img`
- **`devel-flashable` job** →
  `out/ubuntu.img.zst`, `out/system.img`, `out/boot.img`, `out/recovery.img`

`ubuntu.img.zst` = rootfs Ubuntu Touch (ext4 raw, dikompres zstd — `zstd -d` dulu),
`out/system.img` = rootfs yang sama dalam format sparse, langsung bisa
`fastboot flash system`.

## 4. Rootfs `flashable` tidak tersedia untuk angelica

Job `flashable` di template generik mengambil rootfs dari **channel OTA resmi**
UBports (`fetch-and-prepare-latest-ota.sh`), dan template-nya menulis arch-nya
hardcoded `arm64` — padahal angelica `deviceinfo_arch="arm"`. Karena angelica
bukan device resmi, channel OTA-nya memang tidak ada. Repo port sendiri
mematikan job itu:

```yaml
flashable:
  rules:
    - when: never
```

Jadi kalau di fork kamu job `flashable` muncul, biarkan mati. Jalur yang benar
adalah `devel-flashable` (memakai `prepare-fake-ota.sh`, yang menyusun rootfs
dari CI `ubuntu-touch-rootfs` + tarball device-generic Halium + device tarball
dari job `build`).

Versi Ubuntu Touch-nya ditentukan `deviceinfo_ubuntu_touch_release`; default di
`prepare-fake-ota.sh` sekarang **`24.04-2.x`** (channel OTA yang tertanam:
`24.04-2.x/armhf/android9plus/daily`). Untuk memakai rilis lain, timpa di
`deviceinfo` kamu — mis. `deviceinfo_ubuntu_touch_release="focal"` untuk 20.04.

## 5. Scheduled build (opsional)

Pipeline hanya jalan saat push. Untuk rebuild otomatis (mis. rootfs devel berubah),
tambahkan `Schedule` di CI/CD → Schedules (mis. mingguan), lalu ubah rules job:

```yaml
rules:
  - if: $CI_PIPELINE_SOURCE == "push"
  - if: $CI_PIPELINE_SOURCE == "schedule"
```

## 6. Variabel CI (opsional)

Di *Settings → CI/CD → Variables*:

| Variabel | Fungsi |
|---|---|
| `ADAPTATION_TOOLS_BRANCH` | branch build-tools (default `main`) |
| `ADAPTATION_TOOLS_USE_TMP_BUILD_DIR` | set `1` kalau job gagal karena disk penuh |

## 7. Build dandelion (Redmi 9A)

Repo sudah punya job `build-dandelion` yang me-symlink `deviceinfo-dandelion`.
Kalau fork kamu belum ada, tambahkan:

```yaml
build-dandelion:
  tags: [ubports]
  before_script:
    - ln -sf deviceinfo-dandelion deviceinfo
  extends: build
  rules:
    - if: $CI_PIPELINE_SOURCE == "push"
```
