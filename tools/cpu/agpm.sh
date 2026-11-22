#!/bin/bash
# agpm.sh: AGPM-1, GT RC6 with Apple's AGPM IGPU profile minus RCxControl and CPGControl (WhateverXe #87, rodgod-rr).
# The kext is codeless: it re-injects the AGPMController personality for this board-id with a higher probe score,
# built from this Mac's own AppleGraphicsPowerManagement.kext (Apple content, so it is generated, never committed).
#   sudo bash tools/cpu/agpm.sh arm        build the kext, arm ONE boot of the daily XE-15 config plus the kext
#   sudo bash tools/cpu/agpm.sh check TAG  in that boot: AGPM state, then xe15.sh check TAG and cpu-study.sh TAG
# The boot after the armed one is the daily config again (efi.sh boot-back). One variable: the AGPM profile.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-$USER}")
K=$HOMEU/nmx-build/agpm/AGPMNoRC.kext
SRC=/System/Library/Extensions/AppleGraphicsPowerManagement.kext/Contents/Info.plist
die() { echo "STOP: $*"; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"

case "${1:-}" in
arm)
    BID=$(ioreg -l -w0 -d2 -p IODeviceTree | sed -n 's/.*"board-id" = <"\(Mac-[0-9A-F]*\)">.*/\1/p' | head -1)
    [ -n "$BID" ] || die "no board-id in the device tree"
    mkdir -p "$K/Contents" || die "could not create $K"
    /usr/bin/python3 -I - "$SRC" "$BID" "$K/Contents/Info.plist" <<'EOF' || die "could not build the kext"
import plistlib, sys
src, bid, out = sys.argv[1:]
d = plistlib.load(open(src, "rb"))
pers = d["IOKitPersonalities"]["AGPM"]
entry = pers["Machines"][bid]                      # KeyError = no AGPM profile for this board-id
heur = entry["IGPU"]["Heuristic"]
gone = [k for k in ("RCxControl", "CPGControl") if heur.pop(k, None) is not None]
if not gone:
    sys.exit("the IGPU profile has neither RCxControl nor CPGControl: nothing to test")
p = {k: v for k, v in pers.items() if k != "Machines"}
p.update({"IOProbeScore": 5000, "Machines": {bid: entry}})
plistlib.dump({
    "CFBundleDevelopmentRegion": "English", "CFBundleIdentifier": "com.nmx.agpm-norc",
    "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "AGPMNoRC", "CFBundlePackageType": "KEXT",
    "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1.0", "OSBundleRequired": "Root",
    "IOKitPersonalities": {"AGPM-nmx": p},
}, open(out, "wb"))
print(f"AGPMNoRC.kext for {bid}: removed {', '.join(gone)}")
EOF
    plutil -lint "$K/Contents/Info.plist" >/dev/null || die "Info.plist does not parse"
    chown -R "${SUDO_USER:-root}" "$HOMEU/nmx-build/agpm"
    AGPM_KEXT=$K WEXDIR=wex-xe15c WEX_EXTRA="-wex-objpreempt -wex-noccs -wex-hostrps-max" \
        bash "$HERE/../hybrid/efi.sh" wexrtx || die "efi.sh wexrtx failed"
    echo "AGPM-1 armed for one boot. Reboot now."
    ;;
check)
    TAG=${2:?usage: $0 check TAG}
    OUT=$HOMEU/agpm-$TAG.txt
    {
        echo "== $(date '+%F %T') AGPM-1 check"
        echo "loaded: $(kextstat -l -b com.nmx.agpm-norc 2>/dev/null)"
        ioreg -l -w0 > /tmp/agpm-ioreg.$$
        echo "RCxControl entries (want 0): $(grep -c RCxControl /tmp/agpm-ioreg.$$)"
        echo "CPGControl entries (want 0): $(grep -c CPGControl /tmp/agpm-ioreg.$$)"
        grep -o '"IOProbeScore" = 5000' /tmp/agpm-ioreg.$$ | head -1
        rm -f /tmp/agpm-ioreg.$$
    } > "$OUT" 2>&1
    chown "${SUDO_USER:-root}" "$OUT"
    cat "$OUT"
    bash "$HERE/../hybrid/xe15.sh" check "agpm-$TAG" > /dev/null 2>&1
    bash "$HERE/cpu-study.sh" "agpm-$TAG"
    echo "saved $OUT, $HOMEU/xe15-agpm-$TAG.txt, $HOMEU/cpu-study-agpm-$TAG.txt"
    ;;
*) die "usage: sudo bash $0 arm | check TAG" ;;
esac
