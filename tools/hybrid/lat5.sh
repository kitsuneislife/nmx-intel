#!/bin/bash
# lat5.sh: everything for the LAT-5 boot in one go: the RTX app list back on the hybrid (a nullmoth install resets it),
# then the LAT-8 daily config plus WhateverXe fa17909c with PreemptionTimerIntervalUS=500, for ONE boot (efi.sh wexrtx).
#   sudo bash tools/hybrid/lat5.sh        then reboot; the boot after that is the daily LAT-8 config again
# Stops at the first failure.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-root}")
K=$HOMEU/nmx-build/whateverxe/kexts/wex-lat5/WhateverXe.kext/Contents/MacOS/WhateverXe
die() { echo "STOP: $*"; exit 1; }

[ "$(shasum -a 256 "$K" 2>/dev/null | cut -c1-8)" = fa17909c ] || die "wex-lat5 is not WhateverXe fa17909c: $K"

# 1. RTX only for the listed apps (nullmoth 3.0's install put back '*')
bash "$HERE/ondemand.sh" on > /dev/null || die "ondemand on failed"
for a in Roblox RobloxPlayer "Google Chrome" "Google Chrome Helper (Aperitif)"; do
    bash "$HERE/ondemand.sh" add "$a" > /dev/null || die "ondemand add $a failed"
done
echo "1. RTX for: $(grep -v '^#' /Library/GPUBundles/nvmtl-allow.txt | tr '\n' ',' | sed 's/,$//')"

# 2. one boot on LAT-5
WEXDIR=wex-lat5 WEX_EXTRA="-wex-objpreempt" WEX_DEV="PreemptionTimerIntervalUS=500" bash "$HERE/efi.sh" wexrtx \
    || die "efi.sh wexrtx failed"
echo "2. LAT-5 armed for the next boot. Reboot now."
