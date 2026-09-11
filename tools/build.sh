#!/bin/bash
# [A37] Build penuh LineageOS 24.0 untuk OPPO A37.
set -o pipefail
cd /root/a37-24/src/lineage-24 || exit 1
export SOONG_GOMEMLIMIT=24GiB
export LC_ALL=C
source build/envsetup.sh >/dev/null 2>&1 || exit 1
lunch lineage_A37-cp2a-userdebug >/dev/null 2>&1 || { echo "LUNCH GAGAL"; exit 1; }
echo "== mulai $(date +%F\ %T) TARGET_PRODUCT=$TARGET_PRODUCT =="
m bacon
rc=$?
echo "== selesai $(date +%F\ %T) rc=$rc =="
exit $rc
