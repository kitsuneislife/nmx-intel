#!/bin/bash
# setup.sh: monta a árvore de fontes do NMXGPU em ~/nmx-build, como os scripts do nullmoth esperam
# (lá era /Volumes/MiniData/build/gpu-src; aqui é $NMX_SRC, padrão ~/nmx-build/gpu-src).
#
#   ~/nmx-build/nvidia-macos-driver   nullmoth 2.0.2 (d96eaca), branch nmx-intel-build com nmx-src-paths.patch
#   ~/nmx-build/gpu-src/xkpi          link para nvidia-macos-driver/gpu-port/xkpi
#   ~/nmx-build/gpu-src/kpi/drm-kmod  drm-kmod master c16de0f9fa (2026-10-08, Linux 6.14)
#   ~/nmx-build/gpu-src/kpi/freebsd-src  só sys/compat/linuxkpi, sys/contrib/ck e o include do ACPICA, em bbfd52d
#   ~/nmx-build/gpu-src/linux-6.14    só drivers/gpu/drm/xe e include/uapi, tag v6.14
#
# A revisão do freebsd-src não está escrita no nullmoth. Os forks em override/src batem com qualquer commit
# entre d7e7397 (2026-10-05) e bbfd52d (2026-10-10); o 9d82546 (2026-10-11) já muda o linux_pci.c.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
B=$HOME/nmx-build
S=$B/gpu-src
mkdir -p "$S/kpi"

[ -d "$B/nvidia-macos-driver" ] || git clone --filter=blob:none https://github.com/nullmoth/nvidia-macos-driver.git "$B/nvidia-macos-driver"
cd "$B/nvidia-macos-driver"
if ! git rev-parse -q --verify nmx-intel-build >/dev/null; then
    git checkout -b nmx-intel-build d96eaca
    git apply "$HERE/nmx-src-paths.patch"
fi

[ -d "$S/kpi/drm-kmod" ] || git clone --filter=blob:none --no-checkout https://github.com/freebsd/drm-kmod.git "$S/kpi/drm-kmod"
git -C "$S/kpi/drm-kmod" checkout -q c16de0f9fa

if [ ! -d "$S/kpi/freebsd-src" ]; then
    git clone --shallow-since=2026-09-25 --filter=blob:none --sparse https://github.com/freebsd/freebsd-src.git "$S/kpi/freebsd-src"
    git -C "$S/kpi/freebsd-src" sparse-checkout set sys/compat/linuxkpi sys/contrib/ck sys/contrib/dev/acpica/include
fi
git -C "$S/kpi/freebsd-src" checkout -q bbfd52d

if [ ! -d "$S/linux-6.14" ]; then
    git clone --depth 1 --branch v6.14 --filter=blob:none --sparse https://github.com/torvalds/linux.git "$S/linux-6.14"
    git -C "$S/linux-6.14" sparse-checkout set drivers/gpu/drm/xe include/uapi
fi

ln -sfn ../nvidia-macos-driver/gpu-port/xkpi "$S/xkpi"
cd "$S/xkpi"
# fbroot não vem no repo: é onde os includes "compat/linuxkpi/..." e "contrib/dev/acpica/..." do FreeBSD são achados
mkdir -p fbroot && ln -sfn "$S/kpi/freebsd-src/sys/compat" fbroot/compat && ln -sfn "$S/kpi/freebsd-src/sys/contrib" fbroot/contrib
python3 gen_flags.py "$S/kpi/drm-kmod" amd.flags
mkdir -p obj obj-i915 obj-xe lkobj srcobj xnuobj lklogs logs logs-i915
echo "pronto. build: NMX_SRC=$S, depois all.sh, rt.sh, all-i915.sh, all-xe.sh e kext/build.sh <saída>"
