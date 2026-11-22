#!/bin/bash
# cpu-study.sh: one run of the CPU/package baseline for docs/research/wxe-study-2026-11-22.md.
#   sudo bash tools/cpu/cpu-study.sh TAG
# Three phases, each with powermetrics (cpu_power, gpu_power) sampled every second:
#   idle 20 s, one thread busy ~25 s, all 12 threads busy ~30 s.
# Everything goes to ~/cpu-study-TAG.txt. Close heavy apps first and keep the charger plugged in.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-$USER}")
die() { echo "STOP: $*"; exit 1; }

[ "$(id -u)" = 0 ] || die "run with sudo"
TAG=${1:-}
[ -n "$TAG" ] || die "usage: sudo bash tools/cpu/cpu-study.sh TAG"
OUT=$HOMEU/cpu-study-$TAG.txt
PROBE=$HERE/clockprobe
if [ ! -x "$PROBE" ] || [ "$HERE/clockprobe.c" -nt "$PROBE" ]; then
    cc -O2 -Wall -o "$PROBE" "$HERE/clockprobe.c" -lpthread || die "clockprobe did not build"
fi

pm() { powermetrics --samplers cpu_power,gpu_power -i 1000 -n "$1" 2>&1; }

{
    echo "=== cpu-study $TAG $(date '+%F %T')"
    sw_vers -productVersion
    pmset -g batt
    pmset -g therm
    sysctl -n vm.loadavg
    sysctl hw.nperflevels hw.perflevel0.physicalcpu machdep.cpu.thermal.hardware_feedback 2>&1
    echo "AGPM RCxControl entries: $(ioreg -l -w0 > /tmp/cpu-study-ioreg.$$ ; grep -c RCxControl /tmp/cpu-study-ioreg.$$)"
    grep -o '"RCxControl"={[^}]*}' /tmp/cpu-study-ioreg.$$
    rm -f /tmp/cpu-study-ioreg.$$
    grep -o -- '-wex-[a-z0-9-]*' <(nvram boot-args 2>&1)

    echo; echo "=== phase idle (20 s)"
    pm 20

    echo; echo "=== phase single (one thread busy)"
    "$PROBE" single 50 > /tmp/cpu-study-single.$$ &
    P=$!
    pm 22
    wait $P
    cat /tmp/cpu-study-single.$$; rm -f /tmp/cpu-study-single.$$

    echo; echo "=== phase multi (12 threads busy)"
    ( end=$((SECONDS + 32)); while [ $SECONDS -lt $end ]; do "$PROBE" multi 12; done ) > /tmp/cpu-study-multi.$$ &
    P=$!
    pm 30
    wait $P
    cat /tmp/cpu-study-multi.$$; rm -f /tmp/cpu-study-multi.$$
    echo; echo "=== end $(date '+%T')"
} > "$OUT" 2>&1
chown "${SUDO_USER:-$USER}" "$OUT" 2>/dev/null
echo "saved $OUT ($(wc -l < "$OUT") lines)"
