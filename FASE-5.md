# Fase 5 — build ROM penuh

9 September 2026. **BERJALAN** — belum ada zip flashable.

Fase ini bukan soal menulis kode baru. Pohonnya sudah lengkap setelah Fase 0–4;
yang tersisa adalah menjalankan `m bacon` sampai tuntas dan menambal apa pun
yang menghadang. Yang menghadang ternyata dua hal berbeda: **celah hulu**
LineageOS 24.0 dan **batas mesin** 11,7 GB.

## Skor sementara

| | |
|---|---|
| Percobaan build | 18 |
| Celah hulu ditemukan di fase ini | 3 (nomor 6, 7, 8) |
| Repo fork bertambah | 1 (`lineage-sdk`) |
| Zip flashable | **belum** |

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

## 7. Belum terbukti

Boot perangkat; Bluetooth tanpa `libbt-vendor`; kedip LED sesudah migrasi AIDL;
memtrack AIDL; SkiaGL vs fork GLES ULH; jaringan hidup tanpa BPF.
