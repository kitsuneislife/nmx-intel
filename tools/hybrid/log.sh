#!/bin/bash
# log.sh: evidence of the last boot on the hybrid route, written to ~/hybrid.txt (no pipes to type).
#   sudo bash tools/hybrid/log.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HOMEU=$(eval echo "~${SUDO_USER:-root}")
OUT=$HOMEU/hybrid.txt
{
    echo "== $(date) $(sw_vers -productVersion) $(sw_vers -buildVersion)"
    echo "== boot-args: $(nvram boot-args 2>/dev/null | cut -f2-)"
    echo "== kexts"; kextstat 2>/dev/null | grep -E 'Lilu|NootedGreen|TGL|nullmoth|NMIntelFB'
    echo "== iGPU"; ioreg -r -c IOPCIDevice -n IGPU -d 1 -w0 2>/dev/null | grep -E '"(device-id|model|IOName)"'
    ioreg -r -c IOPCIDevice -n GFX0 -d 1 -w0 2>/dev/null | grep -E '"(device-id|model)"'
    echo "== accelerators and framebuffers"; ioreg -l -w0 2>/dev/null | grep -E '"(MetalPluginName|IOClass)" = "(Intel|AppleIntel|IntelAccel|AppleIntelFramebuffer)' | sort -u
    echo "== displays"; system_profiler SPDisplaysDataType 2>/dev/null
    echo "== kernel log (NootedGreen / TGL)"
    /usr/bin/log show --last boot --style compact --predicate 'process == "kernel"' 2>/dev/null \
        | grep -E 'NootedGreen|ngreen|XeNG|AppleIntelTGL|IntelAccelerator|AppleIntelFramebuffer|IGPU' | head -1500
    echo "== WindowServer log"
    /usr/bin/log show --last boot --style compact --predicate 'process == "WindowServer"' 2>/dev/null \
        | grep -iE 'fault|assert|abort|CoreDisplay|Metal|AccessComplete|isRemovable|watchdog' | head -300
    echo "== crash and panic reports since boot"
    BOOT=$(sysctl -n kern.boottime | sed 's/.*sec = \([0-9]*\).*/\1/')
    for f in /Library/Logs/DiagnosticReports/* "$HOMEU"/Library/Logs/DiagnosticReports/*; do
        [ -f "$f" ] && [ "$(stat -f %m "$f")" -ge "$BOOT" ] && { echo "--- $f"; head -60 "$f"; }
    done
    echo "== last panic (any time)"; ls -t /Library/Logs/DiagnosticReports/*panic* 2>/dev/null | head -3
} > "$OUT" 2>&1
chown "${SUDO_USER:-root}" "$OUT"
echo "written: $OUT ($(wc -l < "$OUT") lines)"
