#!/bin/bash
# apply-fixes.sh: aplica source-fixes/ na árvore de ~/nmx-build (depois de setup.sh) e faz commit em cada clone.
#   0001, 0004, 0006, 0008 e 0009 no nullmoth (branch nmx-intel-build), 0002, 0003, 0005 e 0007 no drm-kmod (branch nmx-intel).
# Pode rodar de novo: um patch que já está aplicado (tag fix-NNNN no clone) é pulado.
set -euo pipefail
F=$(cd "$(dirname "$0")/../source-fixes" && pwd)
B=$HOME/nmx-build
S=$B/gpu-src

apply() {   # apply <repo> <patch>; cada patch aplicado ganha a tag fix-NNNN no clone
    local repo=$1 p=$F/$2 tag=fix-${2%%-*}
    if git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        echo "já aplicado: $2"
        return
    fi
    if git -C "$repo" apply --check -R "$p" 2>/dev/null; then
        echo "já aplicado (sem tag): $2"
    else
        git -C "$repo" apply "$p"
        git -C "$repo" add -A -- $(grep '^+++ b/' "$p" | sed 's|^+++ b/||')
        git -C "$repo" commit -qm "$2"
        echo "aplicado: $2"
    fi
    git -C "$repo" tag "$tag"
}

git -C "$S/kpi/drm-kmod" rev-parse -q --verify nmx-intel >/dev/null || git -C "$S/kpi/drm-kmod" checkout -q -b nmx-intel
apply "$B/nvidia-macos-driver" 0001-linux_pci-match-only-the-probing-driver.patch
apply "$S/kpi/drm-kmod" 0002-i915-intel_pch-guess-the-pch-when-none-is-visible.patch
apply "$S/kpi/drm-kmod" 0003-i915-dp_tunnel-no-manager-is-not-an-error.patch
apply "$B/nvidia-macos-driver" 0004-display-bridge-i915-buffer-in-stolen.patch
# 0005 só tem efeito com -DNMX_DRM_DEBUG (a etapa "debug" do build-all.sh)
apply "$S/kpi/drm-kmod" 0005-drm-debug-driver-and-kms-in-diagnostic-builds.patch
apply "$B/nvidia-macos-driver" 0006-display-bridge-i915-take-over-the-boot-framebuffer.patch
apply "$S/kpi/drm-kmod" 0007-i915-ggtt-hold-the-boot-framebuffer-range.patch
apply "$B/nvidia-macos-driver" 0008-display-bridge-i915-bind-the-boot-buffer-in-the-held-range.patch
apply "$B/nvidia-macos-driver" 0009-display-bridge-boot-fb-flag-bits-and-keep-the-gpu-awake.patch
