# Fase 4 — rantai BPF-less

8 September 2026. **SELESAI (kompilasi terverifikasi).**

Kernel A37 adalah 3.10.108 dan **tidak punya eBPF sama sekali**. Yang fatal
bukan kegagalan jalur BPF-nya — itu memang diharapkan — melainkan reaksinya:
proses mati, `init` menghidupkannya lagi karena `reboot_on_failure`, dan
perangkat tidak pernah boot.

## Syarat lulus

| | hasil |
|---|---|
| Rantai BPF-less terpasang | **22 patch** |
| Kompilasi bersih | **rc=0**, 9 modul |
| Tidak bootloop, jaringan hidup tanpa BPF | **belum diuji** — butuh perangkat |

## Set patch diamankan lebih dulu

22 patch disalin ke `patches/` di repo ini. `PLAN-LOS24.md` §6.3 menandai ini
wajib: direktori `zhafknight/los_patches` sudah pernah dipindah sekali di tengah
rilis (`los-23.2_n7000` → `los-23.2_n7000_bpfless`, 25 Agustus 2026), dan patch
yang menghilang di tengah jalan adalah kegagalan yang tidak terdiagnosis cepat.

Koreksi hitungan: **22 patch, bukan 21** seperti tertulis di rencana.

## Hasil: 9 menerap bersih, 13 di-port

| Repo | Bersih | Di-port |
|---|---:|---:|
| `packages/modules/Connectivity` | 4 | 9 |
| `system/bpf` | 2 | 1 |
| `system/netd` | 1 | 2 |
| `packages/modules/DnsResolver` | 0 | 1 |
| `system/vold` | 1 | 0 |
| `frameworks/native` | 1 | 0 |

Sebabnya struktural: patch aslinya untuk 23.2 mengandaikan pola `failed = true`
di `NetBpfLoad.cpp`, sedangkan 24.0 memakai `return N`.

### Kekeliruan metodologi yang sempat terjadi

Saya menduga kegagalannya soal **urutan** — patch berurutan yang diuji satu per
satu dari basis yang sama akan memberi kegagalan palsu, persis cacat alat ukur
di Fase 0. Diuji ulang sebagai rantai, hasilnya **sama persis** (4 bersih,
9 gagal). Hipotesisnya salah; ini memang porting sungguhan.

Yang justru benar soal urutan: di `system/bpf`, patch `052` gagal berdiri
sendiri tapi bersih setelah `050` mendarat.

## Jalur fatal yang TIDAK ada di patch aslinya

Wajar — patch itu ditulis untuk 23.2, dan sebagian jalur ini baru di 24.0 atau
memang terlewat. Ditemukan lewat audit, bukan lewat siklus build:

- **8 `createDir("/sys/fs/bpf/…")`** — kernel 3.10 tidak punya filesystem bpf,
  jadi `/sys/fs/bpf` tidak pernah ter-mount
- **`loadAllObjects()`** dengan `"--- DO NOT EXPECT SYSTEM TO BOOT SUCCESSFULLY ---"`
  dan `sleep(20)`
- **Sanity check enumerasi prog/map** — kernel tanpa syscall `bpf` memberi
  `ENOSYS`, bukan `ENOENT` yang diharapkan kode
- **17 getter map di `BpfNetMaps.java`** yang melempar `IllegalStateException`.
  Ini jalur boot `system_server` yang sesungguhnya dan tidak disentuh patch
  mana pun.

Yang terakhir ditangani di **satu titik**: `initBpfMaps` dibungkus `try/catch`
di `ensureInitialized`, bukan menambal 49 lemparan satu per satu. Yang penting
`sInitialized` tetap tersetel supaya pemanggil berikutnya tidak mencoba lagi
tanpa henti.

## Dua bug DI DALAM patch aslinya

`git apply` sukses bukan berarti patch itu benar. Patch `036` menerap bersih
lalu gagal kompilasi:

```
BpfHandler.cpp:150:10: error: use of undeclared identifier 'isOk'
```

1. **`isOk(x)` tidak ada di 24.0.** `attachProgramToCgroup` mengembalikan
   `Result<void>`, jadi yang benar `x.ok()`.

2. **Patch aslinya memeriksa `ret` DUA KALI:**

```cpp
auto ret  = attachProgramToCgroup(BPF_EGRESS_PROG_PATH, ...);
if (!isOk(ret))  { ALOGE("Failed loading egress program"); }
auto ret2 = attachProgramToCgroup(BPF_INGRESS_PROG_PATH, ...);
if (!isOk(ret))  { ALOGE("Failed loading ingress program"); }   // ret, bukan ret2
```

`ret2` tidak pernah diperiksa. Tidak pernah menggigit di pohon mereka karena
egress dan ingress selalu gagal bersamaan di perangkat BPF-less, sehingga
pesannya tetap muncul dan tidak ada yang curiga.

Keduanya diperbaiki, bukan direproduksi setia.

## Ketidakkonsistenan hulu yang ikut terungkap

`service-connectivity` **tidak bisa dikompilasi terhadap `frameworks/base`-nya
sendiri**:

```
ConnectivityService.java:263  symbol not found
    android.net.NetworkPolicyManager$AllowedTransportsCallback
ConnectivityService.java:791  cannot find symbol
    method notifyDenylistChanged(int[],int[])
```

Diperiksa, dan keduanya di HEAD hulu masing-masing — jadi celah hulu, bukan
pohon usang:

```
frameworks/base  lokal b19a3e2e = hulu b19a3e2e   nol kecocokan kedua simbol
Connectivity     fork  7c04d866 = hulu 7c04d866   merujuk keduanya
```

Ini menghadang perangkat LineageOS 24.0 mana pun, bukan hanya A37, dan
**bukan bagian rantai BPF-less** — karena itu di-commit terpisah.

Setelah simbol pertama, saya berhenti menebak satu per satu dan menyisir
**seluruh** pemanggilan `mPolicyManager`: dari enam metode, tepat dua yang
hilang. Satu siklus audit menggantikan entah berapa siklus build — pelajaran
yang sama seperti audit pemanggil `drawLayers` di Fase 3.

Konsekuensi yang diterima, dicatat spesifik:
- kebijakan transport-per-uid tidak diterapkan; di perangkat tanpa eBPF mesin
  itu memang tidak berfungsi sejak awal
- ikon firewall di UI tidak memantulkan perubahan denylist, tapi
  **pemblokirannya sendiri tetap diterapkan** lewat `replaceFirewallChain`

## Yang SENGAJA tidak dilucuti

Validasi argumen (`Invalid firewall chain`), rc script hilang atau ganda,
gerbang kernel ≥6.2 yang memang tidak menyala di 3.10, dan `execve`. Melucuti
itu berarti menyembunyikan kegagalan yang sungguhan.

`[[noreturn]]` di `BpfMap.h` **dibuang bersama `abort()`** — menghapus salah
satunya saja adalah undefined behavior.

## Alat baru: `verify/cek-manifest.sh`

Dibuat setelah **tiga kali** salah menyalin atribut `groups` saat menambahkan
fork ke local manifest. Ia membandingkan `groups` dan daftar `linkfile` tiap
project yang kita ganti terhadap entri hulunya.

Begitu dijalankan pertama kali, ia langsung menemukan **tiga kesalahan lama
dari Fase 3** yang tidak pernah saya sadari:

```
BEDA frameworks/native              groups: lokal='pdk' hulu='pdk,sysui-studio'
BEDA frameworks/av                  groups: lokal='pdk' hulu='pdk,sysui-studio'
BEDA packages/modules/Connectivity  groups: lokal='pdk' hulu='pdk-cw-fs,pdk-fs'
```

Ketiganya diperbaiki; manifest kini cocok seluruhnya dengan hulu.

## Verifikasi kompilasi

Target modul, **bukan** `bootimage` — `bootimage` tidak menyentuh Connectivity,
netd, vold, maupun DnsResolver, jadi build hijau di sana tidak membuktikan apa
pun tentang fase ini.

```
netbpfload  libnetd_updatable  bpfloader  netd  vold  libnetd_resolv
framework-connectivity-t  service-connectivity  gpuservice        rc=0
```

Kesembilan modul mencakup setiap berkas yang disunting.

## Yang BELUM terbukti

Kompilasi bersih bukan bukti perangkat boot. Yang menunggu perangkat:
- apakah `bpfloader` benar-benar berhenti memicu `reboot_on_failure`
- apakah `netd` tidak lagi crash-loop
- apakah `system_server` melewati init `ConnectivityService`
- apakah jaringan benar-benar hidup tanpa BPF
- statistik data per-aplikasi dan firewall berbasis BPF **tidak akan** berfungsi;
  itu harga yang disepakati di `PLAN-LOS24.md` §K2b, bukan regresi
