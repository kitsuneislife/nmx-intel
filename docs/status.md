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
- **RTX path (Intel test driver off):** RTX-8 ended the freezes; RTX-9 registered the panel as NVAccel head 0;
  RTX-10 got **WindowServer on the RTX's Metal** with VRAM mapped; RTX-11 made the VBL fire. Still no frame: CoreDisplay
  saw the panel on the Intel GPU, which has no display pipe. intelfb-0013 moves NMIntelFB under NVRM (claim + nub).
  Details: [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
- **Built, not installed:** `NMIntelFB b230f46f…`. Installed: `NMIntelFB c07eb921…` (RTX-11). NVRAM
  `nullmoth-intelfb-delay=45`.

## Next step

RTX-12: `tools/intelfb/install.sh`, reboot; 1 min after login `enable.sh`, then `killall -9 WindowServer`.
Success: GPUWrangler lists `fb0:0 /NMIntelFB` under the DG GPU, `nvaccel_iop_ok_h0` growing, the login screen back.

## Open problems

1. RTX-12 result (frames copied? CPU copy cost BAR1 → Intel aperture at 144 Hz).
2. Making it automatic at boot (drop the delay so NVRM's auto-go arms it) once it works.
3. Proper ghost fix (WindowServer never adopting `.Display_boot`) still open; mirror covers both paths.
