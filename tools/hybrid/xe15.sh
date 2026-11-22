#!/bin/bash
# xe15.sh: XE-15c, WhateverXe 8516faf3 = 0.8.3 + 0.8.3/0001..0004 (objpreempt, noccs, the #176 host-RPS governor),
# with the daily args -wex-objpreempt -wex-noccs. Two one-boot steps, one variable each:
#   sudo bash tools/hybrid/xe15.sh            XE-15: 0.8.3 with the governor OFF (-wex-hostrps-max = 0.8.2's RP0 answer)
#   sudo bash tools/hybrid/xe15.sh arm gov    XE-15g: the same kext with the governor ON
#   sudo bash tools/hybrid/xe15.sh keep [gov] stay on it (efi.sh wexrtx-keep with the same args)
#   bash tools/hybrid/xe15.sh check TAG       in that boot: kext, knobs, hangs, 20 GT power samples 0.5 s apart
#                                             (answered and actual MHz, RC6 %), then lat-busy.sh; all into ~/xe15-TAG.txt
# An armed boot is used once; the boot after it is the kept config again (XE-14b, b2bb8e95). Rollback after keep:
#   sudo WEXDIR=wex-xe14b WEX_EXTRA="-wex-objpreempt -wex-noccs" bash tools/hybrid/efi.sh wexrtx-keep
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-$USER}")
WXK=$HOMEU/nmx-build/whateverxe/kexts
K=$WXK/wex-xe15c/WhateverXe.kext/Contents/MacOS/WhateverXe
die() { echo "STOP: $*"; exit 1; }

CMD=${1:-arm}
case "$CMD" in
arm|keep)
    [ "$(id -u)" = 0 ] || die "run with sudo"
    [ "$(shasum -a 256 "$K" 2>/dev/null | cut -c1-8)" = 8516faf3 ] || die "wex-xe15c is not WhateverXe 8516faf3: $K"
    [ -d "$WXK/AMFIPassMod.kext" ] || die "no $WXK/AMFIPassMod.kext (run xe14.sh arm once first)"
    ARGS="-wex-objpreempt -wex-noccs -wex-hostrps-max"; WHAT="XE-15 (governor off)"
    if [ "${2:-}" = gov ]; then ARGS="-wex-objpreempt -wex-noccs"; WHAT="XE-15g (governor on)"; fi
    MODE=wexrtx; [ "$CMD" = keep ] && MODE=wexrtx-keep
    WEXDIR=wex-xe15c WEX_EXTRA="$ARGS" bash "$HERE/efi.sh" $MODE || die "efi.sh $MODE failed"
    echo "$WHAT armed ($MODE, $ARGS). Reboot now."
    ;;
check)
    TAG=${2:?usage: $0 check TAG}
    OUT=$HOMEU/xe15-$TAG.txt
    BOOT=$(sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+),.*/\1/')
    {
        echo "== $(date '+%F %T'), up since $(date -r "$BOOT" '+%F %T')"
        echo "load: $(uptime)"
        echo "boot-args: $(sysctl -n kern.bootargs)"
        echo "WhateverXe: $(kextstat -l -b org.b00t0x.WhateverXe 2>/dev/null)"
        echo "WhateverXeNoCCS (want 1,1): $(ioreg -l -w0 -d1 2>/dev/null | grep -o '"WhateverXeNoCCS" = [^ ]*')"
        echo "gpuRestart reports this boot:"
        find /Library/Logs/DiagnosticReports -name '*.gpuRestart' -newermt "$(date -r "$BOOT" '+%Y-%m-%d %H:%M:%S')" 2>/dev/null
        echo "GT power, 20 samples 0.5 s apart (answer = host RPS reply, actual = RPSTAT1, rc6 = idle % since last):"
        for i in $(seq 20); do ioreg -l -w0 | grep -o '"N97GTPowerSample" = <[0-9a-f]*>'; sleep 0.5; done | python3 -c '
import sys
prev = None; ans = []
for line in sys.stdin:
    h = line.split("<")[1].rstrip(">\n"); q = [int.from_bytes(bytes.fromhex(h[i:i+16]), "little") for i in range(0, len(h), 16)]
    a = ((q[14] >> 23) // 3) * 50; act = ((q[3] >> 11) & 511) * 50 // 3; caps = q[15]
    rc6 = ""
    if prev and q[2] > prev[2]: rc6 = "%5.1f" % min(100, ((q[4] - prev[4]) & 0xffffffff) * 1280 * 100 / (q[2] - prev[2]))
    print("answer %4d MHz  actual %4d MHz  rc6 %5s %%  calls %d  caps %d-%d MHz" % (a, act, rc6, q[12], ((caps >> 16) & 255) * 50, (caps & 255) * 50))
    prev = q; ans.append(a)
if ans: print("answer avg %d MHz over %d samples" % (sum(ans) // len(ans), len(ans)))'
    } > "$OUT" 2>&1
    bash "$HERE/lat-busy.sh" "xe15-$TAG" >> "$OUT" 2>&1
    cat "$OUT"
    ;;
*) die "usage: sudo $0 [arm|keep] [gov] | $0 check TAG" ;;
esac
