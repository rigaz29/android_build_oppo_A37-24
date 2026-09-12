#!/bin/bash
# [A37] Memberi boot waktu penuh. Bukan tambalan: properti persist dan layanan
# bootwatchdog memang dirancang menerima ini.
export ADB_SERVER_SOCKET=tcp:100.117.21.64:5037
exec >>/root/a37-24/report/beri-waktu.log 2>&1
echo "===== $(date +%T) menunggu perangkat ====="
while [ "$(adb get-state 2>/dev/null)" != device ]; do sleep 1; done
echo "$(date +%T) ROM muncul"
adb shell 'setprop persist.a37.bootwatchdog.timeout 1800' 2>&1
adb shell 'setprop ctl.stop bootwatchdog' 2>&1
sleep 2
echo "watchdog: $(adb shell getprop init.svc.bootwatchdog 2>&1)"
echo "batas tersimpan: $(adb shell getprop persist.a37.bootwatchdog.timeout 2>&1)"
# pantau kemajuan boot
for i in $(seq 1 60); do
  BC=$(adb shell getprop sys.boot_completed 2>/dev/null|tr -d '\r')
  echo "$(date +%T) boot_completed=[$BC] zygote=$(adb shell getprop init.svc.zygote 2>/dev/null|tr -d '\r') uptime=$(adb shell cut -d. -f1 /proc/uptime 2>/dev/null|tr -d '\r')s"
  [ "$BC" = "1" ] && { echo "===== BOOT SELESAI ====="; break; }
  sleep 20
done
