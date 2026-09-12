# Fase 6 — tambalan kernel 3.10 dan bring-up di perangkat

10 September 2026. **BERJALAN** — ROM sudah masuk perangkat, belum boot.

Fase ini berbeda sifatnya dari Fase 0–5. Sampai Fase 5 yang diuji adalah
*pipeline build*; di sini yang diuji **perangkatnya**, dan alat ukurnya berubah
total: bukan lagi log build, melainkan ramoops, `/data`, dan `dd` terhadap
partisi.

## Skor

| | |
|---|---|
| Tambalan diterapkan | 27 dari kit 23.2, plus 16 baru untuk 24.0 |
| Repo di-fork untuk itu | 8 (kemudian dikonversi jadi patch) |
| Flash ke perangkat | 12 |
| Titik henti berbeda yang ditemukan | 13 |
| Boot penuh | **ya, 12 September 2026** |
| Stabil + internet | **ya, terverifikasi terpisah** |
| Uptime terpanjang | **2 jam 17 menit tanpa restart** |

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

### Tetapi boot saja belum berarti stabil

Beberapa menit sesudah homescreen, perangkat me-restart sendiri. Bukan panik:
init melakukan shutdown tertib, dan alasannya tercatat jelas.

    sys.boot.reason                 = reboot,factory_reset
    crashrecovery.rescue_boot_count = 4
    sys.system_server.crash_java    = 3
    init: Reboot ending, jumping to kernel
    Restarting system with command 'recovery'

Itu **RescueParty** -- mekanisme pemulihan Android yang naik bertahap ketika
system_server crash berulang, dan tingkat terakhirnya menghapus /data.
Perangkat menghapus datanya sendiri, persis sebagaimana dirancang.

Akarnya satu lapis lebih dalam lagi, dan pesan pengecualiannya sendiri yang
menuntun ke sana:

    IllegalStateException: Lost network stack. This is not the root cause of
    any issue, it is a side effect of a crash that happened earlier.

Yang jatuh lebih dulu adalah proses networkstack:

    FATAL EXCEPTION: NetworkMonitor/100
    Process: com.android.networkstack.process
    java.lang.ExceptionInInitializerError
      at NetworkStackBpfNetMaps.getInstance(NetworkStackBpfNetMaps.java:66)
    Caused by: IllegalStateException: Cannot open configuration map
    Caused by: ErrnoException: nativeBpfFdGet failed: ENOSYS

Yang membuatnya fatal bukan pengecualiannya, melainkan **letaknya**: di dalam
inisialisasi statis `SingletonHolder`. Satu panggilan yang gagal menjatuhkan
seluruh proses, bukan sekadar panggilan itu. -> patch 0011

Pelajaran ketiga, dan yang paling mudah terlewat: **`sys.boot_completed=1`
bukan bukti ROM sehat.** Ia hanya membuktikan boot selesai. Kestabilan harus
diperiksa terpisah -- umur proses `system_server` dibanding uptime, dan
penghitung RescueParty.

Pelajaran keempat menyusul langsung sesudahnya: **tidak adanya crash juga
bukan bukti perbaikan bekerja**, kalau jalur yang diperbaiki belum pernah
dilewati. Kode yang dibuat malas hanya berjalan ketika dipicu; sampai
pemicunya terjadi, "tidak crash" dan "belum dicoba" terlihat persis sama.

Kabar baik yang ikut terlihat di boot itu: WiFi bekerja.

    DhcpClient: Confirmed lease ... DHCP server 192.168.0.1

### Terbukti stabil, dan kali ini jalurnya memang dilewati

Sesudah patch 0011, build 24.0-20260912_003359. Tiga hal diperiksa terpisah,
karena satu saja tidak cukup:

**Jalur yang dulu crash benar-benar dijalankan.** Ini yang paling mudah
terlewat. Pada pemeriksaan pertama sesudah flash, ROM terlihat stabil --
tetapi WiFi belum tersambung, `NetworkMonitor` belum pernah jalan, dan
`NetworkStackBpfNetMaps` yang dibuat malas lewat `SingletonHolder` belum
pernah diinstansiasi. Stabil karena belum disentuh, bukan karena sembuh.
Sesudah WiFi disambungkan:

    NetworkMonitor: 48 baris log
    Cannot open configuration map          1x
    Cannot open uid owner map              1x
    Cannot open data saver enabled map     1x

Ketiga peta tetap gagal dibuka -- memang tidak akan pernah bisa di kernel ini
-- tetapi getternya mencatat lalu mengembalikan peta pengganti, dan prosesnya
selamat.

**Umur proses dibanding uptime.** Ini pembeda antara hidup dan crash-loop:

    uptime = 565s
    zygote                            08:00
    system_server                     07:52
    com.android.networkstack.process  06:18   (PID tetap 6139)

Bandingkan dengan boot sebelumnya: `system_server` berumur 2 detik pada
uptime 579 detik.

**RescueParty diam.**

    crashrecovery.rescue_boot_count = 1
    sys.system_server.crash_java    = (kosong)

Jaringan berfungsi penuh:

    wlan0 192.168.0.188/24 state UP
    ping 8.8.8.8 -> 2/2, 0% loss, rtt 75 ms

Seluruh tumpukan firewall dan statistik per-uid berbasis eBPF mati permanen
di kernel ini, dan internet tetap jalan.

## 8. Dua bug yang hanya muncul sesudah ROM dipakai

Boot yang berhasil tidak menutup pekerjaan. Dua cacat baru muncul ketika ROM
mulai benar-benar dipakai, dan keduanya luput dari seluruh pemeriksaan boot.

### Browser tidak bisa dibuka -- WebViewUpdateServiceImpl2

    FATAL EXCEPTION: main
    Process: org.lineageos.jelly
    Caused by: MissingWebViewPackageException: Failed to load WebView
      provider: No WebView installed

Paketnya sehat sepanjang waktu: terpasang di
/system/product/app/webview/webview.apk, ABI armeabi-v7a yang benar, dan
dumpsys menyebutnya "Valid package ... installed/enabled for all users".
Yang salah adalah pemilihannya. Konstruktor Impl2 mengambil penyedia
availableByDefault PERTAMA lalu berhenti, tanpa memeriksa apakah paketnya
ada:

    for (WebViewProviderInfo provider : webviewProviders) {
        if (provider.availableByDefault) { defaultProvider = provider; break; }
    }

Daftar penyedia LineageOS menempatkan com.google.android.webview di urutan
pertama dan com.android.webview di urutan terakhir. Tanpa GApps yang
terpilih adalah paket yang tidak pernah ada, dan implementasi ini -- berbeda
dengan yang lama -- tidak punya jalan mundur:

    W WebViewUpdateServiceImpl2: Default WebView package
      (com.google.android.webview) not found
    E WebViewUpdateServiceImpl2: Could not find a loadable WebView package

Perbaikannya memilih penyedia bawaan pertama yang BENAR-BENAR TERPASANG,
sehingga urutan prioritas tetap dihormati bila GApps ada. -> patch
frameworks_base/0009

### Low memory killer lumpuh total -- lmkd

Yang ini tidak pernah menjatuhkan apa pun, dan justru itu yang berbahaya.
Satu-satunya tandanya adalah banjir baris log, 157 kali dalam satu boot:

    E lowmemorykiller: pidfd_open for pid N failed; errno=38

pidfd_open baru ada sejak kernel 5.3. Di kernel 3.10 ia selalu ENOSYS, dan
cmd_procprio keluar lebih awal -- sehingga TIDAK ADA satu pun proses yang
pernah terdaftar ke lmkd. Daftar prosesnya kosong, low memory killer tidak
punya apa pun untuk dibunuh, dan OOM killer kernel yang mengambil alih
dengan pilihan korban jauh lebih buruk, termasuk system_server. Pada
perangkat RAM 1 GB ini akibatnya parah.

Sisa lmkd ternyata sudah siap menghadapi pidfd < 0 di seluruh jalur lain,
jadi yang diperlukan hanya berhenti menolak pendaftaran, ditambah kill(2)
biasa di reaper ketika pembunuhan lewat cgroup tidak dapat dipakai.
-> patch system_memory_lmkd/0002

### Terbukti sesudah flash

    webview_provider (setelan tersimpan) = null
    Current WebView package = (com.android.webview, 152.0.7977.64)
    relros started/finished = 1/1

Setelan tersimpan kosong, jadi WebView terpilih otomatis -- bukan warisan
perbaikan manual.

    pidfd_open errno=38 : 157 -> 0
    lmkd fd terbuka     : 67
    /sys/fs/cgroup/system/uid_1000/pid_3121/cgroup.procs
    /sys/fs/cgroup/apps/uid_10148/pid_5955/cgroup.procs

lmkd kini memegang cgroup.procs untuk layanan sistem dan aplikasi -- persis
deskriptor yang dipakainya membunuh process group. Jalur itu berada di
hierarki v1 bernama yang dipasang patch system_core/0003, jadi kedua
perbaikan saling menyambung.

    uptime 2 jam 17 menit, zygote dan system_server tidak pernah restart

### Pelajaran kelima

**Berhenti mengeluh bukan berarti berfungsi.** Menghilangkan 157 baris error
itu mudah; yang membuktikan lmkd benar-benar hidup adalah daftar deskriptor
cgroup.procs yang dipegangnya. Setiap perbaikan perlu bukti positif bahwa
fungsinya berjalan, bukan sekadar bukti negatif bahwa errornya hilang.

### Sapuan bug tersembunyi

Sebelum membangun, seluruh subsistem disapu lewat adb. Yang sehat: sensor
(4 h/w aktif), kamera (2 perangkat), audio (msm8x16sndcardm), telepon (SIM
LOADED, IN_SERVICE), WiFi, getar (AMPLITUDE_CONTROL, dua getaran tercatat
selesai), layar 720x1280@60, baterai. Nol tombstone, nol ANR, nol layanan
restarting; tiga system_app_crash yang tersimpan semuanya browser.

Sengaja tidak ditambal karena kosmetik: resonantFrequencyHz=NaN (motor ERM
memang tidak melaporkan profil frekuensi) dan "Failed to find HDMI node"
(A37 memang tidak punya HDMI).

## 9. GPU page fault yang mematikan perangkat

Sesudah ~35 menit pemakaian, perangkat reboot mendadak. Bukan RescueParty,
bukan factory reset, bukan panik kernel:

    kgsl kgsl-3d0: GPU PAGE FAULT: addr = BF049400 pid = 5944
      [BF047000 - BF048000] (+guard) (pid = 5944) (egl_surface)
       <- fault @ BF049400
      [BF04A000 - BF06E000] (+guard) (pid = 5944) (egl_surface)
    (terulang 4 detik kemudian, alamat dan pid sama persis)
    Watchdog bark! Now = 2107.882536
    Watchdog last pet at 2087.490352
    cpu alive mask from last pet 0-3
    Causing a watchdog bite!

`cpu alive mask 0-3` menegaskan keempat inti masih hidup -- bukan deadlock
CPU, melainkan jalur GPU yang tersangkut. uid 10118 adalah
com.android.systemui, proses yang selalu berjalan.

### Mekanismenya: jalur pemulihan yang tidak pernah dipanggil

Bawaan kernel hanya KGSL_FT_PAGEFAULT_INT_ENABLE (0x1, adreno.h:649), dan
SELURUH pemulihan dibungkus pemeriksaan bit yang mati itu
(kgsl_iommu.c:374):

    iommu_dev->fault = 1;
    if (adreno_dev->ft_pf_policy & KGSL_FT_PAGEFAULT_GPUHALT_ENABLE) {
        adreno_set_gpu_fault(adreno_dev, ADRENO_IOMMU_PAGE_FAULT);
        kgsl_pwrctrl_change_state(device, KGSL_STATE_AWARE);
        adreno_dispatcher_schedule(device);
    }

Tanpa bit itu driver mencatat lalu diam. IOMMU menahan transaksi, GPU
menggantung, tumpukan grafis terblokir, watchdog perangkat keras tidak
terpet 20 detik, dan SoC me-reset paksa. Diperbaiki dengan menulis 0x3 ke
ft_pagefault_policy di init.target.rc.

### Akar penyebabnya BELUM ditemukan, dan hipotesis utama gugur

Aritmetikanya sempat sangat meyakinkan. Alokasi kedua berukuran 147456 byte
-- persis ukuran bilah status pada layar 720 dengan stride 736 -- dan fault
terjadi 3072 byte sebelum awalnya, yaitu tepat satu baris (736 x 4 = 2944).
Membaca satu baris sebelum awal buffer adalah tanda khas ketidakcocokan
stride, dan kita memang memaksa LEGACY_GRALLOC.

Tetapi ada mekanisme yang memeriksanya, dan ia aktif. Gralloc2Mapper::
validateBufferSize melewatkan validasi hanya bila mapper 2.1 tidak ada:

    if (mMapperV2_1 == nullptr) return NO_ERROR;

Perangkat ini punya android.hardware.graphics.mapper@2.1::IMapper,
terdaftar dan dipakai tujuh proses. Validasi ukuran berjalan pada setiap
alokasi, dan NOL kegagalan di seluruh log termasuk arsip. libui dan gralloc
sepakat soal ukuran buffer.

Hipotesisnya gugur. Penyimpangan alamat terjadi di dalam blob Adreno, bukan
di antarmuka gralloc.

### Yang dikerjakan ketika sebab tidak bisa dikejar

Perbaikan yang sama ternyata melakukan lebih dari sekadar memulihkan GPU.
dispatcher_do_fault memanggil kgsl_device_snapshot(device,
cmdbatch->context) (adreno_dispatch.c:1745), sehingga fault berikutnya
meninggalkan status register, konteks yang bersalah, dan command batch yang
sedang berjalan di /sys/class/kgsl/kgsl-3d0/snapshot/.

Pola yang sama dengan bootwatchdog dan tombstoned: ketika penyebab tidak
dapat dikejar langsung, yang dikerjakan adalah membuatnya terekam.
Sebelumnya tiap kemunculan hanya menyisakan lima baris log lalu perangkat
mati.

### Pelajaran keenam

**Aritmetika yang cocok bukan bukti.** 3072 byte yang tepat sama dengan satu
baris stride terasa seperti temuan, dan hampir saya laporkan sebagai sebab.
Yang menyelamatkan adalah bertanya "apakah ada yang seharusnya menangkap ini
kalau benar" -- lalu menemukan validateBufferSize, memastikan ia aktif, dan
mendapati ia tidak pernah gagal. Hipotesis yang cocok dengan angka tetap
harus diuji terhadap mekanisme yang akan membantahnya.

### Enam pelajaran yang paling mahal

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

## 10. Utang yang harus dibayar sebelum rilis

Semuanya diagnostik, sengaja dipasang, dan harus dicabut:

- `WITH_ADB_INSECURE` di `lineage_A37.mk` -- dikomentari, bukan `:= false`
  (`ifdef` bernilai benar untuk nilai apa pun yang tidak kosong)
- `bootwatchdog.sh`: `JEDA=1`, cuplikan tiap iterasi, aliran `/dev/kmsg`
- `ro.adb.secure=0` dan `ro.debuggable=1`
