#!/bin/bash
# log.sh: evidence of the last boot on the hybrid route, written to ~/hybrid.txt (no pipes to type).
#   sudo bash tools/hybrid/log.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HOMEU=$(eval echo "~${SUDO_USER:-root}")
BOOT=$(sysctl -n kern.boottime | sed 's/^{ sec = \([0-9]*\).*/\1/')
# The hybrid boot usually panics and the next boot is GPU-only: read the 20 minutes before this boot too.
PREV="--start '$(date -r $((BOOT - 1200)) '+%Y-%m-%d %H:%M:%S')' --end '$(date -r "$BOOT" '+%Y-%m-%d %H:%M:%S')'"
OUT=$HOMEU/hybrid.txt
{
    echo "== $(date) $(sw_vers -productVersion) $(sw_vers -buildVersion)"
    echo "== boot-args: $(nvram boot-args 2>/dev/null | cut -f2-)"
    echo "== kexts"; kextstat 2>/dev/null | grep -E 'Lilu|NootedGreen|WhateverXe|AMFIPass|b00t0x|TGL|nullmoth|NMIntelFB'
    echo "== iGPU"; ioreg -r -c IOPCIDevice -n IGPU -d 1 -w0 2>/dev/null | grep -E '"(device-id|model|IOName)"'
    ioreg -r -c IOPCIDevice -n GFX0 -d 1 -w0 2>/dev/null | grep -E '"(device-id|model)"'
    echo "== accelerators and framebuffers"; ioreg -l -w0 2>/dev/null | grep -E '"(MetalPluginName|IOClass)" = "(Intel|AppleIntel|IntelAccel|AppleIntelFramebuffer|NMIntelFB)' | sort -u
    echo "== displays"; system_profiler SPDisplaysDataType 2>/dev/null
    for W in "$PREV" "--last boot"; do
        echo "== kernel log (NootedGreen / WhateverXe / TGL), $W"
        eval /usr/bin/log show $W --style compact --predicate "'process == \"kernel\"'" 2>/dev/null \
            | grep -E 'nmx HYB|NootedGreen|ngreen|XeNG|WhateverXe|wex|igfx|AMFIPass|NMIntelFB|AppleIntelTGL|IntelAccelerator|AppleIntelFramebuffer|IGPU|NVAccel: probe' | head -1500
    done
    echo "== WindowServer log"
    /usr/bin/log show --last boot --style compact --predicate 'process == "WindowServer"' 2>/dev/null \
        | grep -iE 'fault|assert|abort|CoreDisplay|Metal|AccessComplete|isRemovable|watchdog' | head -300
    echo "== panic and WindowServer reports from the previous boot on"
    for f in /Library/Logs/DiagnosticReports/*.panic /Library/Logs/DiagnosticReports/WindowServer* \
             "$HOMEU"/Library/Logs/DiagnosticReports/WindowServer*; do
        [ -f "$f" ] && [ "$(stat -f %m "$f")" -ge $((BOOT - 1200)) ] && { echo "--- $f"; head -60 "$f"; }
    done
    echo "== kernel message buffer saved during the hybrid boot (efi.sh boot-once)"
    for f in /var/log/nmx-hybrid-dmesg-*.txt; do
        [ -f "$f" ] && { echo "--- $f ($(wc -l < "$f") lines, $(stat -f %Sm "$f"))"; grep -E 'XeNG|NGreen|ngreen|nmx HYB|Lilu|WhateverXe|wex|igfx|AMFIPass|NMIntelFB|AppleIntelTGL|IntelAccel' "$f" > "$OUT.tmp"
            case $f in *-last.txt) tail -400 "$OUT.tmp" ;; *) head -400 "$OUT.tmp" ;; esac; rm -f "$OUT.tmp"; }
    done
    echo "== XeNG HYB lines from every saved buffer"; grep -ah 'XeNG HYB' /var/log/nmx-hybrid-dmesg-*.txt 2>/dev/null > "$OUT.tmp"; sort -u "$OUT.tmp"; rm -f "$OUT.tmp"
    echo "== Metal tests on the Iris Xe (gputests.sh, run by boot-once)"; cat /var/log/nmx-hybrid-gputests.txt 2>/dev/null
    echo "== libxedrv logs copied from /tmp during the hybrid boot"
    for f in /var/log/nmx-hybrid-xedrv/*.log; do [ -f "$f" ] && { echo "--- $f ($(wc -l < "$f") lines)"; tail -40 "$f"; }; done
    echo "== last panic (any time)"; ls -t /Library/Logs/DiagnosticReports/*panic* 2>/dev/null | head -3
} > "$OUT" 2>&1
chown "${SUDO_USER:-root}" "$OUT"
echo "written: $OUT ($(wc -l < "$OUT") lines)"
