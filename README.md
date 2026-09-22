# ut-angelica

Build **Ubuntu Touch** untuk **Xiaomi Redmi 9C (`angelica`)** — plus **Redmi 9A
(`dandelion`)** — lewat **GitHub Actions**, atau di mesin sendiri.

Repo ini tipis dan sengaja: **tidak menyalin source port UBports.** Saat build,
runner meng-clone source resminya dari GitLab. Jadi yang perlu di-maintain cuma
workflow + script di sini.

| Kebutuhan | Sumber (di-clone saat build) |
|---|---|
| deviceinfo, overlay, ramdisk recovery | `gitlab.com/ubports/.../xiaomi-redmi-9c/xiaomi-angelica` — branch `halium-10.0` |
| Build tools Halium generik | `gitlab.com/ubports/.../halium-generic-adaptation-build-tools` — branch `main` |
| Kernel MT6765 | di-clone otomatis dari URL di `deviceinfo` — branch `halium-10.0` |
| Rootfs Ubuntu Touch | `ubuntu-touch-rootfs` CI UBports (release default **24.04-2.x**) |

Metode: **Halium 10 GSI-port**. Yang dibuild sendiri hanya kernel + boot image +
device tarball. Rootfs-nya dirakit dari CI UBports di job kedua.

## Isi repo

```
.
├── .github/workflows/build.yml   # job build + rootfs
├── scripts/prepare-port.sh       # clone repo port + build tools, terapkan overrides/
├── scripts/make-rootfs.sh        # rakit rootfs siap-flash dari device tarball
├── overrides/                    # (opsional) timpa file repo port tanpa fork
└── docs/ubuntu-touch-angelica/   # catatan porting & flashing
```

## Kenapa bisa jalan di GitHub Actions?

Karena runner `ubuntu-22.04` milik GitHub itu **VM penuh, bukan container**:

- punya `sudo`, `losetup`, dan `mount` → wajib, karena `system-image-from-ota.sh`
  me-loop-mount image rootfs untuk mengisinya. Di container biasa ini gagal.
- **repo publik = menit Actions gratis tanpa batas**, jadi build 1–2 jam tidak
  dihitung biaya.
- batasnya: **maks 6 jam per job**, ~14 GB disk, artifact disimpan 14 hari.

## 1. Push ke GitHub

**Buat repo kosong dulu** di https://github.com/new — nama `ut-angelica`, dan
**jangan** centang *Add a README* (repo harus kosong, `git push` tidak
membuat repo otomatis):

```bash
git add -A && git commit -m "Init Ubuntu Touch build untuk angelica"
git remote add origin https://github.com/<USER>/ut-angelica.git
git branch -M main && git push -u origin main
```

Ganti `<USER>` dengan username GitHub kamu. Soal autentikasi:

- **HTTPS + Git Credential Manager** (default di Git for Windows) — saat `push`
  pertama, browser terbuka untuk login GitHub. Paling gampang, tanpa bikin key.
- **SSH** — kalau mau pakai `git@github.com:<USER>/ut-angelica.git`, harus ada
  key dulu:
  ```bash
  ssh-keygen -t ed25519 -C "email@kamu"
  cat ~/.ssh/id_ed25519.pub   # tempel ke GitHub → Settings → SSH and GPG keys
  ```

Kalau Actions belum aktif: *Settings → Actions → General → Allow all actions*.

Setelah push, workflow langsung jalan. Untuk build manual: tab **Actions →
Ubuntu Touch (angelica) → Run workflow**, bisa pilih `angelica`/`dandelion` dan
apakah sekalian merakit rootfs.

## 2. Build lokal (opsional)

Butuh Linux (Ubuntu 20.04/22.04). Di WSL juga bisa.

```bash
sudo apt-get install -y bc bison build-essential cpio curl fakeroot flex git \
  kmod libelf-dev libssl-dev libtinfo5 lz4 python2 python3 unzip wget xz-utils \
  pahole libbpf-dev img2simg zstd
sudo ln -sf python2 /usr/bin/python

bash scripts/prepare-port.sh          # clone source ke port/
cd port && ./build/build.sh           # build kernel + boot.img + device tarball
cd .. && bash scripts/make-rootfs.sh  # (opsional) rakit rootfs
```

Opsi `port/build/build.sh`: `-b <dir>` workdir, `-o <dir>` output, `-c` clone
saja, `-k` kernel saja, `-m` menuconfig.

Variabel environment yang dikenali `prepare-port.sh`: `DEVICE`
(`angelica`/`dandelion`), `PORT_DIR`, `PORT_BRANCH`, `TOOLS_BRANCH`,
`OVERRIDES_DIR`.

## 3. Artefak yang dihasilkan

**`<device>-build`** (job `build`):

| File | Isi |
|---|---|
| `boot.img` | kernel MT6765 + ramdisk halium (DTB `mt6765`/`angelica` tertanam di dalamnya) |
| `recovery.img` | recovery halium untuk flashing/install |
| `device_angelica.tar.xz` | device tarball: overlay + blob firmware dari device |
| `Module.symvers` | simbol kernel (untuk debug modul) |

**`<device>-flashable`** (job `rootfs`):

| File | Isi |
|---|---|
| `ubuntu.img.zst` | rootfs ext4 raw, dikompres zstd — `zstd -d` dulu sebelum dipakai |
| `system.img` | rootfs yang sama dalam format **sparse**, langsung bisa `fastboot flash` |

> Angelica **tidak** menghasilkan `dtbo.img` terpisah: `deviceinfo`-nya tidak
> mendefinisikan `deviceinfo_dtbo`, dan DTB sudah ikut tertanam di `boot.img`.
> `recovery_dtbo_angelica.img` di repo port hanya blob sisa tool versi lama.

## 4. Flashing singkat

Bootloader harus sudah di-unlock, dan sebaiknya device pernah boot MIUI sekali
supaya partisinya ter-init.

```bash
adb reboot bootloader

# matikan verified boot, kalau tidak bootloop karena boot.img ber-append vbmeta
fastboot flash vbmeta vbmeta_disabled.img
fastboot flash vbmeta_system vbmeta_disabled.img
fastboot flash vbmeta_vendor vbmeta_disabled.img

fastboot flash boot boot.img
fastboot flash recovery recovery.img

# rootfs ke partisi system — wajib lewat fastbootd (dynamic partitions)
zstd -d ubuntu.img.zst                     # atau pakai system.img langsung
fastboot reboot fastboot
fastboot flash system system.img
fastboot reboot
```

`vbmeta_disabled.img` bisa dibuat sendiri:

```bash
avbtool make_vbmeta_image --flags 3 --padding_size 4096 -o vbmeta_disabled.img
```

Detail lengkap + troubleshooting ada di
[`docs/ubuntu-touch-angelica/README.md`](docs/ubuntu-touch-angelica/README.md).

## 5. Kustomisasi tanpa fork

Taruh file apa pun di `overrides/` dengan path yang sama seperti di repo port;
`scripts/prepare-port.sh` akan menimpanya. Contoh: ubah release rootfs jadi
`deviceinfo_ubuntu_touch_release="20.04"` di `overrides/deviceinfo`. Lihat
[`overrides/README.md`](overrides/README.md).

## 6. Troubleshooting

| Gejala | Sebab / solusi |
|---|---|
| Job gagal "No space left on device" | Step *Kosongkan disk runner* sudah membebaskan ruang; kalau masih kurang, hapus step cache (cache mengisi disk) dan/atau pasang `ADAPTATION_TOOLS_USE_TMP_BUILD_DIR=1` (catatan: env ini mematikan manfaat cache karena workdir jadi folder sementara). |
| Install `python2` / `libtinfo5` gagal | Runner harus `ubuntu-22.04`. Di `ubuntu-24.04` paket itu sudah tidak ada. |
| Build mengulang dari nol terus | Cache gagal di-restore. Cek key `port/workdir/downloads` di log step *Cache toolchain*. |
| Job `rootfs` gagal di `system-image-from-ota.sh` | Biasanya karena `losetup`/`mount` diblokir — pastikan pakai runner `ubuntu-22.04` (VM), bukan container. |
| `build.sh: deviceinfo: No such file` | `prepare-port.sh` harus dijalankan dulu; `build.sh` wajib dijalankan **dari dalam** folder port. |
| Artefak kosong | Job `build` gagal sebelum `make-bootimage.sh`; baca log step *Build kernel*. |

## 7. Catatan

- Rootfs dari job `rootfs` adalah rilis **devel/daily** — channel OTA yang
  tertanam di dalamnya (`24.04-2.x/armhf/android9plus/daily`, mengikuti default
  `prepare-fake-ota.sh` upstream) dipakai untuk update selanjutnya.
- Job `flashable` di repo port UBports (rootfs dari OTA resmi) **di-disable**
  (`rules: when: never`) karena angelica bukan device resmi — jadi jangan
  berharap ada channel OTA resmi untuk device ini.
- `deviceinfo_arch="arm"` tapi `deviceinfo_kernel_arch="aarch64"`: toolchain yang
  dipakai 2 arsitektur.
- Kalau device mati total, MTK BROM masih bisa diakses lewat
  [mtkclient](https://github.com/bkerler/mtkclient).
