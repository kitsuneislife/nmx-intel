# Status

> Last updated: 2026-10-16, after test 32. Keep this file short: it is read at the start of every session.

## Where we are

- **Working:** i915 drives the panel (eDP 1920x1080 @ 144 Hz) through our IOFramebuffer `NMXGPUFB`. Desktop stable,
  no freezes; glitch-free with `tools/mirror`. ANV (Vulkan) enumerates "Intel(R) Graphics (RPL-P)".
- **Not working:** acceleration. WindowServer composites in software (~225 % CPU). NMXAccel is off by default.
- **Installed on the Mac (expected):** `NMXGPU 9823079e…` (fixes 0001–0032), libdrm `719cb625…`,
  `tools/probe`, `tools/mirror` (if Lukas ran its installer), knobs at defaults (`nullmoth-gpu-fb` unset = 1).
- **Workarounds in place:** the firmware display is a ghost screen in WindowServer (IOKit removal does not reach
  WindowServer); `tools/mirror` mirrors it. It still costs compositing time.

## Open problems (ranked)

1. **Ghost firmware display.** Proper fix: keep WindowServer from ever adopting `.Display_boot` (e.g. stop IONDRV
   before WindowServer starts without a NULL controller), or make WindowServer drop it on termination.
2. **No acceleration.** See below.
3. **CPU cost** of software compositing at 144 Hz (report 60 Hz? fewer redraws?).

## What acceleration needs (two paths)

**A. Intel Metal for WindowServer (via i915/ANV).** Large.
1. An IOAccelerator WindowServer accepts for `NMXGPUFB`: NMXAccel with `fFB` = our framebuffer (under `NMX_ACCEL` it
   is never set) and the display pipe/scan-out resources wired (`initFramebufferResource`, flips or copies).
2. The RM side NMXAccel calls (`NVRM_GPUVA_FN_HANDLES`, GPU VA alloc/map) implemented in NMXGPU on top of i915 GEM/VM.
3. The nvmtl plugin treating the Intel device as WindowServer-capable (today "app-only GPU" for AMD/Intel).

**B. RTX composites, Intel panel displays (NMIntelFB).** Closer: the NVIDIA side exists (head 4, copy path).
Previous freezes match the IOFBController pitfall (`fFbs[0]` NULL when NMIntelFB is index 4 of NVRM's group and
head 0 never opens). Retry with that knowledge; i915 is not involved (Intel test driver off).

## Next step

Decide with Lukas between A and B. Recommendation: B first (shorter path to an accelerated desktop).
