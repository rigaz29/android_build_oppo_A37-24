# Fase 2 — kernel

7 September 2026. **Sedang berjalan.**

Fase paling berisiko dari seluruh port ini, dan sengaja dikerjakan sendirian:
di 23.2 milestone kernel dicapai gratis (3.10.108 apa adanya kompilasi bersih),
di 24.0 justru di sinilah blocker terbesarnya.

## Syarat lulus

| | status |
|---|---|
| A. kernel 3.10.108 terbangun dengan GCC 4.9 dari pohon 24.0 | **LULUS** |
| B. `m -j8 bootimage` menghasilkan `KERNEL_OBJ/arch/arm64/boot/Image` | menunggu |

Dipecah dua karena keduanya menguji hal berbeda. A menguji **premisnya** —
apakah toolchainnya masih sanggup sama sekali. B menguji **integrasinya** —
apakah `KERNEL_CC` benar-benar menang atas default clang di dalam sistem build.
A bisa dijalankan tanpa soong, jadi tidak berbalapan dengan konversi partial
clone yang sedang menghapus-dan-mengambil-ulang `build/*` dan `prebuilts/*`.

## A. Kernel terbangun dengan GCC 4.9 — LULUS

Mandiri, tanpa soong, tanpa `vendor/lineage`:

```sh
GCC=prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-
make -C kernel/oppo/msm8939 O=$OUT ARCH=arm64 CROSS_COMPILE=$GCC lineageos_a37f_defconfig
make -C kernel/oppo/msm8939 O=$OUT ARCH=arm64 CROSS_COMPILE=$GCC -j8 Image
```

```
rc=0
arch/arm64/boot/Image   18.578.872 byte
2963 satuan kompilasi, 25 warning, nol error
kompiler: real-aarch64-linux-android-gcc (GCC) 4.9.x 20150123 (prerelease)
```

Pembanding 23.2: kernel 18.327.160 byte. Selisih 251 KB wajar untuk sumber yang
sama dengan konfigurasi yang sama.

**Artinya prebuilt GCC 4.9 yang dikembalikan `A37-24.xml` memang berfungsi**, dan
kernel 3.10.108 tidak menuntut apa pun dari Android 17. Yang tersisa murni soal
sistem build.

## B. Perubahan `BoardConfig.mk` untuk integrasi

Diterapkan, belum diuji:

```make
A37_KERNEL_GCC := $(abspath $(TOPDIR))prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin
KERNEL_CC := CC="$(CCACHE_BIN) $(A37_KERNEL_GCC)/aarch64-linux-android-gcc"
KERNEL_CROSS_COMPILE := CROSS_COMPILE="$(A37_KERNEL_GCC)/aarch64-linux-android-"
```

Kenapa ini sah, bukan akal-akalan:

- `KERNEL_CC` **didokumentasikan** sebagai knob device tree di `kernel.mk:53`,
  dan gerbangnya `kernel.mk:264` adalah `ifeq ($(KERNEL_CC),)` — nilai dari
  device tree menang, default clang tidak pernah terpasang.
- `KERNEL_CROSS_COMPILE` **tidak pernah di-assign** di mana pun pada 24.0; ia
  hanya diekspansi di baris perintah make (`kernel.mk:283`, `291`, `299`).
- Urutan include sudah diperiksa: `build/make/core/config.mk:502` meng-include
  `BoardConfigLineage.mk` **sesudah** `BoardConfig.mk` device dibaca, jadi kedua
  nilai sudah terpasang saat gerbang `ifeq` dievaluasi.

Dua baris lama `TARGET_KERNEL_CLANG_COMPILE := false` dan
`TARGET_KERNEL_LLVM_BINUTILS := false` **sengaja dipertahankan** meski kini
no-op senyap — sebagai catatan sejarah, dengan komentar yang menyatakan bahwa
keduanya tidak lagi dibaca siapa pun di 24.0.

### Satu benturan yang sudah diketahui dan dibiarkan sadar

`vendor/lineage/config/BoardConfigKernel.mk:113-114` di 24.0 menambahkan:

```make
KERNEL_MAKE_FLAGS += HOSTCFLAGS="$(KERNEL_HOST_C_LD_FLAGS_SYSROOT) -I.../kernel-build-tools/include"
KERNEL_MAKE_FLAGS += HOSTLDFLAGS="$(KERNEL_HOST_C_LD_FLAGS_SYSROOT) ... -fuse-ld=lld --rtlib=compiler-rt"
```

lalu `KERNEL_MAKE_FLAGS += $(TARGET_KERNEL_ADDITIONAL_FLAGS)` **sesudahnya**.
Karena flag make yang belakangan menang, `HOSTCFLAGS` milik A37 menimpa milik
hulu — dan sysroot `glibc2.17-4.8` itu ikut hilang.

Itu **disengaja**: sysroot glibc 2.17 tidak cocok dengan gcc host modern (mesin
ini gcc 13.3). `HOSTLDFLAGS` hulu tidak tertimpa dan tetap aktif. Dicatat di
`BoardConfig.mk` supaya tidak ada yang "memperbaikinya" tanpa tahu sebabnya.

## Catatan operasional

Build B ditunda sampai konversi partial clone reda. Alasannya bukan kehati-hatian
berlebih: konversi itu menghapus-dan-mengambil-ulang `build/make`, `build/soong`,
`prebuilts/build-tools`, dan `prebuilts/clang` — semuanya build-kritis. Build yang
gagal karena repo hilang di tengah jalan akan menghasilkan diagnosis yang
menyesatkan, dan kit 23.2 sudah penuh contoh berapa mahal itu.
