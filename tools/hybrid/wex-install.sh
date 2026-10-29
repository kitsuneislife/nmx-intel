#!/bin/bash
# wex-install.sh: the macOS side of the WhateverXe route (b00t0x's WhateverXe + WhateverXe Graphics, Apple's TGL
# driver on the Iris Xe). Replaces the NootedGreen stack that tools/hybrid/install.sh put in /Library.
#   sudo bash tools/hybrid/wex-install.sh          install
#   sudo bash tools/hybrid/wex-install.sh remove   take the WhateverXe Graphics files out again
# The pkg's TGL kexts list a7a8 in their personalities, and Apple's framebuffer (IOProbeScore 80000) outranks
# NMIntelFB (61000) in the IOFramebuffer category. Booted without WhateverXe (the GPU-only config) they would take the
# iGPU unpatched. So both personalities get IOPropertyMatch nmx-wex=<01>, a property only config-wex.plist injects
# (wex-config.py): the GPU-only route keeps NMIntelFB. Same kind of Info.plist edit install.sh made for NootedGreen.
# Download first: gh release download v0.3.2 --repo b00t0x/WhateverXe-Graphics (into ~/nmx-build/whateverxe/dl).
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HOMEU=$(eval echo "~${SUDO_USER:-root}")
PKG=$HOMEU/nmx-build/whateverxe/dl/WhateverXe-Graphics-0.3.2.pkg
PKGSHA=7ac6c7149248c483efbd93555294d587a93d81392421f3af8a4f5b1b5fcc0101
EXT=/Library/Extensions; GB=/Library/GPUBundles
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
KB=/System/Library/KernelCollections/BootKernelExtensions.kc; KS=/System/Library/KernelCollections/SystemKernelExtensions.kc
K=/System/Library/Kernels/kernel; KARG=(--allow-missing-kdk); [ -f "$K" ] && KARG+=(--kernel "$K")
FB=$EXT/AppleIntelTGLGraphicsFramebuffer.kext/Contents/Info.plist; AC=$EXT/AppleIntelTGLGraphics.kext/Contents/Info.plist
T=$(mktemp -d)
BAK=$HOMEU/AuxiliaryKernelExtensions.kc.antes-wex
# after the pkg ran, its postinstall has put an ungated collection in place: any later failure puts the old one back
fail() { echo "$1"; [ -n "${PKGRAN:-}" ] && cp -p "$BAK" "$KC" && echo "previous kext collection put back"; exit 1; }

if [ "${1:-}" = remove ]; then
    # the file list of WhateverXe-Graphics' uninstall.sh (it leaves CoreMedia alone below Tahoe)
    for n in AppleIntelTGLCompat AppleIntelTGLGraphics AppleIntelTGLGraphicsFramebuffer; do rm -rf "$EXT/$n.kext"; done
    for n in AppleIntelTGLGraphicsGLDriver AppleIntelTGLGraphicsMTLDriver AppleIntelTGLGraphicsVADriver XeCompilerAdapter XeMetalCompiler; do
        rm -rf "$GB/$n.bundle"; done
    rm -rf "$GB/XeOpenCL"
    for c in Common BigSur Monterey Ventura Sonoma Sequoia Tahoe; do
        pkgutil --pkg-info "org.b00t0x.WhateverXe.$c" >/dev/null 2>&1 && pkgutil --forget "org.b00t0x.WhateverXe.$c" >/dev/null
    done
    echo "removed"
else
    [ -f "$PKG" ] || { echo "no $PKG"; exit 1; }
    [ "$(shasum -a 256 "$PKG" | cut -d' ' -f1)" = "$PKGSHA" ] || { echo "$PKG: wrong SHA-256; nothing changed"; exit 1; }
    cp -p "$KC" "$BAK" || { echo "could not back up the kext collection; nothing changed"; exit 1; }
    # NootedGreen's stack (install.sh): its TGL kexts and bundles share paths and bundle IDs with the pkg's
    for n in AppleIntelTGLGraphics.kext AppleIntelTGLGraphicsFramebuffer.kext HookCase.kext AppleIntelGraphicsShared.bundle \
             AppleIntelTGLGraphicsGLDriver.bundle AppleIntelTGLGraphicsMTLDriver.bundle AppleIntelTGLGraphicsVADriver.bundle \
             AppleIntelTGLGraphicsVAME.bundle; do rm -rf "$EXT/$n"; done
    rm -rf "$GB/AppleIntelTGLGraphicsMTLDriver.bundle" "$GB/AppleIntelGraphicsShared.bundle" /System/Library/Caches/xe.bundle
    echo "installing $(basename "$PKG") (its postinstall rebuilds the kext collection, 1-2 min)..."
    PKGRAN=1
    installer -pkg "$PKG" -target / >"$T/installer.log" 2>&1 || { tail -20 "$T/installer.log"; fail "installer failed"; }
    for P in "$FB" "$AC"; do [ -f "$P" ] || fail "the pkg did not install $P"; done
    # data <01>, so it equals the DeviceProperty wex-config.py injects
    /usr/bin/python3 -I - "$FB" AppleIntelFramebufferController "$AC" Gen7 <<'EOP' || fail "could not gate the TGL personalities"
import plistlib, sys
a = sys.argv[1:]
for path, pers in zip(a[0::2], a[1::2]):
    with open(path, "rb") as f:
        p = plistlib.load(f)
    p["IOKitPersonalities"][pers]["IOPropertyMatch"] = {"nmx-wex": b"\x01"}
    with open(path, "wb") as f:
        plistlib.dump(p, f)
EOP
fi

NEWKC="$KC.nmx-intel-new"; rm -f "$NEWKC"
echo "rebuilding the kext collection (1-2 min)..."
kmutil create -n aux --volume-root / "${KARG[@]}" -B $KB -S $KS --repository "$EXT" -A "$NEWKC" -z >"$T/kmutil.log" 2>&1 \
    || { tail -20 "$T/kmutil.log"; fail "kmutil failed"; }
INS=$(kmutil inspect -a x86_64 -A "$NEWKC" 2>/dev/null) || { rm -f "$NEWKC"; fail "could not read the new collection"; }
for k in com.nullmoth.NVRM com.nullmoth.NVRMFB com.nullmoth.NVAccel com.nullmoth.NMIntelFB com.flxxxxddd.AirportMtkWlan; do
    printf '%s\n' "$INS" | grep -qw "$k" || { rm -f "$NEWKC"; fail "$k is missing from the new collection"; }
done
if [ "${1:-}" != remove ]; then
    for k in org.b00t0x.AppleIntelTGLCompat com.apple.driver.AppleIntelTGLGraphics com.apple.driver.AppleIntelTGLGraphicsFramebuffer; do
        printf '%s\n' "$INS" | grep -qw "$k" || { tail -20 "$T/kmutil.log"; rm -f "$NEWKC"; fail "kmutil left out $k"; }
    done
    for P in "$FB" "$AC"; do
        /usr/libexec/PlistBuddy -c 'Print' "$P" > "$T/p.txt" && grep -q 'nmx-wex' "$T/p.txt" || { rm -f "$NEWKC"; fail "gate missing in $P"; }
    done
fi
mv -f "$NEWKC" "$KC" && rm -rf "$T" || fail "could not replace the collection"
[ "${1:-}" = remove ] || echo "TGLCompat $(defaults read "$EXT/AppleIntelTGLCompat.kext/Contents/Info" CFBundleVersion), gate nmx-wex on both TGL personalities"
echo "done. Reboot; the GPU-only config leaves these idle. tools/hybrid/efi.sh wex switches the EFI."
