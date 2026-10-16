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
- **RTX path (Intel test driver off, now installed):** RTX-8 (intelfb-0009, own controller) **ended the freezes**:
  WindowServer opened NMIntelFB fully, Mac stayed up. But NVAccel only uses head 0 as its framebuffer, so the panel
  (head 4) was never registered and WindowServer stayed in software. intelfb-0010 publishes it as head 0.
  Details: [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
- **Built, not installed:** `NMIntelFB 0d6239e0…`. Installed: `NMIntelFB ca82df9d…` (RTX-8), `NMXGPU 9823079e…`
  (inactive while the Intel test driver is off). NVRAM `nullmoth-intelfb-delay=45`.

## Next step

RTX-9: `tools/intelfb/build.sh` output → `tools/intelfb/install.sh`, reboot; after login `enable.sh` (now also
`nvaccel_iop=1`) + WindowServer restart. Success: `heads_piped` 0x1, `nvaccel_iop_ok_h0` growing, smooth desktop.

## Open problems

1. RTX-9 result (pipe registered? frames copied? CPU copy cost into the aperture at 144 Hz).
2. Making it automatic at boot (drop the delay so NVRM's auto-go arms it) once RTX-9 works.
3. Proper ghost fix (WindowServer never adopting `.Display_boot`) still open; mirror covers both paths.
