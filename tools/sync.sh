#!/bin/bash
# Fase 1 repo sync. Pohon baru, tidak ada commit lokal -> --force-sync aman di sini.
cd /root/a37-24/src/lineage-24
log=/root/a37-24/src/sync.log
echo "=== mulai $(date -Is) ===" >> $log
for i in 1 2 3; do
  echo "--- percobaan $i $(date -Is) ---" >> $log
  repo sync -c -j6 --no-clone-bundle --no-tags --force-sync \
      --optimized-fetch >> $log 2>&1
  rc=$?
  echo "--- rc=$rc $(date -Is) disk=$(df -h /root|tail -1|awk '{print $4}') ---" >> $log
  [ $rc -eq 0 ] && break
  sleep 30
done
echo "=== selesai rc=$rc $(date -Is) ===" >> $log
exit $rc
