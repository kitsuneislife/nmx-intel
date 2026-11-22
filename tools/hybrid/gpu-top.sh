#!/bin/bash
# gpu-top.sh: Iris Xe GPU time per process over a window, from the accelerator's per-client accumulatedGPUTime
# (nanoseconds, read from ioreg twice). "busy %" is GPU time / wall time; above 100 % means overlapping work.
#   bash tools/hybrid/gpu-top.sh [SECONDS [DELAY]]   default 10 s; DELAY waits first (time to hide an app);
#                                                    prints and appends to ~/gpu-top.txt
set -uo pipefail
secs=${1:-10}
sleep "${2:-0}"
snap() {
    ioreg -r -c IntelAccelerator -l -w0 | awk '
        /"IOUserClientCreator"/ { match($0, /pid [0-9]+, [^"]*/); c = substr($0, RSTART + 4, RLENGTH - 4) }
        /"accumulatedGPUTime"/ { match($0, /"accumulatedGPUTime" = [0-9]+/); split(substr($0, RSTART, RLENGTH), a, " = ");
                                 if (c != "") t[c] += a[2] }
        END { for (k in t) print k "\t" t[k] }'
}
a=$(snap); sleep "$secs"; b=$(snap)
{
    echo "== $(date '+%F %T'), ${secs}s, GPU busy % per process (Iris Xe):"
    awk -F'\t' -v s="$secs" 'NR == FNR { t0[$1] = $2; next } { d = $2 - t0[$1]; if (d > 0) printf "%7.1f  %s\n", d / (s * 1e7), $1 }' \
        <(echo "$a") <(echo "$b") | sort -rn | head -8
} | tee -a "$HOME/gpu-top.txt"
