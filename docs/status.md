# Status

> Last updated: 2026-10-21, UPG-2 (nullmoth 2.5.0) prepared; HYB-15 panicked at 25 s (fbTimingsWorker divide by zero), HYB-15b prepared with the guard fixed; full GT reset at boot (the HYB-14 restart fixed CoreAnimation; firmware engine state is the suspect); 10-19 sleep/wake parked (SLEEP-1/2 fail: macOS always does S3); 10-18 WIFI-8: native Wi-Fi at full speed; UPG-1: nullmoth 2.3.6 works. Keep this file short: it is read at the start of every session.

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
real vblank (5), battery numbers (7), sleep relight: **parked 10-19**: SLEEP-1 (`hibernatemode 25`) and SLEEP-2 (HibernationFixup `hbfx-ahbm=1`) both still did S3 (`type 7`); sleep disabled again (`hibernate.sh off`; the forced power-offs tripped nullmoth's boot guard, fix `sudo nvram -d nullmoth-nv-starts`; GUARD-1 prep: NMIntelFB `241aff3d` stands down then, pending); next idea is a real relight in NMIntelFB, `tools/sleep/hibernate.sh`, [tests/sleep-1-hibernate.md](tests/sleep-1-hibernate.md).
**UPG-1 works:** nullmoth NVIDIA driver 2.3.6 installed with our patches: NVRM `8c8873d5`, NVAccel `8166045f`,
NMIntelFB unchanged; shader cache works (WindowServer keeps its own, 70 MB). Undo: `tools/upgrade/rollback.sh`.
**UPG-2 fails (10-21):** nullmoth 2.5.0 + our patches blinks black (`iop_blank 141`, copy 2.93 ms/frame vs 1.44, GPU-wait
timeouts); rolled back to 2.3.6. UPG-3 (2.5.4) next. Details: [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
**Wi-Fi:** WIFI-1 (MT7921, OverlordDev SimpleMtkWlan): WIFI-3 **connects** (WPA2, DHCP on en2) but dies under load; WIFI-4 hung the boot (configd panic), driver removed. **WIFI-5 works**: flxxxxddd's AirportMtkWlan, native Wi-Fi menu. WIFI-6 (5 GHz): 38 down / 5.1 up. WIFI-7 works (prefer 5 GHz, all networks listed). **WIFI-8 works**: upload was capped by a fixed basic TX rate (wifi5-0005); now 37.1 down / 36.9 up, the line's ceiling. Runbook: [knowledge/wifi.md](knowledge/wifi.md); tests: [tests/wifi-1-mt7921.md](tests/wifi-1-mt7921.md).

## Open problems

1. Cost per frame: CE copy + two CPU copies of 8.3 MB (~4 ms CPU per frame, ~35 % of a core) and nullmoth's
   `displaytrace` (~20 %). Staged plan: [knowledge/bridge-optimization.md](knowledge/bridge-optimization.md).
2. Boot without the 45 s delay (WindowServer accelerated from the start, no restart) — untested since RTX-7's freeze.
3. `Invalid display 0x5b81c5c0` in WindowServer ~17/min; battery cost of the RTX always on (unmeasured).
4. Path A (Intel Metal) parked. **Hybrid proposal (10-21):** Iris Xe via JulioNectar's Tahoe stack + nullmoth
   headless with `nvmtl-allow.txt` routing; target Sequoia (port Julio's Tahoe-only parts); plan H0–H4 in [knowledge/hybrid-route.md](knowledge/hybrid-route.md). **H0 done:** Sequoia offsets measured, only
   `libxedrv`'s preflight needed a fix (source-fixes/hybrid/0001); `tools/hybrid/build.sh` builds it all. **HYB-1/2 fail:** panic when WindowServer
   opens the accelerator (`IntelAccelerator+0x150` NULL); NootedGreen's injected personality also matched the RTX. `efi.sh hybrid` boots hybrid
   once (auto fallback works). **HYB-3:** personality limited to the iGPU (hybrid-0003) → **first desktop on the Iris Xe**, heavy artifacts,
   BCS hang, no Wi-Fi (`-nvoff`). **HYB-4:** no `-v`, same artifacts; WindowServer composited on the RTX (NVAccel ignores `-nvoff`). **HYB-5:** no `nvaccel=1`, same artifacts (Intel side). NootedGreen's IOLog is lost in the unified log; **HYB-6:** `dmesg` shows all NootedGreen fixes hooked (V140 1/4); session too short for runtime lines. **HYB-7:** kernel healthy, artifacts are rendering correctness. **HYB-8:** Julio's Metal tests pass on the Xe. **HYB-9:** glyph atlases upload fine. **HYB-10:** no-op, but HWCAPS shows our fuses: 3 DSS, 48 EU (NootedGreen forces 12 SS, 96). **HYB-11:** real 48 EU, same artifacts. **HYB-12:** bug reproduced offscreen by CARenderer: rotated quad loses a triangle, text/icons/opacity missing, solids/gradients fine. **HYB-13:** geomtest flawed (all dark, MSAA resolve suspect); catest losses change between boots. **HYB-14:** plain Metal geometry = RTX; MSAA black + GPU restart; catest after the restart ≈ RTX. The restart does not rebuild the context template; firmware state survives boot (RCS CCID=0x80, BCS stale ring). **HYB-15:** `-ngreenbootgdrst` full GT reset; panic at 25 s in NootedGreen's timings worker (TRANS_LINK_N1 = 0, divide error). **HYB-15b** (pending): same + worker checks the register ([tests/hybrid-1.md](tests/hybrid-1.md)).
