#!/bin/bash
export ADB_SERVER_SOCKET=tcp:100.117.21.64:5037
exec >>/root/a37-24/report/pantau-boot.log 2>&1
echo "===== $(date +%T) mulai memantau ====="
for i in $(seq 1 90); do
  S=$(adb shell 'echo "$(cut -d. -f1 /proc/uptime)|$(getprop sys.boot_completed)|$(getprop init.svc.zygote)|$(getprop init.svc.bootanim)|$(pgrep -c dex2oat 2>/dev/null)"' 2>/dev/null|tr -d '\r')
  [ -z "$S" ] && { echo "$(date +%T) PERANGKAT HILANG"; sleep 10; continue; }
  echo "$(date +%T) uptime=$(echo $S|cut -d'|' -f1)s boot_completed=[$(echo $S|cut -d'|' -f2)] zygote=$(echo $S|cut -d'|' -f3) bootanim=$(echo $S|cut -d'|' -f4) dex2oat=$(echo $S|cut -d'|' -f5)"
  [ "$(echo $S|cut -d'|' -f2)" = "1" ] && { echo "===== BOOT SELESAI pada $(date +%T) ====="; break; }
  sleep 20
done
