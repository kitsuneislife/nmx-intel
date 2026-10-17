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

## RTX-13 — intelfb-0014 — the display pipe exists; no plane
Boot 21:25; `enable.sh` 21:29:07; after `killall -9` the console stayed; power-off, boot 21:31:57.
- [measured, kernel] `trail: agdc-980` (asked during `start`), `AGDC: UP (state 1) on PEGP`, then `iop … OPEN`.
  Unanswered: 0x3, 0x941 (at start); from the new WindowServer 0x2001 and **0x921** (= `NVK5_CMD_LINKCONFIG`).
- [measured, WindowServer 21:29:38–40] no more "no display pipes"; `Setting kIOWSAA to 0x80000013`; `Display id 0x0
  -> 0x5b81c5c0 … isAcc=YES isMUX=NO isBuiltIn=YES`; `Setting mode 0x1 … 1920x1080`; then `Attempting to get
  capabilities from capabilities with no devices`, `Attempting to get capabilities when none exist`, **`No plane
  indices`**; `Display: 0x5b81c5c0 woke on GPU: Intel`. NVK pipelines built; still no transaction.
- [measured, source] NVRMAGDC answers 0x921 and 0x711 (plane-scaler capability) from each framebuffer's
  `NVRMTiming` (13 words) when `debug.nvrmfb_agdc_k5=1`, which NVRM's auto-go sets before the AGDC comes up.

### intelfb-0015
NMIntelFB publishes `NVRMTiming` from the measured Intel timing (pclk, h/v visible, sync start/end, totals, refresh
in mHz, positive syncs) and its AGDC answers 0x921/0x711 with nullmoth's `nvk5_answer` (header copied from
NVRMAGDC). Log `K5 timing: …` (with `REJECTED by nvk5_timing_bad` if invalid); trail `k5-link`, `k5-caps`.
`NMIntelFB a96fc475…`.

## RTX-14 — intelfb-0015 — WindowServer composites on the RTX; the transaction never reaches NVAccel
Boot 21:38; WindowServer restart 21:42:33; console stayed; power-off, boot 21:44:18.
- [measured, kernel] `K5 timing: pclk 346486882 1920x1080 h 1968-2000/2080 v 1083-1088/1157 143975 mHz` (accepted);
  `trail: k5-link`, `k5-caps`; further 0x711 types and 0x925 answered Unsupported (NVRMAGDC does the same).
- [measured, WindowServer] no "capabilities … with no devices"; `Display 0x5b81c5c0 … isAcc=YES`, mode 1920x1080;
  NVMTL: a 1920x1080 IOSurface in VRAM, GPUPass/ViewportToNDC pipelines, `surface-out -> dirty`, `the swap waits in
  NVAccel`; login-window drawing (text textures, fixed_frag shaders) continued. Then `Transaction Target State …
  Plane Index: 0 … Fetch - Pipe … EOTF - GPU`, `Attempting to get capabilities from plane with no gamma` and
  **`Fallback GPU Display Pipe transaction submission failed`** — 186 times. `Invalid display 0x5b81c5c0` (SkyLight).
- [measured, kernel] no `iop: K6` line: no transaction reached `NVDisplayPipe::performTransaction`; kernel quiet
  after 21:42:47. Registration log: `pipe 0 active(+0x298) = 0`.
- [measured, nullmoth 803515b] the Intel-panel copy path was only tried with a real NVIDIA head 0 beside it.
- [inferred] the family refuses transactions on a pipe whose framebuffer resource is NULL (NVAccel returns NULL for a
  CPU-only scanout, `phys 0`).

### intelfb-0016
`nvScanoutInfo`: NMIntelFB allocates once a VRAM block the size of the panel (its own NVKMS device) and answers its
`phys`/size/handle, so `initFramebufferResource` creates a scanout vidmem as for an NVIDIA head; `kva` stays the Intel
surface (performTransaction's copy target). NVAccel only records a scanout vidmem's address and never frees it;
home flips skip non-NVIDIA framebuffers. Trail `scanres`; knob `nullmoth-intelfb-scanres=0`. `NMIntelFB 1d3ea017…`.

## RTX-15 — intelfb-0016 — **accelerated desktop on the internal panel** (first working run)
Boot 21:54; `enable.sh` 21:58:51; `killall -9 WindowServer` → login window, session works. Lukas: wallpaper,
animations, transparency and YouTube work; a short stall while entering the session after the password.
- [measured, kernel] `trail: scanres`; `scanout resource: VRAM phys 0x7c22200000 (8323072 bytes)`; `nvaccelfb=3:
  scanout-backed display pipe ENABLED`; `iop … transaction hooks OPEN`; 21:59:01 `iop: K6 plane 0: surface yes id 0x2
  1920x1080 row 7680 fmt 0x42475241 | resource NVResource … kva 1 scanout 0`. No "submission failed" in WindowServer.
- [measured, sysctl ~6 min later] `nvaccel_iop_ok 14801` (all `_h0`, all `src_surf`), `iop_fail 0`, `iop_blank 5`,
  `copy_skip 25`, `surface_gpu_waits 6475`, `timeouts 13`, `wait_max_us 102100`; `vm_refused 0`.
- [measured, system_profiler] one display: RTX 3050, Metal 3, 1920x1080, main, mirror off (no ghost display).
- [measured, resource use, Claude app streaming text] ~89 frames/s copied (10 s sample: 887 frames); WindowServer
  ~67 % CPU (user ~48 %, system ~19 %; software compositing was ~225 %), kernel_task ~33 % [unverified source].
  WindowServer logs `Invalid display 0x5b81c5c0` (SkyLight) ~17/min.
- [measured, `nvrm-accel.cpp`] every frame: GPU makes the surface's pixels current in system memory
  (`nvAccelSurfCopyReady`), then `performTransaction` copies the whole frame (8.3 MB) word by word through `volatile`
  pointers into NMIntelFB's surface, synchronously. [inferred] that copy is most of WindowServer's system time and
  the per-frame GPU wait the cost behind the stall at login; dirty-row copies or a GPU write straight into the Intel
  surface would cut it (NVAccel is nullmoth's binary: changing it means building NVAccel).

### RTX-16 prep: `tools/intelfb/auto.sh`
No kext change. A LaunchDaemon does at every boot what was manual: waits for NMIntelFB under NVRM, 15 s, runs
`enable.sh` (3 tries), and restarts WindowServer only while the login window is up (console owner root); with a user
already logged in it only enables. `nullmoth-intelfb-auto=0` turns it off; log tag `nmx-intelfb-auto`.

## RTX-16 — `auto.sh` — **accelerated from the login window, no manual step, no restart**
Boot 22:11; Lukas logged in 22:14. The login window was already accelerated (transparent password field); short
stalls while apps open, nothing unusual.
- [measured, log] 22:12:42 WindowServer 1160 starts; 22:12:51 headless check "a display head published"; 22:12:59
  `trail: scanres`; 22:13:00 `iop … transaction hooks OPEN`; logger `enabled: agdc 1 iop 1` then `user _windowserver
  already logged in` — **no restart** (the login window's console owner is `_windowserver`, not root).
- [measured] the same WindowServer 1160 took the panel by itself: 22:13:43 `Display 0x5b81c5c0 … isAcc=YES`,
  22:13:44 `iop: K6 transaction #0`; #600 at 22:14:18 with real content. Later `iop_ok 3754`, `iop_fail 0`,
  `wait_max_us 101129`, `timeouts 10`.
- [inferred] the WindowServer restart of RTX-9…15 is not needed once the pipe is enabled; what makes WindowServer
  re-evaluate ~43 s later is not identified.
- `auto.sh` changed: waits up to 90 s for the first frame and restarts WindowServer only if none came and the console
  owner is `root` or `_windowserver`.


### RTX-17 prep: NVAccel built from source (bridge plan stage 0)
- [measured] the installed NVAccel (`f0edef4e`, 243,512 B) is nullmoth **v2.1.0** (the 1401 app reports 2.1.0), not
  the 2.0.2 tree our `nmx-intel-build` branch is based on: 2.0.2 lacks the `nvaccel_surface_gpu*` swap wait (commit
  `e75be1e`, in v2.1.0), whose 100 ms limit is the `surface_gpu_wait_max_us` ~101 ms seen since RTX-15.
- `~/ogkm610` = NVIDIA open-gpu-kernel-modules `610.57.04` (shallow clone). nullmoth's Darwin RM build is not public;
  `tools/accel/build.sh` writes `_out/Darwin_x86_64/compile_cmds.sh` with upstream `src/nvidia/Makefile`'s x86_64
  defines. Branch `nmx-accel` of the clone at v2.1.0, worktree `~/nmx-build/accel/src`.
- [measured] built from v2.1.0: strings, undefined and exported symbols identical to the installed binary; `__cstring`
  20,184, `__const` 31,728, `__data` 4,536 equal; `__text` 56,233 vs 56,345 (−112 B) [inferred: compiler, Apple clang
  17 here]. v2.2.0 builds the same binary as v2.1.0; v2.3.1 adds `nullmoth-nv-starts`. `NVAccel 29a7f015`.
- RTX-17 tests only this: our build of unchanged v2.1.0 installed by `tools/accel/install.sh` (keeps the original in
  `~/NVAccel.kext.original`; `restore` puts it back). Expected: everything as RTX-16.

## RTX-17 — our NVAccel `29a7f015` (v2.1.0 unchanged) — **same as RTX-16**
Checkpoint `~/nmx-checkpoints/20261016-233841-rtx16-funcionando` first (`tools/checkpoint.sh`). Boot 23:40:17;
`displaytrace` stopped (bridge plan stage 1: no `log stream` running).
- [measured] loaded hash `29a7f015`; 23:41:31 headless check "a display head published"; 23:41:40 `iop … hooks OPEN`;
  23:42:24 WindowServer `isAcc=YES`; 23:42:25 `K6 transaction #0`; #600 at 23:42:52 with real content (64/64 varied).
- [measured] `iop_ok 4548`, `iop_fail 0`, `iop_blank 106` (all before the first real frame, not growing), `copy_skip 3`;
  pageoff CE ~1.35 ms + CPU ~1.0–1.7 ms per frame, as with nullmoth's binary.
- [measured, 10 s] 75 frames/s; WindowServer ~60 %, kernel_task ~33 % (as RTX-16; `trustd` 50 % right after boot).

### accel-0001 (RTX-18 prep)
Two run-time knobs, both 0 at boot, so the stages are compared in one boot without reboots: `debug.nvaccel_iop_memcpy`
(stage 2) and `debug.nvaccel_iop_direct` (stage 3); `nvaccel_iop_copy_us` / `nvaccel_iop_ok` = µs per copied frame
(copy engine + CPU, from after the composite wait). `NVAccel 41260d45`. Plan: 60 s each of 0/0, 1/0, 1/1 with the same
on-screen load, `top` + counters for each.

## RTX-18 — accel-0001 `41260d45` — **direct path works; memcpy alone gains nothing**
Boot ~23:52; `tools/accel/ab.sh` 23:55 with a YouTube video playing full width and nothing else touched (Lukas).
`~/nmx-ab-20261016-235516.txt` [measured]:

| memcpy / direct | frames/s | µs per copied frame | kernel_task | kernel_task per frame/s | WindowServer |
| --- | --- | --- | --- | --- | --- |
| 0 / 0 | 42 | 3971 | 21 % | 0.50 | 29 % |
| 1 / 0 | 49 | 3891 | 22 % | 0.45 | 34 % |
| 1 / 1 | 44 | 2746 | 15 % | 0.34 | 33 % |

- [measured] 0 failures, 0 blank in all three; `iop_direct_frames` 6515, every direct frame logged "on the panel from
  staging"; no CE timeout. Lukas saw nothing wrong on screen.
- [inferred] µs per frame = composite-to-panel time: CE ~1.4 ms + `writeBytes` ~1.2 ms + panel copy ~1.3 ms.
  `memcpy` does not speed the panel copy: the write-combined aperture limits it, not the loop. The direct path removes
  the `writeBytes` copy (−1.2 ms, −31 %; kernel_task per frame −32 %). What is left is the CE wait and one CPU copy
  into the aperture: stage 4 (CASO) removes both.
- `shutdown_stall` at 23:51:39 (the reboot that installed it): 20 such reports in DiagnosticReports, not new.
- Next: `auto.sh` turns both knobs on after enabling (`nullmoth-accel-fast=0` keeps them off).
