#!/bin/bash
# build-airport.sh: builds AirportMtkWlan (flxxxxddd/SimpleMtkWlan v1.5.0: the MT7921 driver behind macOS's native
# Wi-Fi menu, IO80211 Sequoia 15.2+ ABI) with our patches (source-fixes/wifi/flx-v1.5.0/*.patch). Source and
# MacKernelSDK pinned by commit; the fork's own build-macos.sh (Command Line Tools only). Debug configuration: the one
# the fork's hardware tests ran with; the persistent log is read with the fork's tools/mtklog.sh.
# Output: ~/nmx-build/wifi5/out/AirportMtkWlan.kext. GPL-2.0; the binary is not versioned (MediaTek firmware inside).
#   bash tools/wifi/build-airport.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")/../.." && pwd)
W=$HOME/nmx-build/wifi5
REPO=https://github.com/flxxxxddd/SimpleMtkWlan.git; REV=${REV:-9a9c2ea703a199dbcc0cd3f1771a9d712e10ca0a}   # v1.5.0
MKS=$HOME/nmx-build/wifi/mks; MKS_REV=3f750085caa17ec3a7880f11c11bf4f48cd6a164   # the fork's submodule commit
[ -d "$W/src/.git" ] || git clone -q "$REPO" "$W/src"
[ -d "$MKS/.git" ] || git clone -q https://github.com/acidanthera/MacKernelSDK.git "$MKS"
git -C "$MKS" checkout -q "$MKS_REV"
git -C "$W/src" fetch -q origin "$REV" 2>/dev/null || true
git -C "$W/src" checkout -q -f -B nmx-wifi5 "$REV"
for p in "$HERE"/source-fixes/wifi/flx-v1.5.0/*.patch; do
  git -C "$W/src" -c user.name=nmx -c user.email=nmx@localhost am -q "$p"
  echo "patch: $(basename "$p")"
done
( cd "$W/src" && rm -rf build && AIRPORT_OS=sequoia MACKERNELSDK="$MKS" ./build-macos.sh Debug AirportMtkWlan ) > "$W/build.log" 2>&1 \
  || { tail -30 "$W/build.log"; echo "build falhou (log: $W/build.log)"; exit 1; }
rm -rf "$W/out" && mkdir -p "$W/out"
ditto "$W/src/build/Debug/sequoia/AirportMtkWlan.kext" "$W/out/AirportMtkWlan.kext"
codesign -f -s - "$W/out/AirportMtkWlan.kext" >/dev/null 2>&1 || true
B=$W/out/AirportMtkWlan.kext/Contents/MacOS/AirportMtkWlan
grep -q -a -- -mtkwlanoff "$B" || { echo "safe-boot switch missing from the binary"; exit 1; }
# Every external symbol must come from a KPI a third-party kext may link (kmutil refuses com.apple.kpi.private:
# WIFI-5's first install failed on thread_call_cancel_wait). _RESERVED vtable slots are bound by the kernel.
LIBS=$(kmutil libraries -p "$W/out/AirportMtkWlan.kext" --arch x86_64 2>/dev/null)
MISSING=$(comm -23 <(nm -u "$B" | awk '{print $1}' | sort -u) <(printf '%s\n' "$LIBS" | awk '/^\t\t/{print $1}' | sort -u) | grep -v _RESERVED || true)
[ -z "$MISSING" ] || { echo "symbols this kernel does not export: $MISSING"; exit 1; }
! printf '%s\n' "$LIBS" | grep -q com.apple.kpi.private || { printf '%s\n' "$LIBS" | grep kpi.private; echo "private KPI used"; exit 1; }
cp "$W/src/tools/mtklog.sh" "$W/out/mtklog.sh"
echo "AirportMtkWlan $(shasum -a 256 "$B" | cut -c1-8) ($(git -C "$W/src" log --oneline -1))"
