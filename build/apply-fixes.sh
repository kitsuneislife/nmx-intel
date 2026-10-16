#!/bin/bash
# apply-fixes.sh: aplica source-fixes/ na árvore de ~/nmx-build (depois de setup.sh) e faz commit em cada clone.
#   0001, 0004, 0006, 0008 a 0015 e 0017 a 0022, 0024 a 0028 no nullmoth (branch nmx-intel-build), 0002, 0003, 0005, 0007, 0016 e 0023 no drm-kmod (branch nmx-intel).
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
apply "$B/nvidia-macos-driver" 0010-diagnostic-trail-in-nvram.patch
apply "$B/nvidia-macos-driver" 0011-finer-trail-publish-steps-and-takeover-failures.patch
apply "$B/nvidia-macos-driver" 0012-heartbeat-after-attach-and-reap-freed-objects-before-takeover.patch
apply "$B/nvidia-macos-driver" 0013-trail-each-framebuffer-call-earlier-heartbeat-bisect-switches.patch
apply "$B/nvidia-macos-driver" 0014-hold-the-boot-framebuffer-stolen-pages-and-stamp-the-beat-in-the-trail.patch
apply "$B/nvidia-macos-driver" 0015-test-switches-in-nvram-and-the-beat-in-the-trail-first.patch
apply "$S/kpi/drm-kmod" 0016-i915-no-fbc-and-no-psr-on-xnu.patch
apply "$B/nvidia-macos-driver" 0017-one-vnode-per-device-node-so-drm-opens-work.patch
apply "$B/nvidia-macos-driver" 0018-enxio-from-fdopen-is-success.patch
apply "$B/nvidia-macos-driver" 0019-get-pciinfo-finds-the-pci-function-above-the-drm-child.patch
apply "$B/nvidia-macos-driver" 0020-nvram-log-of-every-user-request.patch
apply "$B/nvidia-macos-driver" 0021-rcu-readers-may-block.patch
apply "$B/nvidia-macos-driver" 0022-heartbeat-every-second-irq-count-io-time.patch
apply "$S/kpi/drm-kmod" 0023-i915-power-events-in-the-request-log.patch
apply "$B/nvidia-macos-driver" 0024-no-nmxaccel-claim-without-our-framebuffer.patch
apply "$B/nvidia-macos-driver" 0025-fb-vbl-on-its-own-thread-only-when-enabled.patch
apply "$B/nvidia-macos-driver" 0026-fb-own-dependent-id-accel-off-by-default.patch
apply "$B/nvidia-macos-driver" 0027-vbl-on-from-registration-drop-firmware-fb.patch
apply "$B/nvidia-macos-driver" 0028-drop-firmware-fb-by-pci-children.patch
