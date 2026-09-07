# Kit port LineageOS 24.0 — OPPO A37 (msm8916)

Lanjutan dari [`android_build_oppo_A37-23`](https://github.com/rigaz29/android_build_oppo_A37-23),
yang berakhir dengan ROM 23.2 yang boot, dipakai harian, dengan kamera AIDL dan
FBE Adiantum terbukti jalan.

Isinya hasil analisis kode sumber, bukan perkiraan.
**Fase 0 dan Fase 1 selesai.** Pohon 24.0 tersinkron (1236 project), `lunch` lolos.

| Berkas | Isi |
|---|---|
| [`PLAN-LOS24.md`](PLAN-LOS24.md) | Dokumen utama. Kernel, device tree, vendor blob, userspace, 9 fase kerja |
| [`FASE-0.md`](FASE-0.md) | Hasil verifikasi: 51 klaim, 18 cherry-pick ULH diuji nyata, release config |
| [`FASE-1.md`](FASE-1.md) | Manifest + sync: branch `lineage-24`, validasi 17 project, kendala ruang disk |
| [`tools/sync.sh`](tools/sync.sh) | `repo sync` dengan percobaan ulang dan catatan disk |
| [`A37-24.xml`](A37-24.xml) | Draf local manifest LOS 24.0 — sudah divalidasi parser XML |

## Sasaran

**LineageOS 24.0 = Android 17** (`refs/tags/android-17.0.0_r1`), API penuh 37.0,
1067 project. Release config **`cp2a`** — dari
`vendor/lineage/vars/aosp_target_release`; 23.2 memakai `bp4a`.

```sh
unset -f grep                            # jebakan lingkungan, masih berlaku
source build/envsetup.sh
lunch lineage_A37-cp2a-userdebug
```

## Lima temuan yang membentuk seluruh rencana

**1. Android 17 tidak menuntut satu pun fitur kernel baru.**
`bionic/libc/SYSCALLS.TXT` 23.2 lawan 24.0: **274 syscall lawan 274**, nol
tambahan, nol penghapusan. `arc4random.h` tidak berubah sama sekali. Backport
kernel yang sudah dikerjakan untuk 23.2 terbawa apa adanya.

**2. Blocker sesungguhnya bukan kernel, melainkan toolchain kernel.**
`vendor/lineage/config/BoardConfigKernel.mk` di 24.0 membuang **seluruh** jalur
GCC — dari 36 rujukan `KERNEL_TOOLCHAIN|CLANG_COMPILE|GCC_PREBUILTS` menjadi
**nol**. `kernel.mk:265` kini `KERNEL_CC := CC="clang" LD=ld.lld`, dan commit
`de40b978` mencabut prebuilt GCC 4.9 dari manifest. Kernel A37 3.10.108 mati di
`scripts/mod/devicetable-offsets.c` kalau dikompilasi clang.

Jalan keluarnya murah: `KERNEL_CC` hanya diset `ifeq ($(KERNEL_CC),)`, dan
`KERNEL_CROSS_COMPILE` tidak pernah di-assign di 24.0 — keduanya bebas diisi
device tree.

**3. Tiga hal benar-benar patah di Android 17.**
`configstore` dihapus total dari `hardware/interfaces`; `libion` dijadikan no-op
oleh AOSP lalu dipulihkan LineageOS di balik `soong_config_set_bool,libion,legacy_impl,true`;
`displayservice` HIDL pindah ke fork LineageOS. Gerbang NetBpfLoad 25Q4 naik dari
`ALOGW` menjadi `return 7` — batas kernel efektif 5.4 → 5.10.

**4. Belum ada fork `lineage-24.0` dari ULH maupun acroreiser.**
Keduanya mentok di `lineage-23.2`. Beban forward-portnya **19 commit** — dan
Fase 0 sudah menguji 18 di antaranya dengan cherry-pick nyata ke `lineage-24.0`:

| | commit | bersih | konflik | hunk |
|---|---:|---:|---:|---:|
| Total | 18 | **13** | 5 | 18 |

`system/core` yang semula dikhawatirkan (refactor `libprocessgroup_platform`)
justru bersih seluruhnya. Sisa konfliknya terpusat di satu commit —
`c7f2fee2 Forward-port GLES Render Engine`, 10 dari 18 hunk.

**5. Android 17 bukan patahan keras untuk perangkat Qualcomm lawas.**
Delta device tree Mi-Thorium `a16_qpr2/master` ke `a17/master` hanya **8 commit**,
dan tak satu pun menyentuh kernel.

## Backport kernel: berapa patch userspace yang benar-benar bisa dihapus

Dihitung dari daftar berkas patch yang sesungguhnya, bukan diperkirakan.

| Tier | Patch hilang | Ongkos kernel |
|---|---:|---|
| 1 — `epoll_pwait2`, MADV_WIPEONFORK, GpuWork tracepoint | **3** | ~2 commit |
| 2 — cgroup v2 penuh | **6** | ~985 commit |
| 3 — eBPF + BTF (butuh Tier 2 dulu) | **22** | ~470 commit |
| 4 — kernel tidak menolong | **58** | ∞ |

Backport kernel paling banyak menghapus **31 dari 89 patch dengan ongkos ~1.455
commit**, dan 58 sisanya tetap harus dikerjakan di userspace apa pun yang
terjadi. Hanya Tier 1 yang rasionya masuk akal.

## Basis

| Komponen | Sumber |
|---|---|
| Kernel | `rigaz29/kernel_oppo_msm8939` branch `lineage-23` |
| Device tree | `rigaz29/rb_device_oppo_A37` branch `lineage-23` |
| Vendor blob | `rigaz29/rb-vendor_oppo_A37` branch `lineage-23` |

## Rujukan

- [LineageOS](https://github.com/LineageOS) — manifest dan sumber `lineage-24.0`
- [Ultra-Legacy-Hippeastrum](https://github.com/Ultra-Legacy-Hippeastrum) — fork legacy, mentok `lineage-23.2`
- [acroreiser](https://github.com/acroreiser) — a6010 (msm8916, kernel 3.10.108), pembanding kernel
- [Mi-Thorium](https://github.com/Mi-Thorium) — satu-satunya rujukan Android 17 di perangkat QCOM lawas (`a17/master`)
- [zhafknight/los_patches](https://github.com/zhafknight/los_patches) — set `los-23.2_n7000_bpfless`, 89 patch

## Memeriksa ulang klaim di dokumen ini

Seluruh perintahnya ada di `PLAN-LOS24.md` bagian 11, dan tidak satu pun
memerlukan pohon yang sudah di-sync. Contoh yang paling menentukan:

```sh
# Nol perubahan syscall antara Android 16 dan 17
for b in lineage-23.2 lineage-24.0; do
  curl -s https://raw.githubusercontent.com/LineageOS/android_bionic/$b/libc/SYSCALLS.TXT \
  | grep -vE '^\s*#|^\s*$' | sed 's/(.*//' | tr -d ' \t' | sort -u > /tmp/$b.lst
done
diff /tmp/lineage-23.2.lst /tmp/lineage-24.0.lst && echo "identik"

# Jalur GCC sudah hilang
for b in lineage-23.2 lineage-24.0; do printf '%s: ' $b
  curl -s https://raw.githubusercontent.com/LineageOS/android_vendor_lineage/$b/config/BoardConfigKernel.mk \
  | grep -cE 'KERNEL_TOOLCHAIN|CLANG_COMPILE|GCC_PREBUILTS'
done
```
