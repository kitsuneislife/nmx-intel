# Status

> Last updated: 2026-10-16, RTX-8 prepared. Keep this file short: it is read at the start of every session.

## Goal and decision

Smooth daily desktop on the internal panel (animations, YouTube). Decided with Lukas (10-16): **path B first** — the
RTX composites with Metal, NMIntelFB shows the frames on the Intel panel. **Path A** (Intel Metal via i915/ANV:
IOAccelerator for `NMXGPUFB`, RM calls on i915 GEM/VM, nvmtl treating Intel as WindowServer-capable) is parked until
B works. 60 Hz is not wanted.

## Where we are

- **i915 path (Intel test driver on):** stable desktop on `NMXGPUFB`, 1920x1080 @ 144 Hz, software compositing
  (~225 % CPU). Ghost firmware display hidden by `tools/mirror` — which had never run (launchd EX_CONFIG); fixed.
- **RTX path:** RTX-1..7 froze. Root cause [inferred, strong]: NMIntelFB sat alone at index 4 of NVRM's dependent
  group (no NVRMFB head starts on this laptop: `heads 0x0`), so IOGraphics' `fFbs[0]` was NULL. intelfb-0009 gives it
  its own controller. Details: [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
- **Built, not installed:** `NMIntelFB ca82df9d…`; updated `tools/mirror`. Installed: `NMXGPU 9823079e…`, libdrm
  `719cb625…`. NVRAM `nullmoth-intelfb-delay=45` kept.

## Next step

RTX-8: reinstall the mirror, turn the Intel test driver off in the app, `tools/intelfb/install.sh`, reboot; after
login `tools/intelfb/enable.sh` + WindowServer restart. Read `nullmoth-intelfb-trail`/`-beat` (expect `dep-own`,
`open-idx0`), `debug.nvaccel_iop_ok_h4` > 0 means frames reach the panel.

## Open problems

1. RTX-8 result (freeze gone? frames copied? speed of the CPU copy into the aperture at 144 Hz).
2. Ghost firmware display on the RTX path too (IONDRV stays); mirror now covers `NMIntelFB`.
3. Proper ghost fix (WindowServer never adopting `.Display_boot`) still open.
