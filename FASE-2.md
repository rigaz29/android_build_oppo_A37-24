# Fase 2 — kernel

7-8 September 2026. **SELESAI.**

Fase paling berisiko dari seluruh port ini, dan sengaja dikerjakan sendirian:
di 23.2 milestone kernel dicapai gratis (3.10.108 apa adanya kompilasi bersih),
di 24.0 justru di sinilah blocker terbesarnya.

## Syarat lulus

| | hasil |
|---|---|
| A. kernel 3.10.108 terbangun dengan GCC 4.9 dari pohon 24.0 | **LULUS** |
| B. `m bootimage` menghasilkan `KERNEL_OBJ/arch/arm64/boot/Image` | **LULUS** |

```
boot.img    20.369.408 byte
dt.img         210.944 byte
kernel      18.578.872 byte
Image       18.578.872 byte
```

### Struktur boot image diverifikasi, bukan disimpulkan dari build hijau

```
magic        ANDROID!
page_size    2048
offset 40    210944      = ukuran dt.img persis        COCOK
offset dt    20158464 -> b'QCDT'                       COCOK
```

`dt_size` **210.944** adalah persis angka yang dicatat `BoardConfig.mk` sebagai
`dt_size` partisi recovery TWRP yang terbukti boot di perangkat ini. Bukan
"mestinya benar" — dicocokkan dengan referensi dari perangkat.

### Kernel: dua jalur, keluaran identik

`Image` byte-identik antara build mandiri (Fase 2A, tanpa soong) dan build dari
dalam pohon (Fase 2B, lewat `KERNEL_CC`). Dua toolchain path berbeda, byte yang
sama — konfirmasi terkuat bahwa override `KERNEL_CC` benar-benar dipakai dan
bukan diam-diam jatuh ke clang.

---

## Empat belas percobaan build

| # | Berhenti di | Sebab | Kelas |
|---|---|---|---|
| 1 | soong bootstrap | plugin Go ULH sepolicy vs API blueprint 24.0 | fork ULH |
| 2 | analisis soong | `fs_mgr` ganda — struktur repo 24.0 | fork ULH |
| 3 | analisis soong | `display_intf_headers`, lights HIDL | A37 |
| 4 | analisis soong | power QTI, lights | A37 |
| 5 | analisis soong | `missing variant` | **bug hulu** |
| 6 | analisis soong | OOM, `GOMEMLIMIT` tak sampai | **bug hulu** |
| 7 | kati | 5 modul tidak ada | campuran |
| 8 | kati | 2 modul hulu tersisa | **celah hulu** |
| 9 | kompilasi | ccache rusak | lingkungan |
| 10 | kernel `.config` | `HOSTCC=gcc` tidak ada di PATH | A37 |
| 11 | kernel `modpost` | header glibc baru lawan pustaka 2.17 | A37 |
| 12 | `boot.img` | mkbootimg tanpa `--dt` | **hulu mencabut** |
| 13 | `boot.img` | `dt.img` tak pernah dibuat | **hulu tak berdependensi** |
| 14 | — | **berhasil** | |

Enam dari tiga belas kegagalan adalah **bug atau celah hulu**, bukan salah
konfigurasi A37. Itu ukuran sebenarnya dari "LineageOS 24.0 membuang dukungan
GCC": pencabutannya meninggalkan beberapa lubang terpisah, dan masing-masing
baru terlihat setelah yang sebelumnya ditutup.

---

## Tiga belas repo di-fork

| Repo | Isi perubahan |
|---|---|
| `build/soong` | fsgen non-Treble; `SOONG_GOMEMLIMIT` diteruskan |
| `build/make` | `boot.img` bergantung pada `dt.img` |
| `vendor/lineage` | allowlist 2 modul yang hulunya belum sediakan |
| `system/tools/mkbootimg` | kembalikan `--dt` |
| `frameworks/native` | 9 commit ULH (GLES RenderEngine dll) |
| `system/core` | 3 commit ULH (cgroup v1) |
| `frameworks/av` | 2 commit ULH (OMX software codec) |
| `hardware/qcom-caf/common` | 2 commit ULH (platform pre-UM msm8916) |
| `bionic`, `Connectivity`, `libhidl`, `libhwbinder`, `hardware/ril` | 1 commit ULH masing-masing |

Ditambah tiga repo perangkat sendiri (device, kernel, vendor) dan tiga fork HAL
QCOM msm8916 — total **19 project** di local manifest.

---

## Empat perbaikan toolchain kernel, dan urutan penemuannya

Semuanya akibat satu sebab: **LineageOS 24.0 membuang seluruh jalur GCC**
(`BoardConfigKernel.mk` turun dari 36 rujukan menjadi nol). Tapi lubangnya
terpisah-pisah:

**1. `KERNEL_CC` dan `KERNEL_CROSS_COMPILE`** — knob yang memang disediakan
`kernel.mk:53` dengan gerbang `ifeq ($(KERNEL_CC),)`, jadi nilai device tree
menang. `KERNEL_CROSS_COMPILE` bahkan tidak pernah di-assign di 24.0.

**2. Path harus absolut.** `$(abspath $(TOPDIR))` menghasilkan path **relatif**
karena `TOPDIR` kosong saat `BoardConfig.mk` dievaluasi. Fatal secara senyap:
`kernel.mk:283` menjalankan make dengan `-C $(KERNEL_SRC)`, jadi path relatif
resolve dari direktori kernel. Diganti `$(abspath .)`.

**3. `HOSTCC=clang` wajib eksplisit.** `kernel/oppo/msm8939/Makefile:243`
menetapkan `HOSTCC = gcc` mati, dan kernel 3.10 tidak mengenal `LLVM=1` (nol
kecocokan `ifneq ($(LLVM),)`) sehingga tidak pernah beralih sendiri. PATH ninja
hanya memuat prebuilts:

```
/bin/sh: 1: gcc: not found
make[2]: *** [scripts/Makefile.host:118: scripts/basic/fixdep] Error 127
```

Build mandiri Fase 2A lolos justru karena memakai `/usr/bin/gcc` sistem —
perbedaan lingkungan yang tidak terlihat sampai kernel dibangun dari dalam pohon.

**4. `HOSTCFLAGS` dan `HOSTLDFLAGS` harus ditimpa BERSAMAAN.** Versi pertama
hanya menimpa `HOSTCFLAGS`, sehingga kompilasi memakai header glibc sistem
(2.39) sementara link memakai sysroot glibc 2.17:

```
ld.lld: error: undefined symbol: __isoc23_strtoul
```

`__isoc23_strtoul` simbol glibc 2.38+; header modern mengalihkan `strtoul` ke
sana, pustaka 2.17 tidak memilikinya.

**Kekeliruan ini milik saya, dan komentar saya sendiri sudah mencatatnya.**
`BoardConfig.mk` versi sebelumnya menulis bahwa `HOSTLDFLAGS` hulu "tidak
tertimpa dan tetap aktif" — mencatat ketidakcocokannya dengan benar lalu
menyimpulkannya aman. Nilai penggantinya memulihkan jalur GCC 23.2
(`BoardConfigKernel.mk:198` di sana) yang ikut terhapus di 24.0.

---

## Dua kegagalan build, dan satu koreksi urutan fase

### #1 fork ULH `system/sepolicy` — plugin Go tidak kompatibel

Soong bootstrap mati 48 detik setelah mulai:

```
bug_map.go:66        android.Cat kini blueprint.HostTool, tidak lagi memenuhi
                     blueprint.Rule (missing method String)
cil_compat_map.go:85
flags.go:53, :103    gobtools.CustomEnc kini menuntut method Encode
```

Perbaikannya bukan menambal, melainkan **membuang fork-nya**. Isinya hanya satu
commit, `83b174ea sepolicy: allow su domain in user builds`, dan
`PLAN-LOS24.md` §6.1 sudah menandainya "lewati" sejak Fase 0 karena A37
userdebug. Fork itu tidak pernah dibutuhkan; ia ikut terbawa hanya karena ada
di daftar ULH.

Akibatnya beban forward-port turun dari 19 commit menjadi **18**.

### #2 fork ULH 23.2 tidak bisa dipakai di pohon 24.0 sama sekali

Ini yang mengubah rencana. LineageOS 24.0 **memecah `fs_mgr` keluar dari
`system/core`** menjadi project sendiri:

```
LineageOS/android_system_fs_fs_mgr    di manifest 23.2: 0    di 24.0: 1
system/core/fs_mgr/libsnapshot/...    ADA (dari fork ULH 23.2)
system/fs/fs_mgr/libsnapshot/...      ADA (project baru 24.0)
```

Keduanya ter-checkout, dan soong menolak:

```
system/core/fs_mgr/libsnapshot/snapuserd/Android.bp:57:1
  module "libsnapuserd" already defined                      (8 modul)
frameworks/native/libs/binder/Android.bp:962:1
  module "packagemanager_aidl_interface" already defined
```

**Ketidakcocokannya STRUKTURAL, bukan API.** Dan karena analisis soong mencakup
seluruh pohon, satu bentrokan di mana pun memblokir semuanya — termasuk build
kernel yang sama sekali tidak menyentuh repo itu.

### Koreksi: urutan fase di `PLAN-LOS24.md` keliru

Rencana menaruh Fase 2 (kernel) sebelum Fase 3 (forward-port ULH), dengan
asumsi keduanya bisa dikerjakan terpisah. **Salah.** Forward-port ULH adalah
**prasyarat build**, bukan lanjutan.

Fase 0 dan Fase 1 tidak bisa menangkap ini: Fase 0 memeriksa klaim terhadap
*sumber hulu*, Fase 1 berhenti di `lunch`. Bentrokan modul hanya muncul di
analisis soong, yaitu langkah pertama build sesungguhnya. Pelajaran yang sama
seperti koreksi `BoardConfigQcom.mk` di Fase 1, satu tingkat lebih dalam:
**tiap tahap hanya bisa menggugurkan klaim yang memang terjangkau alatnya.**

### Yang dikerjakan untuk mengisolasi uji kernel

Keenam fork ULH sementara dilepas ke hulu 24.0. Itu **melucuti kemampuan yang
dibutuhkan untuk boot** — GLES RenderEngine, cgroup v1, text relocation, RIL
v6/v8/v9 — dan itu disengaja: tujuannya memisahkan variabel toolchain kernel
dari pekerjaan forward-port, bukan mengklaim ROM ini bisa boot.

Kecualinya `hardware/qcom-caf/common`, yang wajib untuk msm8916. Dibuatkan fork
sendiri `rigaz29/android_hardware_qcom-caf_common` branch `lineage-24` =
LineageOS 24.0 + dua commit ULH yang sudah terbukti di Fase 0, hasilnya
diverifikasi identik dengan ULH 23.2 di ketiga berkas.

## Catatan operasional

Build B ditunda sampai konversi partial clone reda. Alasannya bukan kehati-hatian
berlebih: konversi itu menghapus-dan-mengambil-ulang `build/make`, `build/soong`,
`prebuilts/build-tools`, dan `prebuilts/clang` — semuanya build-kritis. Build yang
gagal karena repo hilang di tengah jalan akan menghasilkan diagnosis yang
menyesatkan, dan kit 23.2 sudah penuh contoh berapa mahal itu.

---

## Fase 6 yang terpaksa dikerjakan lebih awal

Tiga HAL harus dimigrasi sebelum build bisa hijau, jadi sebagian Fase 6
terserap ke sini.

### Lights: HIDL 2.0 ke AIDL ILights V2

`android.hardware.light@2.0` dihapus dari `hardware/interfaces` di Android 17
(tersisa `aidl/` dan `utils/`). HAL keempat yang patah setelah `configstore`,
`libion`, dan `memtrack`.

Implementasi A37 **di-port**, bukan diganti HAL generik. Sebabnya konkret: A37
berkedip lewat `grpfreq`/`grppwm` gaya QCOM, sedangkan
`android.hardware.light-service.lineage` memakai node tunggal
`/sys/class/leds/rgb/rgb_blink`. Memakai HAL generik berarti LED notifikasi
menyala solid tanpa kedip.

`sepolicy/file_contexts` ikut diperbarui ke nama biner baru. Komentar di berkas
itu justru merekam kekeliruan identik yang pernah terjadi — barisnya dulu
menunjuk `-service.a6000`, sisa kang dari Lenovo, sehingga biner A37 tidak
pernah dapat label dan init tidak bisa transisi ke `hal_light_default`.

### Memtrack: HIDL 1.0 ke AIDL

Penggantinya sudah ada di repo yang memang sudah kita fork:
`hardware/qcom-caf/common/memtrack/` menyediakan
`vendor.qti.hardware.memtrack-service` lengkap dengan `memtrack_kgsl.cpp` —
pelacakan memori GPU Adreno, persis kebutuhan perangkat ini.

### libbt-vendor dicabut — konsekuensinya harus diuji

Repo `hardware/qcom-caf/bt` **dihapus dari manifest 24.0**; direktorinya tidak
ada di pohon. `libbt-vendor` adalah lapisan vendor Bluetooth QCOM.

**Kalau Bluetooth tidak hidup, di sinilah titik pertama yang harus dilihat.**
Jalan keluarnya mem-fork `hardware/qcom-caf/bt` dari branch 23.2 dan
mengembalikan dua baris yang kini dikomentari di `device.mk`.

---

## Yang layak diwariskan

### `PRODUCT_ENFORCE_PACKAGES_EXIST_ALLOW_LIST` hanya bisa dipanggil sekali

Kuncinya `PRODUCTS.<mk-produk-teratas>.<VAR>`, dan
`$(lastword $(_include_stack))` menghasilkan `lineage_A37.mk` baik dipanggil
dari device tree maupun dari `vendor/lineage`. Karena `.KATI_READONLY`,
panggilan kedua mana pun langsung galat. Menambahinya dengan `+=` juga percuma.

Sekalian ketahuan pembungkus `enforce-product-packages-exist` **cacat di hulu** —
`$(enforce-...-internal,...)` tanpa `call`, jadi tidak melakukan apa pun.

`TARGET_DISABLE_EPPE := true` sengaja **tidak** dipakai meski satu baris dan
tanpa fork: knob itu mematikan seluruh pemeriksaan, padahal pemeriksaan tersebut
sudah menangkap memtrack HIDL, `libbt-vendor`, dan lights HIDL dalam sesi ini.

### Menolak patch berdasarkan asalnya adalah kesalahan

`PLAN-LOS24.md` §6.3 menyaring `mkbootimg --dt` sebagai "khas Exynos, tidak
relevan", satu daftar dengan Broadcom Wi-Fi dan RIL v6/v8/v9. **Salah** — A37
memakainya juga (`BOARD_KERNEL_SEPARATED_DT := true`), dan penolakannya
berdasar asal patch, bukan kebutuhan perangkat.

Itu persis yang diperingatkan rencana itu sendiri: *"setiap patch disaring
terhadap kemampuan A37 yang sudah diverifikasi, bukan terhadap kemiripan nama
perangkat atau vendor."*

### Dua patch mkbootimg yang setara, dan cara memilihnya

Kit 23.2 punya patch `--dt` sendiri; ULH punya `d96838c5`. ULH sedikit lebih
lengkap (dt ikut dihitung SHA, ada penjaga `header_version > 0`), tapi patch
23.2 **terverifikasi di perangkat**.

Diperiksa langsung pada `boot.img` hasil build: `dt_size` di offset 40 bernilai
210944 dan magic `QCDT` ada di offset yang benar — **identik strukturnya**
dengan yang divalidasi patch 23.2. Satu-satunya delta tersisa adalah SHA
identitas citra, yang tidak diverifikasi bootloader LK legacy.

Karena itu ULH dipertahankan, dengan alasan yang terukur, bukan preferensi.
Kalau nanti terbukti tidak boot, patch 23.2 adalah hal pertama yang ditukar.

---

## Yang BELUM terbukti

`boot.img` **terbangun dan strukturnya benar**. Itu bukan bukti ia **boot**.

Yang masih menunggu perangkat:
- ROM penuh belum dibangun — ini baru `bootimage`
- Bluetooth tanpa `libbt-vendor`
- LED notifikasi setelah migrasi lights ke AIDL
- memtrack AIDL menggantikan HIDL
- rantai BPF-less (Fase 5) belum diterapkan sama sekali
- SkiaGL lawan fork GLES ULH (Fase 6) belum diuji
