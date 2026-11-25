#!/bin/bash
# hdmi-check.sh: after a boot with a display on the HDMI port (wired to the RTX), record whether NVAccel left
# headless mode and WindowServer uses the display. Writes ~/hdmi.txt (no pipes to type).
#   sudo bash tools/hybrid/hdmi-check.sh
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HOMEU=$(eval echo "~${SUDO_USER:-root}")
OUT=$HOMEU/hdmi.txt
{
    echo "== $(date) uptime: $(uptime)"
    echo "== boot-args: $(nvram boot-args 2>/dev/null | cut -f2-)"
    echo "== nvaccel sysctls"
    sysctl debug.nvaccel_headless debug.nvaccel_heads_published debug.nvaccel_heads_registered \
        debug.nvaccel_heads_piped debug.nvaccelfb debug.nvaccel_iop 2>&1
    echo "== NVIDIA framebuffer"
    ioreg -lw0 -r -c NVRMNVDAFramebuffer 2>/dev/null \
        | grep -E '<class|NVAccelHeadless|IODisplayEDID|nvda-eld|connector-type|NVRMFirstPrimaryFlipMs|NVRMTiming|IOFBCurrentPixelCount' \
        | cut -c1-220
    echo "== IODisplayConnect (one per display WindowServer can see)"
    ioreg -lw0 -r -c IODisplayConnect 2>/dev/null | grep -E '<class' | cut -c1-160
    echo "== NVAccelHeadless anywhere"
    ioreg -lw0 2>/dev/null | grep -E 'NVAccelHeadless' | cut -c1-160
    echo "== displays"
    system_profiler SPDisplaysDataType 2>/dev/null
    echo "== kernel log (NVAccel / NVRM), this boot"
    /usr/bin/log show --last boot --style compact --predicate 'process == "kernel"' 2>/dev/null \
        | grep -iE 'NVAccel|NVRM|headless|hotplug' | head -400
    echo "== WindowServer log, this boot"
    /usr/bin/log show --last boot --style compact --predicate 'process == "WindowServer"' 2>/dev/null \
        | grep -iE 'fault|assert|abort|display|Metal|watchdog' | head -300
    echo "== recent panic / WindowServer reports"
    find /Library/Logs/DiagnosticReports "$HOMEU/Library/Logs/DiagnosticReports" -maxdepth 1 \
        \( -name '*.panic' -o -name 'WindowServer*' \) -mtime -1 2>/dev/null
} > "$OUT" 2>&1
chown "${SUDO_USER:-root}" "$OUT"
echo "written: $OUT ($(wc -l < "$OUT") lines)"
grep -E 'nvaccel_headless|heads_registered|heads_piped' "$OUT"
