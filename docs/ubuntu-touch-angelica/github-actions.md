# Build via GitHub Actions — angelica (Redmi 9C)

Workflow yang dipakai repo ini: **`.github/workflows/build.yml`**. Dokumen ini
menjelaskan kenapa isinya begitu, supaya gampang dimodifikasi.

## Fakta upstream yang menentukan desainnya

| Fakta | Konsekuensi di workflow |
|---|---|
| Repo port default branch-nya **`halium-10.0`**, bukan `main` | clone harus `-b halium-10.0` |
| `build.sh` di repo port wajib dijalankan **dari root repo port** (script lain meng-`source deviceinfo` relatif ke CWD) | step build pakai `working-directory: port` |
| Runner GitHub `ubuntu-22.04` itu **VM penuh**, bukan container | `sudo`, `losetup`, `mount` tersedia → `system-image-from-ota.sh` bisa loop-mount rootfs |
| Template CI resmi butuh `python2` + `libtinfo5` | wajib `ubuntu-22.04`; di `ubuntu-24.04` paket itu sudah hilang |
| Job `flashable` di repo port di-disable (`rules: when: never`) karena angelica bukan device resmi | **tidak ada** rootfs dari channel OTA resmi → pakai jalur `prepare-fake-ota.sh` saja |
| `prepare-fake-ota.sh` default ke `deviceinfo_ubuntu_touch_release="24.04-2.x"` | rootfs yang dihasilkan = **Ubuntu Touch 24.04**, channel OTA `24.04-2.x/armhf/android9plus/daily` |
| `deviceinfo` angelica **tidak** mendefinisikan `deviceinfo_dtbo` | tidak ada `dtbo.img`; DTB sudah tertanam di `boot.img` |
| `workdir/downloads` berisi clang + gcc prebuilt + source kernel (beberapa GB) | layak di-cache, menghemat puluhan menit |
| Disk runner ~14 GB, job maks 6 jam | perlu step pembersih disk; build port ini ±30–90 menit |

## Struktur dua job

```
build  ──► artefak <device>-build   (boot.img, recovery.img, device_<device>.tar.xz)
   │
   └──► rootfs   artefak <device>-flashable  (ubuntu.img.zst, system.img, + boot.img)
```

- **`build`** — `scripts/prepare-port.sh` (clone repo port + build tools,
  terapkan `overrides/`), lalu `./build/build.sh` dari dalam `port/`.
- **`rootfs`** — mengunduh device tarball dari job `build`, lalu
  `scripts/make-rootfs.sh` menjalankan `prepare-fake-ota.sh` +
  `system-image-from-ota.sh`, dan meng-compress `rootfs.img` → `ubuntu.img.zst`.
  Job ini juga menghasilkan `system.img` (sparse) yang bisa langsung di-flash.

## Menjalankan

- **Otomatis**: setiap push ke `main`/`master`.
- **Manual**: *Actions → Ubuntu Touch (angelica) → Run workflow*. Ada dua input:
  - `device`: `angelica` (Redmi 9C) atau `dandelion` (Redmi 9A)
  - `make_rootfs`: apakah dilanjut merakit rootfs.

Hasil ada di tab *Actions → (run) → Artifacts*. Disimpan 14 hari.

## Cache toolchain

Key sengaja memuat `github.run_id` supaya cache selalu tersimpan ulang;
`restore-keys` yang membuat run berikutnya tetap memakai isi cache sebelumnya
(pola *rolling cache*). Kalau toolchain terasa basi, ubah prefix key
(`ut-` → `ut-v2-`) untuk memaksa unduh ulang dari nol.

Selama cache hit, unduhan dari `android.googlesource.com` dan GitLab dilewati —
`setup_repositories.sh` memang hanya meng-clone bila foldernya belum ada.

## Opsi lain: import repo port ke GitHub

Kalau kamu butuh mengubah isi repo port secara permanen (bukan sekadar override),
import repo-nya langsung:

1. https://github.com/new/import
   → Repository URL: `https://gitlab.com/ubports/porting/community-ports/android10/xiaomi-redmi-9c/xiaomi-angelica.git`
2. Copy workflow dari repo ini ke `.github/workflows/` (ubah step *Siapkan source*
   menjadi `actions/checkout` biasa).
3. Tambah remote `upstream` untuk sinkronisasi berkala.

Repo port memakai file biner (`ramdisk-recovery.img`,
`recovery_dtbo_*.img`) tapi **bukan** Git LFS (tidak ada `.gitattributes`), jadi
aman di-import ke GitHub.

Untuk sekadar menimpa beberapa file, cara `overrides/` di repo ini lebih ringan —
lihat [`../../overrides/README.md`](../../overrides/README.md).

## Troubleshooting

Lihat tabel di [`../../README.md`](../../README.md#6-troubleshooting).
