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
└── docs/ubuntu-touch-angelica/   # catatan porting, flashing & debugging
    ├── README.md                 #   panduan utama
    ├── debugging.md              #   tes boot & ambil log
    ├── gitlab-ci.md              #   alternatif build via GitLab CI
    └── github-actions.md         #   penjelasan workflow di repo ini
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

**`<device>-build`** (job `build`) — ini bahan mentah, **bukan** untuk flashing:

| File | Isi |
|---|---|
| `device_angelica.tar.xz` | device tarball. Isinya dua folder: `system/` (overlay + blob dari device) dan `partitions/` (`boot.img`, `recovery.img`, `dtbo.img`) |
| `device_angelica_usrmerge.tar.xz` | hardlink ke file di atas, nama lama untuk pipeline yang belum di-update |
| `Module.symvers` | simbol kernel (untuk debug modul) |
| `vbmeta_disabled.img` | vbmeta ber-flag 3 (verification + hashtree disabled) — dibuat workflow pakai `avbtool` |

Perhatikan: `boot.img` **tidak** ada sebagai file lepas di sini. `build.sh` hanya
menaruhnya di dalam `partitions/` lalu memasukkannya ke device tarball.

**`<device>-flashable`** (job `rootfs`) — **inilah yang kamu pakai untuk flashing**:

| File | Isi |
|---|---|
| `boot.img` | kernel MT6765 + ramdisk halium, DTB tertanam, AVB hash footer + vbmeta ber-append |
| `dtbo.img` | DTB `mt6765`/`angelica` untuk partisi `dtbo` |
| `recovery.img` | UBports recovery. **Opsional** — lihat catatan di bawah |
| `system.img` | rootfs ext4 dalam format **sparse**, langsung bisa `fastboot flash` |
| `ubuntu.img.zst` | rootfs yang sama tapi ext4 **raw** + zstd (`zstd -d` kalau mau versi mentah) |
| `vbmeta_disabled.img` | untuk `vbmeta` / `vbmeta_system` / `vbmeta_vendor` |

> `boot.img`/`recovery.img`/`dtbo.img` masuk ke artefak ini lewat jalur yang tidak
> kelihatan: `system-image-from-ota.sh` mengekstrak device tarball lalu menjalankan
> `cp partitions/* out/`.
>
> **`dtbo.img` ada** — `deviceinfo` angelica mendefinisikan
> `deviceinfo_dtbo="mediatek/mt6765.dtb mediatek/angelica.dtb"` dan
> `deviceinfo_skip_dtbo_partition` tidak di-set, jadi `make-dtboimage.sh` jalan.
> Yang **tidak** dipakai adalah `deviceinfo_recovery_dtbo` (dan file
> `recovery_dtbo_angelica.img`): tidak ada satu pun tool di build-tools yang
> membacanya — di `make-bootimage.sh` variabelnya cuma `--recovery_dtbo $DTBO`,
> yang isinya `partitions/dtbo.img`.

## 4. Flashing singkat

Bootloader harus sudah di-unlock, dan sebaiknya device pernah boot MIUI sekali
supaya partisinya ter-init.

**Prasyarat**: firmware Android 10 (MIUI **12.0.22** untuk 9C) — bukan MIUI 12.5/13.
Kalau sekarang masih Android 11+, flash balik stock A10 dulu.

```bash
adb reboot bootloader

# 1) matikan verified boot
fastboot flash vbmeta vbmeta_disabled.img
fastboot flash vbmeta_system vbmeta_disabled.img
fastboot flash vbmeta_vendor vbmeta_disabled.img

# 2) boot + dtbo — rootfs BELUM, supaya kalau gagal kamu hemat satu flash besar
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot reboot            # lihat dulu nomor seri USB — lihat debugging.md §2
```

Kalau seri USB berubah jadi `Mer Debug telnet on port 23 on usb0 192.168.2.15`
atau muncul logo UBports, kernel + initramfs hidup. Lanjut:

```bash
# 3) rootfs ke partisi system — wajib lewat fastbootd (dynamic partitions)
fastboot reboot fastboot
fastboot delete-logical-partition product   # beri ruang untuk system
fastboot flash system system.img
fastboot reboot
```

> **Ubuntu Touch bukan ROM Android** — tidak ada zip yang di-flash lewat
> TWRP/OrangeFox. Rootfs UT itu image ext4 mentah yang ditulis ke blok partisi
> `system`.
>
> **Baris `fastboot flash recovery` sengaja tidak ada di atas.** Partisi
> `recovery` terpisah dari `boot`/`system`, jadi kamu bisa mempertahankan
> OrangeFox (untuk nandroid backup/restore) sambil mencoba UT. `recovery.img`
> bikinan kita adalah UBports recovery yang hanya perlu untuk jalur OTA resmi,
> sedangkan rootfs **tetap** lewat `fastbootd` — recovery berbasis TWRP sering
> gagal menulis image besar ke logical partition.

`delete-logical-partition product` menghapus partisi `product` (tidak dipakai UT)
supaya `system` dapat ruang di dalam `super`. Kalau sebenarnya `product` tidak ada,
perintahnya cuma melaporkan partisi tidak ditemukan — tidak berbahaya. Konsekuensinya
kamu perlu flash stock ROM untuk mengembalikannya.

Detail lengkap ada di [`docs/ubuntu-touch-angelica/README.md`](docs/ubuntu-touch-angelica/README.md).

**Kalau bootloop / tidak booting** → [`docs/ubuntu-touch-angelica/debugging.md`](docs/ubuntu-touch-angelica/debugging.md):
urutan cek tanpa device, peta gejala → alat, dan cara ambil `console-ramoops`,
`diagnosis.log`, serta `journalctl` dari device.

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
