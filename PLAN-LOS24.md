# Rencana port LineageOS 24.0 (Android 17) ke OPPO A37

Ditulis 7 September 2026. Dokumen kerja.

Setiap klaim di bawah ditelusuri ke berkas dan baris di sumber yang benar-benar
diambil (manifest `lineage-24.0`, pohon LineageOS/AOSP di branch itu, repo ULH,
acroreiser, Mi-Thorium, zhafknight), atau ke pohon A37 sendiri. Yang belum
diverifikasi ditandai tegas — jangan diperlakukan sebagai fakta.

Basis: kernel, device tree, dan vendor blob A37 branch `lineage-23`, yaitu ROM
23.2 yang sudah boot, dipakai harian, dengan kamera AIDL dan FBE Adiantum
terbukti jalan.

---

## 1. Sasaran

**LineageOS 24.0 = Android 17.**

```
LineageOS/android default.xml @ lineage-24.0
  remote aosp  revision="refs/tags/android-17.0.0_r1"
  <project> : 1067        (23.2: 993)
```

API level penuhnya **37.0** — dibaca dari `bpf/headers/include/bpf/BpfUtils.h:157`
di Connectivity `lineage-24.0`:

```cpp
const bool isAtLeast25Q2 = (api_level_full >= 3600);  // 36.0
const bool isAtLeast25Q4 = (api_level_full >= 3610);  // 36.1
const bool isAtLeast26Q2 = (api_level_full >= 3700);  // 37.0   <- kita di sini
const bool isAtLeast26Q4 = (api_level_full >= 3710);  // 37.1
```

Angka itu yang menentukan gerbang mana yang menyala (bagian 4.2).

Release config: 23.2 memakai `bp4a`. Untuk `android-17.0.0_r1` yang tersedia
`cp1a` dan `cp2a` (diperiksa di `platform/build/release/release_configs/`):

```
cp1a   inherits: bp4a
cp2a   inherits: mainline_2026_04, cp1a
```

Mi-Thorium menyebut Android 17 sebagai "CP2A" di pesan commit mereka. **Pastikan
sendiri sesudah sync** dengan `lunch` — jangan tebak; salah release config
menghasilkan galat `Cannot locate config makefile for product` yang terlihat
seperti masalah device tree.

---

## 2. Ringkasan: sembilan temuan yang membentuk rencana ini

**1. Android 17 tidak menuntut satu pun fitur kernel baru.**
Diadu langsung, `bionic/libc/SYSCALLS.TXT` 23.2 lawan 24.0: **274 syscall lawan
274, nol tambahan, nol penghapusan.** `arc4random.h` tidak berubah sama sekali.
Backport kernel yang sudah dikerjakan untuk 23.2 (MADV_WIPEONFORK, PSI,
workingset, Adiantum DIRECT_KEY) terbawa apa adanya.

**2. Blocker sesungguhnya bukan kernel, melainkan toolchain kernel.**
LineageOS 24.0 **membuang seluruh jalur GCC** dari sistem build kernel. Kernel
A37 3.10.108 hanya bisa dikompilasi GCC 4.9. Ini pekerjaan terbesar yang
benar-benar baru di rilis ini. Rinciannya dan jalan keluarnya di bagian 4.1.

**3. Gerbang NetBpfLoad naik dari 5.4 ke 5.10, dan yang tadinya peringatan kini
mematikan.**

```diff
  // 25Q4 bumps the kernel requirement up to 5.10
  if (isAtLeast25Q4 && !isAtLeastKernelVersion(5, 10)) {
-     ALOGW("Android 25Q4 requires kernel 5.10.");        // 23.2
+     ALOGE("Android 25Q4 requires kernel 5.10.");        // 24.0
+     return 7;
  }
```

Satu gerbang fatal lagi yang harus dilucuti (jalur userspace) atau ditipu
(jalur spoof). Gerbang 26Q4 (5.15) di bawahnya **belum** menyala — butuh
`api_level_full >= 3710`, kita 3700.

**4. Belum ada fork `lineage-24.0` dari ULH maupun acroreiser.**
Diperiksa branch demi branch: keduanya mentok di `lineage-23.2`. Port ini harus
melakukan forward-port sendiri. Kabar baiknya, beban itu **terukur dan kecil**:
**19 commit** (bagian 6.1).

**5. `configstore` dihapus total dari Android 17.**
`hardware/interfaces/configstore` ada di 23.2 (1.0 dan 1.1), **404 di 24.0**.
Nol rujukan tersisa di `surfaceflinger/Android.bp`, `opengl/libs/Android.bp`,
`vulkan/libvulkan/Android.bp`. `manifest.xml:95-102` A37 mendeklarasikannya.

**6. AOSP menjadikan `libion` no-op; LineageOS memulihkannya di balik soong config.**
Seluruh tumpukan grafis/kamera/media msm8916 memakai ION
(`BoardConfig.mk:493` `TARGET_USES_ION := true`). Tanpa satu baris soong config,
ROM ini tidak akan berfungsi.

**7. Android 17 bukan patahan keras untuk perangkat Qualcomm lawas.**
Bukti terkuat dari luar: delta device tree Mi-Thorium `a16_qpr2/master` ke
`a17/master` **hanya 8 commit**, dan tak satu pun menyentuh kernel. Repo kernel
mereka bahkan tidak punya branch a16 atau a17 — default-nya masih
`mithorium/a13/master`.

**8. HIDL masih hidup.** `hwservicemanager`, `system/libhidl`, `system/tools/hidl`
tetap ada di manifest 24.0. Audio HAL HIDL **6.0 masih terdaftar** di
`FactoryHal.cpp:53-58` — berkas itu identik antara 23.2 dan 24.0. Manifest A37
yang 24 HAL tidak perlu dimigrasi karena panik; hanya `configstore` yang
benar-benar gugur.

**9. Rantai BPF-less pindah tempat, tidak hilang.**
`zhafknight/los_patches` memecah setnya pada 25 Agustus 2026 menjadi
`los-23.2_n7000` (50 patch, **tanpa** rantai BPF-less) dan
`los-23.2_n7000_bpfless` (89 patch, **dengan** rantai itu). `tools/patches.sh`
kit 23.2 menunjuk direktori yang salah sekarang. Perbaiki, dan **salin patch itu
ke repo sendiri** — ketergantungan pada direktori pihak ketiga yang bisa
dipindah lagi adalah risiko yang tidak perlu.

---

## 3. Basis: apa yang sudah dimiliki

| Komponen | Sumber | Keadaan |
|---|---|---|
| Kernel | `rigaz29/kernel_oppo_msm8939` `lineage-23` | 3.10.108, arm64, PSI + workingset + Adiantum DIRECT_KEY + MADV_WIPEONFORK |
| Device tree | `rigaz29/rb_device_oppo_A37` `lineage-23` | 792 berkas; kamera AIDL, LiveDisplay AIDL |
| Vendor blob | `rigaz29/rb-vendor_oppo_A37` `lineage-23` | 338 berkas, 333 entri `A37-vendor.mk` |

### Inventaris kernel A37, diperiksa langsung di klon

```
ADA :  kernel/sched/psi.c        mm/workingset.c    mm/list_lru.c
       lib/lockref.c             mm/vmacache.c      fs/crypto/policy.c
       CONFIG_CRYPTO_ADIANTUM=y  CONFIG_PSI=y       MADV_WIPEONFORK

TIDAK: kernel/bpf/*              include/uapi/linux/btf.h
       kernel/cgroup/cgroup.c    (masih kernel/cgroup.c tunggal = cgroup v1)
       drivers/android/binder.c  (masih drivers/staging/android/binder.c)
       close_range()             gpu_work_period tracepoint di drivers/gpu/msm/
```

Defconfig aktif `arch/arm64/configs/lineageos_a37f_defconfig`:

```
CONFIG_ANDROID_TREBLE_SPOOF_KERNEL_VERSION=y
CONFIG_ANDROID_TREBLE_BYPASS_KERNEL_VERSION_CHECKS=y
CONFIG_ANDROID_TREBLE_SPOOF_KERNEL_VERSION_PREFIX="3.17"
CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX="3.17"
```

---

## 4. Kernel

### 4.1 K-A (WAJIB, dan ini pekerjaan terbesar rilis ini). Toolchain kernel

**Masalahnya.** `vendor/lineage/config/BoardConfigKernel.mk` di `lineage-24.0`
tidak lagi mengenal satu pun knob GCC. Diadu berdampingan dengan 23.2:

```
             lineage-23.2                     lineage-24.0
             ------------------------------   -----------------------------
knob         TARGET_KERNEL_CLANG_COMPILE      hilang
             TARGET_KERNEL_NO_GCC             hilang
             TARGET_KERNEL_LLVM_BINUTILS      hilang
             TARGET_KERNEL_CROSS_COMPILE_PREFIX  hilang
             KERNEL_TOOLCHAIN                 hilang
             KERNEL_TOOLCHAIN_arm64 :=        hilang
               $(GCC_PREBUILTS)/aarch64/
               aarch64-linux-android-4.9/bin
```

Dan `vendor/lineage/build/tasks/kernel.mk:264-266` sekarang:

```make
ifeq ($(KERNEL_CC),)
    KERNEL_CC := CC="$(CCACHE_BIN) clang" LD=ld.lld
endif
```

Prebuilt-nya pun dicabut dari manifest — commit `de40b978 manifest: Drop GCC
prebuilts` membuang tiga project `prebuilts/gcc/linux-x86/{aarch64,arm,x86}`.

Kenapa ini mematikan untuk A37: `BoardConfig.mk:73` menyetel
`TARGET_KERNEL_CLANG_COMPILE := false` justru karena kernel 3.10 **mati di tahap
paling awal** kalau dikompilasi clang:

```
scripts/mod/devicetable-offsets.c:10:2: error: unexpected token at start of statement
```

Itu integrated assembler clang menolak keluaran asm bergaya gcc yang dipakai
kernel 3.10 untuk menurunkan offset struktur. Di 24.0 kedua baris
`TARGET_KERNEL_CLANG_COMPILE := false` dan `TARGET_KERNEL_LLVM_BINUTILS := false`
menjadi **no-op senyap** — tidak ada yang membacanya lagi, dan build akan
langsung memanggil clang.

**Jalan keluar, diurutkan dari yang paling murah.**

**A-1 (disarankan). Setel `KERNEL_CC` dan `KERNEL_CROSS_COMPILE` sendiri.**
Ini bukan akal-akalan; `KERNEL_CC` memang didokumentasikan sebagai knob device
tree di `kernel.mk:53`, dan gerbangnya `ifeq ($(KERNEL_CC),)` — artinya nilai
dari device tree menang dan default clang tidak pernah terpasang.
`KERNEL_CROSS_COMPILE` bahkan **tidak pernah di-assign di mana pun** pada 24.0;
ia hanya diekspansi di baris perintah make (`kernel.mk:283`), jadi sepenuhnya
bebas dipakai.

Di `BoardConfig.mk`:

```make
A37_GCC := $(abspath .)/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin
KERNEL_CC            := CC="$(CCACHE_BIN) $(A37_GCC)/aarch64-linux-android-gcc"
KERNEL_CROSS_COMPILE := CROSS_COMPILE="$(A37_GCC)/aarch64-linux-android-"
```

Di local manifest, kembalikan project yang dibuang `de40b978`. Reponya masih ada
— diperiksa: `LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9`,
default branch `lineage-19.1`.

Yang harus diperiksa saat mengerjakan, karena belum diuji:

- `KERNEL_CLANG_TRIPLE=CLANG_TRIPLE=aarch64-linux-gnu-` tetap ikut terkirim ke
  make. Untuk kernel 3.10 itu variabel make yang tidak dipakai siapa pun —
  **harusnya** tidak berbahaya, tapi buktikan, jangan asumsikan.
- `PATH_OVERRIDE` tetap menaruh direktori clang di depan PATH. Karena `CC` dan
  `CROSS_COMPILE` kita absolut, ini semestinya tidak berpengaruh. Yang berisiko
  justru `HOSTCC`, yang akan jatuh ke clang di PATH.
- `KERNEL_MAKE_FLAGS += HOSTCFLAGS="..."` kini membawa `--sysroot=...glibc2.17-4.8`.
  `BoardConfig.mk:340` A37 sudah menyetel `TARGET_KERNEL_ADDITIONAL_FLAGS :=
  HOSTCFLAGS="-fuse-ld=lld ..."`, dan `kernel.mk:276` menambahkannya **sesudah**
  — jadi milik kita menang dan sysroot itu hilang. Gabungkan keduanya, jangan
  timpa.

**A-2 (cadangan). `BOARD_CUSTOM_KERNEL_MK`.**
Patch `094-local-0001-kernel-support-BOARD-CUSTOM-KERNEL-MK` di set n7000
menambahkan kait di `vendor/lineage/build/tasks/kernel.mk`:

```make
ifdef BOARD_CUSTOM_KERNEL_MK
include $(BOARD_CUSTOM_KERNEL_MK)
endif
```

Enam baris. Dengan itu, seluruh aturan build kernel bisa dipindah ke berkas
milik device tree, lepas dari perubahan hulu apa pun. Lebih tahan banting dari
A-1 terhadap perubahan LineageOS berikutnya, tapi berarti menambal
`vendor/lineage` — repo yang berubah hampir tiap hari.

**A-3. `TARGET_PREBUILT_KERNEL`.**
Masih didukung penuh di 24.0 (`kernel.mk:157-245`). Bangun kernel di luar pohon
dengan GCC 4.9, umpankan `Image` jadi. Paling sederhana, tapi memutus
`KERNEL_OBJ` — dan `sensors/Android.mk` A37 punya dependensi ke `KERNEL_OBJ/usr`
yang sudah pernah menggigit (catatan build Adiantum, kegagalan (1)). Perlu
`TARGET_PREBUILT_KERNEL_HEADERS`.

**A-4 (jangan). Clang-kan kernel 3.10.**
Tidak ada preseden yang bisa dipinjam: acroreiser tetap GCC di 23.2
(`android_device_lenovo_a6010/BoardConfig.mk:59-65`, kernel 3.10.108 yang sama).
Mi-Thorium memang clang penuh (`TARGET_KERNEL_CLANG_VERSION := r563880c`,
`LLVM=1`) — tapi kernel mereka 4.9/4.19, bukan 3.10.

> **Urutan kerja untuk K-A:** coba A-1 lebih dulu. Kegagalannya murah dan cepat
> ketahuan (kernel gagal build dalam menit pertama, bukan jam ketiga). Kalau
> A-1 buntu karena `HOSTCC`, naik ke A-2.

### 4.2 K-B (WAJIB, satu baris). Awalan spoof versi kernel

Mekanismenya sudah aktif; hanya nilainya yang usang.

```diff
-CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX="3.17"
+CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX="5.10.199"
```

Kenapa `5.10.199` dan bukan `5.10`: `NetBpfLoad.cpp:1613-1640` menjalankan blok
`REQUIRE(5, 10, 199)` di bawah `isAtLeastV`, plus `isLtsKernel()`. Keduanya hanya
`ALOGW` dan tidak pernah `return`, jadi tidak fatal — tapi memilih angka yang
lolos gratis.

`ANDROID_TREBLE_SPOOF_BPF_KERNEL_BITNESS` **tetap tidak diperlukan**. Alasannya
tidak berubah di Android 17: `KernelUtils.h:141-180` berpindah personality ke
`PER_LINUX` dulu sebelum membaca `uname()`, jadi proses 32-bit tetap melihat
`aarch64` dari kernel arm64 kita, dan `isKernel32Bit()` bernilai salah. Gerbang
`return 9` di `:1596` tidak menyala.

Peringatan yang sama seperti di 23.2, dan sekarang lebih penting: **spoof hanya
membuat NetBpfLoad mau jalan.** Ia lalu benar-benar mencoba memuat program BPF di
kernel yang tidak punya `kernel/bpf/` sama sekali. Kalau K-D tidak dikerjakan,
K-B sendirian mengubah kegagalan jinak menjadi bootloop. **Jangan pasang K-B di
fase awal.**

### 4.3 K-C (opsional, murah). Tiga backport kecil dengan rasio bagus

| Backport | Biaya | Yang dihapus dari userspace |
|---|---|---|
| `epoll_pwait2()` | 2 commit | patch `bionic/001-...epoll_pwait2-fall-back...` |
| `gpu_work_period` tracepoint di KGSL | belum diukur | patch `frameworks/native/010-...Stall-GpuWork...` |
| `close_range()` + flag-nya | 5 commit | tidak ada pemanggil yang terbukti — **lewati** |

`close_range` sengaja diturunkan statusnya. Di 23.2 ia masuk daftar K3 "WAJIB"
karena ikut dalam rentetan 167 commit acroreiser, lalu terbukti tidak dibutuhkan
untuk build maupun boot. Tanpa pemanggil yang teridentifikasi, ini backport
tanpa alasan.

`gpu_work_period` perlu diukur dulu: tracepoint itu tidak ada di
`drivers/gpu/msm/` A37 (diperiksa: nol kecocokan), dan menambahkannya ke KGSL
lawas bukan salin-tempel. Kerjakan hanya kalau patch userspace-nya bermasalah.

### 4.4 K-D (OPSIONAL, dan inilah jawaban pertanyaan "backport apa supaya patch userspace hilang")

Pertanyaannya diajukan dengan benar, dan jawaban jujurnya tidak menyenangkan.
Dari 89 patch di set `_bpfless`, inilah pemetaan patch → fitur kernel yang bisa
menghapusnya:

| Kelompok | Patch | Fitur kernel yang menghapusnya | Biaya kernel |
|---|---:|---|---:|
| **Tier 1 — murah** | **3** | | |
| `bionic/001` epoll_pwait2 fall back | 1 | syscall `epoll_pwait2` | 2 commit |
| `bionic/003` MADV_WIPEONFORK | 1 | sudah dikerjakan (`db809bdd`) | selesai |
| `frameworks/native/010` Stall GpuWork | 1 | tracepoint `gpu_work_period` di KGSL | belum diukur |
| **Tier 2 — mahal** | **6** | **cgroup v2 penuh** | **~985 commit** |
| `system/core` 023, 024, 025, 030 | 4 | | |
| `frameworks/base/005` Ignore cgroup creation errors | 1 | | |
| `lmkd/032` Auto-promote on cgroup v2 | 1 | | |
| **Tier 3 — sangat mahal** | **22** | **eBPF + BTF + map types** (butuh Tier 2 lebih dulu) | **~470 commit** |
| Connectivity 036-043, 045-048, 091 | 13 | | |
| `system/bpf` 050-052 · `system/netd` 053, 054, 093 | 6 | | |
| DnsResolver 049 · vold 055 · frameworks/native 009 | 3 | | |
| **Tier 4 — kernel tidak menolong** | **58** | — | ∞ |
| `frameworks/native` (GLES RenderEngine 012-019, libbinder, GLES loading, display power) | 11 | | |
| `frameworks/base` (brightness, hwui ashmem, fs-verity, Power HAL, ripple/stretch, am) | 11 | | |
| `frameworks/av` (OMX software codec, audio SCO/APM, kamera) | 11 | | |
| `packages/modules/Bluetooth` | 6 | | |
| `system/core` · `bionic` | 6 | | |
| `system/apex` · `hardware/ril` | 4 | | |
| sisanya (`vendor/lineage`, mkbootimg, sepolicy, libhidl, libhwbinder, `kernel/configs`, libhardware, `hardware/interfaces`, broadcom/wlan) | 9 | | |

Angka-angka itu dihitung dari daftar berkas `los-23.2_n7000_bpfless/patches/`
yang sesungguhnya, bukan diperkirakan — 3 + 6 + 22 + 58 = 89.

Catatan tumpang tindih yang penting supaya tidak menghitung ganda: ULH
`system/core` `61b57678` dan `90ef1146` adalah **patch yang sama** dengan n7000
023 dan 024, hanya lewat jalur berbeda; `README-bpfless.md` kit 23.2 sudah
mencatat bahwa keduanya gagal diterapkan karena fork ULH sudah memuatnya.
Begitu pula ULH Connectivity `9d842efa` — set `_bpfless` sengaja tidak
menyertakan patch BTF legacy karena rantai GSI menyentuh area
`NetBpfLoad.cpp` yang sama (`NOT_INCLUDED.md`).

**Vonis.**

```
Tier 1     :   3 patch hilang  <-  ~2 commit kernel        rasio bagus
Tier 2     :   6 patch hilang  <-  ~985 commit kernel      rasio buruk
Tier 3     :  22 patch hilang  <-  ~470 commit kernel      rasio buruk
                                    (dan Tier 2 wajib lebih dulu)
Tier 4     :  58 patch         <-  tidak ada backport yang menolong
```

Jadi **backport kernel paling banyak menghapus 31 dari 89 patch dengan ongkos
sekitar 1.455 commit kernel**, dan 58 sisanya — mayoritas mutlak — tetap harus
dikerjakan di userspace apa pun yang terjadi. Kerjakan Tier 1. Tolak Tier 2 dan
3 kecuali ada fitur yang benar-benar dituntut (statistik data per-aplikasi,
firewall berbasis BPF), dan itu pun sebagai proyek tersendiri.

Ongkos kernelnya (~985 dan ~470 commit) diwarisi dari pengukuran di
`PLAN-LOS23.md` §K2a — jarak pohon A37 ke a6010 acroreiser dihitung dari titik
pisah 2018 (`d27773cc6d3`, 5 April 2018), bukan diperkirakan.

### 4.5 K-E (opsional, setelah ROM hidup). Penyetelan

Tidak berubah dari daftar di `PLAN-BACKPORT-KERNEL.md`. Yang masih tersisa dan
belum dikerjakan: `mm/vmacache` (sudah ada tapi pernah dicabut lalu dikembalikan
— lihat commit `70bef761`), `lib/lockref`, penyetelan I/O, dan rentetan Revert
acroreiser (overclock 1,6 GHz, SCHED_FIFO, oom_reaper, `process_mrelease`).

Pelajaran dari PSI dan workingset yang jangan diulang: **perkiraan jumlah berkas
selalu meleset ke bawah**, karena lapisan pendukung (API yang tidak ada di 3.10)
tidak terlihat sampai dicoba. PSI diperkirakan "1522 baris + 10 berkas",
kenyataannya butuh shim `kthread_delayed_work`, `wq_worker_last_func`,
`jiffies_to_nsecs`, dan pembukaan lima fungsi static di `core.c`. Workingset
diperkirakan "dua berkas", kenyataannya 46 commit.

---

## 5. Device tree

Delapan perubahan. Enam pertama wajib; dua terakhir dipicu keputusan lain.

### 5.1 ION — WAJIB, dua baris

AOSP mematikan `libion` di Android 17 (`dc46f2d4 libion: Deprecate libion`,
`933200ed libion: Make all functions no-ops`). LineageOS memulihkannya:

```
LineageOS/android_system_memory_libion   4a1e7d00
  "The legacy real implementation can be enabled from a device tree with:
   $(call soong_config_set_bool,libion,legacy_impl,true)"

LineageOS/android_system_memory_libdmabufheap   57925b76
  sama, knob yang sama
```

Di `device.mk`:

```make
# ION
$(call soong_config_set_bool,libion,legacy_impl,true)
```

Di `BoardConfig.mk`, bersama include sepolicy lain:

```make
include device/lineage/sepolicy/libion/sepolicy.mk
```

Direktori itu ada — diperiksa di `LineageOS/android_device_lineage_sepolicy`
`lineage-24.0`: `atv common exynos libion libperfmgr qcom`.

Ini persis yang dikerjakan Mi-Thorium di `f1b04382`, dan alasan mereka layak
dikutip: *"At least one blob directly depends on this, with many other bits and
pieces likely."*

Catatan pengukuran yang jujur: pemindaian `DT_NEEDED` atas 338 blob A37
menghasilkan **nol** yang menautkan `libion.so` secara langsung. Jadi
ketergantungannya tidak lewat blob, melainkan lewat HAL yang dibangun dari
sumber — `hardware/qcom-caf/msm8916/{display,media}` dengan
`TARGET_USES_ION := true` dan `TARGET_USES_NEW_ION_API := true`
(`BoardConfig.mk:493-494`). Tetap wajib, hanya jalur ketergantungannya berbeda
dari dugaan Mi-Thorium.

### 5.2 configstore — WAJIB, cabut deklarasinya

```
hardware/interfaces/configstore @ lineage-23.2 :  1.0/ 1.1/ utils/ OWNERS README.md
hardware/interfaces/configstore @ lineage-24.0 :  404
```

Nol rujukan tersisa di `frameworks/native` 24.0 — diperiksa di
`services/surfaceflinger/Android.bp`, `opengl/libs/Android.bp`,
`vulkan/libvulkan/Android.bp`, ketiganya 0.

Buang blok `manifest.xml:95-102`:

```xml
<hal format="hidl">
    <name>android.hardware.configstore</name>
    <transport>hwbinder</transport>
    <version>1.1</version>
    <interface>
        <name>ISurfaceFlingerConfigs</name>
        <instance>default</instance>
    </interface>
</hal>
```

`device.mk` A37 tidak menyebut paket configstore mana pun (diperiksa: nol
kecocokan), jadi tidak ada yang perlu dicabut di sana. Yang perlu diperiksa saat
mengerjakan: apakah ada perilaku SurfaceFlinger yang selama ini datang dari
`ISurfaceFlingerConfigs` dan kini harus pindah ke `PRODUCT_VENDOR_PROPERTIES`.

### 5.3 displayservice — WAJIB kalau SurfaceFlinger memerlukannya

`android.frameworks.displayservice@1.0` diganti fork LineageOS
`lineage.frameworks.displayservice@1.0`, yang tinggal di
`hardware/lineage/interfaces/_frameworks/displayservice`.

`frameworks/native/services/surfaceflinger/Android.bp:345,362,366` di 24.0
menggerbangnya lewat soong config:

```
] + select(soong_config_variable("surfaceflinger", "register_displayservice"), {
    true: ["-DREGISTER_DISPLAYSERVICE"],
...
    true: ["lineage.frameworks.displayservice@1.0", "libdisplayservicehidl"],
...
    true: ["lineage.frameworks.displayservice@1.0.xml"],
```

Mi-Thorium menyalakannya (`4dab86cb`):

```make
MITHORIUM_PRODUCT_PACKAGES += lineage.frameworks.displayservice@1.0.vendor
$(call soong_config_set_bool,surfaceflinger,register_displayservice,true)
```

**Untuk A37 belum tentu perlu.** Mi-Thorium memakai
`android.hardware.graphics.composer@2.1-service` dan blob display yang mencarinya.
Periksa dulu: kalau tidak ada yang mencari `IDisplayService` di `/vendor`,
biarkan mati. Pemindaian blob A37 memberi **nol** kecocokan
`android.frameworks.displayservice` — jadi kemungkinan besar tidak diperlukan,
tapi HAL display yang dibangun dari sumber belum diperiksa.

### 5.4 Toolchain kernel — WAJIB

Lihat 4.1. Perubahan di `BoardConfig.mk`: buang dua baris yang kini no-op
(`TARGET_KERNEL_CLANG_COMPILE`, `TARGET_KERNEL_LLVM_BINUTILS` — biarkan sebagai
komentar dengan alasannya, jangan hapus catatannya), tambahkan `KERNEL_CC` dan
`KERNEL_CROSS_COMPILE`, gabungkan `HOSTCFLAGS`.

### 5.5 `TARGET_COMPILE_WITH_MSM_KERNEL` — TIDAK berlaku untuk A37

Mi-Thorium menambahkannya di `5a6c7d41` dengan catatan *"It's now unset from
lineage side"*. Ditelusuri: variabel itu didefinisikan di
`hardware/qcom-caf/common/BoardConfigQcom.mk` pada 23.2 dan **hilang di 24.0**.

A37 tidak terpengaruh, dan alasannya sudah terdokumentasi di `BoardConfig.mk:23-31`:
device tree A37 **tidak pernah meng-include `BoardConfigQcom.mk`** sama sekali;
ia mendeklarasikan platformnya sendiri di `:44` (`QCOM_BOARD_PLATFORMS += msm8916`).
Dicatat di sini supaya tidak ada yang menyalinnya dari Mi-Thorium tanpa
memeriksa.

### 5.6 Yang TIDAK berubah — jangan sentuh

| Hal | Bukti |
|---|---|
| Audio HIDL 6.0 | `frameworks/av/media/libaudiohal/FactoryHal.cpp:53-58` identik 23.2 vs 24.0 |
| Kamera AIDL provider | `hardware/lineage/interfaces/camera/aidl/provider` ada di 24.0 (7 entri) |
| LiveDisplay AIDL sysfs | `.../livedisplay/aidl/sysfs` ada di 24.0 (13 entri) |
| vibrator, touch | keduanya ada di `hardware/lineage/interfaces` 24.0 |
| userspace 32-bit | `build/make/core/board_config.mk` 24.0 tidak punya gerbang fatal untuk `TARGET_ARCH := arm` |
| `libstdc++.so` | tetap dibangun `bionic/libc/Android.bp` (31 rujukan, sama di 23.2 dan 24.0) — penting, **161 blob A37 menautkannya** |
| Adiantum/FBE | tidak ada perubahan `fs/crypto` maupun `libfscrypt` yang mengenai kita |

### 5.7 Peringatan berumur menengah: 32-bit

Komentar baru di `bionic/libc/SYSCALLS.TXT` 24.0, yang tidak ada di 23.2:

```
# especially in Chrome, and it probably makes more sense to just wait for x86
# to be removed than put the effort in.
# See http://b/423197304 for more background, and http://b/435724036 for advice
# on how to test WebView changes if you do decide to try to remove these before
# we just drop 32-bit entirely.
```

"before we just drop 32-bit entirely" adalah pernyataan niat, bukan jadwal. Tidak
memblokir 24.0. Tapi ini menaikkan nilai `plan-64bit/` — dan sekaligus tidak
mengubah vonisnya, karena kendala di sana (RAM 1,84 GB, partisi system tersisa
878 MB, 160 blob kamera tanpa padanan 64-bit) sama sekali tidak tersentuh oleh
niat Google.

---

## 6. Userspace

### 6.1 Forward-port fork ULH — 19 commit, terukur

Diukur dengan membandingkan tiap fork ULH `lineage-23.2` terhadap hulu
LineageOS `lineage-23.2`:

| Repo | Ahead | Isi |
|---|---:|---|
| `frameworks/native` | **9** | rantai GLES RenderEngine (6), SF backpressure, libbinder threadpool, display_intf_headers |
| `system/core` | **3** | cgroup v2 absen (2), camera feature extensions |
| `frameworks/av` | **2** | dua Revert OMX software codec |
| `hardware/qcom-caf/common` | **2** | Revert "QCOM: RIP pre-UM families" + Bring back legacy platform definitions |
| `bionic` | **1** | linker: partially allow text relocations |
| `system/sepolicy` | **1** | allow su domain in user builds (**tidak relevan** — A37 userdebug) |
| `Connectivity` | **1** | Do not require BTF on pre-5.15 |
| **Total** | **19** | |

Daftar commit lengkap, siap di-cherry-pick:

```
frameworks/native   e2e91300 Revert "Delete genTextures and deleteTextures from RenderEngine"
                    cd1402b9 Revert "Remove useFramebufferCache parameter in drawLayers()" and fix new code
                    c7f2fee2 Forward-port GLES Render Engine to 16 QPR2
                    93877b86 renderengine: gles: unconditionally skip PostRenderCleanup
                    fcc10e35 renderengine: gles: Fix QPR2 build errors
                    d4f1d339 renderengine: compilation fixes for 16 QPR1
                    9fe1c2a8 surfaceflinger: remove display_intf_headers dependency
                    b3ddc63b libbinder: make threadpool shrinking non-fatal
                    e4247554 SF: Bring back support for disabling backpressure propagation
system/core         61b57678 Fix support for devices without cgroupv2 support
                    90ef1146 Revert "libprocessgroup: CgroupSetup should fail if a required controller fails to mount"
                    f5f2bd6d Camera: Add feature extensions
frameworks/av       e0b8d0eb Revert "Remove source code of all the OMX software codec plugins"
                    2c60a0fd Revert "Disable building software OMX codecs"
qcom-caf/common     624fa247 Revert "QCOM: RIP pre-UM families"
                    7b118701 QCOM: Bring back legacy platform definitions
bionic              7001b90a linker: partially allow text relocations
Connectivity        9d842efa Do not require BTF on pre-5.15
system/sepolicy     83b174ea sepolicy: allow su domain in user builds        <- lewati
```

**Friksi yang sudah bisa diperkirakan:**

- **`system/core` cgroup (61b57678).** Menyentuh `init/service.cpp` dan
  `libprocessgroup/setup/cgroup_map_write.cpp`. Keduanya **masih ada** di 24.0
  (diperiksa: HTTP 200). Tapi 24.0 memperkenalkan `libprocessgroup_platform`
  (commit "libprocessgroup: Introduce libprocessgroup_platform") — refactor yang
  hampir pasti menggeser konteks hunk. Patch aslinya kecil (+3/-0 dan +3/-3) dan
  isinya membungkus blok gagal dengan `#if 0`, jadi konfliknya akan sepele
  diselesaikan, bukan sepele dihindari.

- **Rantai GLES RenderEngine (9 commit).** Ini yang terberat. `libs/renderengine`
  berubah nyata antara 23.2 dan 24.0:

  ```
  RenderEngine.cpp   + skia::Cache::initializeGraphiteDiskCache()
                     + skia::Cache::initializeGaneshDiskCache()  (dua tempat)
  Android.bp         ColorSpaces.cpp keluar dari skia/
                     + skia/compat/Base64.cpp, skia/compat/PipelineCallbackHandler.cpp
                     + libipcrenderbuffer_static (tiga tempat)
                     - skia/filters/KawaseBlurDualFilter.cpp
                     - cc_library_static librenderengine_includes
  ```

  Dan ada arah baru yang perlu diwaspadai — komentar di `RenderEngine.cpp:35`:

  ```cpp
  // TODO: b/341728634 - Don't compile Ganesh unless requested once Graphite is the stable default.
  ```

  Android 17 menambah backend **Graphite** (Vulkan). Jalur `GraphicsApi::GL` masih
  ada dan tetap memanggil `SkiaGLRenderEngine` (Ganesh), jadi 24.0 belum
  memutus apa pun. Tapi arah upstream jelas: Ganesh akan menyusul GLES.
  Untuk A37 — Adreno 306, `ro.opengles.version=196608`, tanpa Vulkan — itu berarti
  fork GLES ULH bukan solusi sementara, melainkan permanen.

### 6.2 Sepolicy QCOM legacy

`Ultra-Legacy-Hippeastrum/android_device_qcom_sepolicy` hanya punya
`lineage-22.2-legacy` sampai `lineage-23.2-legacy`. LineageOS punya
`lineage-24.0` dan `lineage-24.0-legacy-um`.

Jaraknya besar dan ini bukan rebase sepele:

```
ULH lineage-23.2-legacy  vs  LineageOS lineage-23.2-legacy-um
  ahead 641   behind 1672
```

Pohon pre-UM itu praktis proyek terpisah, bukan varian. **Rencana: pakai
`lineage-23.2-legacy` ULH apa adanya di 24.0 lebih dulu.** Sepolicy vendor
sebagian besar tidak bergantung versi platform, dan A37 tetap permissive
(`BoardConfig.mk:292`). Yang akan menggigit bukan runtime melainkan waktu build
— `sepolicy_test` dan `check_vintf_compatible` diadu terhadap `system/sepolicy`
24.0 yang berubah. Itu kelas kegagalan #10 dan #11 di 23.2, dan pola
penyelesaiannya sudah ada di kit 22.2.

### 6.3 Set patch n7000 — perbaiki alamatnya lebih dulu

`zhafknight/los_patches` sekarang punya tiga direktori:

```
los-20.0_n8000
los-23.2_n7000            50 patch   TANPA rantai BPF-less
los-23.2_n7000_bpfless    89 patch   DENGAN rantai BPF-less
```

Riwayatnya: `ecda2398 rename to bpfless` (25 Agu) lalu `476d134b add patch (drop
bpfless)` (25 Agu) — pemecahan menjadi dua profil, bukan penghapusan. Kit 23.2
kita menunjuk `los-23.2_n7000`, yang **sekarang salah**.

**Tindakan:** perbaiki `tools/patches.sh`, lalu **salin 89 patch itu ke repo
kit sendiri**. Alasannya bukan paranoia: direktori itu sudah pernah dipindah
sekali dalam dua minggu, dan patch yang menghilang di tengah rilis adalah
kegagalan yang tidak akan terdiagnosis cepat.

Rantai BPF-less, lengkap (21 patch):

```
Connectivity   036 Allow-failing-to-load-bpf-programs-for-BPF-less-devices
               037 Support-non-working-BPF-maps-on-old-BPF-less-kernel
               038 netd-Remove-4.14-kernel-restrictions
               039 More-bpf-errors-ignore
               040 Revert-netdupdatable-add-back-abort-on-init-fail
               041 Additional-bpf-prevent-crash
               042 Some-additional-handling-of-bpf-less-device
               043 NetBpfLoad-Relax-all-kernel-version-and-capability-checks   <- inti
               045 BpfHandler-and-BpfNetMaps-convert-fatal-errors-to-non-fatal
               046 treat-non-optional-BPF-program-load-failures-as-non-fatal
               047 Tethering-fall-back-to-modern-DNS-resolver
               048 net-Gracefully-fallback-when-eBPF-firewall-maps-are-unavailable
               091 ClatCoordinator-make-fatal-permission-result-non-fatal
DnsResolver    049 Dont-abort-if-the-DnsHelper-failed-to-init-on-BPF-less
system/bpf     050 Support-no-bpf-usecase
               051 Prepare-for-the-future-making-bpfloader.rs-fails-all
               052 bpfloader-relax-kernel-version-gates-and-fatal-errors
system/netd    053 Support-no-bpf-usecase
               054 Dont-abort-in-case-of-cgroup-bpf-setup-fail
               093 netd-make-controller-initialization-failures-non-fatal
system/vold    055 vold-use-sdcardfs-as-fallback-when-FUSE-BPF-is-unavailable
```

**Patch 043 harus disesuaikan untuk Android 17.** Ia dibuat untuk 23.2, ketika
gerbang 25Q4 masih `ALOGW` tanpa `return`. Di 24.0 gerbang itu punya `return 7`
(bagian 2, temuan 3). Periksa apakah patch itu sudah mencakupnya — kalau tidak,
tambahkan satu hunk. Ini kegagalan yang akan terlihat sebagai
`init: Service bpfloader ... reboot_on_failure` dan mudah salah didiagnosis
sebagai "patch tidak terpasang".

### 6.4 Patch lain yang layak diambil dari set 24.0-relevan

| Patch | Kenapa |
|---|---|
| `081 compatibility_matrices-restore-old-kernel-config-entries` | matriks VINTF menuntut config kernel yang 3.10 tak punya |
| `082 Restore-old-kernel-configs-and-lower-version-requirements` (`kernel/configs`) | pasangan dari 081 |
| `020 Disable-O_DIRECT-for-old-kernels` (`system/apex`) | sudah dipakai di 23.2 |
| `092 apexd-avoid-bootloader-reboot-on-bootstrap-failure` | sudah dipakai di 23.2 |
| `088 services-tolerate-unavailable-Power-HAL-hint-support` | terbukti penghenti boot di A37 23.2 |
| `095 reboot-must-be-fast-on-legacy-too` | kini juga ada di `legacy_support_patches` ULH |
| `098 linkerconfig-expose-gpsd-legacy-dependencies` | A37 memakai GPS legacy dari device tree |

Patch lokal A37 sendiri yang terbawa apa adanya, karena hulunya tidak berubah:

```
patches/bionic/0001-arc4random-jangan-abort-bila-kernel-tak-mengenal-MADV.patch
patches/bionic/0002-A37-kembalikan-rename-ke-syscall-renameat.patch
```

`arc4random.h` di bionic `lineage-24.0` diperiksa berkas demi berkas: masih
`async_safe_fatal("arc4random data MADV_WIPEONFORK failed: %m")` di baris 64,
`_rs_forkdetect()` masih stub kosong. Patch A37 menerap tanpa perubahan.

Yang tetap **DITOLAK**, alasannya tidak berubah:
`init-cap-SELinux-policy-version-on-pre-4.9-kernels` (kernel A37 punya xperms
penuh, dan spoof `"3.17"` untuk `init` membuat patch itu salah menyimpulkan),
dan `Revert-Remove-framework-support-for-audio-HIDL-HAL-V5` (audio 6.0 masih
terdaftar di `FactoryHal.cpp` 24.0).

---

## 7. Local manifest 24.0 — perbedaan dari `A37-23.xml`

Semua target `remove-project` diadu terhadap manifest 24.0. Hasilnya:

| Target | Status di 24.0 |
|---|---|
| `LineageOS/android_frameworks_native` | ADA |
| `LineageOS/android_system_core` | ADA |
| `LineageOS/android_bionic` | ADA |
| `LineageOS/android_system_sepolicy` | ADA |
| `platform/system/libhidl` | ADA |
| `platform/system/libhwbinder` | ADA |
| `platform/hardware/ril` | ADA |
| `LineageOS/android_hardware_qcom-caf_common` | ADA |
| `LineageOS/android_hardware_sony_timekeep` | **TIDAK ADA** |

Empat perubahan konkret:

**1. `timekeep`.** Dibuang dari manifest 24.0. Reponya masih ada dan **punya
branch `lineage-24.0`**. Karena `A37-23.xml` sudah menambahkannya sendiri
(bukan `remove-project`), cukup naikkan `revision` ke `lineage-24.0`.

**2. Daftar `linkfile` `qcom-caf/common` BERUBAH.** Dua entri dibuang di 24.0:

```diff
     <linkfile src="os_pickup_qssi.bp" dest="hardware/qcom-caf/msm8953/Android.bp" />
-    <!-- msm8996 (sudah dikomentari di 23.2) -->
-    <linkfile src="os_pickup.bp"      dest="hardware/qcom-caf/msm8998/Android.bp" />
     <linkfile src="os_pickup_qssi.bp" dest="hardware/qcom-caf/sdm660/Android.bp" />
-    <linkfile src="os_pickup_qssi.bp" dest="hardware/qcom-caf/sdm845/Android.bp" />
     <linkfile src="os_pickup_qssi.bp" dest="hardware/qcom-caf/sm8150/Android.bp" />
```

14 linkfile menjadi 12 (dihitung: `A37-23.xml` 14, snippets 24.0 12). Peringatan di kepala `A37-23.xml` berlaku penuh di sini:
`remove-project` + tambah-ulang menghapus **seluruh** linkfile milik entri resmi,
jadi selisih apa pun berarti symlink hilang, dan gejalanya muncul jauh kemudian
sebagai modul yang tidak ditemukan.

**3. Prebuilt GCC 4.9 harus ditambahkan sendiri** (lihat 4.1, jalur A-1):

```xml
<project name="LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9"
         path="prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9"
         remote="gh" revision="lineage-19.1" clone-depth="1" />
```

**4. Fork ULH tetap menunjuk `lineage-23.2`** untuk sementara, karena branch
24.0 belum ada. Begitu 19 commit di 6.1 selesai di-forward-port, pindahkan ke
branch sendiri (`rigaz29/...` `lineage-24`) — jangan menunggu ULH.

Sisanya sama: `device/qcom/sepolicy-legacy` dari ULH `lineage-23.2-legacy`,
tiga HAL QCOM msm8916 fork sendiri, dan tiga project perangkat.

Draf lengkapnya ada di `A37-24.xml` di direktori ini.

---

## 8. Vendor blob

**Tidak ada perubahan yang diperlukan.** Blob berasal dari ROM Android 10 dan
tidak peduli versi OS di atasnya; yang bisa memutusnya adalah pustaka platform
yang menghilang. Diperiksa dengan `readelf -d` atas seluruh 338 berkas:

```
libstdc++.so         161 blob   <- tetap dibangun bionic/libc/Android.bp di 24.0
libhidltransport.so   17 blob   <- dari fork ULH system/libhidl
libhidlbase.so        17 blob
libhwbinder.so        12 blob   <- dari fork ULH system/libhwbinder
libgui.so              5 blob
libEGL.so / libGLESv2  5 blob
libion.so              0 blob   <- lihat 5.1
android.hardware.configstore   0 blob
android.frameworks.displayservice  0 blob
```

Dua yang terakhir bernilai justru karena nol: penghapusan configstore dan
perpindahan displayservice **tidak menyentuh blob sama sekali**, hanya kode yang
dibangun dari sumber. Itu memperkecil risiko 5.2 dan 5.3 secara nyata.

Yang tetap harus dijaga: solusi `libstdc++_vendor` + symlink dari 23.2
(**bukan** menambahkan `/system/${LIB}` ke search path namespace vendor — itu
sudah dicoba, mematikan seluruh HAL AIDL vendor, dan penjelasan lengkapnya ada
di `patches/README-bpfless.md`).

---

## 9. Urutan kerja

Setiap fase punya syarat lulus. Jangan lanjut sebelum terpenuhi.

| Fase | Isi | Lulus bila |
|---|---|---|
| **0** | Verifikasi ulang seluruh klaim dokumen ini terhadap pohon nyata sesudah sync. Tentukan release config (`cp1a` atau `cp2a`). | daftar temuan tervalidasi; `lunch lineage_A37-<cfg>-userdebug` menghasilkan `TARGET_PRODUCT=lineage_A37` |
| **1** | Manifest + sync. Cabang `lineage-24` untuk kernel/DT/vendor. GCC prebuilt masuk. | 1067+ project sync nol error; `QCOM_BOARD_PLATFORMS` memuat msm8916 |
| **2** | **K-A saja.** Kernel terbangun dengan GCC. | `m -j8 bootimage` menghasilkan `KERNEL_OBJ/arch/arm64/boot/Image` |
| **3** | Forward-port 19 commit ULH ke 24.0. | tiga repo fork terbangun bersih |
| **4** | Device tree: ION, configstore, displayservice. Perbaiki alamat set n7000, salin patch ke repo sendiri. | ROM terbangun sampai `.zip` |
| **5** | Flash dan boot. Terapkan rantai BPF-less (21 patch, dengan penyesuaian 043 untuk gerbang 25Q4). | boot sampai homescreen; jaringan hidup |
| **6** | Uji SkiaGL hulu sekali; kalau abort `SkImage`, pasang fork GLES ULH. | nol abort `SkImage` di `logcat -b crash` |
| **7** | K-B (spoof 5.10.199) — **hanya kalau K-D dikerjakan**, kalau tidak lewati. K-C Tier 1. | tidak ada regresi |
| **8** | Opsional: penyetelan kernel, sepolicy enforcing, build `user` | ukur sebelum/sesudah |

**Fase 2 sengaja sendirian.** Di 23.2 milestone kernel dicapai gratis — 3.10.108
apa adanya kompilasi bersih. Di 24.0 justru di sinilah risiko terbesar berada,
dan menyatukannya dengan pekerjaan lain akan mengaburkan diagnosis.

Perhatikan bahwa **K-B pindah dari fase awal ke fase 7**. Di 23.2 ia sudah
diturunkan menjadi opsional; di 24.0 ia harus lebih jauh lagi ke belakang, karena
gerbang yang harus ditipu bertambah satu dan akibat salah pasangnya tetap sama:
bootloop.

---

## 10. Risiko

**Toolchain kernel (tinggi).** Satu-satunya risiko yang benar-benar baru di
rilis ini. Tiga jalan keluar sudah dipetakan (4.1) dan yang termurah tidak
memerlukan fork apa pun, tapi **belum satu pun diuji**. Kalau ketiganya buntu,
konsekuensinya bukan "ROM lebih lambat" melainkan "kernel tidak bisa dibangun
dari dalam pohon ROM".

**Tidak ada ULH 24.0 (sedang).** 19 commit adalah beban yang jelas, tapi angka
itu mengukur *jumlah*, bukan *kesulitan*. Rantai GLES RenderEngine berhadapan
dengan `libs/renderengine` yang sudah bergeser, dan patch cgroup `system/core`
berhadapan dengan refactor `libprocessgroup_platform`. `legacy_support_patches`
ULH masih aktif (commit terakhir 6 September 2026) — kalau branch 24.0 mereka
muncul di tengah jalan, itu menghemat pekerjaan, tapi **jangan menunggunya**.

**Grafis (sedang, dan memburuk perlahan).** SkiaGL terbukti menjatuhkan
SurfaceFlinger di Adreno 306 pada era Android 12. Skia terus berubah, jadi uji
sekali sebelum menganggap fork GLES wajib. Yang baru di 24.0: kedatangan
Graphite dan TODO b/341728634 menandakan Ganesh sendiri akan dicabut suatu saat.
Itu bukan masalah 24.0, tapi menetapkan bahwa fork GLES adalah beban permanen.

**Rantai BPF-less (rendah, tapi butuh perhatian).** Patch 043 dibuat ketika
gerbang 25Q4 belum fatal. Butuh satu hunk tambahan. Kegagalannya akan terlihat
persis seperti "patch tidak terpasang", jadi periksa isinya, bukan status
penerapannya.

**Ketergantungan pihak ketiga (rendah, mudah dihilangkan).** Set n7000 sudah
dipindah sekali. Salin ke repo sendiri di Fase 4 dan risiko ini hilang.

**Yang BUKAN risiko, dan layak dicatat supaya tidak dikhawatirkan ulang:**
syscall kernel (nol perubahan), HIDL (masih hidup), audio 6.0 (masih terdaftar),
userspace 32-bit (belum diblokir), blob vendor (nol yang tersentuh perubahan
24.0), Adiantum/FBE (tidak tersentuh).

---

## 11. Cara memeriksa ulang klaim di dokumen ini

Semua di bawah dijalankan tanpa perlu pohon yang sudah di-sync.

```sh
# Sasaran dan jumlah project
gh api repos/LineageOS/android/contents/default.xml?ref=lineage-24.0 --jq .content \
  | base64 -d | grep -E 'android-17|<project' | head

# API level penuh -> gerbang mana yang menyala
curl -s https://raw.githubusercontent.com/LineageOS/android_packages_modules_Connectivity/lineage-24.0/bpf/headers/include/bpf/BpfUtils.h \
  | grep -n 'isAtLeast2'

# Gerbang 25Q4 fatal atau tidak
for b in lineage-23.2 lineage-24.0; do echo "== $b"; \
  curl -s https://raw.githubusercontent.com/LineageOS/android_packages_modules_Connectivity/$b/bpf/loader/NetBpfLoad.cpp \
  | grep -A4 'isAtLeast25Q4'; done

# Jalur GCC sudah hilang atau belum
for b in lineage-23.2 lineage-24.0; do echo "== $b"; \
  curl -s https://raw.githubusercontent.com/LineageOS/android_vendor_lineage/$b/config/BoardConfigKernel.mk \
  | grep -cE 'KERNEL_TOOLCHAIN|CLANG_COMPILE|GCC_PREBUILTS'; done

# configstore masih ada atau tidak
gh api repos/LineageOS/android_hardware_interfaces/contents/configstore?ref=lineage-24.0 --jq '.[].name'

# Nol perubahan syscall
for b in lineage-23.2 lineage-24.0; do \
  curl -s https://raw.githubusercontent.com/LineageOS/android_bionic/$b/libc/SYSCALLS.TXT \
  | grep -vE '^\s*#|^\s*$' | sed 's/(.*//' | tr -d ' \t' | sort -u > /tmp/$b.lst; done
diff /tmp/lineage-23.2.lst /tmp/lineage-24.0.lst && echo "identik"

# Beban forward-port ULH
for r in android_frameworks_native android_system_core android_bionic \
         android_frameworks_av android_hardware_qcom-caf_common \
         android_packages_modules_Connectivity android_system_sepolicy; do
  printf '%-42s ' "$r"
  gh api "repos/Ultra-Legacy-Hippeastrum/$r/compare/LineageOS:lineage-23.2...Ultra-Legacy-Hippeastrum:lineage-23.2" --jq .ahead_by
done

# Delta Android 17 di perangkat Qualcomm lawas lain
gh api repos/Mi-Thorium/android_device_xiaomi_mithorium-common/compare/a16_qpr2/master...a17/master \
  --jq '.commits[].commit.message | split("\n")[0]'
```

---

## 12. Inventaris sumber

Yang sudah diunduh ke `ref/`:

```
build23     rigaz29/android_build_oppo_A37-23      kit 23.2 (PLAN-LOS23, PLAN-BACKPORT-KERNEL)
device23    rigaz29/rb_device_oppo_A37  lineage-23  792 berkas
vendor23    rigaz29/rb-vendor_oppo_A37  lineage-23  338 blob
kernel23    rigaz29/kernel_oppo_msm8939 lineage-23  3.10.108
```

Rujukan yang dipakai dan statusnya per 7 September 2026:

| Sumber | Branch tertinggi | Nilai |
|---|---|---|
| LineageOS | `lineage-24.0` | sasaran |
| Ultra-Legacy-Hippeastrum | `lineage-23.2` | 19 commit untuk di-forward-port; `legacy_support_patches` aktif (6 Sep) |
| acroreiser | `lineage-23.2` | pembanding kernel 3.10.108; tidak ada 24.0 |
| Mi-Thorium | `a17/master` | **satu-satunya rujukan Android 17 di perangkat QCOM lawas** — 8 commit |
| zhafknight | `los-23.2_n7000_bpfless` | 89 patch, termasuk rantai BPF-less |
| MisterZtr `LineageOS_gsi` | `lineage-23.2` | hulu bagi set n7000 |

Yang **belum** diperiksa dan sebaiknya diperiksa di Fase 0:

- `hardware/qcom-caf/msm8916/{audio,display,media}` fork sendiri terhadap
  perubahan `hardware/qcom-caf/common` 24.0 (kegagalan `display_defs.h` di 23.2
  datang dari sini)
- apakah HAL display yang dibangun dari sumber memerlukan `IDisplayService`
  (menentukan 5.3)
- `system/sepolicy` 24.0 versus sepolicy legacy ULH — kelas kegagalan
  `sepolicy_test` dan `check_vintf_compatible`
- apakah ada perilaku SurfaceFlinger yang hilang bersama `ISurfaceFlingerConfigs`
