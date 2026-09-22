# Debugging & ambil log — angelica (Redmi 9C)

Panduan ini buat kalau build sudah ke-flash tapi **bootloop**, **layar hitam**,
atau **nyangkut di logo MI**.

## Kenapa device ini lebih ribet

- **MT6765 tidak mengekspos UART**, jadi tidak ada serial console untuk membaca
  log boot dari awal. Log harus diambil lewat jalur lain: `pstore` (kernel),
  USB-network gadget Halium (initramfs), atau SSH/adb (rootfs).
- **Partisi `system` dinamis**, jadi flashing rootfs wajib lewat `fastbootd`
  (`fastboot reboot fastboot`).

## 0. Persiapan sebelum flash (jalur pulang)

Lakukan ini **sebelum** flashing apa pun. Kalau device mati total dan tidak ada
image stock, pemulihannya jauh lebih susah.

1. Unduh **ROM fastboot resmi angelica** (MIUI) — di dalamnya ada `boot.img`,
   `vbmeta.img`, `dtbo.img` stock untuk balik kalau gagal.
2. Catat kondisi bootloader:
   ```bash
   fastboot getvar current-slot     # ada output = device A/B
   fastboot getvar all > getvar.txt
   ```
3. Siapkan **mtkclient** (https://github.com/bkerler/mtkclient) untuk mode BROM —
   ini satu-satunya jalur kalau bootloader/kernel sama-sama tidak jalan.
4. Driver USB Xiaomi/Google terpasang (Windows) supaya `adb`/`fastboot` seeing.

## 1. Cek dulu tanpa device (menghemat siklus flash)

Jalankan di WSL/Linux. Tool-nya sudah ada kalau kamu pernah build lokal
(`workdir/downloads/...`); kalau tidak:

```bash
curl -LO https://raw.githubusercontent.com/LineageOS/android_system_tools_mkbootimg/lineage-20.0/unpack_bootimg.py
```

```bash
# a) Isi boot.img: header, cmdline, DTB
python3 unpack_bootimg.py --boot_img out/boot.img --out /tmp/bootunpack
ls -l /tmp/bootunpack
strings /tmp/bootunpack/dtb | grep -i -m3 -e angelica -e "Redmi 9C"

# b) Footer AVB (harus tidak error)
python3 workdir/downloads/avb/avbtool verify_image --image out/boot.img

# c) Isi device tarball (overlay + blob)
tar -tJf out/device_angelica.tar.xz | head -30

# d) Rootfs: device & channel OTA harus cocok
zstd -d out/ubuntu.img.zst -o /tmp/ubuntu.img
sudo mount -o loop,ro /tmp/ubuntu.img /mnt
cat /mnt/etc/system-image/channel.ini
sudo umount /mnt
```

| Yang dicek | Harusnya |
|---|---|
| `bootimg_info` (dari `unpack_bootimg.py`) | `header_version: 2`, cmdline berisi `systempart=/dev/mapper/system:ro` |
| `dtb` di boot.img | mengandung `angelica` (DTB angelica + mt6765 di-concat) |
| `avbtool verify_image` | tidak error |
| `device_angelica.tar.xz` | berisi `overlay/`, `lib/modules/`, blob |
| `channel.ini` | `device: angelica`, `channel: 24.04-2.x/armhf/android9plus/daily` |

Blok d di atas **tidak wajib** — cuma memastikan rootfs tahu dia untuk device apa.

## 2. Flash bertahap, jangan sekaligus

Tiap langkah sengaja dibiarkan untuk melihat tahap mana yang berhasil:

```bash
fastboot flash vbmeta vbmeta_disabled.img
fastboot flash vbmeta_system vbmeta_disabled.img
fastboot flash vbmeta_vendor vbmeta_disabled.img

fastboot flash boot out/boot.img
fastboot flash recovery out/recovery.img
fastboot reboot
```

Kalau device sudah tidak sampai layar apa pun, mundur ke langkah yang sudah
terbukti jalan (`fastboot flash boot boot_stock.img` dari ROM resmi).

`system` **jangan** di-flash dulu: booting tanpa rootfs yang benar tetap
memberi informasi (initramfs akan bilang dia gagal mount), dan menghemat waktu
flash image ~1 GB.

## 3. Membaca tahap boot dari nomor seri USB (dari dokumentasi Halium)

Halium membocorkan status early-init lewat **nomor seri** gadget USB-nya, jadi
kamu bisa tahu seberapa jauh boot berjalan:

```bash
# Linux
while : ; do lsusb -v 2>/dev/null | grep -Ee 'iSerial +[0-9]+ +[^ ]' ; done | uniq
```

| Yang muncul | Artinya |
|---|---|
| `... Mer Debug setting up (DONE_SWITCH=no)` | initramfs jalan, sedang menyiapkan jaringan USB |
| `... Mer Debug telnet on port 23 on usb0 192.168.2.15` | early init **gagal**, telnet siap — lanjut ke §5 |
| `... GNU/Linux devices on rndis0 10.15.19.82` | **sistem berhasil boot** — lanjut ke §6 |

Di Windows `lsusb` tidak ada; pakai WSL2 + [usbipd-win](https://github.com/dorssel/usbipd-win)
(`usbipd list` lalu `usbipd attach --wsl <id>`) supaya device USB-nya terlihat
di dalam WSL, dan telnet/SSH-over-USB bisa dipakai seperti contoh.

## 4. Peta gejala → alat

| Gejala | Tahap | Alat |
|---|---|---|
| Layar diam total, atau balik sendiri ke fastboot | bootloader / AVB | `avbtool verify_image`, cek `vbmeta_disabled.img` benar-benar ke-flash |
| Nyala sebentar lalu mati/reboot berulang | kernel / DTB | **pstore** (§5) |
| Nyangkut di logo MI | initramfs Halium | **telnet** (§5b) |
| Ada adapter USB network muncul tapi UI tidak muncul | rootfs / systemd | **SSH** (§6) |
| UI muncul lalu blank / crash | Lomiri | `journalctl --user -b` (§6) |

## 5a. Kernel log lewat pstore

Setelah device gagal boot, **boot ulang ke `recovery.img`** yang kita build
(recovery itu "sistem yang jalan" untuk membaca log boot sebelumnya):

```bash
adb devices
adb shell 'ls /sys/fs/pstore/'
adb shell 'cat /sys/fs/pstore/console-ramoops-0' > console-ramoops.txt
adb shell 'cat /proc/last_kmsg'            > last_kmsg.txt   # kernel lama saja
```

Nama filenya bisa `console-ramoops-0` atau varian lain — lihat dulu isi
direktorinya. `pstore` hanya terisi kalau **kernel panic**, jadi kalau device
cuma *hang* (diam tanpa reboot) biasanya kosong.

Kalau `/sys/fs/pstore/` kosong, cek apakah kernelnya memang menyimpan:

```bash
grep -E 'PSTORE|RAMOOPS' \
  workdir/downloads/kernel-xiaomi-mt6765/arch/arm64/configs/angelica_halium_defconfig
```

Yang dibutuhkan: `CONFIG_PSTORE=y`, `CONFIG_PSTORE_CONSOLE=y`,
`CONFIG_PSTORE_RAM=y`. Kalau ada tapi tetap kosong, berarti region `ramoops`
tidak di-reserve di DTB → jalur yang bisa dipakai tinggal telnet (§5b).

## 5b. Initramfs Halium lewat telnet

Kalau nomor seri USB menunjukkan `Mer Debug telnet ... on usb0 192.168.2.15`:

```bash
# 1) cari nama interface USB (Linux)
dmesg | tail        # cari baris "... renamed from usb0" -> mis. enp0s20f0u7

# 2) kalau MAC-nya 00:00:00:00:00:00, set manual
sudo ip link set enp0s20f0u7 address 02:01:02:03:04:08

# 3) set jaringan
sudo ip address add 192.168.2.1 dev enp0s20f0u7
sudo ip route add 192.168.2.15 dev enp0s20f0u7
ping -c 2 192.168.2.15

# 4) masuk
telnet 192.168.2.15
```

Perintah pertama di dalam shell: **`cat diagnosis.log`** — di situ biasanya
sudah tertulis kenapa initramfs menyerah (biasanya gagal mount
`/dev/mapper/system`, atau modul kernel tidak ketemu).

## 6. Log rootfs / OS (setelah sistem jalan)

Rootfs **devel** dari job `rootfs` sengaja dibikin gampang di-debug oleh
`prepare-fake-ota.sh` upstream:

- `sshd` dijalankan saat startup dengan `PasswordAuthentication=yes` dan
  `PermitEmptyPasswords=yes`
- `usb-tethering` dijalankan saat startup
- secure ADBD dimatikan (`/etc/default/adbd` → `ADBD_SECURE=0`) — supaya bisa
  debug saat host key device sudah berubah

Saat nomor seri USB sudah bilang `rndis0 10.15.19.82`:

```bash
# langsung lewat USB, tidak perlu WiFi
ssh phablet@10.15.19.82        # password: kosong, kalau ditolak coba "phablet"
```

Di dalam device:

```bash
sudo journalctl -b -p err          # error level sejak boot terakhir
sudo journalctl -b | less           # semua
sudo journalctl --user -b          # sesi user (Lomiri)
cat /var/log/syslog
systemctl --failed
```

Kalau Android container-nya jalan: `adb logcat`.

Kalau sistem jalan dan kamu hanya perlu update rootfs tanpa flash ulang:

```bash
sudo system-image-cli -c devel -b 0
```

## 7. Naikkan verbosity kernel

Bos sudah bisa melihat lebih banyak dari kernel dengan menambah
`ignore_loglevel` ke cmdline, lewat mekanisme `overrides/`:

```bash
# overrides/deviceinfo — salin deviceinfo port dulu, lalu ubah baris cmdline
deviceinfo_kernel_cmdline="bootopt=64S3,32N2,64N2 buildvariant=user systempart=/dev/mapper/system:ro ignore_loglevel"
```

Jalankan build ulang → log kernel jadi jauh lebih berisik di `pstore`/telnet.
Hapus lagi kalau sudah selesai.

## 8. Kalau device benar-benar tidak mau nyala

- **mtkclient** (BROM mode) bisa masuk walau bootloader mati:
  `python mtk r boot boot_stock.img` untuk dump, `python mtk w boot boot.img`
  untuk menulis. Device harus dalam keadaan mati, lalu colok USB sambil tahan
  tombol volume.
- Partisi `expdb` di MTK menyimpan exception log; kalau perlu, dump dengan
  mtkclient dan cari string teks di dalamnya.

## 9. Di mana minta bantuan

Kirimkan **empat hal ini** saat melapor — tanpa ini orang susah menebak:

1. `console-ramoops.txt` (atau output telnet `cat diagnosis.log`)
2. `dmesg` dari device yang jalan
3. `deviceinfo` dan `git log --oneline -5` dari repo port
4. gejala persisnya (layar apa yang muncul, berapa detik, berapa kali reboot)

- Forum: https://forums.ubports.com
- Tutorial porting: https://docs.ubports.com/en/latest/porting/build_and_boot/index.html
- Dokumentasi debugging Halium: https://docs.halium.org/en/latest/porting/debug-build/
