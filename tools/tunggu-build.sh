#!/bin/bash
while pgrep -f 'a37-24/tools/build\.sh' >/dev/null; do sleep 30; done
echo "=== BUILD SELESAI ==="
tail -25 /root/a37-24/report/build.log
ls -la /root/a37-24/src/lineage-24/out/target/product/A37/lineage-24.0-*.zip 2>/dev/null|tail -3
