#!/bin/bash
# cleanup.sh: clears the leftovers of the test phase from Sequoia (2026-11-13). Keeps everything a rollback or a
# rebuild still uses: pkg-2.9 and pkg-2.3.6 (nvrm/build.sh), ~/ogkm615 (accel/build.sh), ~/nmx-2.3.6, the newest
# checkpoints, WhateverXe kexts/dl, the aux KC backup from before WhateverXe, config-antes-remove-tahoe.
#   sudo bash tools/cleanup.sh       lists what would go and its size (changes nothing)
#   sudo bash tools/cleanup.sh go    does it: loose test logs are packed into ~/nmx-build/old-logs-2026.tar.xz first
#                                    (kept as evidence), the rest is deleted
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=$(eval echo "~${SUDO_USER:-root}"); [ "$H" != /var/root ] || { echo "run with sudo from your user"; exit 1; }
cd "$H" || exit 1
shopt -s nullglob
# loose logs of the tests, recorded in docs/tests/
LOGS=(b5.txt b7a.txt bl2.txt guard1.txt hang.txt hybrid.txt ioreg.txt k7.txt k8.txt k9.txt mtk.txt n.txt n[2-9]*.txt
      nmx.txt p2 p3 p4 rtx2*.txt wifi1-*.txt install-2.*.log nmx-ab-*.txt
      nmx-build/whateverxe/*.txt nmx-build/whateverxe/*.log /Users/Shared/nmx-probe*.txt)
# obsolete: superseded builds and backups of states that no longer exist
CP=(nmx-checkpoints/*); OLDCP=("${CP[@]:0:${#CP[@]}-3}")   # all but the 3 newest (names start with the date)
DEL=(nmx-build/pkg-2.5.0 nmx-build/pkg-2.5.4 nmx-build/pkg-2.6.4 nmx-2.1.0 nmx-2.5.0 nmx-2.5.4 nmx-2.6.4 ogkm610
     AuxiliaryKernelExtensions.kc.antes-accel AuxiliaryKernelExtensions.kc.antes-hybrid
     AuxiliaryKernelExtensions.kc.antes-intelfb AuxiliaryKernelExtensions.kc.antes-wifi
     config-antes-hibernate.plist config-antes-hybrid.plist config-antes-v.plist
     nmx-build/whateverxe/build-base nmx-build/whateverxe/build-diag nmx-build/whateverxe/build-diag2
     nmx-build/whateverxe/build-xe5 nmx-build/whateverxe/build-xe6
     Library/Caches/com.anthropic.claudefordesktop.ShipIt "${OLDCP[@]}")
have=(); for f in "${LOGS[@]}"; do [ -e "$f" ] && have+=("$f"); done; LOGS=("${have[@]}")
have=(); for f in "${DEL[@]}"; do [ -e "$f" ] && have+=("$f"); done; DEL=("${have[@]}")
PROBE=/Library/LaunchDaemons/com.kitsune.nmxprobe.plist   # boot-time test probe (2 min of ioreg every boot)

if [ "${1:-}" != go ]; then
    echo "== packed into ~/nmx-build/old-logs-2026.tar.xz, then removed:"; [ ${#LOGS[@]} -gt 0 ] && du -shc "${LOGS[@]}" | tail -1
    echo "== deleted:"; [ ${#DEL[@]} -gt 0 ] && du -sh "${DEL[@]}" && du -shc "${DEL[@]}" | tail -1
    [ -f "$PROBE" ] && echo "== boot probe daemon removed (tools/probe/install.sh remove)"
    echo "nothing changed; to do it: sudo bash tools/cleanup.sh go"; exit 0
fi
if [ ${#LOGS[@]} -gt 0 ]; then
    A=nmx-build/old-logs-2026.tar.xz
    tar -cJf "$A" "${LOGS[@]}" 2>/dev/null && tar -tJf "$A" >/dev/null && chown "${SUDO_USER}" "$A" \
        || { rm -f "$A"; echo "packing the logs failed; nothing deleted"; exit 1; }
    echo "logs packed: $A ($(du -sh "$A" | cut -f1))"
    rm -rf "${LOGS[@]}"
fi
[ ${#DEL[@]} -gt 0 ] && rm -rf "${DEL[@]}" && echo "deleted ${#DEL[@]} obsolete items"
[ -f "$PROBE" ] && bash "$(cd "$(dirname "$0")" && pwd)/probe/install.sh" remove
command -v brew >/dev/null && sudo -u "$SUDO_USER" brew cleanup -s >/dev/null 2>&1 && echo "brew cleanup done"
sync; df -h /System/Volumes/Data | tail -1
