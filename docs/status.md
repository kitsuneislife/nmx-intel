# Status

> Last updated: 2026-10-16, RTX-15 works; RTX-16 prepared. Keep this file short: it is read at the start of every session.

## Goal and decision

Smooth daily desktop on the internal panel (animations, YouTube). Decided with Lukas (10-16): **path B first** — the
RTX composites with Metal, NMIntelFB shows the frames on the Intel panel. **Path A** (Intel Metal via i915/ANV:
IOAccelerator for `NMXGPUFB`, RM calls on i915 GEM/VM, nvmtl treating Intel as WindowServer-capable) is parked until
B works. 60 Hz is not wanted.

## Where we are

- **RTX path works (RTX-15, 10-16):** the RTX composites the whole desktop with Metal, NVAccel copies each frame into
  NMIntelFB on the Intel panel. Lukas: wallpaper, animations, transparency, YouTube all work; one short stall when
  the session starts. One display only (no ghost). ~89 frames/s copied while busy, 0 failures; WindowServer ~67 %
  CPU (was ~225 % software). Details: [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
- Still manual per boot: `enable.sh`, then `killall -9 WindowServer`. Installed: `NMIntelFB 1d3ea017…`, NVRAM
  `nullmoth-intelfb-delay=45`, Intel test driver off.
- **i915 path (Intel test driver on):** stable software desktop on `NMXGPUFB`, 144 Hz; `tools/mirror` hides the ghost.

## Next step

RTX-16: `sudo bash tools/intelfb/auto.sh install`, reboot, wait at the login window (~1 min) until it restarts by
itself. Success: log `nmx-intelfb-auto` "restarting WindowServer", accelerated login with no manual step.

## Open problems

1. Cost per frame: full 8.3 MB `volatile` word copy in `performTransaction` + a GPU→system-memory sync each frame
   (NVAccel, nullmoth's binary). Options: dirty rows, faster copy, GPU writing into the Intel surface.
2. Boot without the 45 s delay (WindowServer accelerated from the start, no restart) — untested since RTX-7's freeze.
3. `Invalid display 0x5b81c5c0` in WindowServer ~17/min; battery cost of the RTX always on (unmeasured).
4. Path A (Intel Metal) parked.
