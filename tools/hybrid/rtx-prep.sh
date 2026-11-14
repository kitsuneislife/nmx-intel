#!/bin/bash
# rtx-prep.sh: everything for one RTX-only boot on nullmoth's own hybrid path (NMH-1), in one go. Each step is skipped
# when it is already done, so it can be run again (for example with NMHYBRID=2 for the next level).
#   sudo bash tools/hybrid/rtx-prep.sh                 nullmoth release from $PKG, its NMIntelFB, our auto job off,
#                                                      efi.sh rtx (nmhybrid=${NMHYBRID:-1}, one boot)
#   sudo NMHYBRID=2 bash tools/hybrid/rtx-prep.sh      the same with another level
# Stops at the first failure. Reboot afterwards.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-root}")
PKG=${PKG:-$HOMEU/nmx-build/pkg-3.0}; P=$PKG/x/pkgroot
h() { shasum -a 256 "$1" 2>/dev/null | cut -c1-8; }
die() { echo "STOP: $*"; exit 1; }

[ -f "$P/install.sh" ] || die "no extracted package in $P"
(cd "$P" && shasum -a 256 -c SHA256SUMS --quiet) || die "package files do not match SHA256SUMS"

# 1. nullmoth release
if [ "$(h /Library/Extensions/NVRM.kext/Contents/MacOS/NVRM)" != "$(h "$P/Library/Extensions/NVRM.kext/Contents/MacOS/NVRM")" ]; then
    sudo -u "${SUDO_USER:-root}" bash "$REPO/tools/checkpoint.sh" save "antes-${PKG##*pkg-}" || die "checkpoint failed"
    CHECK=1 bash "$P/install.sh" > "$HOMEU/install-check.log" 2>&1; grep -q "CHECK PASS" "$HOMEU/install-check.log" || die "install check failed: $HOMEU/install-check.log"
    bash "$P/install.sh" > "$HOMEU/install-${PKG##*pkg-}.log" 2>&1 || die "install failed: $HOMEU/install-${PKG##*pkg-}.log"
    echo "1. nullmoth installed: $(grep -m1 'Undo:' "$HOMEU/install-${PKG##*pkg-}.log")"
else echo "1. nullmoth already installed"; fi

# 2. nullmoth's NMIntelFB (install.sh does not install it)
K=$P/Library/NullMoth/kexts/NMIntelFB.kext
if [ "$(h /Library/Extensions/NMIntelFB.kext/Contents/MacOS/NMIntelFB)" != "$(h "$K/Contents/MacOS/NMIntelFB")" ] \
   || ! kmutil inspect -a x86_64 -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc 2>/dev/null | grep -q com.nullmoth.NMIntelFB; then
    SRC=$K bash "$REPO/tools/intelfb/install.sh" > "$HOMEU/install-intelfb.log" 2>&1 || die "NMIntelFB install failed: $HOMEU/install-intelfb.log"
    echo "2. NMIntelFB installed"
else echo "2. NMIntelFB already installed"; fi
echo "   NMIntelFB $(h /Library/Extensions/NMIntelFB.kext/Contents/MacOS/NMIntelFB)"

# 3. our old bridge job would turn its own sysctls on
if [ -f /Library/LaunchDaemons/com.nmxintel.intelfb-auto.plist ]; then
    bash "$REPO/tools/intelfb/auto.sh" remove >/dev/null || die "could not remove intelfb-auto"; echo "3. intelfb-auto removed"
else echo "3. intelfb-auto already off"; fi

# 4. one boot on the rtx config
bash "$HERE/efi.sh" rtx || die "efi.sh rtx failed"
