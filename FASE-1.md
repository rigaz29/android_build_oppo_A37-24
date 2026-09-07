# Fase 1 — manifest dan sync

7 September 2026. **SELESAI — ketiga syarat lulus terpenuhi.**

## Syarat lulus

| | hasil |
|---|---|
| 1067+ project sync nol error | **1236 / 1236**, nol `.git` hilang, nol baris fatal |
| `lunch lineage_A37-cp2a-userdebug` → `TARGET_PRODUCT=lineage_A37` | **terpenuhi** |
| `QCOM_BOARD_PLATFORMS` memuat msm8916 | **terpenuhi** |

```
TARGET_PRODUCT           lineage_A37        PLATFORM_VERSION      17
TARGET_DEVICE            A37                PLATFORM_SDK_VERSION  37
TARGET_BOARD_PLATFORM    msm8916            TARGET_BUILD_VARIANT  userdebug
TARGET_ARCH              arm                TARGET_RELEASE        cp2a
TARGET_KERNEL_ARCH       arm64              QCOM_HARDWARE_VARIANT msm8916

repo sync   rc=0   193 GB   sisa disk 59 GB
```

## 1. Yang sudah tuntas

### Tiga branch `lineage-24` dibuat

Local manifest menunjuk branch yang **belum ada** — sync akan gagal tanpa ini.
Dibuat dari `lineage-23` supaya ROM 23.2 yang stabil tidak pernah tersentuh:

```
rigaz29/rb_device_oppo_A37    lineage-24  bc04b737
rigaz29/kernel_oppo_msm8939   lineage-24  756cb462
rigaz29/rb-vendor_oppo_A37    lineage-24  1a23fb28
```

### `repo init` dan validasi manifest

```
repo init -u https://github.com/LineageOS/android.git -b lineage-24.0 \
          --git-lfs --no-clone-bundle

.repo/manifests/default.xml   1067 project
                              revision="refs/tags/android-17.0.0_r1"
repo manifest                 rc=0, 1236 project (default + snippets + lokal)
```

Ketujuh belas project A37 teresolusi, nol hilang — diperiksa dengan parser XML
atas keluaran `repo manifest`, bukan dengan membaca berkas sumbernya:

```
device/oppo/A37                    rigaz29/rb_device_oppo_A37          lineage-24
kernel/oppo/msm8939                rigaz29/kernel_oppo_msm8939         lineage-24
vendor/oppo                        rigaz29/rb-vendor_oppo_A37          lineage-24
prebuilts/gcc/.../aarch64-4.9      LineageOS/android_prebuilts_gcc...  lineage-19.1
frameworks/native                  ULH/android_frameworks_native       lineage-23.2
system/core                        ULH/android_system_core             lineage-23.2
bionic                             ULH/android_bionic                  lineage-23.2
system/sepolicy                    ULH/android_system_sepolicy         lineage-23.2
system/libhidl                     ULH/android_system_libhidl          lineage-23.2
system/libhwbinder                 ULH/android_system_libhwbinder      lineage-23.2
hardware/ril                       ULH/android_hardware_ril            lineage-23.2
hardware/qcom-caf/common           ULH/android_hardware_qcom-caf_common lineage-23.2
device/qcom/sepolicy-legacy        ULH/android_device_qcom_sepolicy    lineage-23.2-legacy
hardware/qcom-caf/msm8916/audio    rigaz29/android_hardware_qcom_audio lineage-23
hardware/qcom-caf/msm8916/display  rigaz29/android_hardware_qcom_display lineage-22
hardware/qcom-caf/msm8916/media    rigaz29/android_hardware_qcom_media lineage-22
hardware/sony/timekeep             LineageOS/android_hardware_sony_timekeep lineage-24.0
```

Seluruh 17 branch juga dicek keberadaannya lewat API **sebelum** sync dimulai.
Kegagalan di jam ketiga karena satu branch salah nama adalah biaya yang tidak
perlu.

## 2. Dua temuan operasional

### `--fail-fast=false` tidak sah di repo 2.65

Percobaan pertama mati dalam hitungan detik:

```
main.py: error: --fail-fast option does not take a value
```

`--fail-fast` adalah flag tanpa nilai. Dibuang dari `tools/sync.sh`.

### Jebakan `grep` dari 23.2 TIDAK berlaku di mesin ini

`RILIS.md` dan `PLAN-LOS23.md` §8b mencatat bahwa `lunch` gagal untuk semua
product karena `grep` adalah **fungsi shell** yang mengalihkan ke `ugrep`,
sehingga `envsetup.sh:588` (`local legacy=$(echo $1 | grep "-")`) menghasilkan
string kosong.

Diperiksa di mesin ini:

```
type -t grep   ->  alias        (grep --color=auto)
ugrep          ->  tidak ada
profil         ->  nol rujukan ugrep
```

`grep` di sini **alias**, bukan fungsi — dan alias tidak diekspansi di skrip
non-interaktif, jadi `envsetup.sh` memakai `/usr/bin/grep`. `unset -f grep`
tetap tidak berbahaya dan tetap dipakai sebagai jaring pengaman, tapi jangan
salah mendiagnosis kegagalan `lunch` di sini sebagai jebakan itu.

## 3. Perintah sync

```sh
repo sync -c -j6 --no-clone-bundle --no-tags --force-sync --optimized-fetch
```

`--force-sync` aman **hanya di sini** karena pohonnya baru dan belum ada satu
pun commit lokal. Sesudah Fase 3 mulai menaruh commit, berlaku peringatan keras
dari kit 23.2: pada 1 September 2026 `--force-sync` menghapus 47 dari 61 patch
tanpa peringatan, dan kerusakannya baru ketahuan lewat lima kegagalan build
berturut-turut yang seluruhnya salah didiagnosis. Mulai Fase 3, cadangkan dulu.

`-j6`, bukan `-j8`: mesin ini 11,7 GB RAM dan pengalaman 23.2 menunjukkan
paralelisme tinggi ditebas pengawas memori.

## 4. Kendala ruang disk — dicatat sekarang, menggigit di Fase 2

```
tersedia sebelum sync   252 GB
perkiraan pohon 24.0    ~180 GB   (23.2 = 173 GB pada 993 project; 24.0 = 1067)
sisa untuk out/         ~70 GB
```

Catatan build 23.2: `out/` tumbuh dari 13 GB menjadi **71 GB**, dan pengemasan
OTA butuh ~10 GB transien di luar pohon. Jadi ruangnya **pas-pasan, bukan lega**.

Yang bisa dilakukan sebelum Fase 2, diurutkan dari yang paling murah:

1. `ccache -M 6G && ccache -c` saat tahap pengemasan (tidak memperlambat apa pun,
   karena pengemasan tidak mengompilasi)
2. hapus `ref/` (982 MB) dan `verify/trees/` (1,2 GB) — keduanya klon repo publik
   yang bisa diambil ulang
3. kalau tetap kurang: `repo sync` ulang dengan `--partial-clone`

Kegagalan disk penuh **tidak selalu menghentikan build** — catatan Adiantum 23.2
mencatat `apexd_host` dan `system.img` terpotong diam-diam, dan ninja
menganggapnya selesai karena stempel waktunya berubah. 357 berkas harus dibuang
dan dibangun ulang. Jangan menyalakan build besar tanpa pemantau ruang disk.


---

## 5. Dua temuan yang mengubah dokumen rencana

### 5a. Jebakan senyap: release config yang salah TIDAK menolak

Ini yang paling berbahaya dari seluruh Fase 1. Ketiga release config diterima
`lunch` **tanpa satu pun galat**, dan hanya satu yang benar:

```
lunch lineage_A37-cp2a-userdebug   RELEASE_PLATFORM_VERSION=CP2A  SDK=37  PLATFORM_VERSION=17
lunch lineage_A37-cp1a-userdebug   RELEASE_PLATFORM_VERSION=CP1A  SDK=36  PLATFORM_VERSION=16
lunch lineage_A37-bp4a-userdebug   RELEASE_PLATFORM_VERSION=BP4A  SDK=36  PLATFORM_VERSION=16
```

`PLAN-LOS24.md` versi pertama mencantumkan `cp1a` sebagai kandidat yang setara.
Kalau itu yang dipakai, seluruh pohon 24.0 membangun **Android 16** — diam-diam,
dan gejalanya baru muncul jauh kemudian sebagai ketidakcocokan yang tampak acak.

`build/release/release_configs/` memuat sebelas config; `vendor/lineage` hanya
menyediakan `cp2a.textproto`. Yang menentukan `vendor/lineage/vars/aosp_target_release`.

### 5b. KOREKSI: klaim `BoardConfigQcom.mk` di §5.5 SALAH

`PLAN-LOS24.md` §5.5 menulis bahwa A37 "tidak pernah meng-include
`BoardConfigQcom.mk` sama sekali". Diukur di pohon nyata, itu keliru:

```
vendor/lineage/config/BoardConfigLineage.mk:9-11
    ifeq ($(BOARD_USES_QCOM_HARDWARE),true)
        include hardware/qcom-caf/common/BoardConfigQcom.mk
    endif

device/oppo/A37/BoardConfig.mk:468
    BOARD_USES_QCOM_HARDWARE := true
```

Hasil sesudah `lunch`:

```
BOARD_USES_QCOM_HARDWARE        = true
QCOM_HARDWARE_VARIANT           = msm8916     <- di 23.2 tercatat KOSONG
TARGET_COMPILE_WITH_MSM_KERNEL  = true
```

A37 **memang** meng-include berkas itu — lewat `vendor/lineage`, bukan langsung.

Kesimpulan praktisnya tidak berubah: A37 tetap tidak perlu menyetel
`TARGET_COMPILE_WITH_MSM_KERNEL` sendiri seperti Mi-Thorium. Tapi sebabnya
berbeda dari yang ditulis — bukan karena berkasnya tak pernah dibaca, melainkan
karena fork ULH masih memuat baris itu (`BoardConfigQcom.mk:283`), dan
`624fa247` yang kita cherry-pick justru mengembalikannya.

**Pelajaran yang lebih penting dari koreksinya sendiri:** klaim itu diwarisi dari
`PLAN-LOS23.md` §8b dan tidak pernah diukur ulang di pohon 24.0. Fase 0 memeriksa
51 klaim terhadap *sumber hulu*, tapi klaim ini hanya bisa gugur di *pohon yang
sudah dirakit*. Temuan yang diwarisi antar rilis adalah hipotesis, bukan fakta.

---

## 6. Keadaan disk sesudah sync

```
pohon      193 GB      (perkiraan 180 GB — meleset 13 GB ke atas)
sisa       59 GB
```

Build 23.2 mencatat `out/` tumbuh sampai **71 GB** plus ~10 GB transien untuk
pengemasan OTA. **59 GB tidak cukup.** Ini harus diselesaikan sebelum Fase 2,
bukan saat build sudah berjalan.

Yang tersedia, diurutkan dari yang paling murah:

| Tindakan | Hemat | Ongkos |
|---|---:|---|
| hapus `ref/` dan `verify/trees/` | ~2,2 GB | nol — keduanya klon repo publik |
| `ccache -M 6G` saat pengemasan | bervariasi | nol; pengemasan tidak mengompilasi |
| hapus `.repo/project-objects` yang tidak dipakai | bervariasi | perlu `repo sync -l` untuk pulih |
| `repo sync --partial-clone` ulang | puluhan GB | perlu jaringan saat build |
| tambah disk | — | di luar kendali sesi ini |

Yang **tidak** boleh dilakukan: menyalakan build besar dan berharap cukup.
Catatan Adiantum 23.2 mencatat bahwa disk penuh tidak menghentikan build — ia
meninggalkan `apexd_host` dan `system.img` terpotong yang lolos sebagai "sudah
dibangun" karena stempel waktunya berubah, dan 357 berkas harus dibuang dan
dibangun ulang.
