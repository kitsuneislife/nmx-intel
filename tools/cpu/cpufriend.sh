#!/bin/bash
# cpufriend.sh: CPUFRIEND-1, does the frequency vector's EPP (0x80, balanced) hold the all-core clock down?
# EPP-1 showed machdep.xcpm.epp_override is read only, so the vector has to be replaced at boot: CPUFriend (Lilu
# plugin, acidanthera 1.3.0) plus a codeless CPUFriendDataProvider.kext carrying this Mac's own board-id resource
# plist with only the `epp` tunable changed in each FrequencyVector. Apple content: generated, never committed.
#   sudo bash tools/cpu/cpufriend.sh arm       ONE boot of the daily config (XE-15 + AGPMNoRC) plus CPUFriend
#   sudo bash tools/cpu/cpufriend.sh keep      same, as the daily config
#   sudo bash tools/cpu/cpufriend.sh check TAG in that boot: CPUFriend state, xe15.sh check, cpu-study.sh
# Knobs (pass with sudo VAR=...): EPP=0x20 sets the epp tunable (CPUFRIEND-1), HWP=off switches XCPM's HWP off
# (CPUFRIEND-2). Change one per test. With neither set it stops. WEX_ADD="a=1 b=2" appends boot-args (rtd3.sh).
# Rollback from keep: sudo bash tools/cpu/agpm.sh keep (the daily without CPUFriend).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-$USER}")
B=$HOMEU/nmx-build/cpufriend
CPUF=$B/dl/x/CPUFriend.kext
PROV=$B/CPUFriendDataProvider.kext
AGPM=$HOMEU/nmx-build/agpm/AGPMNoRC.kext
EPP=${EPP:-}
HWP=${HWP:-}
die() { echo "STOP: $*"; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"

case "${1:-}" in
arm|keep)
    ROUTE=wexrtx; [ "$1" = keep ] && ROUTE=wexrtx-keep
    [ -n "$EPP$HWP" ] || die "set EPP=0x.. or HWP=off (one per test)"
    [ -f "$CPUF/Contents/MacOS/CPUFriend" ] || die "no $CPUF (unzip CPUFriend-1.3.0-RELEASE.zip into $B/dl/x)"
    [ -f "$AGPM/Contents/Info.plist" ] || die "no $AGPM (run agpm.sh keep first)"
    BID=$(ioreg -l -w0 -d2 -p IODeviceTree | sed -n 's/.*"board-id" = <"\(Mac-[0-9A-F]*\)">.*/\1/p' | head -1)
    [ -n "$BID" ] || die "no board-id in the device tree"
    RES=/System/Library/Extensions/IOPlatformPluginFamily.kext/Contents/PlugIns/X86PlatformPlugin.kext/Contents/Resources/$BID.plist
    [ -f "$RES" ] || die "no X86PlatformPlugin resource plist for $BID"
    mkdir -p "$PROV/Contents" || die "could not create $PROV"
    /usr/bin/python3 -I - "$RES" "$EPP" "$HWP" "$PROV/Contents/Info.plist" <<'EOF' || die "could not build the data provider"
import plistlib, sys
res, epp, hwp, out = sys.argv[1:]
d = plistlib.load(open(res, "rb"))
vecs = d["IOPlatformPowerProfile"]["FrequencyVectors"]
# tunables are 36-byte records: 16-byte name, 4-byte type, 16-byte value at +20 (an int, or a string for type 1)
def record(v, i, key):
    hits = [o for o in range(0, len(v) - 36) if v[o:o + 16] == key.encode().ljust(16, b"\0")]
    if len(hits) != 1:
        sys.exit(f"vector {i}: expected one '{key}' record, found {len(hits)}")
    return hits[0]
for i, v in enumerate(vecs):
    v = bytearray(v)
    if epp:
        e = int(epp, 0)
        if not 0 <= e <= 255:
            sys.exit("EPP must be 0-255")
        o = record(v, i, "epp") + 20
        old = int.from_bytes(v[o:o + 4], "little")
        v[o:o + 4] = e.to_bytes(4, "little")
        print(f"vector {i}: epp 0x{old:x} -> 0x{e:x}")
    if hwp:
        if hwp not in ("on", "off"):
            sys.exit("HWP must be on or off")
        o = record(v, i, "hwp")
        if v[o + 16:o + 20] != (1).to_bytes(4, "little"):
            sys.exit(f"vector {i}: 'hwp' is not a string record")
        old = bytes(v[o + 20:o + 36]).split(b"\0")[0].decode()
        v[o + 20:o + 36] = hwp.encode().ljust(16, b"\0")
        print(f"vector {i}: hwp {old} -> {hwp}")
    vecs[i] = bytes(v)
plistlib.dump({
    "CFBundleIdentifier": "org.acidanthera.driver.CPUFriendDataProvider", "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "CPUFriendDataProvider", "CFBundlePackageType": "KEXT", "CFBundleShortVersionString": "1.0.1",
    "CFBundleVersion": "1.0.1", "OSBundleRequired": "Root",
    "IOKitPersonalities": {"CPUFriendDataProvider": {   # same personality as CPUFriend's ResourceConverter.sh
        "CFBundleIdentifier": "com.apple.driver.AppleACPIPlatform", "IOClass": "AppleACPICPU",
        "IONameMatch": "processor", "IOProbeScore": 1100, "IOProviderClass": "IOACPIPlatformDevice",
        "cf-frequency-data": plistlib.dumps(d, fmt=plistlib.FMT_XML)}},
}, open(out, "wb"))
EOF
    plutil -lint "$PROV/Contents/Info.plist" >/dev/null || die "Info.plist does not parse"
    chown -R "${SUDO_USER:-root}" "$B"
    AGPM_KEXT=$AGPM EXTRA_KEXTS="$CPUF $PROV" WEXDIR=wex-xe15c WEX_EXTRA="-wex-objpreempt -wex-noccs -wex-hostrps-max${WEX_ADD:+ $WEX_ADD}" \
        bash "$HERE/../hybrid/efi.sh" "$ROUTE" || die "efi.sh $ROUTE failed"
    echo "CPUFRIEND ($1, epp ${EPP:-unchanged}, hwp ${HWP:-unchanged}) installed. Reboot now."
    ;;
check)
    TAG=${2:?usage: $0 check TAG}
    OUT=$HOMEU/cpufriend-$TAG.txt
    {
        echo "== $(date '+%F %T') CPUFRIEND check, up since $(sysctl -n kern.boottime)"
        echo "CPUFriend: $(kextstat -l -b org.acidanthera.driver.CPUFriend 2>/dev/null)"
        ioreg -l -w0 > /tmp/cpuf-ioreg.$$
        echo "cf-frequency-data entries (want >= 1): $(grep -c '"cf-frequency-data"' /tmp/cpuf-ioreg.$$)"
        echo "RCxControl entries (want 0): $(grep -c RCxControl /tmp/cpuf-ioreg.$$)"
        rm -f /tmp/cpuf-ioreg.$$
        sysctl machdep.xcpm.vectors_loaded_count machdep.xcpm.hard_plimit_max_100mhz_ratio
        log show --last boot --predicate 'sender == "CPUFriend" OR eventMessage CONTAINS[c] "cpuf"' --style compact 2>/dev/null | tail -5
    } > "$OUT" 2>&1
    chown "${SUDO_USER:-root}" "$OUT"
    cat "$OUT"
    bash "$HERE/../hybrid/xe15.sh" check "cpuf-$TAG" > /dev/null 2>&1
    bash "$HERE/cpu-study.sh" "cpuf-$TAG"
    echo "saved $OUT, $HOMEU/xe15-cpuf-$TAG.txt, $HOMEU/cpu-study-cpuf-$TAG.txt"
    ;;
*) die "usage: sudo bash $0 arm | keep | check TAG" ;;
esac
