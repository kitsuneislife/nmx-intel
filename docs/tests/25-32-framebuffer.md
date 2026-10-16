# Tests 25–32: our framebuffer (`NMXGPUFB`, `fb=1`) on the desktop

> **Summary.** The `NMXGPUFB` freezes were a NULL `IOFBController` (no `IOFBDependentID` → controller only created
> in `open()`); 0026 fixed it and the **desktop ran on our framebuffer at 144 Hz** (test 26). Remaining glitches were
> traced to the firmware display (`.Display_boot`), which WindowServer keeps as a second screen (at x=1920) writing
> into the panel's pages. Removing it from IOKit is not enough (and two ways of removing it crash); **mirroring it
> removes the glitches** (`tools/mirror`). Along the way: VBL off by default (0031) and a shadow framebuffer in RAM
> (0032), because the aperture reads at ~2.6 MB/s.

## Test 25 — 0025 (`fb=1`, NMIntelFB removed)

Two runs, both froze. Trail `… registered fb-new fb-start fb-started @543`, beat `ms=564 irq=107`, attaching=1. Same
point as test 13; no `fb-vbl-on` → not the VBL.
- [measured, IOGraphics `IOFramebuffer.cpp`] `IOFramebuffer::start` already does `PMinit`, `joinPMtree`,
  `registerService`, and creates the `IOFBController` only if `IOFBDependentID` is set
  (`copyController(kDepIDCreate)`); otherwise only in `open()`. Until then `__private->controller` is NULL and
  `IOFramebuffer::setPowerState` (`FBGATEGUARD`, triggered by our `registerPowerDriver`) and WindowServer's
  `extGetAttribute` dereference it.
- [measured] The saved NMIntelFB panics (14:55, 15:03, 16:00; uptime 34–61 s): page fault `CR2 0x170` in
  `IOFramebuffer::extGetAttribute + 0x111`, task WindowServer — `kIOFBWSStartAttribute` reads `controller->fFbs[0]`.
  Explains RTX-2/6b. With i915 loaded the panic is not saved; the Mac just stops.
- [measured, `kexts/NVRM/accel/nvrm-accel.cpp`] Under `NMX_ACCEL`, `fbm` is `nullptr` so `fFB` is never set and
  `nvAccelRmHandles` fails for every surface ("RM refused"). By design (`gpu-port/README.md`, `plugin/nvmtl_vk.c`)
  AMD/Intel Metal is **apps only**; WindowServer draws unaccelerated.

### 0026
`NMXGPUFB` gets `IOFBDependentID = 'NMXI'<<32 | NMXGPU registry id` and `IOFBDependentIndex = 0` before
`IOFramebuffer::start` (trail `fb-dep`, knob `nullmoth-gpu-fbdep`). `nullmoth-gpu-accel` defaults to 0 also with
`fb=1`. `838aa8d3…`.

## Test 26 — 0026 — **desktop on `NMXGPUFB`, no freeze**

Trail `… fb-dep fb-start fb-started fb-pm fb-reg fb-ps1 published fb-con fb-en fb-irq fb-ga fb-gac fb-cur fb-modes
fb-inf fb-cf fb-tim fb-pix fb-sa fb-setmode fb-ap fb-vram fb-sac fb-gam @199443`; beat `ms=207585 open=30
ioctl=130`. `system_profiler`: main display 1920x1080 @ **144 Hz** on `NMXGPUFB`.
- Lukas: desktop reached; cursor fast (was slow); animations no longer stall; **many glitches** (flicker, parts drawn
  only under the cursor).
- Two framebuffers online (ours + `.Display_boot`); WindowServer registered VBL (`fb-irq`) but never enabled it.

### 0027
VBL enabled at `registerForInterruptType` (IOGraphics only calls `setInterruptState` to throttle); after
`registerService`, `terminate()` IONDRVs of the same PCI via `getMatchingServices` (knob `nullmoth-gpu-ndrv`).
`3fc8feaf…`.

## Test 27 — 0027
Trail `… fb-reg fb-ps1 ndrv-none published … fb-tim fb-vbl … fb-vbl-off fb-gam fb-vbl-on`. VBL runs. `ndrv-none`:
`.Display_boot` not found (although it is under `GFX0@2`). WindowServer log: `Creating FB 1 of 2` / `2 of 2`.

### 0028
Walk GFX0's children in the service plane, `terminate()` every IOFramebuffer that is not ours
(`ndrv-c<children>`). `d002eae8…`.

## Test 28 — 0028 — freeze on terminate
Trail `… fb-pm fb-ps1 fb-reg @548`. [measured, IOGraphics] `IOFramebuffer::terminate` takes `FBGATEGUARD`; the
firmware IONDRV has no dependent ID and is not opened yet → NULL controller again.

### 0029
Record the firmware framebuffers (`ndrv-c<children>-<found>`); a thread (`ndrv-wait`) waits up to 10 min for each to
get its `IODisplayConnect` child (created in `open()`, controller exists), waits 2 s, terminates (`ndrv-term`,
`ndrv-gone`, `ndrv-timeout`). `a954ffc0…`.

## Test 29 — 0029 — panic in an Apple driver
Trail `… ndrv-c2-1 published ndrv-wait … fb-vbl-off ndrv-term @45316`. Froze at the Apple-logo progress screen.
[measured] `Kernel-2026-10-16-170517.panic`: `CR2 0` in `AppleUpstreamUserClientDriver::fbNotificationOccurred +
0x1e` ← `IOFramebuffer::deliverFramebufferNotification(kIOFBNotifyTerminated)` ← `IOFramebuffer::terminate` ←
`ndrvDropThread`.

### 0030
`s->IOService::terminate()` (skips the IOFramebuffer override and its notification). `52305765…`.

## Test 30 — 0030 — one IOKit framebuffer, no freeze, same glitches
Trail `… ndrv-term ndrv-gone fb-gam fb-vbl-on @139143`; ioreg has only `NMXGPUFB`; `system_profiler` one display.
`Unsupported sw composite destination` (~5,000/boot) appears in **every** boot, IONDRV ones included → normal for
unaccelerated WindowServer.

### 0031
No VBL by default (`kIOReturnUnsupported`, trail `fb-novbl`), like IONDRV; knob `nullmoth-gpu-vbl=1`. `c1445517…`.

## Test 31 — 0031 — same glitches; the aperture is very slow
Video `HACKINTOSH_GLITCHES_1.mp4`: login clock flickers/freezes, text vanishes while typing, avatar appears only under
the cursor, windows/animations flicker.
- [measured, `tools/vram/dump.c`] VRAM content matches the desktop.
- [measured, `tools/vram/watch.c`] reading one 8 MB frame from the published VRAM (GGTT aperture, uncached) takes
  ~3.2 s (~2.6 MB/s). `top`: WindowServer ~260 % CPU.

### 0032
Shadow framebuffer: 8 MB contiguous RAM (`IOBufferMemoryDescriptor`) published as VRAM/aperture; a thread copies
changed rows to the aperture (mapped write-combined) ~60×/s, `sfence` (trail `fb-shadow`, `fb-copy`,
`fb-noshadow`; knob `nullmoth-gpu-shadow`). `9823079e…`.

## Test 32 — 0032 — **the stale firmware display**
Trail `… fb-start fb-shadow fb-started … fb-copy ndrv-term ndrv-gone fb-gam @322996`. Lukas: glitches nearly the
same; update lines sweep the screen; **the cursor leaving the right edge appears on the left and leaves a white
square**; the Dock missing. WindowServer still ~225 % CPU (main ~85 % + 6 compositor threads ~20 %).
- [measured, `tools/vram/displays.c`] CoreGraphics: **2 online, active displays** — ours `5b81c5c1` (0,0) and the
  firmware's `5b81c5c0` at (1920,0), although `.Display_boot` left IOKit. 0030 skips `kIOFBNotifyTerminated`, so
  WindowServer never drops it.
- [inferred] This was the glitch source since test 26: the firmware screen draws straight into the GOP pages the panel
  scans; the cursor "to the right" is on it; the Dock may live there.
- [measured] Live `CGConfigureDisplayMirrorOfDisplay(firmware → ours)`: **glitches gone** (Lukas, looking at the
  screen).
- `tools/mirror`: LaunchAgent `com.nmxintel.mirror` (login window + session); if `NMXGPUFB` exists, mirrors onto the
  main display every display with the same panel (vendor/model/serial; external monitors untouched); re-applies
  after each reconfiguration and every 5 s in the first minute. Tested live: re-mirrored in < 1 s.

State after test 32: stable desktop through i915 on `NMXGPUFB`, 1920x1080 @ 144 Hz, no glitches with the mirror;
**no acceleration** (software compositing, ~225 % CPU). Next: [../status.md](../status.md).
