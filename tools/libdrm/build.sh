#!/bin/bash
# build.sh: compila o libdrm.2.dylib do nullmoth (b97cbde + gpu-port/patches/libdrm-macos.patch) com a nossa correção
# (source-fixes/libdrm-0001: no macOS, o número de um nó /dev/dri vem do nome, porque os nós do NMXGPU são clones).
# Saída: ~/nmx-build/libdrm/build-nmx/libdrm.2.dylib. Usa um venv com meson e ninja em ~/nmx-build/venv.
set -euo pipefail
R=$(cd "$(dirname "$0")/../.." && pwd)
B=$HOME/nmx-build
[ -d "$B/venv" ] || { python3 -m venv "$B/venv"; "$B/venv/bin/pip" install -q meson ninja; }
if [ ! -d "$B/libdrm" ]; then
    git clone -q https://gitlab.freedesktop.org/mesa/drm.git "$B/libdrm"
    git -C "$B/libdrm" checkout -q -b nmx-intel b97cbde
    git -C "$B/libdrm" apply "$B/nvidia-macos-driver/gpu-port/patches/libdrm-macos.patch"
    git -C "$B/libdrm" apply "$R/source-fixes/libdrm-0001-darwin-node-numbers-from-names.patch"
fi
cd "$B/libdrm"
export PATH=$B/venv/bin:$PATH
[ -d build-nmx ] || meson setup build-nmx -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
    -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled \
    -Dcairo-tests=disabled -Dman-pages=disabled -Dvalgrind=disabled -Dtests=false -Dudev=false \
    -Dc_link_args=-Wl,-install_name,/Library/GPUBundles/nvmtl/libdrm.2.dylib
ninja -C build-nmx
codesign -s - -f build-nmx/libdrm.2.dylib
shasum -a 256 build-nmx/libdrm.2.dylib
