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
- **RTX path (Intel test driver off):** RTX-8 ended the freezes (own controller). RTX-9 (head 0): NVAccel registered
  the panel's pipe, but the restarted WindowServer hung: NVAccel asks its primary framebuffer for RM handles and VRAM,
  which only NVRMFB answered (and NVRMFB quits with no NVIDIA display). intelfb-0011: NMIntelFB owns an NVKMS device
  and answers them. Details: [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
- **Built, not installed:** `NMIntelFB 29893f31…`. Installed: `NMIntelFB 0d6239e0…` (RTX-9). NVRAM
  `nullmoth-intelfb-delay=45`.

## Next step

RTX-10: `tools/intelfb/install.sh`, reboot; 1 min after login `enable.sh`, then `killall -9 WindowServer`
(TERM is ignored). Success: trail `kapi-dev … rmh vram1`, `nvaccel_iop_ok_h0` growing, the desktop back after login.

## Open problems

1. RTX-9 result (pipe registered? frames copied? CPU copy cost into the aperture at 144 Hz).
2. Making it automatic at boot (drop the delay so NVRM's auto-go arms it) once RTX-9 works.
3. Proper ghost fix (WindowServer never adopting `.Display_boot`) still open; mirror covers both paths.
