#!/bin/bash
# epp.sh: EPP-1, does XCPM's HWP energy/performance preference hold the all-core clock down?
# The board-id frequency vector (Mac-E1008331FDC96864, MacBookPro16,1) sets hwp on, epp 0x80 (balanced),
# perf-bias 5. XNU exposes machdep.xcpm.epp_override; this sweeps it at runtime, no reboot, no EFI change.
#   sudo bash tools/cpu/epp.sh TAG     writes ~/cpu-epp-TAG.txt and prints a summary
# Per value: one thread 12 s (clockprobe single 12), then 12 threads ~15 s with package power sampled.
# The original value is restored at the end (and a reboot resets it anyway).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-$USER}")
die() { echo "STOP: $*"; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"
TAG=${1:?usage: sudo bash tools/cpu/epp.sh TAG}
OUT=$HOMEU/cpu-epp-$TAG.txt
PROBE=$HERE/clockprobe
if [ ! -x "$PROBE" ] || [ "$HERE/clockprobe.c" -nt "$PROBE" ]; then
    cc -O2 -Wall -o "$PROBE" "$HERE/clockprobe.c" -lpthread || die "clockprobe did not build"
fi
ORIG=$(sysctl -n machdep.xcpm.epp_override) || die "no machdep.xcpm.epp_override on this kernel"
trap 'sysctl -w machdep.xcpm.epp_override=$ORIG >/dev/null 2>&1' EXIT
TMP=$(mktemp -d) || die "no temp dir"

run() {  # $1 = label; prints one summary line, full data to $OUT
    "$PROBE" single 12 > "$TMP/s"
    ( end=$((SECONDS + 16)); while [ $SECONDS -lt $end ]; do "$PROBE" multi 12; done ) > "$TMP/m" &
    local p=$!
    powermetrics --samplers cpu_power -i 1000 -n 14 > "$TMP/pm" 2>&1
    wait $p
    local s m w
    s=$(awk '/^single/ {t+=$3; n++} END {if (n) printf "%.2f", t/n}' "$TMP/s")
    m=$(sed -n 's/.*sum=\([0-9.]*\).*/\1/p' "$TMP/m" | awk '{t+=$1; n++} END {if (n) printf "%.1f", t/n}')
    w=$(sed -n 's/.*package power (CPUs+GT+SA): \([0-9.]*\)W/\1/p' "$TMP/pm" | awk '{t+=$1; n++} END {if (n) printf "%.1f", t/n}')
    { echo "--- $1"; cat "$TMP/s" "$TMP/m"; grep -E "package power|CPU Average frequency|Performance Limited" "$TMP/pm"; } >> "$OUT"
    printf '%-14s 1 thread %5s GHz   12 threads %5s GHz-equiv   package %5s W\n' "$1" "$s" "$m" "$w"
}

{
    echo "=== cpu-epp $TAG $(date '+%F %T'), epp_override was $ORIG"
    sysctl -n vm.loadavg
    pmset -g batt
} > "$OUT"
echo "epp_override was $ORIG; load $(sysctl -n vm.loadavg)"
run "as booted"
for v in 128 64 32 1; do
    if ! sysctl -w machdep.xcpm.epp_override=$v >/dev/null 2>>"$OUT"; then
        echo "STOP: the kernel refused epp_override=$v (see $OUT)"; break
    fi
    run "epp=$v (read $(sysctl -n machdep.xcpm.epp_override))"
done
sysctl -w machdep.xcpm.epp_override=$ORIG >/dev/null 2>&1
rm -rf "$TMP"
chown "${SUDO_USER:-root}" "$OUT"
echo "restored epp_override=$(sysctl -n machdep.xcpm.epp_override); saved $OUT"
