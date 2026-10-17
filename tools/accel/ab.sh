#!/bin/bash
# ab.sh: compares the bridge knobs of accel-0001 in one boot. For each setting (memcpy/direct = 0/0, 1/0, 1/1) it
# settles 10 s, then measures 60 s: frames, µs per copied frame, failures, kernel_task and WindowServer CPU. Keep the
# same thing on screen the whole time (a playing video). Ends with 1/1 on; a reboot puts both back to 0.
# With "ram" (RTX-20, stage 4a) it compares direct=1 (staging + CPU copy) with direct=2 + debug.nmintelfb_ram=1 (the
# copy engine writes straight into the panel's RAM) and ends with the RAM scanout on.
#   sudo bash tools/accel/ab.sh          results in ~/nmx-ab-<date>.txt
#   sudo bash tools/accel/ab.sh ram
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
sysctl -n debug.nvaccel_iop_direct >/dev/null 2>&1 || { echo "este NVAccel não tem accel-0001"; exit 1; }
[ "$(sysctl -n debug.nvaccel_iop)" = 1 ] || { echo "desktop acelerado ainda não ligou (debug.nvaccel_iop=0)"; exit 1; }
OUT=$(eval echo "~${SUDO_USER:-root}")/nmx-ab-$(date +%Y%m%d-%H%M%S).txt
WS=$(pgrep -x WindowServer | head -1)
cpu() { top -l 7 -s 10 -stats pid,cpu -pid 0 -pid "$WS" 2>/dev/null \
        | awk -v ws="$WS" '$1=="0"{if (sk++) {k+=$2;nk++}} $1==ws{if (sw++) {w+=$2;nw++}} END{printf "kernel_task %.0f%%  WindowServer %.0f%%", (nk?k/nk:0), (nw?w/nw:0)}'; }   # top's first sample is not a rate: skipped
c() { sysctl -n "debug.nvaccel_$1"; }
SETS=("0 0 0" "1 0 0" "1 1 0")
if [ "${1:-}" = ram ]; then
    sysctl -n debug.nmintelfb_ram >/dev/null 2>&1 && sysctl -n debug.nvaccel_iop_ram_frames >/dev/null 2>&1 \
        || { echo "falta o NMIntelFB com intelfb-0017 ou o NVAccel com accel-0002"; exit 1; }
    SETS=("1 1 0" "1 2 1")
fi
for set in "${SETS[@]}"; do
    set -- $set
    sysctl -w debug.nvaccel_iop_memcpy=$1 debug.nvaccel_iop_direct=$2 >/dev/null
    if [ "${3:-0}" = 1 ]; then
        sysctl -w debug.nmintelfb_ram=1 >/dev/null || { echo "a tela na RAM não ligou: $(sysctl -n debug.nmintelfb_ram) (veja o log do NMIntelFB)"; exit 1; }
    elif sysctl -n debug.nmintelfb_ram >/dev/null 2>&1; then sysctl -w debug.nmintelfb_ram=0 >/dev/null; fi
    echo "memcpy=$1 direct=$2 ram=${3:-0}: medindo 70 s..."
    sleep 10
    ok0=$(c iop_ok); us0=$(c iop_copy_us); f0=$(c iop_fail); d0=$(c iop_direct_frames); b0=$(c iop_blank); r0=$(c iop_ram_frames 2>/dev/null || echo 0)
    load=$(cpu)
    ok=$(( $(c iop_ok) - ok0 )); us=$(( $(c iop_copy_us) - us0 ))
    line="memcpy=$1 direct=$2 ram=${3:-0}  frames/s $((ok / 60))  us/frame $(( ok ? us / ok : 0 ))  fail $(( $(c iop_fail) - f0 ))  direct $(( $(c iop_direct_frames) - d0 ))  blank $(( $(c iop_blank) - b0 ))  ram $(( $(c iop_ram_frames 2>/dev/null || echo 0) - r0 ))  $load"
    echo "$line"; echo "$line" >> "$OUT"
done
echo "resultado em $OUT (fica ligado o último ajuste até reiniciar)"
