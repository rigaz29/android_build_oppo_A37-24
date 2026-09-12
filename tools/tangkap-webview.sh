#!/bin/bash
export ADB_SERVER_SOCKET=tcp:100.117.21.64:5037
OUT=/root/a37-24/report/webview-boot
mkdir -p $OUT
exec >>$OUT/jejak.log 2>&1
echo "===== $(date +%T) menunggu perangkat hilang ====="
while [ "$(adb get-state 2>/dev/null)" = device ]; do sleep 1; done
echo "$(date +%T) perangkat hilang (reboot berjalan)"
while [ "$(adb get-state 2>/dev/null)" != device ]; do sleep 1; done
echo "$(date +%T) perangkat kembali -- menangkap log"
# ambil segera, sebelum buffer berputar
adb logcat -b all -d > $OUT/logcat-boot.txt 2>/dev/null
echo "logcat: $(wc -c < $OUT/logcat-boot.txt) byte"
for i in 1 2 3 4 5 6; do
  sleep 20
  adb shell 'dumpsys webviewupdate' > $OUT/dumpsys-$i.txt 2>/dev/null
  echo "$(date +%T) sample $i: $(grep -a 'Current WebView package' $OUT/dumpsys-$i.txt|head -1)"
done
adb logcat -b all -d > $OUT/logcat-lanjut.txt 2>/dev/null
echo "===== selesai $(date +%T) ====="
