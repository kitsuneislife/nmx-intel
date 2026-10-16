#!/bin/bash
# Compila o NMIntelFB do nullmoth (kexts/NMIntelFB, framebuffer do painel interno ligado na Intel) com os nossos
# patches (source-fixes/intelfb-*.patch). Fonte: o clone em ~/nmx-build/nvidia-macos-driver, na revisão $REV.
# Saída: ~/nmx-build/intelfb/out/NMIntelFB.kext. Não versionamos o binário (licença PolyForm Noncommercial).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/../.." && pwd)
NM=${NM:-$HOME/nmx-build/nvidia-macos-driver}
REV=${REV:-v2.1.0}
W=$HOME/nmx-build/intelfb
rm -rf "$W/src" "$W/out" && mkdir -p "$W/src" "$W/out/NMIntelFB.kext/Contents/MacOS"
git -C "$NM" archive "$REV" kexts/NMIntelFB | tar -x -C "$W/src" --strip-components 2
for p in "$HERE"/source-fixes/intelfb-*.patch; do
  [ -f "$p" ] || continue
  patch -s -d "$W/src" -p1 < "$p"
  echo "patch: $(basename "$p")"
done
SDK=$(xcrun --show-sdk-path); KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
xcrun clang++ -arch x86_64 -fapple-kext -mkernel -nostdinc -I"$KHDR" -I"$W/src" \
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -std=c++17 -fno-rtti -fno-exceptions -fno-builtin \
  -fno-common -Wall -Wno-unused-parameter -Wno-inconsistent-missing-override -O2 \
  -c "$W/src/intelfb.cpp" -o "$W/out/intelfb.o"
xcrun clang++ -arch x86_64 -fapple-kext -nostdlib -Xlinker -kext -lkmodc++ -lkmod -lcc_kext "$W/out/intelfb.o" \
  -o "$W/out/NMIntelFB.kext/Contents/MacOS/NMIntelFB"
cp "$W/src/Info.plist" "$W/out/NMIntelFB.kext/Contents/Info.plist"
codesign -f -s - "$W/out/NMIntelFB.kext" >/dev/null 2>&1 || true
echo "NMIntelFB $(shasum -a 256 "$W/out/NMIntelFB.kext/Contents/MacOS/NMIntelFB" | cut -c1-8) $(stat -f %z "$W/out/NMIntelFB.kext/Contents/MacOS/NMIntelFB") B ($REV)"
