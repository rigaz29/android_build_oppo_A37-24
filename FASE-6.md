# Fase 6 — tambalan kernel 3.10 dan bring-up di perangkat

10 September 2026. **BERJALAN** — ROM sudah masuk perangkat, belum boot.

Fase ini berbeda sifatnya dari Fase 0–5. Sampai Fase 5 yang diuji adalah
*pipeline build*; di sini yang diuji **perangkatnya**, dan alat ukurnya berubah
total: bukan lagi log build, melainkan ramoops, `/data`, dan `dd` terhadap
partisi.

## Skor

| | |
|---|---|
| Tambalan diterapkan | 27 dari kit 23.2, plus 13 baru untuk 24.0 |
| Repo di-fork untuk itu | 8 (kemudian dikonversi jadi patch) |
| Flash ke perangkat | 12 |
| Titik henti berbeda yang ditemukan | 12 |
| Boot penuh | **ya, 12 September 2026** |

---

## 1. Dua belas titik henti, dan kenapa itu kemajuan

Tiap perbaikan memindahkan kegagalan lebih dalam. Itu bukan basa-basi: ia
membuktikan hipotesis sebelumnya benar, karena gejalanya tidak berulang.

| flash | berhenti di | detik |
|---|---|---|
| 1 | init tahap pertama tidak menemukan fstab | 4,15 |
| 2 | block device `/system` tidak muncul, 20 detik `wait` | 24,48 |
| 3 | vold jalan, berhenti sebelum zygote | 13,3 |
| 4 | `post-fs` sampai `restorecon /cache`, zygote tak pernah mulai | 13,5 |
| 5 | `netd1shot` gagal, `reboot_on_failure` me-reboot | 14,1 |
| 6 | surfaceflinger SIGSEGV di libEGL, 18 kali | ~5 detik sekali |
| 7 | surfaceflinger SIGABRT `gralloc-mapper is missing`, 17 kali | ~5 detik sekali |
| 8 | zygote SIGABRT `createProcessGroup` saat fork system_server | 31 kali |
| 9 | `NetworkStatsService` melempar saat peta BPF tak terbuka | boot phase 200 |
| 10 | `BpfNetMaps` mengembalikan null, pemakainya men-dereferensi | ConnectivityService |
| 11 | `setChildChain` membaca `.val` dari nilai null | ConnectivityService |
| 12 | dua ring buffer eBPF memakai ctor yang sengaja abort | phase 550 |

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

## 3b. Kenapa diagnosisnya buta — ramoops salah ukur

Ditemukan 11 September, sesudah berhari-hari menyimpulkan dari log rusak.

`/proc/iomem` pada perangkat menunjukkan wilayah yang benar-benar dicadangkan
hanya **1 MB**:

```
9ff00000-9ff3ffff : persistent_ram
9ff40000-9ff7ffff : persistent_ram
9ff80000-9ffbffff : persistent_ram
9ffc0000-9fffffff : persistent_ram      <- berakhir di sini
a0300000-ffffffff : System RAM          <- a0000000-a02fffff tidak terdaftar
```

Sementara cmdline menyetel `ramoops.mem_size=0x400000`, yaitu **4 MB**.
Selisihnya menjulur ke `0xa0000000-0xa02fffff`, wilayah yang bukan System RAM
maupun persistent_ram dan kemungkinan milik firmware modem. Pembagiannya sendiri
juga sudah melebihi kapasitas sejak awal: console 1 MB + dmesg 2x256 KB +
pmsg 256 KB = 1,75 MB untuk wilayah 1 MB.

Akibatnya persis seperti yang teramati sepanjang bring-up:

| | letak | akibat |
|---|---|---|
| `console` 1 MB | muat di 1 MB sah | selalu masih terbaca |
| `dmesg` 2x256 KB | di luar wilayah sah | 1638 blok hancur, pola 0x55 |
| `pmsg` 256 KB | di luar wilayah sah | tersisa 2-3 KB dari 256 KB |

> Yang paling mahal bukan lognya rusak, melainkan rusaknya TIDAK KONSISTEN.
> `pmsg` sempat melonjak dari 3 KB ke 57 KB lalu menyusut lagi, dan lonjakan itu
> dibaca sebagai perubahan perilaku boot. Padahal itu variasi kerusakan memori,
> bukan sinyal. Satu putaran diagnosis terbuang karenanya.

Dikoreksi di `0c36f058` menjadi 1 MB total: console 256 KB, pmsg 256 KB,
dmesg 4 x 128 KB. Angka 4 MB semula dipilih tanpa memeriksa berapa yang
dicadangkan; pemeriksaan itu satu perintah dan seharusnya dilakukan sebelum
menyandarkan berhari-hari diagnosis padanya.

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

## 5. Flash 5 sampai 8 — empat blocker berikutnya

Pola yang sama berlanjut: tiap perbaikan memindahkan kegagalan lebih dalam,
dan itulah buktinya hipotesis sebelumnya benar.

### Flash 5 — `reboot_on_failure` mengubah kegagalan tertangani jadi bootloop

    init: Service 'netd1shot' (pid 568) exited with status 255
    init: Service netd1shot has 'reboot_on_failure' option and failed,
          shutting down system.
    init: Reboot start, reason: reboot,netd1shot-fail

`netd1shot` memverifikasi netd dapat dijalankan sekali dengan benar.
Andaian di baliknya: netd yang gagal menandakan kerusakan fatal. Di kernel
tanpa eBPF andaian itu tidak berlaku -- netd memang sengaja berjalan tanpa
BPF. Dua perbaikan: `NetdUpdatable` mengembalikan 0 alih-alih -1, dan
`reboot_on_failure` dicabut dari `netd.rc`.

Yang tidak terduga: shutdown yang dipicunya **tidak pernah tuntas**. dmesg
berlanjut sampai detik 103 dengan zygote pada status `stopping`. Sebagian
dari apa yang selama ini terlihat sebagai bootloop sebenarnya sistem yang
tergantung di tengah shutdown.

### Flash 6 — satu baris `LOCAL_MODULE_PATH` yang salah

    ueventd: Added '/vendor/etc/ueventd.rc' to import list
    ueventd: Unable to read config file '/vendor/etc/ueventd.rc':
             open() failed: No such file or directory

`rootdir/Android.mk` memasang `ueventd.rc` di `$(TARGET_OUT_VENDOR)` --
layout pra-Oreo. init membacanya di `/vendor/etc/`. Akibatnya aturan
`/dev/kgsl-3d0 0666 system system` tidak pernah dipakai, node GPU tetap
`0600 root:root`, dan surfaceflinger (uid 1000) kena EACCES:

    Adreno-GSL: open(/dev/kgsl-3d0) failed: errno 13. Permission denied
    Adreno-EGL: <egliInitState:679>: gsl library open failure
    libEGL: eglInitialize(0x1) failed (EGL_NOT_INITIALIZED)

Ini murni izin DAC, **bukan SELinux**: seluruh denial pada boot itu bertanda
`permissive=1` dan tidak ada satu pun untuk kgsl. Membedakan keduanya lebih
awal menghemat banyak waktu.

Kegagalan EGL itu lalu tersamar oleh bug AOSP asli. `DisplayImpl()` hanya
menginisialisasi `dpy` dan `state`; empat pointer di `queryString` baru diisi
setelah `eglInitialize()` berhasil. Pada cabang gagal isinya sampah, dan
sampah bukan-NULL lolos penjagaan `if (exts)` di `findExtension()`:

    signal 11 (SIGSEGV), fault addr 0x200
      #00 strchr+4 / #01 strstr+10
      #02 egl_display_t::initialize+962   libEGL.so

Satu dari 18 crash berbunyi `no suitable EGLConfig found` alih-alih SIGSEGV
-- pada run itu sampahnya kebetulan jinak sehingga `initialize()` terlewati
dan kegagalan muncul satu langkah kemudian. Sumbernya sama.

### Flash 7 — Android 17 menutup jalur gralloc lama

    Abort message: 'gralloc-mapper is missing'
      #03 libui.so (GraphicBufferMapper::GraphicBufferMapper()+152)

`GraphicBufferMapper` mencoba Gralloc5 lalu Gralloc4, dan baru turun ke
Gralloc3/Gralloc2 bila `requireMapper4()` salah:

    return android_get_device_api_level() >= 36 && flags::require_gralloc4_or_newer();

API level perangkat ini 37, jadi cabang Gralloc2 tertutup padahal A37 hanya
punya blob gralloc1. `LEGACY_GRALLOC` adalah jalur hulu untuk perangkat
seperti ini -- variabel soong config, dan **wajib bertipe bool**:
tanpa `SOONG_CONFIG_TYPE_libui_legacy_gralloc := bool` soong menolak
analisis karena cabang `true:` pada `select()` bertipe bool sedangkan
variabelnya terdaftar string. Satu build hilang karena pelajaran itu.

### Flash 8 — cgroup v2 tidak ada, dan zygote menganggapnya fatal

    zygote: JNI FatalError: createProcessGroup(1000, 0) failed:
            No such file or directory

Rantainya panjang tapi lurus:

    Failed to mount cgroup v2: No such device
    Failed to create directory for /sys/fs/cgroup/apps: No such file or directory
    init: Command 'SetupCgroups' failed: Failed to setup cgroups
      -> /sys/fs/cgroup/system/ tidak pernah terbentuk
      -> createProcessGroup gagal -> zygote mati sebelum system_server

Diuji langsung di perangkat, bukan diduga:

    grep cgroup2 /proc/filesystems              tidak ada
    mkdir /sys/fs/cgroup/uji                    ENOENT
    mount -t cgroup -o none,name=android ...    rc=0
    mkdir -p /sys/fs/cgroup/system/uid_1000/pid_999   OK
    echo $PID > .../cgroup.procs                OK, terbaca kembali

`/sys/fs/cgroup` **ada** di kernel ini, tetapi hanya sebagai direktori
kobject sysfs kosong -- `mkdir` di dalamnya memberi ENOENT, bukan EPERM.
Itu menjelaskan errno yang semula membingungkan.

Perbaikannya: saat `cgroup2` gagal dengan ENODEV, mount **hierarki v1
bernama** (`none,name=android`) di jalur yang sama. Itu memberi direktori
bersarang dan `cgroup.procs` sungguhan, jadi pelacakan dan pembunuhan
process group tetap berfungsi -- bukan cgroup palsu. Dibatasi pada ENODEV
supaya kegagalan mount cgroup2 karena sebab lain tidak tersamar.

## 6. Dua celah kernel 3.10 lain yang ikut tertambal

`tombstoned` tidak pernah bisa menulis tombstone: `O_TMPFILE` baru ada sejak
kernel 3.11, jadi `openat()` gagal EOPNOTSUPP, `PLOG(FATAL)` membunuhnya, dan
init menghidupkannya lagi -- tiap crash memicu putaran itu sekali lagi.
Perangkat jadi tidak punya tombstone justru ketika paling dibutuhkan. Jalur
mundurnya: berkas sementara bernama lewat `mkostemp()`, dipindahkan dengan
`renameat()` alih-alih `linkat()`. Sesudah tambalan ini boot berikutnya
menghasilkan **62 berkas tombstone**, dan 31 di antaranya menunjuk langsung
ke penyebab flash 8.

`/metadata` lenyap karena init melakukan `Switching root to '/system'` pada
detik 2,91, sementara direktori itu hanya ada di ramdisk.
`create_root_structure.mk` membuatnya hanya bila
`BOARD_USES_METADATA_PARTITION` diset -- dan A37 memang tidak punya partisi
metadata, jadi menyalakan flag itu akan menyatakan sesuatu yang tidak benar
tentang perangkat kerasnya. `BOARD_ROOT_EXTRA_FOLDERS` menambah titik-kait
tanpa klaim apa pun soal partisi, lalu ditimpa tmpfs di `early-init`.
Sesudahnya ketiga layanan `aconfigd` keluar dengan status 0 (sebelumnya 5,
6, dan 1) dan apexd tidak lagi gagal menulis konfigurasinya.

## 7. Terbukti: ROM boot

12 September 2026, pukul 00:2x. Diverifikasi lewat adb ke perangkat yang
sedang berjalan, bukan dari layar:

    sys.boot_completed        = 1
    dev.bootcomplete          = 1
    init.svc.bootanim         = stopped
    ro.build.version.release  = 17
    ro.build.version.sdk      = 37
    kernel                    = 3.10.108-lineageos-g756cb462334-dirty
    boot phase                = 1000  (PHASE_BOOT_COMPLETED)
    crash                     = 0

Proses yang berjalan: `com.android.systemui`, `com.android.launcher3`,
`org.lineageos.setupwizard`, `com.android.managedprovisioning`.
Bukti mentahnya di `report/boot-berhasil/`.

### Dua pelajaran yang paling mahal

**Menutup satu lubang sering hanya memindahkan kegagalan.** Peta BPF null ->
peta yang mengabaikan segalanya -> peta berbasis memori: tiga iterasi untuk
satu persoalan, karena dua yang pertama menambal gejala di titik terdekat.
Baru yang ketiga menutup kelasnya. Gejalanya pun sempat identik meski
penyebabnya sudah bergeser, dan itu hampir menyesatkan.

**Memperbaiki satu berkas tanpa menyisir tetangganya.** `LoopbackEventHandler`
duduk di direktori yang sama dengan `LocalNetEventHandler` dengan bug yang
sama persis, dan terlewat. Satu siklus build dan flash terbuang. Sesudahnya
seluruh pohon disisir, dan ternyata tidak ada pemakai ketiga.

Satu lagi yang lebih kecil tapi sama jenisnya: pola pencarian `get[A-Za-z]+`
melewatkan `getL4sEnabledMap` karena namanya mengandung angka -- dan skrip
verifikasinya memakai pola yang sama, sehingga melaporkan bersih padahal
tidak.

## 8. Utang yang harus dibayar sebelum rilis

Semuanya diagnostik, sengaja dipasang, dan harus dicabut:

- `WITH_ADB_INSECURE` di `lineage_A37.mk` -- dikomentari, bukan `:= false`
  (`ifdef` bernilai benar untuk nilai apa pun yang tidak kosong)
- `bootwatchdog.sh`: `JEDA=1`, cuplikan tiap iterasi, aliran `/dev/kmsg`
- `ro.adb.secure=0` dan `ro.debuggable=1`
