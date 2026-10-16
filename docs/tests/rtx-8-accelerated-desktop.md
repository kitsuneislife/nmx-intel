# Tests RTX-8 – : the RTX composites, the Intel panel shows it (accelerated desktop)

> **Summary.** The RTX path resumed on 2026-10-16 as the shortest way to an accelerated desktop (decision with Lukas;
> Intel Metal, path A of [../status.md](../status.md), waits until this works). RTX-8 tests one change: NMIntelFB in
> an `IOFBController` of its own (intelfb-0009) instead of index 4 of NVRM's group, where `fFbs[0]` was NULL because
> no NVRMFB head ever starts on this laptop.

Setup as in [rtx-1-7-nmintelfb.md](rtx-1-7-nmintelfb.md): Intel test driver **off** (no `nmxintel=1`),
`tools/intelfb/install.sh`, then at run time `tools/intelfb/enable.sh` (`debug.nvaccel_igpu=1`, `debug.nvaccelfb=3`)
and a WindowServer restart. NVRAM `nullmoth-intelfb-delay=45` kept from RTX-7 (same conditions, one variable).

## Evidence before RTX-8 (2026-10-16, Intel test driver on)
- [measured, ioreg] NVRM `nvrm-display = "heads 0x0 accel 0 …"`; four `NVRMDisplay` nubs (`fb-index` 0–3), index 0
  with `connected-displays = 0`, none with an NVRMFB child.
- [measured, IOGraphics `IOFramebuffer.cpp`] `open()`: `controller->fFbs[IOFBDependentIndex] = this`;
  `FOREACH_FRAMEBUFFER` stops at the first NULL; `kIOFBWSStartAttribute` reads `fFbs[0]->messaged`.
- [measured, NVAccel `nvrm-accel.cpp`] `fbPublished` takes the head number from `IOFBDependentIndex` once, at first
  publish; frames reach a CPU-only scan-out (NMIntelFB) by copy, decided by `kva && !phys`, not by the index.
- [measured, `IOFramebuffer::probeAccelerator`] the accelerator is found by walking the PCI device's children; the
  dependent ID plays no part.

### intelfb-0009
Own `IOFBDependentID 0x4E4D494E00000001`, `IOFBDependentIndex 4` before `IOFramebuffer::start` (NVAccel → head 4);
`open()` override sets the index to 0 before `IOFramebuffer::open`. Trail `dep-own` (or `dep-nvrm` with
`nullmoth-intelfb-dep=2`), `open-idx0`. [unverified] NVAccel must see the publish before WindowServer opens the
panel; the 45 s delay keeps that order. `NMIntelFB ca82df9d…`.

Also: `tools/mirror` fixed (it never ran: launchd EX_CONFIG, see pitfalls) and now also acts when `NMIntelFB` exists.

## RTX-8 — intelfb-0009 — **no freeze**; NVAccel never takes the panel
Intel test driver off; boot 19:08:38. Lukas: desktop came up normally; `enable.sh` answered "NMIntelFB not active".
- [measured] Trail `start wait go mmio mode-A-1920x1080-s0 surf dep-own fb-started ga:gnps vbl pm power sp1 sp-done ok
  open-idx0 con ec … ga:vrsv ga:clam sa:capd gam2 alive`; beat `ms=163973 vbl=0 calls=114 last=gam2`. First time
  WindowServer opened NMIntelFB fully and the Mac stayed up (the 2-min guard cleared). ioreg: `IOFBDependentIndex = 0`,
  `display0`/`AppleDisplay` under NMIntelFB.
- [measured] `enable.sh` bug: `ioreg -c NMIntelFB -d1` lists only the root (0 matches); needs `-r`. Fixed.
- [measured, kernel log] `NVAccel: NMIntelFB published -- … (index 4 kept)` at 19:09:37; earlier, 19:09:17–26,
  `registerFramebuffer(1): no framebuffer has published yet` (NVRM auto-go); 19:09:51 `headless check: no NVIDIA
  display head after 60 s -- MetalPluginName restored WITHOUT arming … WindowServer stays on the display's GPU
  (NMIntelFB)`. sysctl: `nvaccel_headless 1`, `nvaccelfb 0`, `nvaccel_iop 0`. NVRM `nvrm-display = heads 0x0 accel 0`.
- [measured, source] NVAccel makes only index 0 its `fFB`; `registerFramebufferLocked` returns early without `fFB`, so
  `debug.nvaccelfb=3` could never register head 4 here. NVRM's auto-go (`NVRM.cpp`) writes `nvaccelfb=1`, `4`, then
  `nvaccel_iop=1` only after heads publish (≤ 20 s wait); `performTransaction` (the copy into the panel) refuses while
  `nvaccel_iop=0`.
- [measured, source] Every other `fFB` use (VRAM alloc/free, RM handles, CRC, flips) calls NVRM functions that
  NMIntelFB answers `kIOReturnUnsupported` — the same failure as `fFB` NULL; flips refuse non-NVRM framebuffers.

### intelfb-0010
In its own group the panel publishes as NVAccel head **0** (knob `nullmoth-intelfb-head=4` = RTX-8). Trail
`dep-own-h0` / `dep-own-h4`. `enable.sh` also writes `debug.nvaccel_iop=1` and prints heads/iop counters (h0, h4).
Delay 45 s kept so NVRM's auto-go does not arm anything at boot; enabling stays manual and a reboot undoes it.
`NMIntelFB 0d6239e0…`. Can NVAccel build here? No: needs nullmoth's `open-gpu-kernel-modules` tree (`~/ogkm610`).

## RTX-9 — intelfb-0010 (pending)
