#!/bin/zsh
# Builds the hybrid route's Iris Xe stack for Sequoia: JulioNectar's NootedGreen fork plus its user-space Metal pieces,
# pinned to $XPS_REV, with our diffs from source-fixes/hybrid/*.patch. Apple's 16.0.32 driver bundles come from
# NootedGreen's sle_Internal at $NG_REV. Output stays in ~/nmx-build/hybrid (TSNPL code and Apple binaries: never
# versioned here). Nothing is installed.
set -euo pipefail
HERE=${0:A:h:h:h}
W=$HOME/nmx-build/hybrid; XPS=$W/xps
XPS_REPO=https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe.git; XPS_REV=356c818
NG_REPO=https://github.com/sgiammori/NootedGreen.git; NG_REV=95f81898be65cb9f7b3d370ca78054be4cc8a62d
NG=$XPS/build/deps/NootedGreen

[[ -d $XPS/.git ]] || git clone -q $XPS_REPO $XPS
git -C $XPS checkout -q -f $XPS_REV   # -f drops a previous run's patches
[[ -d $NG/.git ]] || git clone -q $NG_REPO $NG
git -C $NG checkout -q $NG_REV
for p in $HERE/source-fixes/hybrid/*.patch(N); do
  git -C $XPS apply $p
  echo "patch: ${p:t}"
done

(cd $XPS && zsh build-nootedgreen.sh)
zsh $XPS/macos/build-all.sh $NG/sle_Internal/sle

for f in $XPS/build/NootedGreen.kext/Contents/MacOS/NootedGreen $XPS/macos/out/libxedrv.dylib \
         $XPS/macos/out/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver; do
  echo "${f:t} $(shasum -a 256 $f | cut -c1-8)"
done
