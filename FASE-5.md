# Fase 5 — build ROM penuh

9 September 2026. **SELESAI** — `rc=0`, zip flashable terbentuk.

```
lineage-24.0-20260910_004703-UNOFFICIAL-A37.zip
849,8 MB   md5 50e6d938d9b26374bd0a3bda4f353b87
```

Zip pertama (`20260909_170246`) lolos build tetapi DITOLAK TWRP di assert
perangkat; lihat §6e. Zip di atas hasil perbaikan itu, dan assert-nya sudah
diverifikasi memuat `A37f` pada `ro.product.device` maupun `ro.build.product`.

ROM ini **belum pernah boot**. Yang terbukti sampai di sini adalah pipeline
build dan bahwa paketnya lolos assert TWRP, bukan bahwa perangkatnya menyala.

Fase ini bukan soal menulis kode baru. Pohonnya sudah lengkap setelah Fase 0–4;
yang tersisa adalah menjalankan `m bacon` sampai tuntas dan menambal apa pun
yang menghadang. Yang menghadang ternyata dua hal berbeda: **celah hulu**
LineageOS 24.0 dan **batas mesin** 11,7 GB.

## Skor sementara

| | |
|---|---|
| Percobaan build | 28 |
| Celah hulu ditemukan di fase ini | 7 (nomor 6-12) |
| Repo fork bertambah | 3 (`lineage-sdk`, `hardware_lineage_interfaces`, `packages_modules_adb`) |
| Zip flashable | **849,8 MB**, `rc=0` |
| Verifikasi artefak | `ro.adb.secure=0`, `ro.debuggable=1`, `dt_size=210944` |

---

## 1. Celah hulu #6 — empat API hilang dari `frameworks/base`

`LineageParts` gagal dengan 9 galat yang berpangkal pada empat simbol yang ada
di lineage-23.2 dan nol di lineage-24.0:

| berkas | simbol |
|---|---|
| `atv/KeyHandler.java:15,21` | `com.android.internal.os.DeviceKeyHandler` |
| `gestures/KeyHandler.java:42,48` | idem |
| `hardware/DisplayRotation.java:66,122` | `Settings.System.ACCELEROMETER_ROTATION_ANGLES` |
| `input/ButtonSettings.java:389,623` | `Settings.System.VOLUME_KEY_CURSOR_CONTROL` |
| `input/BacklightTimeoutSeekBar.java:47` | `AbsSeekBar.updateTouchProgress` |

Bahwa ini celah hulu dan bukan pohon usang dibuktikan `lineage-sdk` 24.0 yang
masih menyimpan `LineageButtons.java` dan `config_deviceKeyHandlerClasses` —
sisi konsumennya utuh, hanya sisi `frameworks/base` yang tertinggal saat rebase
ke Android 17.

Dipulihkan dari 23.2 (`35ad1f68`) di `frameworks/base` `8939b15f`:

1. `DeviceKeyHandler.java`, identik byte-per-byte.
2. `AbsSeekBar.updateTouchProgress` — kaitan lengkap, situs panggil di
   `trackTouchEvent` plus metode `protected`-nya.
3. Dua konstanta `Settings.System` berikut validator `NON_NEGATIVE_INTEGER`
   untuk yang pertama (23.2 pun hanya memvalidasi yang pertama).
4. Penegakan sudut rotasi: `RotationPolicy.isRotationAllowed()` dikembalikan dan
   `DisplayRotation` memakainya lagi — medan, observer, pembacaan setelan, dan
   situs keputusan rotasi.

**Perilaku bawaan tidak berubah.** Bila pengguna belum menyetel mask,
`isRotationAllowed` memakai `(1|2|8)` saat `config_allowAllRotations` salah dan
`(1|2|4|8)` saat benar — persis padanan syarat lama
`sensorRotation != ROTATION_180 || getAllowAllRotations() == ENABLED`.
`getAllowAllRotations()` menyelesaikan `UNDEFINED` secara malas, sehingga
`!= DISABLED` yang dipakai 23.2 setara dengan `== ENABLED` yang dipakai 24.0.

Sengaja **tidak** dipulihkan: pengiriman tombol ke `DeviceKeyHandler` di
`PhoneWindowManager` dan konsumen `VOLUME_KEY_CURSOR_CONTROL`. Antarmukanya
terkompilasi dan setelannya tersimpan, tetapi belum ada yang membacanya. Itu
port tersendiri ke PWM Android 17 dan tidak diperlukan untuk boot.

## 2. Celah #7 — bukan salah LineageOS

`LineageDatabaseHelper` merujuk dua konstanta yang lenyap dari
`android.provider.Settings` di 24.0. Godaannya menambahkannya kembali ke
`Settings.java`; itu **salah arah**. AOSP 17 sendiri yang memindahkannya:

| konstanta | rumah barunya |
|---|---|
| `UIDS_ALLOWED_ON_RESTRICTED_NETWORKS` | `android.net.ConnectivitySettingsManager` (`@SystemApi MODULE_LIBRARIES`, tak terjangkau aplikasi sistem biasa) |
| `TETHERING_ALLOW_VPN_UPSTREAMS` | konstanta privat di `Tethering.java:193` |

Nilainya kini milik modul, bukan kerangka kerja. Yang benar adalah memakai nama
kuncinya langsung — persis yang AOSP lakukan di `Tethering.java`, dan persis
idiom yang sudah dipakai berkas yang sama untuk
`"sfps_require_screen_on_to_auth_enabled"`. Nama kunci tidak berubah sehingga
jalur upgrade basis data tetap membaca baris yang sama.

`lineage-sdk` menjadi fork ke-27.

## 3. Celah #8 — satu tambalan, dua repo, satu paruh hilang

Empat target `build.prop` gagal:

```
FAILED: .../build/soong/system-build.prop/android_common/build.prop
gen_build_prop.py, line 452, in append_additional_vendor_props
KeyError: 'RecoveryDefaultTouchRotation'
```

Konsumennya ada, produsennya tidak:

| | 23.2 | 24.0 |
|---|---|---|
| `build/soong/scripts/gen_build_prop.py` | baris 441–442 | baris 452–453 (**sama**) |
| `build/make/core/soong_extra_config.mk` | baris 51 | **hilang** |

Ini pola yang berbeda dari celah-celah sebelumnya: kedua paruh satu tambalan
LineageOS tinggal di **repo berbeda**, dan hanya satu yang ikut ke 24.0.
Diperbaiki di `build/make` `7d28b450`.

### Sapuan seluruh kelas

Agar tidak membayar satu siklus build per kunci, seluruh kelas disapu sekaligus:

| | |
|---|---|
| Kunci dibaca `gen_build_prop.py` | 104 |
| Absen dari `product_config.json` | 6 |
| Dijaga `if "X" in config:` | 5 (aman) |
| **Dibaca dengan subscript telanjang** | **1** — yang ini |

`gen_build_prop.py` satu-satunya skrip yang membaca `product_config.json`, jadi
kelas ini tuntas.

## 4. Batas mesin — dan dua kesalahan diagnosis

Ini bagian yang paling mahal, dan sebagian besar biayanya kesalahan sendiri.

### Yang terjadi

Analisis soong dingin untuk A37 di mesin 11,7 GB perlu **±80 menit** sebelum
menulis byte pertama. Selama itu soong **diam total** — tidak ada keluaran,
tidak ada berkas baru.

Saya menyimpulkan itu spiral maut `GOMEMLIMIT` dan memasang penjaga otomatis.
**Penjaga itu membunuh dua build yang sehat**:

| versi | diskriminator | mati di | kenapa salah |
|---|---|---|---|
| v1 | major fault tinggi + nol tulisan | menit ke-2 | soong sedang membaca masukan dengan page cache dingin — polanya identik |
| v2 | jalan >35 menit + nol tulisan 10 menit | menit ke-35 | berkas `.ninja` memang baru ditulis di akhir |

Keduanya proksi yang juga menggambarkan analisis sehat. Percobaan 14 (dibunuh
menit ke-45) dan 16 (menit ke-35) kemungkinan besar hanya kurang waktu.

### Yang sebenarnya, dari `gctrace`

Instrumen yang benar ada di runtime Go, bukan di heuristik. `SOONG_GODEBUG`
diteruskan lewat jalur yang sama dengan `GOMEMLIMIT` (`build/soong` `fe2337bf`),
karena `env -i` memutus keduanya. Hasilnya:

```
gc 105 @5291.789s 33%: ... 18348->20183->18309 MB, 18348 MB goal, 12 P
```

**Live heap 18,3 GB.** Itu di atas 5GiB *maupun* 14GiB, sehingga pada kedua
nilai Go menurunkan goal-nya sampai menyamai live heap dan menjalankan GC
sesering mungkin. Mekanismenya memang spiral — tetapi kesimpulan praktisnya
keliru: fraksi CPU di GC berhenti di **33%**, bukan 90%. Analisisnya
**terdegradasi, bukan buntu**, dan tetap selesai. Menaikkan 5→14 GiB tidak
mengubah apa pun justru karena keduanya sama-sama di bawah 18,3 GB.

Angka yang benar harus **di atas** live heap: `SOONG_GOMEMLIMIT=24GiB` memberi
±5,7 GB ruang sampah sebelum GC dipicu, dan masih di bawah RAM+swap (11,7+32 GB).

### Pelajaran

> Diam bukan kegagalan. Sebelum membunuh proses yang lama, cari instrumen yang
> mengukur langsung — bukan proksi yang kebetulan cocok.

Komentar di `build/soong/ui/build/soong.go` (`44d6f097`) menyatakan spiral itu
sebagai fakta lengkap dengan angka. **Itu harus ditulis ulang** dengan temuan
`gctrace` di atas; ditunda sampai ROM jadi karena menyentuh `build/soong`
membatalkan analisis dan memaksa 80 menit lagi.

## 5. Yang juga menghabiskan waktu

`git log -S` sisa investigasi sesi sebelumnya masih berjalan di latar. Pada
partial clone `blob:none`, pickaxe menarik **setiap blob** dari setiap commit —
13 GB disk dan sebagian besar RAM. Gejalanya terbaca seperti build yang rakus.

> `git log -S` dan `git grep` tidak boleh dipakai di pohon partial clone.

## 6. Setelan build yang terbukti

```bash
export SOONG_GOMEMLIMIT=24GiB     # di atas live heap 18,3 GB terukur
export SOONG_GODEBUG=gctrace=1    # satu-satunya pembeda spiral yang tak ambigu
m -j4 bacon                       # -j4, bukan -j6: tiap R8 -JXmx4096M
```

`-j4` berasal dari catatan 23.2 (RILIS.md §5). Bila OOM tetap terjadi gejalanya
menyesatkan — belasan `FAILED:` pada target Java yang tampak seperti galat
kompilasi; pembedanya satu baris: `error: action cancelled when ninja exited`.

Penjaga disk tetap dipakai (ambang 6 GB) karena disk penuh **tidak**
menghentikan build, melainkan meninggalkan berkas terpotong yang lolos sebagai
"sudah dibangun". Penjaga spiral **tidak** dipakai — dua versinya sudah terbukti
membunuh build yang sehat, dan tidak ada penjaga lebih baik daripada penjaga
yang salah.

## 6b. Celah hulu 9, 10, 11 — jalur yang hanya dilewati perangkat lawas

Tiga celah terakhir punya benang merah: semuanya di kode yang perangkat modern
tidak pernah sentuh, sehingga bisa rusak lama tanpa ketahuan.

### #9 — generator OTA mengandaikan dynamic partitions

```
ota_from_target_files.py:584 ModifyTargetFilesDynamicPartitionInfo
FileNotFoundError: META/dynamic_partitions_info.txt
```

Baris 1332-1334 menyalakan `disable_ublk` otomatis untuk perangkat yang tidak
mendukung ublk, lalu baris 1452 menulis flag itu ke berkas info dynamic
partition tanpa penjaga. Kedua sisi saling meniadakan: `supports_ublk` membaca
`ro.virtual_ab.ublk.enabled`, properti Virtual A/B, dan Virtual A/B mensyaratkan
dynamic partitions. Jadi perangkat yang berkasnya tidak pernah dihasilkan justru
yang dijamin masuk cabang itu. Makin lawas, makin pasti gagal.
Diperbaiki di `build/make` `5badd464`.

### #10 — `non_ab_ota.py` lupa `zip -y`

Gejalanya menyamar sebagai disk penuh: `exit code 14`, `Output file write
failure` — padahal disk 20 GB lega. Pembedanya `zip I/O error: Bad address`
(EFAULT) dan nama berkasnya: `RECOVERY/RAMDISK/d/kvm/*`.

`RECOVERY/RAMDISK/d` adalah symlink absolut ke `/sys/kernel/debug`. Di perangkat
itu benar. Tetapi saat host mengemas, `zip -r .` mengikutinya dan mengarsipkan
debugfs milik HOST yang sedang hidup — ribuan berkas semu yang ukurannya berubah
sambil dibaca.

Basis kode ini sudah tahu jawabannya, hanya tidak di berkas itu:

| pemanggil | perintah |
|---|---|
| `sign_target_files_apks.py:1797` | `zip ... -y -r .` |
| `sign_target_files_apks.py:1799` | `zip ... -y -0 -r .` |
| `non_ab_ota.py:569` | `zip ... -r . -0` |

Bertahan tanpa ketahuan karena namanya `non_ab_ota.py` — hanya perangkat non-A/B
yang menyentuhnya — dan hanya menggigit bila build berjalan sebagai root di host
yang punya debugfs ter-mount. Diperbaiki di `build/make` `00fd8b81`.

### #11 — FCM level 5 dicabut, dan HAL HIDL menyusul

`compatibility_matrix.202604.xml` hanya mengenal varian AIDL:
`bluetooth.audio` 3-6 dan `health` 3-5. Deklarasi HIDL keduanya pasti ditolak.
Untuk bluetooth audio, deklarasi manual di `manifest.xml` perangkat justru YANG
MEMICU penolakan, karena paket AIDL membawa `vintf_fragment` sendiri.
Diperbaiki di device tree `65b86520`.

Lalu `target-level="5"` sendiri gugur: Android 17 hanya mengirim matrix untuk
level 7 ke atas. Komentar di manifest itu memperingatkan dirinya sendiri —
level 5 dipilih justru karena `compatibility_matrix.5.xml` nol menyebut
`android.hardware.radio`, sehingga `IRadio 1.5-6` tidak mengikat perangkat yang
hanya punya `@1.4::IRadio`.

**Diuji sebelum diterapkan, bukan sesudah.** `checkvintf` sudah ada sebagai
biner di `out/host`, dan pohon hasil build masih utuh, jadi manifest TERBANGUN
disunting sementara ke level 7 dan `checkvintf` dijalankan langsung dengan
dirmap serta properti yang sama persis: **COMPATIBLE, rc=0**. Kekhawatirannya
tidak terwujud karena aturan pewarisan HIDL `HalManifest.cpp:384-390`.
Diperbaiki di device tree `1a68b033`.

> Alat tahap pengemasan sudah terbangun di `out/host`. Hipotesis tentangnya bisa
> diuji dalam detik, bukan dengan siklus build 90 menit.

## 6e. Celah hulu #12 — ditemukan oleh perangkat, bukan oleh build

Build percobaan 28 lolos `rc=0` dan menghasilkan zip bertanda tangan. Zip itu
tetap gagal di TWRP:

```
script aborted: E3004: This package is for "A37" devices; this is a "A37f".
Updater process ended with ERROR: 1
```

Tidak ada kerusakan: assert berjalan sebelum partisi mana pun disentuh, dan
`recovery.log` memastikannya lewat "Install took 0 second(s)".

Bukan salah setelan. Device tree SUDAH menyetel:

```make
TARGET_OTA_ASSERT_DEVICE := A37,a37,a37f,A37f,A37fw,a37fw,A37m,a37m,msm8916,msm8939
```

tetapi variabel itu nol dibaca di seluruh `build/make` 24.0. Dukungan
multi-perangkat adalah tambalan LineageOS bertiga bagian, dan ketiganya hilang:

| bagian | fungsi | rujukan 23.2 |
|---|---|---|
| `core/Makefile` | pancarkan `ota_override_device` ke misc_info | baris 6239 |
| `common.py` | baca kunci itu, jatuh ke `ro.product.device` | baris 448 |
| `edify_generator.py` | pecah daftar koma, periksa juga `ro.build.product` | baris 138-146 |

Diperbaiki di `build/make` `31103b33`, dan `AssertDevice` diuji langsung di
Python sebelum build ulang alih-alih sesudahnya.

> **Pelajaran yang lebih besar dari tambalannya.** `rc=0` hanya membuktikan
> pipeline build, bukan bahwa zip-nya bisa dipasang. Kelas kegagalan ini hanya
> muncul di perangkat, dan hanya menggigit perangkat yang kode variannya berbeda
> dari nama device tree-nya. Verifikasi artefak sesudah build (properti, dt_size,
> struktur zip) TIDAK menangkapnya; yang menangkapnya adalah membaca
> updater-script yang dihasilkan dan membandingkannya dengan `ro.product.device`
> perangkat sungguhan.

## 6f. Penjaga disk membuktikan dirinya

Percobaan 29 dihentikan penjaga di sisa 5 GB saat pengemasan OTA. Tandanya
`error: action cancelled when ninja exited` -- pembeda yang dicatat RILIS.md 23.2
antara build yang DIBUNUH dan galat kompilasi sungguhan.

Yang tertinggal: zip 86,6 MB, dari yang seharusnya 849,8 MB. Tanpa penjaga,
berkas terpotong itu akan lolos sebagai "sudah dibangun" dan baru ketahuan saat
flash.

Ruang dibebaskan dengan urutan yang benar, dan urutan itu penting: pertama sisa
kerja (`out/soong/.temp`, 8,4 GB), lalu **object store** `.repo`
(`platform/external` + `cts.git`, 9,8 GB). Object store tidak pernah dibaca
proses build -- hanya `repo sync` -- sehingga menghapusnya aman dan pulih lewat
sync ulang. Itu justru kebalikan dari kesalahan clang di §6c, di mana yang
terhapus adalah worktree yang memang dipakai kompilasi dan analisis.

## 6c. Kesalahan sendiri yang berbiaya

Selain dua penjaga di §4 yang membunuh build sehat:

**Menghapus versi clang saat disk kritis.** Alasannya "kompilasi sudah selesai,
tinggal pengemasan" — keliru. Bindgen memakai `clang-r584948` lewat
`ClangDefaultVersion` di `global.go` (baris yang sudah dibaca berjam-jam
sebelumnya dan tidak dihubungkan), dan soong men-`stat` tiga versi lain saat
analisis karena `prebuilts/clang/host/linux-x86/Android.bp:661` mendeklarasikan
`dirgroup` yang mencantumkannya. Benar soal *target*, salah soal *analisis*.
Ongkosnya satu siklus.

Pemangkasan yang benar dilakukan belakangan: yang dihapus **object store**
`.repo` (8,4 GB, hanya dibutuhkan `repo sync`), bukan worktree yang dipakai
kompilasi dan analisis.

**Regresi javadoc yang lolos tinjauan.** Commit Fase 4 menyisipkan
`pauseDownload`/`resumeDownload` di antara javadoc `restartDownload` dan
metodenya, sehingga `@hide` milik hulu jadi blok yatim dan metode itu telanjang.
Metalava lalu memperlakukannya sebagai API publik baru. Yang membuatnya lolos:
diff-nya **nol penghapusan** — teks javadoc tidak hilang, hanya berpindah
pemilik. Diperbaiki di `886171e9`.

**`--` di dalam komentar XML, dua kali lagi** (total lima kali di proyek ini),
meski sanitasi otomatis sudah dibuat sendiri dan tidak dipakai. Tertangkap
validator sebelum commit. Sejak itu pemeriksaannya dijalankan SEBELUM menulis.

**`groups=` salah lagi saat menambah fork** — tertangkap `verify/cek-manifest.sh`,
skrip yang memang dibuat untuk kelas kesalahan ini. Skripnya bekerja.

## 6d. Hal yang tidak boleh dilakukan di pohon ini

`git log -S` dan `git grep` pada partial clone `blob:none` menarik **setiap
blob** dari setiap commit. Satu proses `git log -S` yang tertinggal dari sesi
sebelumnya memakan 13 GB disk dan sebagian besar RAM selama 12 menit pertama
sebuah build, dan gejalanya terbaca persis seperti build yang rakus.

## 7. Belum terbukti

**Boot perangkat.** ROM ini belum pernah di-flash. Yang terbukti di fase ini
adalah pipeline build, bukan perangkatnya.

Juga belum terbukti: Bluetooth tanpa `libbt-vendor`; kedip LED sesudah migrasi
AIDL lights; health dan bluetooth.audio sesudah pindah ke AIDL; SkiaGL vs fork
GLES ULH; jaringan hidup tanpa BPF.

Terbukti secara kompilasi (bukan runtime): memtrack AIDL, dan jalur FunctionFS
legacy adb.

## 8. Fase 6 — 28 patch kompatibilitas yang masih absen

Seluruh 63 patch kit 23.2 diuji terhadap pohon 24.0 dengan `git apply --check
--reverse`. Hasilnya perlu dibaca hati-hati: **"tidak bisa di-reverse" biasanya
berarti sudah diterapkan dalam bentuk port-tangan**, bukan belum ada. Contoh
telak, `build_make/0701-releasetools-zip-y` terbaca "belum" padahal perbaikan
yang sama diturunkan ulang secara mandiri di fase ini sebagai `00fd8b81`, tanpa
tahu kit lama sudah memuatnya.

Yang benar-benar absen adalah **28 patch yang menempel MULUS** — artinya kodenya
belum tersentuh sama sekali:

| kelas | repo | jml |
|---|---|---|
| kritis-boot | `bionic` | 5 |
| kritis-boot | `system_core` | 5 |
| kritis-boot | `frameworks_base` | 4 |
| kritis-boot | `system_memory_lmkd` | 2 |
| kritis-boot | `frameworks_native` | 2 |
| kritis-boot | `system_apex` | 1 |
| kritis-boot | `system_sepolicy` | 1 |
| stabilitas runtime | telephony, wifi, BT, NetworkStack, wlan, Connectivity | 8 |

Diverifikasi sampel: `system/apex/apexd/apexd_loop.cpp:612` masih memakai
`O_DIRECT` tanpa syarat, sedangkan loop device kernel 3.10 tidak mendukungnya.

Kelas "stabilitas runtime" berasal dari **debug perangkat nyata** di 23.2, bukan
tebakan; ia tidak memblokir boot tetapi menentukan sinyal, wifi dan Bluetooth.

Urutan yang dipilih: build lebih dulu sampai `rc=0`, baru 28 patch diterapkan.
Alasannya bukan kehati-hatian berlebih — semuanya menempel mulus sehingga murah
— melainkan supaya kalau ada yang rusak sesudahnya, penyebabnya tidak ambigu
antara "pipeline belum pernah jalan" dan "patch ini yang salah". Baseline itu
sekarang ada.
