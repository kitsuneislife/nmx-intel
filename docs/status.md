# Status

> Last updated: 2026-10-18, UPG-1: nullmoth 2.3.6 works. Keep this file short: it is read at the start of every session.

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
- **Automatic since RTX-16:** `tools/intelfb/auto.sh` (LaunchDaemon) enables at boot; the login window's WindowServer
  adopts the RTX by itself (no restart). Installed: `NMIntelFB 1d3ea017…`, NVRAM
  `nullmoth-intelfb-delay=45`, Intel test driver off.
- **i915 path (Intel test driver on):** stable software desktop on `NMXGPUFB`, 144 Hz; `tools/mirror` hides the ghost.

## Next step

Bridge plan: stages 0–3 done. Our NVAccel `41260d45` (accel-0001): the direct copy cuts ~31 % per frame (RTX-18);
`auto.sh` turns it on at boot (RTX-19, works). **RTX-20 (stage 4a) works**: the panel scans out of RAM and the copy
engine writes it, 2.78 → 1.44 ms per frame, no CPU copy left (NMIntelFB `6145a549`, NVAccel `a4d13738`). RTX-21: `auto.sh`
turns it on at boot (works). **Sleep breaks the panel**: S3 resets the Intel display engine (RTX-22: every display
register 0 after wake) and nothing relights it; sleep is off for now (`pmset`). **RTX-23** flip (4b) works (NMIntelFB `59c98103`, NVAccel
`659dfa20`); RTX-24: `auto.sh` turns it on at boot (works). **RTX-25** (4c) works: NVRM `f5171d7b` (binary patch) sleeps during the copy; kernel_task ~4 %
(RTX-16: ~40 %). Stage 4 done. **BL-2** brightness works (NMIntelFB `36afddf1`). Open:
real vblank (5), battery numbers (7), sleep relight.
**UPG-1 works:** nullmoth NVIDIA driver 2.3.6 installed with our patches: NVRM `8c8873d5`, NVAccel `8166045f`,
NMIntelFB unchanged; open: does the new shader cache (`aircache`) fill. Undo: `tools/upgrade/rollback.sh`. Details: [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
**Wi-Fi:** WIFI-1 (MT7921, OverlordDev SimpleMtkWlan): WIFI-3 **connects** (WPA2, DHCP on en2) but dies under load; WIFI-4 hung the boot (configd panic), driver removed: [tests/wifi-1-mt7921.md](tests/wifi-1-mt7921.md).

## Open problems

1. Cost per frame: CE copy + two CPU copies of 8.3 MB (~4 ms CPU per frame, ~35 % of a core) and nullmoth's
   `displaytrace` (~20 %). Staged plan: [knowledge/bridge-optimization.md](knowledge/bridge-optimization.md).
2. Boot without the 45 s delay (WindowServer accelerated from the start, no restart) — untested since RTX-7's freeze.
3. `Invalid display 0x5b81c5c0` in WindowServer ~17/min; battery cost of the RTX always on (unmeasured).
4. Path A (Intel Metal) parked.
