# overrides/

Semua isi folder ini (kecuali README ini) akan **di-copy menimpa** repo port
setelah clone, sebelum build dijalankan. Ini cara mengubah build tanpa harus
mem-fork repo port UBports.

Diterapkan oleh `scripts/prepare-port.sh`, jadi jalan baik di lokal maupun di
GitHub Actions.

## Cara pakai

Bikin file dengan path yang sama seperti di repo
[`xiaomi-angelica`](https://gitlab.com/ubports/porting/community-ports/android10/xiaomi-redmi-9c/xiaomi-angelica).
Contoh:

```
overrides/
├── deviceinfo                      # timpa deviceinfo bawaan
└── overlay/system/etc/...          # tambah/ubah file di overlay device
```

## Contoh yang berguna untuk angelica

Ubah release rootfs yang dirakit `scripts/make-rootfs.sh` (default upstream
sekarang `24.04-2.x`):

```bash
# overrides/deviceinfo — salin deviceinfo port dulu, lalu ubah baris relevan
deviceinfo_name="Redmi 9C"
deviceinfo_manufacturer="Xiaomi"
deviceinfo_codename="angelica"
deviceinfo_arch="arm"
deviceinfo_kernel_arch="aarch64"
deviceinfo_halium_version=10
deviceinfo_kernel_source="https://gitlab.com/ubports/community-ports/android10/xiaomi-redmi-9c/kernel-xiaomi-mt6765"
deviceinfo_kernel_source_branch="halium-10.0"
deviceinfo_kernel_defconfig="angelica_halium_defconfig"
# ... variabel lain wajib tetap ada, kalau hilang build akan gagal
deviceinfo_ubuntu_touch_release="24.04-2.x"
```

> Kalau `overrides/deviceinfo` ada **dan** kamu menjalankan varian `dandelion`,
> symlink `deviceinfo-dandelion` yang dipilih — jadi yang menang adalah varian
> device, bukan override.
