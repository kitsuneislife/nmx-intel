#!/bin/bash
# xe14.sh: XE-14, the daily LAT-8 config plus -wex-noccs (WhateverXe 29a78c34 = 0.8.2 + 0001..0006 + 0008), ONE boot.
#   sudo bash tools/hybrid/xe14.sh         arm it, then reboot; the boot after that is the daily config again
#                                          (the new kext stays on the ESP, but without -wex-noccs it is LAT-8's source)
#   bash tools/hybrid/xe14.sh check TAG    in the XE-14 boot: knob record, driver log line, hangs this boot, then
#                                          lat-busy.sh TAG; everything into ~/xe14-TAG.txt
#   sudo bash tools/hybrid/xe14.sh keep    stay on XE-14 (efi.sh wexrtx-keep with the same args)
# ~/nmx-build was lost on 11-22 and rebuilt; arming first copies the ESP's current WhateverXe.kext to kexts/wex-daily
# (rollback: sudo WEXDIR=wex-daily WEX_EXTRA="-wex-objpreempt" bash tools/hybrid/efi.sh wexrtx-keep) and the ESP's
# AMFIPassMod.kext to kexts/, which efi.sh needs. Stops at the first failure.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-$USER}")
WXK=$HOMEU/nmx-build/whateverxe/kexts
K=$WXK/wex-xe14/WhateverXe.kext/Contents/MacOS/WhateverXe
ARGS="-wex-objpreempt -wex-noccs"
die() { echo "STOP: $*"; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || die "run with sudo"; }

CMD=${1:-arm}
case "$CMD" in
arm|keep)
    need_root
    [ "$(shasum -a 256 "$K" 2>/dev/null | cut -c1-8)" = 29a78c34 ] || die "wex-xe14 is not WhateverXe 29a78c34: $K"
    diskutil mount disk0s1 >/dev/null 2>&1
    ESP=$(diskutil info disk0s1 2>/dev/null | sed -n 's/^ *Mount Point: *//p')
    [ -n "$ESP" ] || die "could not mount the ESP (disk0s1)"
    OCK=$ESP/EFI/OC/Kexts
    if [ ! -d "$WXK/wex-daily/WhateverXe.kext" ]; then
        [ -d "$OCK/WhateverXe.kext" ] || die "no WhateverXe.kext on the ESP to keep as wex-daily"
        mkdir -p "$WXK/wex-daily" && cp -R "$OCK/WhateverXe.kext" "$WXK/wex-daily/" || die "could not save wex-daily"
    fi
    if [ ! -d "$WXK/AMFIPassMod.kext" ]; then
        [ -d "$OCK/AMFIPassMod.kext" ] || die "no AMFIPassMod.kext on the ESP"
        cp -R "$OCK/AMFIPassMod.kext" "$WXK/" || die "could not save AMFIPassMod.kext"
    fi
    chown -R "${SUDO_USER:-root}" "$WXK"
    echo "1. kept: wex-daily $(shasum -a 256 "$WXK/wex-daily/WhateverXe.kext/Contents/MacOS/WhateverXe" | cut -c1-8)," \
         "AMFIPassMod $(shasum -a 256 "$WXK/AMFIPassMod.kext/Contents/MacOS/"* | cut -c1-8)"
    MODE=wexrtx; [ "$CMD" = keep ] && MODE=wexrtx-keep
    WEXDIR=wex-xe14 WEX_EXTRA="$ARGS" bash "$HERE/efi.sh" $MODE || die "efi.sh $MODE failed"
    echo "2. XE-14 armed ($MODE). Reboot now."
    ;;
check)
    TAG=${2:?usage: $0 check TAG}
    OUT=$HOMEU/xe14-$TAG.txt
    BOOT=$(sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+).*/\1/')
    {
        echo "== $(date '+%F %T'), up since $(date -r "$BOOT" '+%F %T')"
        echo "boot-args: $(sysctl -n kern.bootargs)"
        echo "WhateverXe: $(kextstat -l -b org.b00t0x.WhateverXe 2>/dev/null)"
        echo "WhateverXeNoCCS (occurrences, patched; want 1,1):"
        ioreg -l -w0 -d1 2>/dev/null | grep '"WhateverXeNoCCS"'
        echo "driver log, Multi-Context (want Disabled):"
        /usr/bin/log show --style compact --start "$(date -r "$BOOT" '+%Y-%m-%d %H:%M:%S')" \
            --predicate 'eventMessage CONTAINS "Multi-Context"' 2>/dev/null | grep -v '^Timestamp' | tail -3
        echo "gpuRestart reports this boot:"
        find /Library/Logs/DiagnosticReports -name '*.gpuRestart' -newermt "$(date -r "$BOOT" '+%Y-%m-%d %H:%M:%S')" 2>/dev/null
    } > "$OUT" 2>&1
    bash "$HERE/lat-busy.sh" "xe14-$TAG" >> "$OUT" 2>&1
    cat "$OUT"
    ;;
*) die "usage: sudo $0 [arm|keep] | $0 check TAG" ;;
esac
