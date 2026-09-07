# Fase 0 — hasil verifikasi

Dijalankan 7 September 2026. Skrip dan pohon uji ada di `verify/`.

## Ringkasan

| | |
|---|---|
| Klaim diuji | **51** |
| Lulus | **51** |
| Klaim gugur | **0** |
| Tes yang salah tulis (bukan klaim gugur) | 4 — lihat catatan di bawah |
| Cherry-pick ULH → 24.0 diuji | **18 commit nyata** |
| Release config | **`cp2a`** — terjawab |

Tidak ada satu pun temuan di `PLAN-LOS24.md` yang gugur. Dua di antaranya
justru terbukti **lebih ringan** dari yang diperkirakan, dan itu mengubah
peringkat risiko.

---

## 1. Release config: `cp2a` <span>terjawab</span>

Pertanyaan terbuka Fase 0 terjawab tanpa perlu sync:

```
vendor/lineage/vars/aosp_target_release
  lineage-23.2 :  aosp_target_release=bp4a
  lineage-24.0 :  aosp_target_release=cp2a

vendor/lineage/release/release_configs/
  lineage-23.2 :  bp4a.textproto
  lineage-24.0 :  cp2a.textproto      <- satu-satunya
```

Perintah lunch yang benar:

```sh
unset -f grep            # jebakan lingkungan dari 23.2, masih berlaku
source build/envsetup.sh
lunch lineage_A37-cp2a-userdebug
```

**Umpan palsu yang hampir menyesatkan.** `grep -c bp4a` atas seluruh
`vendor/lineage` branch `lineage-24.0` masih menghasilkan **31** kecocokan,
sementara `cp1a` dan `cp2a` nol lewat pencarian kode GitHub. Ditelusuri, 31 itu
seluruhnya direktori aconfig basi (`release/aconfig/bp4a/...`) plus
`release/build_config/bp4a.textproto` yang tertinggal — bukan konfigurasi aktif.
Yang menentukan `vars/aosp_target_release`, dan isinya `cp2a`.

Pelajaran yang sama seperti penyaringan patch di 23.2: **hitungan kecocokan
bukan bukti; yang membuktikan adalah berkas mana yang benar-benar dibaca.**

---

## 2. Uji cherry-pick nyata — hasil jauh lebih baik dari perkiraan

Ini yang tidak bisa dijawab API mana pun. Delapan belas commit ULH benar-benar
di-cherry-pick ke `lineage-24.0` di klon nyata (`verify/trees/`).

| Repo | Commit | Bersih | Konflik | Hunk konflik |
|---|---:|---:|---:|---:|
| `hardware/qcom-caf/common` | 2 | 1 | 1 | 1 |
| `bionic` | 1 | 1 | 0 | 0 |
| `system/core` | 3 | **3** | 0 | 0 |
| `packages/modules/Connectivity` | 1 | 1 | 0 | 0 |
| `frameworks/av` | 2 | 2 | 0 | 0 |
| `frameworks/native` | 9 | 5 | 4 | 17 |
| **Total** | **18** | **13** | **5** | **18** |

`system/sepolicy` (1 commit, su domain di build user) sengaja tidak diuji —
tidak relevan untuk A37 yang userdebug.

### 2a. Dua perkiraan di dokumen yang ternyata terlalu pesimis

**`system/core` menerap BERSIH, ketiganya.** `PLAN-LOS24.md` §6.1 menulis
bahwa refactor `libprocessgroup_platform` di 24.0 "hampir pasti menggeser
konteks hunk". Ternyata tidak: `61b57678`, `90ef1146`, dan `f5f2bd6d` ketiganya
menerap tanpa konflik sama sekali. Perkiraan itu benar sebagai kewaspadaan,
salah sebagai ramalan.

**Rantai GLES: 4 konflik, bukan 6.** Pengukuran pertama melaporkan 6 konflik
dari 9 commit. Angka itu **keliru**, dan sebabnya cacat di alat ukur saya
sendiri: skrip menguji tiap commit terpisah dari basis yang sama, sehingga
`93877b86` dan `fcc10e35` — yang hanya menyentuh
`libs/renderengine/gl/GLESRenderEngine.cpp` — pasti gagal, karena berkas itu
baru lahir dari `c7f2fee2` yang di-abort sebelumnya.

Dibuktikan, bukan diasumsikan:

```
libs/renderengine/gl/ di lineage-24.0            : tidak ada
c7f2fee2 membawa 24 berkas gl/, semuanya BARU     : 0 modifikasi
gl/GLESRenderEngine.cpp dalam daftar konflik c7f2fee2 : 0

uji: pasang c7f2fee2, lalu dua commit hilir
  93877b86  BERSIH
  fcc10e35  BERSIH
```

Karena berkas baru tidak pernah konflik kecuali sudah ada, dan
`gl/GLESRenderEngine.cpp` tidak termasuk berkas yang bentrok di `c7f2fee2`,
kedua commit hilir itu menerap begitu forward-portnya mendarat.

### 2b. Konflik yang benar-benar butuh tangan manusia

```
frameworks/native
  e2e91300  Revert "Delete genTextures and deleteTextures"      2 berkas,  2 hunk
  cd1402b9  Revert "Remove useFramebufferCache parameter"       4 berkas,  4 hunk
  c7f2fee2  Forward-port GLES Render Engine to 16 QPR2          6 berkas, 10 hunk
  e4247554  SF: Bring back support for disabling backpressure   1 berkas,  1 hunk

hardware/qcom-caf/common
  624fa247  Revert "QCOM: RIP pre-UM families"                  1 berkas,  1 hunk
```

Berkas yang bentrok di `c7f2fee2`: `libs/renderengine/Android.bp`,
`RenderEngine.cpp`, `skia/SkiaGLRenderEngine.cpp`,
`threaded/RenderEngineThreaded.cpp`, `services/surfaceflinger/Layer.cpp`,
`SurfaceFlinger.cpp`. Persis area yang `PLAN-LOS24.md` §6.1 tandai berubah
antara 23.2 dan 24.0 (`ColorSpaces.cpp` pindah, `skia/compat/*` masuk,
`libipcrenderbuffer_static` ditambahkan) — jadi prediksi *lokasi*-nya tepat,
hanya *skalanya* yang dilebihkan.

### 2c. Konflik qcom-caf sudah diselesaikan dan diverifikasi

`624fa247` konflik pada `BoardConfigQcom.mk`, dan bentuknya sepele: HEAD kosong
lawan blok tambahan. Diselesaikan dengan mengambil sisi masuk, lalu `7b118701`
menerap bersih di atasnya. Hasilnya diadu dengan ULH `lineage-23.2`:

```
                       hasil uji   ULH 23.2
qcom_boards.mk         msm8916=1   msm8916=1   cocok
qcom_defs.mk           msm8916=1   msm8916=1   cocok
BoardConfigQcom.mk     msm8916=2   msm8916=2   cocok

QCOM_BOARD_PLATFORMS += msm8916    qcom_boards.mk:22
BR_FAMILY := msm8909 msm8916       qcom_defs.mk:8
QCOM_HARDWARE_VARIANT := msm8916   BoardConfigQcom.mk:380
```

Lapisan QCOM untuk msm8916 **terbukti bisa dipulihkan di 24.0**.

### 2d. Temuan sampingan yang menjelaskan Mi-Thorium

Commit teratas `hardware/qcom-caf/common` di `lineage-24.0`:

```
2cd569f  common: Drop no longer used TARGET_COMPILE_WITH_MSM_KERNEL
```

Itu penjelasan langsung untuk commit Mi-Thorium `5a6c7d41` ("It's now unset from
lineage side, however our stuff still needs it"). Dan `624fa247` yang kita
cherry-pick justru **mengembalikannya** (`BoardConfigQcom.mk:283`).

Untuk A37 tetap tidak relevan — device tree A37 tidak pernah meng-include
`BoardConfigQcom.mk` — tapi §5.5 `PLAN-LOS24.md` kini punya sebab, bukan hanya
akibat.

---

## 3. Klaim yang lolos, dikelompokkan

<details><summary>A. Sasaran dan versi (5)</summary>

- manifest 24.0 menunjuk `refs/tags/android-17.0.0_r1`
- 1067 project di 24.0, 993 di 23.2
- `isAtLeast26Q2 = api_level_full >= 3700` — kita di sini
- `isAtLeast26Q4 = 3710` — belum menyala
</details>

<details><summary>B. Kernel: syscall dan gerbang (13)</summary>

- `SYSCALLS.TXT` 274 = 274; nol syscall baru, nol dihapus
- `arc4random.h` identik byte-per-byte 23.2 vs 24.0
- masih `async_safe_fatal` untuk `MADV_WIPEONFORK`
- gerbang 25Q4: `ALOGW` di 23.2 → `ALOGE` + `return 7` di 24.0
- gerbang 26Q4 (5.15) ada di 24.0, tidak ada di 23.2
- `REQUIRE(5, 10, 199)` ada — dasar pemilihan angka spoof
- `isKernel64Bit()` masih pindah personality sebelum `uname()`
</details>

<details><summary>C. Toolchain kernel (17)</summary>

- `BoardConfigKernel.mk`: 36 rujukan GCC di 23.2 → **0** di 24.0
- `TARGET_KERNEL_CLANG_COMPILE`, `TARGET_KERNEL_NO_GCC`,
  `TARGET_KERNEL_LLVM_BINUTILS`, `TARGET_KERNEL_CROSS_COMPILE_PREFIX`:
  keempatnya hilang
- `kernel.mk:265` default `CC="clang" LD=ld.lld`
- **`ifeq ($(KERNEL_CC),)` di `kernel.mk:264`** — escape hatch terkonfirmasi
- `KERNEL_CROSS_COMPILE` nol assignment, tapi 3 ekspansi di baris make
- `TARGET_KERNEL_ADDITIONAL_FLAGS` ditambahkan **sesudah** `HOSTCFLAGS` hulu
- `de40b978` = "manifest: Drop GCC prebuilts"; repo GCC 4.9 masih ada,
  branch `lineage-19.1`, dan binari `bin/aarch64-linux-android-gcc` benar-benar
  ada di sana
</details>

<details><summary>D. Yang patah di Android 17 (11)</summary>

- configstore: ada di 23.2, **404** di 24.0; nol rujukan tersisa di
  surfaceflinger, opengl/libs, vulkan/libvulkan
- libion: `933200ed` no-op, `4a1e7d00` pulih di balik
  `soong_config_set_bool,libion,legacy_impl,true`; di-fork LineageOS di manifest
- libdmabufheap sama (`57925b76`)
- `device/lineage/sepolicy/libion/sepolicy.mk` benar-benar ada
- SF 24.0 digerbangi `register_displayservice`, memakai fork
  `lineage.frameworks.displayservice@1.0`, dan nol rujukan ke yang AOSP
</details>

<details><summary>E. Fork ULH dan QCOM (14)</summary>

- ahead_by: 9 + 3 + 1 + 2 + 2 + 1 + 1 = **19**
- ULH dan acroreiser: nol branch mengandung "24"
- acroreiser masih `TARGET_KERNEL_CLANG_COMPILE := false` di 23.2
- msm8916 nol di ketiga berkas QCOM 24.0
- `qcom_boards.mk` identik byte-per-byte 23.2 vs 24.0
- `TARGET_COMPILE_WITH_MSM_KERNEL` ada di 23.2, hilang di 24.0
</details>

<details><summary>F. Yang tidak berubah (11)</summary>

- `FactoryHal.cpp` identik; audio HIDL 6.0 masih terdaftar
- `hwservicemanager`, `libhidl`, `tools/hidl` masih di manifest
- livedisplay AIDL sysfs, camera AIDL provider, vibrator, touch: keempatnya ada
- `libstdc++` masih dibangun bionic (31 rujukan)
- `board_config.mk` 24.0 tanpa gerbang fatal untuk `TARGET_ARCH := arm`
</details>

<details><summary>G. Manifest dan sumber luar (10)</summary>

- timekeep dibuang dari manifest 24.0, branch `lineage-24.0` ada
- linkfile qcom-caf/common: 12 di 24.0; `A37-24.xml` memuat 12 yang sama
- 8 target `remove-project` semuanya valid
- Mi-Thorium `a16_qpr2` → `a17` = 8 commit; repo kernel tanpa branch a16/a17
- `los-23.2_n7000_bpfless` = 89 patch; `los-23.2_n7000` = 50
</details>

### Empat tes yang salah tulis

Semuanya cacat pengukuran, bukan klaim gugur. Dicatat karena polanya berulang:

| Tes | Sebab | Klaim |
|---|---|---|
| C4 | `$(KERNEL_CC)` ikut disubstitusi shell di dalam petik ganda; harus `grep -F` | benar |
| D9, D10 | menuntut tepat 1 kemunculan padahal klaimnya "ada" (3 dan 2) | benar |
| E4 | acroreiser menyetel flag itu **dua kali** di berkas yang sama | benar |

---

## 4. Yang masih butuh pohon ter-sync

Tidak bisa dituntaskan tanpa `repo sync` penuh (~173 GB), dan karena itu
dipindahkan ke Fase 1:

- `lunch lineage_A37-cp2a-userdebug` menghasilkan `TARGET_PRODUCT=lineage_A37`
  — perintahnya sudah pasti, hasilnya belum diuji
- `KERNEL_CC` override benar-benar membangun kernel 3.10 dengan GCC 4.9
  (**risiko tertinggi yang tersisa**; jalur `HOSTCC` dan `CLANG_TRIPLE` belum
  terbukti)
- `hardware/qcom-caf/msm8916/{audio,display,media}` fork sendiri terhadap
  `qcom-caf/common` 24.0
- sepolicy legacy ULH terhadap `system/sepolicy` 24.0
  (`sepolicy_test`, `check_vintf_compatible`)
- apakah HAL display yang dibangun dari sumber memerlukan `IDisplayService`

## 5. Akibat terhadap peringkat risiko

| Risiko | Sebelum | Sesudah | Sebab |
|---|---|---|---|
| Tidak ada ULH 24.0 | sedang | **rendah** | 13 dari 18 bersih; 18 hunk total, terpusat di satu commit |
| Toolchain kernel | tinggi | **tinggi** | tidak berubah — belum ada satu pun yang diuji dengan build nyata |
| Grafis | sedang | sedang | konflik terpusat di `c7f2fee2` seperti diduga, skalanya lebih kecil |

**Fase 2 tetap satu-satunya fase berisiko tinggi**, dan alasannya menguat:
sekarang terbukti bahwa seluruh pekerjaan userspace terukur dan sebagian besar
otomatis, sementara toolchain kernel tetap tidak terbukti sampai ada kernel yang
benar-benar terbangun.

## 6. Cara mengulang verifikasi ini

```sh
cd verify
. lib.sh                                    # chk(), raw(), code()
./pick.sh <repo> <sha>...                   # uji cherry-pick ke lineage-24.0
```

Pohon uji di `verify/trees/` adalah klon `--filter=blob:none` dengan remote
`ulh` sudah terpasang. Tidak ikut di-commit (lihat `.gitignore`).
