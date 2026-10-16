#!/bin/bash
# sudo bash tools/probe/install.sh         instala o diagnóstico de boot (roda em todo boot, 2 min, só lê)
# sudo bash tools/probe/install.sh remove  tira
set -e
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
P=/Library/LaunchDaemons/com.kitsune.nmxprobe.plist
if [ "${1:-}" = remove ]; then
  launchctl bootout system "$P" 2>/dev/null || true
  rm -f "$P"; rm -rf /usr/local/nmx-probe
  echo "removido"; exit 0
fi
H=$(cd "$(dirname "$0")" && pwd)
mkdir -p /usr/local/nmx-probe
clang -O1 -o /usr/local/nmx-probe/nmx-probe "$H/nmx-probe.c"
cp "$H/run.sh" /usr/local/nmx-probe/run.sh
cp "$H/com.kitsune.nmxprobe.plist" "$P"
chown -R root:wheel /usr/local/nmx-probe "$P"; chmod 755 /usr/local/nmx-probe/run.sh; chmod 644 "$P"
echo "instalado: no próximo boot, /Users/Shared/nmx-probe.txt"
