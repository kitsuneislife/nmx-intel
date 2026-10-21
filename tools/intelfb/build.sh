#!/bin/bash
# Compila o NMIntelFB do nullmoth (kexts/NMIntelFB, framebuffer do painel interno ligado na Intel) com os nossos
# patches (source-fixes/intelfb/*.patch). Fonte: o clone em ~/nmx-build/nvidia-macos-driver, na revisão $REV.
# Saída: ~/nmx-build/intelfb/out/NMIntelFB.kext. Não versionamos o binário (licença PolyForm Noncommercial).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/../.." && pwd)
NM=${NM:-$HOME/nmx-build/nvidia-macos-driver}
REV=${REV:-v2.5.0}   # v2.1.0 and v2.3.6 give the same binary (kexts/NMIntelFB unchanged)
W=$HOME/nmx-build/intelfb
rm -rf "$W/src" "$W/out" && mkdir -p "$W/src" "$W/out/NMIntelFB.kext/Contents/MacOS"
git -C "$NM" archive "$REV" kexts/NMIntelFB | tar -x -C "$W/src" --strip-components 2
for p in "$HERE"/source-fixes/intelfb/intelfb-*.patch; do
  [ -f "$p" ] || continue
  patch -s -d "$W/src" -p1 < "$p"
  echo "patch: $(basename "$p")"
done
# intelfb-0011 needs NVKMS's kernel API headers, from NVIDIA's open-gpu-kernel-modules at the tag NVRM is built from
# (MIT/GPL; fetched once per tag, not versioned here). 2.5.0 moved NVRM to 615.78.08; the 610 and 615 headers give
# the same NMIntelFB binary (the members we use did not move).
OGKM_TAG=${OGKM_TAG:-615.78.08}; KAPI=$W/kapi-hdr-$OGKM_TAG
if [ ! -s "$KAPI/nvkms-kapi.h" ]; then
  mkdir -p "$KAPI"
  for f in nvidia-modeset/kapi/interface/nvkms-kapi.h common/sdk/nvidia/inc/nvtypes.h common/inc/nv_mig_types.h \
           nvidia/arch/nvalloc/unix/include/nv-gpu-info.h common/unix/common/inc/nv_dpy_id.h \
           common/unix/common/inc/nv_common_utils.h nvidia-modeset/interface/nvkms-api-types.h \
           nvidia-modeset/interface/nvkms-format.h common/sdk/nvidia/inc/cpuopsys.h common/sdk/nvidia/inc/nvlimits.h \
           common/sdk/nvidia/inc/nvmisc.h common/sdk/nvidia/inc/nvstatus.h common/sdk/nvidia/inc/nvstatuscodes.h; do
    curl -sfL -o "$KAPI/$(basename "$f")" "https://raw.githubusercontent.com/NVIDIA/open-gpu-kernel-modules/$OGKM_TAG/src/$f" \
      || { echo "could not fetch $f"; rm -f "$KAPI/nvkms-kapi.h"; exit 1; }
  done
fi
SDK=$(xcrun --show-sdk-path); KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
xcrun clang++ -arch x86_64 -fapple-kext -mkernel -nostdinc -I"$KHDR" -I"$W/src" -I"$KAPI" \
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -std=c++17 -fno-rtti -fno-exceptions -fno-builtin \
  -fno-common -Wall -Wno-unused-parameter -Wno-inconsistent-missing-override -O2 \
  -c "$W/src/intelfb.cpp" -o "$W/out/intelfb.o"
xcrun clang++ -arch x86_64 -fapple-kext -nostdlib -Xlinker -kext -lkmodc++ -lkmod -lcc_kext "$W/out/intelfb.o" \
  -o "$W/out/NMIntelFB.kext/Contents/MacOS/NMIntelFB"
cp "$W/src/Info.plist" "$W/out/NMIntelFB.kext/Contents/Info.plist"
codesign -f -s - "$W/out/NMIntelFB.kext" >/dev/null 2>&1 || true
echo "NMIntelFB $(shasum -a 256 "$W/out/NMIntelFB.kext/Contents/MacOS/NMIntelFB" | cut -c1-8) $(stat -f %z "$W/out/NMIntelFB.kext/Contents/MacOS/NMIntelFB") B ($REV)"
