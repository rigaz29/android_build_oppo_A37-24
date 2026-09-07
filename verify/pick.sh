#!/bin/bash
# Uji cherry-pick nyata commit ULH ke lineage-24.0. Tidak mengubah apa pun permanen.
r=$1; shift
cd /root/a37-24/verify/trees/$r || exit 1
git checkout -q -B uji origin/lineage-24.0 2>/dev/null || git checkout -q -B uji lineage-24.0
ok=0; conf=0; empty=0
for c in "$@"; do
  subj=$(git log -1 --format=%s "$c" 2>/dev/null | cut -c1-58)
  out=$(git cherry-pick -x "$c" 2>&1)
  if [ $? -eq 0 ]; then ok=$((ok+1)); printf "  \033[32mBERSIH\033[0m   %.8s %s\n" "$c" "$subj"
  elif echo "$out" | grep -q 'allow-empty\|nothing to commit'; then
    empty=$((empty+1)); printf "  \033[36mKOSONG\033[0m   %.8s %s (sudah ada di hulu)\n" "$c" "$subj"; git cherry-pick --skip -q 2>/dev/null || git cherry-pick --abort 2>/dev/null
  else
    conf=$((conf+1))
    files=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
    n=$(git diff --name-only --diff-filter=U | wc -l)
    printf "  \033[31mKONFLIK\033[0m  %.8s %s\n           %s berkas: %s\n" "$c" "$subj" "$n" "$files"
    git cherry-pick --abort 2>/dev/null
  fi
done
printf "  ── %s: bersih=%d konflik=%d kosong=%d\n" "$r" "$ok" "$conf" "$empty"
