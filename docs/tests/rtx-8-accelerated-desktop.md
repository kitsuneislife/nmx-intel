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

## RTX-9 — intelfb-0010 — pipe registered; the new WindowServer hangs
Boot 19:18:09. `enable.sh`: `nvaccelfb 1`, `nvaccel_iop 1`, `headless 0`, `heads_published 1`, `heads_piped 1`.
`killall WindowServer` did nothing (same pid 990, started 19:19:09); `killall -9` → the screen showed the `-v`
console text and stayed so (photos: AppleKeyStore lines, `[5005(nmx-mirror)]`); Lukas forced a power-off, boot 19:26:46.
- [measured, kernel log 19:21:07] `found_framebuffer(NMIntelFB index 0) … index 0 -> pipe 0`, `initFramebufferResource
  (head 0, index 0): CPU-only scanout 1920 x 1080 pitch 7680 … frames are copied`, `MetalPluginName restored`,
  `iop: … transaction hooks OPEN`.
- [measured] 19:24:20 the new WindowServer opened the accelerator (IOAccelDevice2, NV2DContext, NVSurface,
  **IOAccelDisplayPipeUserClient2**); 19:24:23 `NVTask::allocate: RM refused 8294400 bytes -- no GPU address`
  (1920×1080×4), again 19:25:00 and 19:25:33. Nothing reached the panel.
- [measured, source] `nvAccelGpuVaAlloc` → `nvAccelRmHandles` asks `fFB` for `nvRmHandles` (the NVKMS device whose
  `hRmClient` NVRM's `nvGpuVaAlloc` uses); `NVVidMemory` asks `fFB` for `nvAllocVram`/`nvFreeVram`. NVRMFB answers
  them; NMIntelFB said unsupported. NVRMFB itself had allocated the device and quit: `only 0 display(s) connected`.
- [inferred] So the RTX-path needs, on this laptop, a framebuffer that owns an NVKMS device; head 0 is the only one
  NVAccel asks.

### intelfb-0011
NMIntelFB allocates its own NVKMS device (`allocateDevice` from the `NVRMDisplay` nub's `nvkms-kapi` table and
`gpu-id`; no ownership grab) and answers `nvRmHandles`, `nvAllocVram` (NVRMFB's grant: SCANOUT pitch video memory,
kernel map, `phys-for-va`, zero + live check, cookie; budget half of an ≥ 4 GB BAR1) and `nvFreeVram`. Trail
`kapi-dev` / `kapi-none` / `kapi-fail` / `kapi-off`, `rmh`, `vram1`. Knob `nullmoth-intelfb-kapi=0`. Headers:
open-gpu-kernel-modules `610.57.04` (NVRM's tag), fetched by `build.sh`. [measured] `NVRMRmHandles` is
`{version, kapiDevice, hClient, hDevice, hSubDevice}` (checked against `nvrm_gpuva_abi.h`). `NMIntelFB 29893f31…`.
[unverified] the copy path speed: WindowServer's frames would be read through BAR1 by the CPU.

## RTX-10 — intelfb-0011 — WindowServer runs on the RTX; nothing reaches the panel
Boot 19:38; `enable.sh` 19:41:35 (`heads_piped 1`); `killall -9` → screen stayed on the `-v` console (photo); Lukas
waited, then forced a power-off (boot 19:44:00).
- [measured, kernel log] 19:41:51 `trail: rmh`, `RM handles: kapiDevice … *** the accelerator can now build GPU page
  tables ***`; three `nvAllocVram: 8323072 bytes VRAM, phys 0x7c22800000…` (+ 64 KB, 256 KB), each `MM commit: MAPPED
  gpuVA 0x120000000 … *** the GPU can reach these bytes ***`; `surfvram` ok 2 refused 0. 24 MB in use at most.
- [measured, WindowServer log] `NVMTL: vk: UP in this Metal process — "NVIDIA GeForce RTX 3050 6GB Laptop GPU (NVK
  GA107-A)"`, command queue, CoreDisplay metallib, samplers; `IOAccelDisplayPipeUserClient2` opened. WindowServer
  stayed alive (touchpad events 19:42:23), no crash report. **No display-pipe transaction** (no `iop: K6` line).
  GPUWrangler: `gpu 0xd9df (IG) 8086.a7a8 … fb0:0 /NMIntelFB`, `gpu 0xcb26 (DG) 10de.25ac … accel /NVAccel`;
  `IOPresentment: Unable to get AGDC information … Unable to acquire map` (also on IG).
- [measured, trail in the log] after `found_framebuffer`: `ga:mirr is vbl-off`; never `vbl-on`, never `vbl1`; beat
  `vbl=0` in every NMIntelFB test. NVRMFB's `setInterruptState` is a no-op and its VBL always fires (hw vblank or
  timer). [inferred] the accelerated display pipe waits for a vsync that never comes.
- [measured] `kapi: … VRAM budget 48 MB of BAR1 64 MB`: `getDeviceMemoryWithRegister(BAR1)` is stale after NVRM
  places the 8 GB BAR1 (allocations landed at BAR1 + 552 MB).

### intelfb-0012
VBL fires whenever registered (`fVblOn` set at registration, `setInterruptState` cannot turn it off); knob
`nullmoth-intelfb-vbl=0` = old behaviour; trail `vbl-always`, first fire `vbl1`. BAR1 = first device range ≥ 256 MB
(NVRMFB's `surveyBar1`). Also moved a misplaced 0009 comment. `NMIntelFB c07eb921…`. Note: this also gives the
software-composited boot (before `enable.sh`) a 144 Hz VBL for the first time.

## RTX-11 — intelfb-0012 — the VBL fires; CoreDisplay finds no display pipe for the panel
Boot 19:53; `enable.sh` 19:56:03; after `killall -9` the screen stayed on the console; power-off, boot 19:58:57.
- [measured, kernel log] `trail: vbl-always`, `vbl1` (19:54:04), `kapi: … VRAM budget 4096 MB of BAR1 8192 MB`;
  after the restart `rmh`, `vram1`, surfaces; WindowServer still creating surfaces at 19:58:00. No transaction.
- [measured, WindowServer log] GPUWrangler `gpu 0xd9df (IG) … fb0:0 /NMIntelFB` → `CoreDisplay: Creating FB 1 of 1`
  on the Intel GPU (IOPresentment errors, a DisplayPipe hash error in `CoreDisplay::Framebuffer::Framebuffer`);
  `gpu 0xcb26 (DG) … accel /NVAccel` → `GPU: FB: 0 of 0 opened`; then **`System set to use IOP but no display pipes
  are present`**, `Setting kIOWSAA to 0x3`.
- [inferred] CoreDisplay pairs a framebuffer with the GPU above it in the registry; NVAccel's pipe is on the NVIDIA
  GPU, which has no framebuffer. nullmoth's virtual build puts NMIntelFB on an `NVRMDisplay` nub under NVRM for this.
- [measured, ioreg] on the RTX path GFX0's only framebuffer is NMIntelFB (no IONDRVFramebuffer).

### intelfb-0013
`NMIntelFBClaim` (IOService, Intel GPU, `IOFramebuffer` category, score 61000, the same checks as NMIntelFB's probe)
holds GFX0 (no IONDRV) and, from a thread, publishes an `NVRMDisplay` nub under NVRM (`nm-intel-panel`, `fb-index 4`,
NVRM's `nvkms-kapi`/`gpu-id`/`phys-for-va`) once NVRM's nub 0 exists; personality `NMIntelFBPanel` starts NMIntelFB
on it (score 60000 > NVRMFB 1000), which drives the Intel GPU through `gIfbPCI`. Knob `nullmoth-intelfb-nvparent=0` =
no claim, NMIntelFB on GFX0 as before. Log `claim: Intel-panel NVRMDisplay nub published under NVRM`. Claim trail
tokens are cleared when NMIntelFB starts (read the log). `NMIntelFB b230f46f…`.

## RTX-12 — intelfb-0013 — the panel is on the NVIDIA GPU; still no display pipe
Boot 20:05; `claim: Intel-panel NVRMDisplay nub published under NVRM` (20:06:09); `enable.sh` 20:09:44; after
`killall -9` the console stayed; power-off, boot 21:15:51.
- [measured, WindowServer log 20:09:54] `gpu 0xcb26 (DG) 10de.25ac … agdc 0x000000000 … accel /NVAccel … fb0:0
  /NVRM/NVRMDisplay/NMIntelFB`; `Creating FB 1 of 1`; `IOPresentment: Unable to get AGDC information … Unable to
  locate service dependencies … Unable to acquire map`; again `System set to use IOP but no display pipes are present`.
- [measured, kernel] `IOAccelDisplayPipeUserClient2`, `vram1`, surfaces; no transaction.
- [measured, source `kexts/NVRMAGDC/nvrm-agdc.cpp`] "WindowServer reads AGDC command 0x980 when it (re)starts and
  builds one display pipe per entry in the reply." NVRMAGDC lists only `NVRMNVDAFramebuffer`s (none here) and starts
  only on `debug.nvrmfb_agdc=1`, which NVRM's auto-go writes between `nvaccelfb` and `nvaccel_iop`.

### intelfb-0014
`NMIntelFBAGDC` (an `AppleGraphicsDeviceControl`, nullmoth's reconstructed header; link
`com.apple.AppleGraphicsDeviceControl`, same 17 imports as NVRMAGDC) on the NVIDIA PCI device: command 1 = vendor
NVIDIA 0x10de class 2, command 0x980 = one framebuffer (the panel), portMask 1 << 1, as NVRMAGDC's one-head reply.
Started by `sysctl debug.nmintelfb_agdc=1` (registered only when NMIntelFB runs on the nub); state 1 up, 2 starting,
< 0 failed; trail `agdc`, first 0x980 `agdc-980`. `enable.sh`: `nvaccelfb=3` → `nmintelfb_agdc=1` (waits for 1) →
`nvaccel_iop=1`. `NMIntelFB 937ae0fa…`.

## RTX-13 — intelfb-0014 (pending)
