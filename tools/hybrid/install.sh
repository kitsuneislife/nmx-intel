#!/bin/bash
# install.sh: puts the hybrid route's macOS side in place (what Julio's macos/install-macos.sh does), then rebuilds the
# auxiliary kext collection the way tools/intelfb/install.sh does and checks nullmoth's kexts are still in it.
# Apple's TGL kexts match only the spoofed 9A49 (accelerator, after the plutil edit) or 9A49/A7A0/FF20 (framebuffer),
# never our a7a8, so they stay idle under the GPU-only config [inferred]. Build first: zsh tools/hybrid/build.sh
#   sudo bash tools/hybrid/install.sh          install
#   sudo bash tools/hybrid/install.sh remove   take it all out again
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HOMEU=$(eval echo "~${SUDO_USER:-root}")
XPS=$HOMEU/nmx-build/hybrid/xps; OUT=$XPS/macos/out
SLE=$XPS/build/deps/NootedGreen/sle_Internal/sle; LE=$XPS/build/deps/NootedGreen/sle_Internal/le
EXT=/Library/Extensions; GB=/Library/GPUBundles; XE=/System/Library/Caches/xe.bundle
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
KB=/System/Library/KernelCollections/BootKernelExtensions.kc; KS=/System/Library/KernelCollections/SystemKernelExtensions.kc
K=/System/Library/Kernels/kernel; KARG=(--allow-missing-kdk); [ -f "$K" ] && KARG+=(--kernel "$K")
TGLK="AppleIntelTGLGraphics.kext AppleIntelTGLGraphicsFramebuffer.kext"
HCK=$XPS/build/HookCase.kext   # NootedGreen's symbol library: both TGL kexts depend on org.smichaud.HookCase
TGLB="AppleIntelTGLGraphicsMTLDriver AppleIntelTGLGraphicsGLDriver AppleIntelTGLGraphicsVADriver AppleIntelTGLGraphicsVAME AppleIntelGraphicsShared"
T=$(mktemp -d)
put() { rm -rf "$2" && ditto "$1" "$2" && chown -R root:wheel "$2" || { echo "could not copy $1"; exit 1; }; echo "  $2"; }

if [ "${1:-}" = remove ]; then
    for k in $TGLK HookCase.kext; do rm -rf "$EXT/$k"; done
    for b in $TGLB; do rm -rf "$EXT/$b.bundle"; done
    rm -rf "$GB/AppleIntelTGLGraphicsMTLDriver.bundle" "$GB/AppleIntelGraphicsShared.bundle" "$XE"
    echo "removed"
else
    [ -d "$OUT/xe.bundle" ] && [ -d "$OUT/AppleIntelTGLGraphicsMTLDriver.bundle" ] || { echo "no $OUT: run zsh tools/hybrid/build.sh"; exit 1; }
    [ -f "$HCK/Contents/MacOS/HookCase" ] || { echo "no $HCK: run zsh tools/hybrid/build.sh"; exit 1; }
    [ -d "$LE/AppleIntelTGLGraphics.kext" ] && [ -d "$SLE/AppleIntelGraphicsShared.bundle" ] || { echo "no NootedGreen sle_Internal: run zsh tools/hybrid/build.sh"; exit 1; }
    for k in $TGLK; do put "$LE/$k" "$EXT/$k"; done
    put "$HCK" "$EXT/HookCase.kext"
    P=$EXT/AppleIntelTGLGraphics.kext/Contents/Info.plist
    # the accelerator matches the spoofed device-id (9A49) and needs a version above the stock one (Julio's installer)
    plutil -replace IOKitPersonalities.Gen7.IOPCIPrimaryMatch -string 0x9a498086 "$P" \
        && plutil -replace CFBundleVersion -string 16.0.2 "$P" || { echo "could not edit $P"; exit 1; }
    for b in $TGLB; do put "$SLE/$b.bundle" "$EXT/$b.bundle"; done
    put "$OUT/AppleIntelTGLGraphicsMTLDriver.bundle" "$GB/AppleIntelTGLGraphicsMTLDriver.bundle"
    put "$SLE/AppleIntelGraphicsShared.bundle" "$GB/AppleIntelGraphicsShared.bundle"
    put "$OUT/xe.bundle" "$XE"
    echo "MTL driver $(shasum -a 256 "$GB/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver" | cut -c1-8), libxedrv $(shasum -a 256 "$GB/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/libxedrv.dylib" | cut -c1-8)"
fi

[ -f "$HOMEU/AuxiliaryKernelExtensions.kc.antes-hybrid" ] || cp -p "$KC" "$HOMEU/AuxiliaryKernelExtensions.kc.antes-hybrid"
NEWKC="$KC.nmx-intel-new"; rm -f "$NEWKC"
echo "rebuilding the kext collection (1-2 min)..."
kmutil create -n aux --volume-root / "${KARG[@]}" -B $KB -S $KS --repository "$EXT" -A "$NEWKC" -z >"$T/kmutil.log" 2>&1 \
    || { tail -20 "$T/kmutil.log"; echo "kmutil failed; the collection is unchanged"; exit 1; }
INS=$(kmutil inspect -a x86_64 -A "$NEWKC" 2>/dev/null) || { echo "could not read the new collection"; rm -f "$NEWKC"; exit 1; }
for k in com.nullmoth.NVRM com.nullmoth.NVRMFB com.nullmoth.NVAccel com.nullmoth.NMIntelFB com.flxxxxddd.AirportMtkWlan; do
    printf '%s\n' "$INS" | grep -qw "$k" || { echo "$k is missing from the new collection; unchanged"; rm -f "$NEWKC"; exit 1; }
done
if [ "${1:-}" != remove ]; then
    for k in org.smichaud.HookCase com.xxxxx.driver.AppleIntelTGLGraphics com.xxxxx.driver.AppleIntelTGLGraphicsFramebuffer; do
        printf '%s\n' "$INS" | grep -qw "$k" || { tail -20 "$T/kmutil.log"; echo "kmutil left out $k; unchanged"; rm -f "$NEWKC"; exit 1; }
    done
fi
mv -f "$NEWKC" "$KC" && rm -rf "$T" || { echo "could not replace the collection"; exit 1; }
echo "done. The GPU-only config ignores these; tools/hybrid/efi.sh hybrid switches the EFI."
