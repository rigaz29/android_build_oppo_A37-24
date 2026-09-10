# Fase 6 — tambalan kernel 3.10 dan bring-up di perangkat

10 September 2026. **BERJALAN** — ROM sudah masuk perangkat, belum boot.

Fase ini berbeda sifatnya dari Fase 0–5. Sampai Fase 5 yang diuji adalah
*pipeline build*; di sini yang diuji **perangkatnya**, dan alat ukurnya berubah
total: bukan lagi log build, melainkan ramoops, `/data`, dan `dd` terhadap
partisi.

## Skor

| | |
|---|---|
| Tambalan diterapkan | 27 (dari kit 23.2, semuanya menempel mulus) |
| Repo di-fork untuk itu | 8 (kemudian dikonversi jadi patch) |
| Flash ke perangkat | 4 |
| Titik henti berbeda yang ditemukan | 4 |
| Boot penuh | **belum** |

---

## 1. Empat titik henti, dan kenapa itu kemajuan

Tiap perbaikan memindahkan kegagalan lebih dalam. Itu bukan basa-basi: ia
membuktikan hipotesis sebelumnya benar, karena gejalanya tidak berulang.

| flash | berhenti di | detik |
|---|---|---|
| 1 | init tahap pertama tidak menemukan fstab | 4,15 |
| 2 | block device `/system` tidak muncul, 20 detik `wait` | 24,48 |
| 3 | vold jalan, berhenti sebelum zygote | 13,3 |
| 4 | `post-fs` sampai `restorecon /cache`, zygote tak pernah mulai | 13,5 |

### Flash 1 — fstab tidak pernah sampai ke ramdisk

```
init: [libfstab] ReadDefaultFstab(): failed to find device default fstab
Kernel panic - not syncing: Attempted to kill init! exitcode=0x00007f00
```

`GetFstabPath()` (libfstab/fstab.cpp:469-491) mencari enam lokasi, tetapi saat
init tahap pertama berjalan **tidak satu pun partisi sudah ter-mount**, sehingga
hanya `/fstab.` dan `/first_stage_ramdisk/fstab.` yang terjangkau. Modul
`fstab.qcom` memasang ke `TARGET_OUT_VENDOR_ETC`, yaitu ke dalam system image
yang belum ada. Isi ramdisk hasil build memang hanya `init` dan direktori kosong.

Sekaligus baris `/system` bertanda `recoveryonly`, sehingga fs_mgr melewatinya
pada boot normal. Itu benar untuk perangkat yang `/system`-nya di-mount pihak
lain, tetapi cmdline A37 tidak punya `root=` maupun `skip_initramfs`.

### Flash 2 — alias `bootdevice` belum ada di tahap pertama

```
init: [libfs_mgr] Failed to open '/dev/block/bootdevice/by-name/system'
```

`devices.cpp:567` SELALU membuat `/dev/block/platform/<str>/by-name/<partisi>`,
tetapi `/dev/block/by-name/<partisi>` hanya dibuat bila `is_boot_device` benar,
dan `devices.cpp:271` menentukannya dengan membandingkan **apa adanya**:

| | |
|---|---|
| `info.str` dari sysfs | `soc.0/7824900.sdhci` |
| `androidboot.bootdevice` | `7824900.sdhci` |

Tidak cocok. Diverifikasi di perangkat lewat TWRP, bukan diasumsikan.

### Flash 3 dan 4 — zygote tidak pernah dimulai

Gejalanya khas dan menyingkirkan seluruh kelas dugaan sekaligus:

| | |
|---|---|
| `/data/tombstones/` | kosong |
| `/data/anr/` | kosong |
| `/data/dalvik-cache/` | kosong |
| panic / reboot di log | tidak ada |

Tidak ada yang *crash*. Zygote memang tidak pernah **mulai**.

Rantainya:

```
init.rc:1271        on nonencrypted -> class_start main     (zygote hidup di sini)
builtins.cpp:579    queue_fs_event() memicu "nonencrypted" HANYA untuk
                    FS_MGR_MNTALL_DEV_NOT_ENCRYPTABLE (0) atau kode terenkripsi
builtins.cpp:607    untuk nilai negatif -> Error("Invalid code")
```

Jadi bila `fs_mgr_mount_all` mengembalikan -1, `class main` tidak pernah
dimulai, tanpa satu pun pesan kegagalan yang mencolok.

Yang membuatnya -1: `/cache` gagal di-mount, dan `/cache` tidak punya `nofail`.

## 2. Yang membuktikannya bukan kode, melainkan `dd`

```
init: [libfs_mgr] Invalid f2fs superblock on '.../by-name/cache'
init: [libfs_mgr] mount_with_alternatives(): skipping mount due to invalid magic
```

Godaannya menyimpulkan partisinya rusak. Diperiksa langsung dari TWRP:

| offset | isi | arti |
|---|---|---|
| 1080 | `53ef` | magic ext4 yang **sah** |
| 1024 | `0080` | bukan magic f2fs |

`/cache` sehat dan ext4; fstab yang mendaftarkan f2fs lebih dulu. Urutan `/data`
sengaja tidak diubah, karena userdata memang F2FS dan log memastikannya
ter-mount benar.

> Log memberi tahu APA yang gagal. Hanya pengukuran langsung yang memberi tahu
> apakah yang salah datanya atau konfigurasinya.

## 3. Batas ramoops, dan kenapa adb jadi penting

Ramoops perangkat ini rusak berat dan makin memburuk tiap boot:

| berkas | blok tak terpulihkan |
|---|---|
| `console-ramoops-0` | 1145 → 1167 |
| `pmsg-ramoops-0` | 23 |

`pmsg` hanya menyisakan 2.948 B dari 256 KB yang dikonfigurasi. Artinya jendela
yang terbaca terlalu sempit untuk menyimpulkan, dan menebak dari situ hanya
membakar siklus flash.

Karena itu `WITH_ADB_INSECURE` dan tambalan FunctionFS legacy bukan kemewahan:
keduanya satu-satunya jalan mendapat logcat **hidup dan utuh** dari perangkat
yang macet di logo. `adbd` jalan di `class core`, jauh sebelum zygote.

## 4. Tambalan yang diterapkan

27 tambalan dari kit 23.2, semuanya menempel mulus ke pohon 24.0 — artinya
kodenya memang belum tersentuh, tidak ada yang dipaksa.

| repo | jml | inti |
|---|---|---|
| `bionic` | 5 | arc4random tanpa `getrandom`, `rename` syscall, `epoll_pwait2`, property area, pthread |
| `system/core` | 5 | dm-verity, libprocessgroup tanpa cgroup v2, init toleran EROFS, f2fs METASYNC |
| `frameworks/base` | 4 | fs-verity, splice, toleransi layanan tak tersedia |
| `frameworks/opt/telephony` | 3 | stack trace radio, rekursi PhoneSwitcher, retry DDS |
| `frameworks/native` | 2 | `/dev/binder` vendor, GpuWork |
| `system/memory/lmkd` | 2 | tekanan memori |
| lainnya | 6 | apex `O_DIRECT`, sepolicy kernel lama, wifi, BT, NetworkStack, wlan |

## 5. Belum terbukti

Boot penuh. Semua yang di atas memindahkan kegagalan, belum menghilangkannya.
