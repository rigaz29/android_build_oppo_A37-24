#!/bin/bash
# Terapkan seluruh tambalan A37 ke pohon LineageOS 24.0 yang baru disinkronkan.
#
# Menggantikan pola fork: repo tetap milik hulu, perubahan hidup sebagai patch di
# repo kit ini. Konsekuensinya skrip ini WAJIB dijalankan ulang setiap kali
# `repo sync` menyentuh repo yang ditambal.
#
#   PERINGATAN: `repo sync --force-sync` membuang perubahan lokal TANPA bertanya,
#   termasuk hasil skrip ini. Selalu jalankan ulang sesudahnya.
#
# Pemakaian:  tools/apply-patches.sh /jalur/ke/pohon [--check]
#   --check   hanya menguji, tidak menerapkan apa pun
set -u
TREE="${1:-}"; MODE="${2:-}"
[ -n "$TREE" ] && [ -d "$TREE" ] || { echo "pakai: $0 <pohon> [--check]"; exit 1; }
DIR="$(cd "$(dirname "$0")/.." && pwd)/patches"
[ -d "$DIR" ] || { echo "direktori patches tidak ada: $DIR"; exit 1; }

ok=0; skip=0; gagal=0
for pd in "$DIR"/*/; do
  name="$(basename "$pd")"
  repo="$TREE/${name//_//}"
  # lineage-sdk memakai tanda hubung, bukan garis bawah
  [ -d "$repo" ] || repo="$TREE/$name"
  if [ ! -d "$repo/.git" ] && [ ! -f "$repo/.git" ]; then
    echo "  LEWAT   $name (repo tidak ada)"; skip=$((skip+1)); continue
  fi
  for p in "$pd"*.patch; do
    [ -f "$p" ] || continue
    b="$(basename "$p")"
    if git -C "$repo" apply --check --reverse "$p" >/dev/null 2>&1; then
      echo "  SUDAH   $name/$b"; skip=$((skip+1)); continue
    fi
    if ! git -C "$repo" apply --check "$p" >/dev/null 2>&1; then
      echo "  KONFLIK $name/$b"; gagal=$((gagal+1)); continue
    fi
    if [ "$MODE" = "--check" ]; then
      echo "  BISA    $name/$b"; ok=$((ok+1)); continue
    fi
    if git -C "$repo" am --keep-cr --3way "$p" >/dev/null 2>&1; then
      echo "  OK      $name/$b"; ok=$((ok+1))
    else
      git -C "$repo" am --abort >/dev/null 2>&1
      if git -C "$repo" apply "$p" >/dev/null 2>&1; then
        echo "  OK*     $name/$b (apply, bukan am)"; ok=$((ok+1))
      else
        echo "  GAGAL   $name/$b"; gagal=$((gagal+1))
      fi
    fi
  done
done
echo "──────────────────────────────────────────"
echo "  diterapkan=$ok  dilewati=$skip  gagal=$gagal"
[ "$gagal" -eq 0 ]
