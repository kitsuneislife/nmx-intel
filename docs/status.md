# Status

> Last updated: 2026-10-16, RTX-8 prepared. Keep this file short: it is read at the start of every session.

## Goal and decision

Smooth daily desktop on the internal panel (animations, YouTube). Decided with Lukas (10-16): **path B first** — the
RTX composites with Metal, NMIntelFB shows the frames on the Intel panel. **Path A** (Intel Metal via i915/ANV:
IOAccelerator for `NMXGPUFB`, RM calls on i915 GEM/VM, nvmtl treating Intel as WindowServer-capable) is parked until
B works. 60 Hz is not wanted.

## Where we are

- **i915 path (Intel test driver on):** stable desktop on `NMXGPUFB`, 144 Hz, software compositing (~225 % CPU).
  Ghost firmware display hidden by `tools/mirror` (fixed 10-16: it had never run; now `state = running`).
- **RTX path (Intel test driver off):** step by step, each test past the last one's wall: RTX-10 WindowServer on the
  RTX's Metal; RTX-12 panel under the NVIDIA GPU; RTX-13 display pipe (AGDC 0x980); RTX-14 plane (AGDC K5):
  **WindowServer now composites the whole desktop on the RTX**, but every display-pipe transaction fails before
  NVAccel ("Fallback GPU Display Pipe transaction submission failed"). intelfb-0016 gives the pipe a VRAM scanout
  resource. Details: [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
- **Built, not installed:** `NMIntelFB 1d3ea017…`. Installed: `NMIntelFB a96fc475…` (RTX-14). NVRAM
  `nullmoth-intelfb-delay=45`.

## Next step

RTX-15: `tools/intelfb/install.sh`, reboot; 1 min after login `enable.sh`, then `killall -9 WindowServer`.
Success: trail `scanres`, kernel `iop: K6 …`, `nvaccel_iop_ok_h0` growing, the login screen on the panel. If the
submission still fails: disassemble IOAcceleratorFamily2's transaction path (BootKC) for the refusing check.

## Open problems

1. RTX-15 result (frames copied? CPU copy cost BAR1 → Intel aperture at 144 Hz).
2. Making it automatic at boot (drop the delay so NVRM's auto-go arms it) once it works.
3. Proper ghost fix (WindowServer never adopting `.Display_boot`) still open; mirror covers both paths.
