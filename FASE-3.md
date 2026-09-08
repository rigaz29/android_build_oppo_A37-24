# Fase 3 — forward-port ULH ke LineageOS 24.0

8 September 2026. **SELESAI.** 21 commit di 9 repo, semuanya ter-push dan SHA-nya
diverifikasi cocok antara lokal dan GitHub.

## Kenapa ini prasyarat, bukan lanjutan

Rencana awal menempatkan Fase 3 sesudah Fase 2 (kernel). **Itu keliru**, dan
ketahuan di percobaan build kedua: fork ULH `lineage-23.2` tidak bisa dipakai di
pohon 24.0 sama sekali. Bukan soal API, melainkan struktur repo — LineageOS 24.0
memecah `fs_mgr` keluar dari `system/core` menjadi project sendiri, sehingga
8 modul `snapuserd` plus `packagemanager_aidl_interface` terdefinisi ganda.

Karena analisis soong mencakup **seluruh** pohon, satu bentrokan di mana pun
memblokir semuanya — termasuk build kernel yang tidak menyentuh repo itu.

## Hasil

| Repo | Commit | Konflik | Basis |
|---|---:|---|---|
| `frameworks/native` | 9 | 5 hunk | LineageOS 24.0 |
| `system/core` | 3 | bersih | LineageOS 24.0 |
| `frameworks/av` | 2 | bersih | LineageOS 24.0 |
| `hardware/qcom-caf/common` | 2 | 1 hunk | LineageOS 24.0 |
| `bionic` | 1 | bersih | LineageOS 24.0 |
| `packages/modules/Connectivity` | 1 | bersih | LineageOS 24.0 |
| `system/libhidl` | 1 | bersih | AOSP `android-17.0.0_r1` |
| `system/libhwbinder` | 1 | bersih | AOSP `android-17.0.0_r1` |
| `hardware/ril` | 1 | bersih | AOSP `android-17.0.0_r1` |
| **Total** | **21** | **6 hunk** | |

`system/sepolicy` sengaja **tidak** ikut — lihat `FASE-2.md` §#1.

### Koreksi hitungan: 21, bukan 18

Fase 0 melaporkan 19 commit (18 sesudah `sepolicy` gugur). Angka itu terlalu
rendah karena tiga repo tidak terukur: `libhidl`, `libhwbinder`, dan
`hardware/ril` adalah fork **AOSP**, bukan LineageOS, sehingga
`compare/LineageOS:...` mengembalikan 404 dan diam-diam terlewat.

Diukur ulang terhadap tag `android-17.0.0_r1`: tepat satu commit relevan per
repo, di luar `Snap for`/`Merge`/`OWNERS`.

## Lima resolusi konflik di `frameworks/native`

Tidak satu pun berupa "pilih salah satu". Semuanya **pertahankan HEAD, tambahkan
ULH** — persis yang dimaksud judul commit `cd1402b9` "…and fix new code".

| Berkas | Resolusi |
|---|---|
| `RenderEngine.cpp` | jalur GL memakai `GLESRenderEngine` (ULH). Mengonfirmasi analisis `PLAN-LOS24.md` §7: ULH **mengganti** SkiaGL, bukan menambah pilihan |
| `Android.bp` | `ColorSpaces.cpp` (HEAD, pindah dari `skia/`) **dan** `Description.cpp` (era GLES) |
| `SkiaGLRenderEngine.cpp` | include Panopticon (HEAD) + path `../gl/GLExtensions.h` (ULH) — benar, karena `skia/GLExtensions.h` memang dihapus commit ini |
| `RenderEngineThreaded.cpp` | capture `panopticon::share()` (HEAD) + `useFramebufferCache` (ULH) |
| `SurfaceFlinger.cpp` | kondisi refactor HEAD + `cleanFramebufferCache()` dan penjaga `mPropagateBackpressure` (ULH) |

Dua commit hilir (`93877b86`, `fcc10e35`) menerap **bersih** begitu `c7f2fee2`
mendarat — persis seperti yang dibuktikan di Fase 0, dan 26 berkas `gl/` masuk
tanpa konflik sama sekali.

## Tiga temuan yang layak diwariskan

### 1. Git menandai baris yang bertabrakan, bukan konsekuensinya

Sesudah konflik `cd1402b9` selesai, `drawLayers` dan `drawLayersInternal` punya
parameter `useFramebufferCache` di header **dan** implementasi — tetapi **dua
pemanggilnya tidak**, karena barisnya berada di luar wilayah konflik sehingga
versi HEAD bertahan diam-diam:

```
RenderEngineThreaded.cpp:306   instance.drawLayersInternal(..., base::unique_fd(fd));
RenderEngineBench.cpp:194      re.drawLayers(display, layers, outputBuffer, base::unique_fd())
```

Keduanya akan gagal kompilasi jauh kemudian dengan galat yang tampak tidak
berhubungan.

**Aturan untuk sisa proyek ini: setiap konflik yang mengubah tanda tangan fungsi
harus diikuti audit SELURUH pemanggilnya**, termasuk yang tidak disentuh git.
Audit itu juga memeriksa `CompositionEngine/src/{Output,planner/CachedSet}.cpp`
— keduanya ternyata sudah benar, dibawa cherry-pick itu sendiri.

### 2. Patch ULH memuat salah ketik yang tidak pernah menggigit di pohon mereka

```c
#define SFTRACE_TAG SDTRACE_TAG_GRAPHICS
```

`SDTRACE_TAG_GRAPHICS` tidak ada di mana pun di seluruh pohon — diperiksa dengan
grep rekursif; satu-satunya kemunculan adalah penanda konflik itu sendiri.
Mengambil sisi ULH secara membabi buta berarti mengimpor makro tak terdefinisi.
Versi HEAD (`ATRACE_TAG ATRACE_TAG_GRAPHICS`) yang dipakai.

**Konsekuensinya untuk cara kerja: sisi ULH bukan sumber kebenaran.** Ia patch
untuk pohon lain; tiap barisnya tetap harus diadu dengan pohon kita.

### 3. Klon `--filter=blob:none` TIDAK BISA push ke repo kosong

```
remote: fatal: did not receive expected object 768011e1...
error: remote unpack failed: index-pack failed
```

Blob-nya tidak ada di lokal, jadi pack yang dikirim tidak lengkap.

Lima repo LineageOS lolos karena di-**fork server-side** lebih dulu (`gh repo
fork`), sehingga objek basisnya sudah ada di GitHub dan hanya delta yang
dikirim. Tiga repo AOSP dibuat kosong, jadi butuh riwayat penuh — diselesaikan
dengan klon penuh, yang murah karena ketiganya hanya 3-4 MB.

**Kaidahnya: fork server-side kalau hulunya ada di GitHub; klon penuh kalau
tidak.**

## Catatan tentang pelaporan status

Dua kali dalam fase ini laporan status saya salah karena logika shell — sempat
melaporkan `GAGAL` untuk lima push yang sebenarnya berhasil. Sejak itu setiap
push diverifikasi dengan **membandingkan SHA lokal dengan SHA di GitHub lewat
API**, bukan dengan menafsirkan keluaran perintah.

Sama halnya dengan `pgrep -f 'repo sync'` di Fase 1 yang mencocokkan command
line bash-nya sendiri sehingga menggantung 1 jam 21 menit. Polanya sama:
**periksa keadaan, jangan tafsirkan keluaran.**
