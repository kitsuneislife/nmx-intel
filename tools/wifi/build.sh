#!/bin/bash
# Compila o driver de Wi-Fi MT7921 (SimpleMtkWlan, fork OverlordDev, versão Ethernet "stageB" para o Sequoia) com os
# nossos patches (source-fixes/wifi/*.patch). Fonte e MacKernelSDK fixados por commit; o build é o sequoia_build/build.sh
# do próprio fork (só Command Line Tools). Saída: ~/nmx-build/wifi/out/SimpleMtkWlan{,-diag}.kext. GPL-2.0; não
# versionamos o binário (o firmware MediaTek vai embutido).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/../.." && pwd)
W=$HOME/nmx-build/wifi
REPO=https://github.com/OverlordDev/SimpleMtkWlan.git; REV=${REV:-5b791c9cdc6368221a19b0d8eea6c6d5c0639709}
MKS_REPO=https://github.com/acidanthera/MacKernelSDK.git; MKS_REV=3f750085caa17ec3a7880f11c11bf4f48cd6a164
[ -d "$W/src/.git" ] || git clone -q "$REPO" "$W/src"
[ -d "$W/mks/.git" ] || git clone -q "$MKS_REPO" "$W/mks"
git -C "$W/mks" checkout -q "$MKS_REV"
git -C "$W/src" checkout -q -f -B nmx-wifi "$REV"
for p in "$HERE"/source-fixes/wifi/wifi-*.patch; do
  [ -f "$p" ] || continue
  git -C "$W/src" -c user.name=nmx -c user.email=nmx@localhost am -q "$p"
  echo "patch: $(basename "$p")"
done
( cd "$W/src/sequoia_build" && MKS="$W/mks" SOURCES=stageB bash build.sh ) > "$W/build.log" 2>&1 \
  || { tail -30 "$W/build.log"; echo "build falhou (log: $W/build.log)"; exit 1; }
rm -rf "$W/out" && mkdir -p "$W/out"
for k in SimpleMtkWlan SimpleMtkWlan-diag; do
  ditto "$W/src/sequoia_build/out/stageB/$k.kext" "$W/out/$k.kext"
  codesign -f -s - "$W/out/$k.kext" >/dev/null 2>&1 || true
  echo "$k $(shasum -a 256 "$W/out/$k.kext/Contents/MacOS/SimpleMtkWlan" | cut -c1-8) ($(git -C "$W/src" log --oneline -1))"
done
nm "$W/out/SimpleMtkWlan-diag.kext/Contents/MacOS/SimpleMtkWlan" >/dev/null
grep -q -a -- -mtkwlanoff "$W/out/SimpleMtkWlan-diag.kext/Contents/MacOS/SimpleMtkWlan" \
  || { echo "safe-boot switch missing from the binary"; exit 1; }
