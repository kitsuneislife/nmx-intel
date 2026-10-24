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

## RTX-19 — `auto.sh` turns the fast copy on at boot — **works**
`auto.sh install` first failed (`cp: tools/intelfb/auto.sh: No such file or directory`: it copied `$0` after `cd`
into its folder; fixed `1900923`). Boot 10-17 08:56:26.
- [measured, logger] 08:57:51.337 `enabled: agdc 1 iop 1`; 08:57:51.358 `fast copy on (memcpy 1, direct 1)`;
  08:58:34.953 `frames reach the panel (iop_ok 6); no restart`.
- [measured, sysctl] `iop_ok 9664` = `iop_direct_frames 9664` (every frame direct), `iop_fail 0`, `iop_blank 102`
  (boot, before the first real frame); `iop_copy_us / iop_ok` = 2796 µs per frame (RTX-18 direct: 2746).
  kernel_task ~16 %.

## RTX-20 prep — stage 4a: the panel scans out of RAM, the copy engine writes it
Plan: [knowledge/bridge-optimization.md](../knowledge/bridge-optimization.md) "Stage 4 plan". Two builds, both off
until switched on at runtime:
- `intelfb-0017` (NMIntelFB `6145a549`): `sysctl debug.nmintelfb_ram=1` allocates a panel-sized wired buffer in RAM
  (contiguous when possible), copies the current picture into it (then `clflush`), saves the GGTT entries of the
  scanout (GGTT `fSurf`.., BAR0 + 8 MiB) and points them at the buffer (`phys | 1`, then `GFX_FLSH_CNTL_GEN6` = 1),
  checking each entry reads back. `PLANE_SURF`, the GGTT offset and the aperture view do not change. `=0` writes the
  saved entries back. The page list goes to NVAccel through `nmIntelFBRamPages`.
- `accel-0002` (NVAccel `a4d13738`): `debug.nvaccel_iop_direct=2` gives those pages to NVRM's page-off, so the copy
  engine writes the frame onto the panel and no CPU copy is left; anything that does not fit falls back to the
  direct=1 staging path. Counter `debug.nvaccel_iop_ram_frames`.
- Test: `sudo bash tools/accel/ab.sh ram` (70 s direct=1, then 70 s direct=2 + RAM scanout; ends with the RAM scanout on).
- [unverified] whether the copy engine's writes reach RAM before the display reads them (snooped PCIe writes vs a
  display that does not snoop): stale stripes or flicker on screen would say no.

## RTX-20 — stage 4a: panel scans out of RAM, the copy engine writes it — **works**
Installed NMIntelFB `6145a549` + NVAccel `a4d13738`, rebooted, `sudo bash tools/accel/ab.sh ram` with a YouTube video
full screen. `~/nmx-ab-20261017-094317.txt` [measured]:

| setting | frames/s | µs per copied frame | kernel_task | kernel_task per frame/s | WindowServer |
| --- | --- | --- | --- | --- | --- |
| direct=1 (staging + CPU copy) | 38 | 2780 | 15 % | 0.39 | 27 % |
| direct=2 + RAM scanout | 52 | 1436 | 11 % | 0.21 | 38 % |

- [measured, log] 09:44:28.71 `ram scanout: 2025 pages at 0x1a7959000 in 1 run(s)`; 09:44:28.76 `ram scanout on: GGTT
  0x0..0x7e9000 now RAM (firmware PTE[0] was 0x3e800001)` (the switch, picture copy included, took ~52 ms); from
  09:44:28.80 every frame logged `copy engine into the panel's RAM`.
- [measured, sysctl after the test] `nmintelfb_ram 1`, `iop_direct 2`, `iop_ram_frames 6478`, `iop_fail 0`,
  `iop_blank 102` (all from boot, as in RTX-19). Lukas: no stripes, no stale picture, nothing wrong on screen; so the
  copy engine's writes reach RAM before the display reads them [measured on screen].
- [inferred] what is left per frame (~1.4 ms) is the copy engine itself, during which NVRM spins (`IODelay`) under its
  locks: the remaining kernel_task share. That is RTX-23 (4c). WindowServer rose with the frame rate (more frames
  composited per second), not per frame.
- Firmware PTE format confirmed: `phys | 1` (stolen memory at 0x3e800000).
- Numbering from here: RTX-21 = `auto.sh` turns the RAM scanout on at boot (`nullmoth-accel-ram=0` keeps it off),
  RTX-22 = flip (4b), RTX-23 = the copy-engine wait without spinning (4c).

## RTX-21 — `auto.sh` turns the RAM scanout on at boot — **works**
Boot 10-17 09:49:03.
- [measured, logger] 09:50:24.898 `enabled: agdc 1 iop 1`; 09:50:24.916 `fast copy on (memcpy 1, direct 1)`;
  09:50:25.101 `ram scanout on (direct 2)`; 09:51:10.579 `frames reach the panel (iop_ok 7); no restart`.
- [measured, sysctl 09:54] `nmintelfb_ram 1`, `iop_direct 2`, `iop_ram_frames 13489` = `iop_ok 13489` (every frame
  through the RAM scanout), `iop_fail 0`. Lukas: normal use looks fine.
- The log command in `auto.sh`'s header found nothing: `logger -t` does not put the tag in `eventMessage`. Fixed to
  `--predicate 'process == "logger"'`.
- Sleep/wake with the RAM scanout on: lid closed ~30 s at ~09:56 and reopened, picture fine, `iop_ram_frames 21258` =
  `iop_ok`, `iop_fail 0`. But the Mac **did not sleep** [measured]: `pmset -g log` has no Sleep/Wake entry since the
  09:49 boot, `pmset -g` shows sleep prevented by assertions (the Claude app, runningboardd, coreaudiod, bluetoothd),
  and NMIntelFB's trail shows no `sp0`/`sp1`, only `sc:prob` at 09:56:48. Real sleep still untested: `pmset sleepnow`.
- **Real sleep (`pmset sleepnow`, ~10:01) — fails: black panel after wake, hard reboot** [measured]:
  - `pmset -g log`: 10:01:25 `Entering Sleep state due to 'Software Sleep'`; 10:02:13 `Wake from Normal Sleep [CDNVA]
    : due to PWRB XDCI CNVW/User`, `Display is turned on`. Sleep notifications: `NVRM driver is slow (SetState to 0)
    (6183 ms)`.
  - NVRM: `sleep #1: suspending the GPU` → `rm_power_management(STANDBY) -> 0x0 in 6183 ms`; `wake #1:` … `PMC_BOOT_0 =
    0xb77000a1 - the GPU answers` … `GPU running`. The RTX came back.
  - NMIntelFB: only `sp1`, `sp-done` (10:02:13), then `gc:pwak`, `gc:chng` (10:02:38). No `sp0` was logged before
    sleep. No NVAccel frame line after wake.
  - `WindowServer_…100303.userspace_watchdog_timeout.spin` / `.ips`: the WindowServer main thread waited
    (TH_UNINT) inside IOGraphicsFamily for 40 s; `displayState OFF`. The only thread in our kexts was NMIntelFB's VBL
    thread in its normal wait (`vblThread+212`). Nothing of NVAccel/NVRM was on a stack.
  - [inferred] S3 powers the iGPU's display engine down, and nothing lights it again: the firmware does not re-run the
    GOP on resume, NMIntelFB only adopts the firmware's mode, and i915 is not running. Unrelated to the RAM scanout,
    then; but untested without it (sleep was never tried on the RTX path before).
  - Until fixed: avoid sleeping (screen off is fine).

## RTX-22 prep — what the display looks like after sleep
`intelfb-0018` (NMIntelFB `eaf67fa1`, on top of 0017): logs `power <0|1>: trans … plane … surf … pp …/… blc …/…/…
blc2 … pte0 …` at each power change and offers the same line as `sysctl debug.nmintelfb_regs`. Test with
`nvram nullmoth-accel-ram=0` (RAM scanout off) to separate the two questions: does the pipe/plane/panel power come back
after wake at all. The backlight registers in the same line also answer brightness BL-1.

## RTX-22 — display registers across sleep — **the display engine comes back blank**
NMIntelFB `eaf67fa1`, `nullmoth-accel-ram=0` (RAM scanout off). `pmset sleepnow` 10:17:31 (DarkWake, then Sleep
10:18:01), woken 10:18:30: panel black again, hard reboot. Same failure without the RAM scanout, so it is not 4a's.
[measured] NMIntelFB log:

| when | trans | plane | surf | pp status/control | blc ctl/freq/duty | pte0 |
| --- | --- | --- | --- | --- | --- | --- |
| before (10:17:28 / :31) | c0000000 | 94000008 | 0 | 80000008 / 00000067 | 80000000 / 4b00 / 4b00 | 3e800001 |
| after wake (10:18:30) | 0 | 0 | 0 | 0 / 0 | 0 / 0 / 0 | 3e800001 |

- [measured] S3 resets the whole display engine: pipe/transcoder off, plane off, panel power off, backlight PWM off.
  The GGTT entry survives (it lives in stolen memory, in self-refresh RAM). The firmware's S3 resume does not relight
  the panel. So WindowServer's wait on the dark display (RTX-21) follows.
- [measured] Brightness (BL-1 answered): PWM controller 1 is the live one, enabled, period 0x4b00 (19200), duty 0x4b00
  (100 %); controller 2 unused. Brightness = writing `BXT_BLC_PWM_DUTY1` (0xC8258).
- Fix options: (a) relight the panel on wake (what i915's display resume does: power wells, CDCLK, DPLL, combo PHY,
  DDI buffers, eDP link training over AUX, transcoder, pipe, plane, panel power sequence, backlight) — a mode set
  from scratch; (b) hibernate instead of S3 (the firmware boots fully, the GOP lights the panel, NMIntelFB
  re-adopts) — depends on hibernation working on this hackintosh; (c) no system sleep (display sleep only).

## RTX-23 prep — stage 4b: two RAM buffers flipped at vblank
- `intelfb-0019` (NMIntelFB `59c98103`, on top of 0017/0018): `debug.nmintelfb_ram=2` adds a second RAM buffer at
  GGTT 0x800000 (2 MiB past buffer 0; linear planes need 256 KiB alignment), filled with the current picture. The page
  list NVAccel gets is the buffer not on screen, once `PLANE_SURFLIVE` (0x701AC) shows the last flip reached the panel
  (waits up to 20 ms in 1 ms sleeps). `nmIntelFBRamFlip` writes `PLANE_SURF` = that buffer (latched at the next
  vblank). Going back to 1 or 0 flips to buffer 0 first, then restores buffer 1's GGTT entries. Counters
  `nmintelfb_flips`, `nmintelfb_flip_waits`, `nmintelfb_flip_wait_us`, `nmintelfb_flip_late`.
- `accel-0003` (NVAccel `659dfa20`): after each copy-engine frame into the RAM pages, calls `nmIntelFBRamFlip` with
  that page list (outside the locks); ignored unless mode 2.
- Limit: the aperture view (`fSurfMap`, IOFramebuffer's VRAM range) still covers buffer 0 only, so CPU fallback
  writes while buffer 1 is on screen are not seen until the next flip.
- Test: `sudo bash tools/accel/ab.sh flip` (ram=1, then ram=2), watching a video with fast horizontal motion for
  tearing (a horizontal cut line in mode 1 that should vanish in mode 2).
- Sleep stays off (RTX-22): `pmset` settings given to Lukas.

## RTX-23 — stage 4b: two RAM buffers flipped at vblank — **works**
Installed NMIntelFB `59c98103` + NVAccel `659dfa20`, `sudo bash tools/accel/ab.sh flip` with a fast-motion video.
`~/nmx-ab-20261017-103422.txt` [measured]:

| setting | frames/s | µs per copied frame | kernel_task | kernel_task per frame/s | WindowServer | flips | waits | late |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ram=1 (one buffer) | 73 | 1440 | 15 % | 0.21 | 45 % | 0 | 0 | 0 |
| ram=2 (flip) | 56 | 1591 | 12 % | 0.21 | 35 % | 3409 | 233 | 0 |

- [measured, log] 10:35:33.909 `buffer 1, 2025 pages at 0x3e8240000 in 1 run(s)`; `GGTT 0x800000..0xfe9000 now
  buffer 1 (old PTE[0] 0x3f000001)` (the firmware maps all of stolen memory linearly: GGTT 8 MiB → stolen + 8 MiB);
  `flipping between GGTT 0x0 and 0x800000`.
- [measured, sysctl afterwards] `flips 5824`, `flip_waits 486`, `flip_wait_us 1064220` (~2.2 ms per wait, slept in
  1 ms steps, not spun), `flip_late 0`, `iop_fail 0`. Lukas: no visual problem in either half.
- [inferred] the flip costs no CPU per frame (kernel_task per frame/s 0.21 in both); the +150 µs per frame is the
  latch wait (~8 % of frames find the last flip not yet on the panel), which is sleeping time. `blank 25` in the
  ram=1 half: one-colour video frames [inferred]; 0 in the flip half.
- Next (RTX-24): `auto.sh` turns mode 2 on at boot (`nullmoth-accel-ram=1` keeps one buffer, `=0` none).

## RTX-24 — `auto.sh` turns the flip on at boot — **works**
`nullmoth-accel-ram` deleted, `auto.sh` reinstalled, rebooted.
- [measured, logger] 10:43:22.465 `fast copy on (memcpy 1, direct 1)`; 10:43:22.751 `ram scanout on (mode 2, direct
  2)`; 10:44:08.388 `frames reach the panel (iop_ok 8); no restart`.
- [measured, sysctl] `nmintelfb_ram 2`, `nmintelfb_flips 7840`, `nmintelfb_flip_late 0`, `iop_fail 0`. Lukas: normal.

## RTX-25 prep — stage 4c: NVRM sleeps while the copy engine works
- Building NVRM from source is not possible as published: nullmoth's README and `kexts/NVRM/patches/README.md` assume
  an already-built Darwin RM ("the original NVIDIA 610.57.04 Darwin modeset archive and compile commands"), and
  `make TARGET_OS=Darwin` in `src/nvidia` of open-gpu-kernel-modules fails with 2618 errors (882 `Unsupported target
  OS`, 807 `PORT_BREAKPOINT` undeclared, the rest the OS-UNIX control types) [measured, `~/nmx-build/ogkm-darwin`].
- So a binary patch of the installed NVRM (`12fcabf3`), `tools/nvrm/build.sh` → `f5171d7b`: in
  `nvrm_ce_copy_to_pages`' contiguous-run wait, `osDelayUs(10)` (IODelay, spin) → `os_delay(1)` (IOSleep 1 ms) and
  the spin limit 200000 → 2000 (timeout stays ~2 s). Only those 9 bytes differ outside the load commands/signature
  [measured, `cmp`]. RM's GPU lock waiters sleep on a semaphore (`locks.c`), so sleeping with it held is allowed.
- `tools/nvrm/install.sh` (via `tools/accel/install.sh` with `KX=NVRM`; `restore` puts nullmoth's back from
  `~/NVRM.kext.original`).
- Expected: kernel_task per frame/s well under RTX-23's 0.21; µs per frame up a little (1 ms sleep granularity:
  ~2 ms instead of ~1.4 ms). Test: `sudo bash tools/accel/ab.sh flip` with the same kind of video, compare with RTX-23.

## RTX-25 — stage 4c: the copy-engine wait sleeps — **works**
Installed NVRM `f5171d7b`, rebooted, `sudo bash tools/accel/ab.sh flip`. `~/nmx-ab-20261017-115622.txt` [measured]:

| setting | frames/s | µs per copied frame | kernel_task | kernel_task per frame/s | WindowServer | flips / waits / late |
| --- | --- | --- | --- | --- | --- | --- |
| ram=1 | 46 | 2364 | 4 % | 0.09 | 26 % | — |
| ram=2 (flip) | 44 | 2454 | 4 % | 0.09 | 25 % | 2683 / 121 / 0 |
| RTX-23 ram=2, spinning NVRM | 56 | 1591 | 12 % | 0.21 | 35 % | 3409 / 233 / 0 |

- [measured] kernel_task per frame/s 0.21 → 0.09 (−57 %); `iop_fail 0`, `flip_late 0`, no copy-engine timeout in
  the log; `iop_ram_frames 12334` since boot. Installed hash checked (`f5171d7b`).
- [inferred] µs per frame rose ~0.8 ms: the 1 ms sleep granularity (the copy itself takes ~1.4 ms, the wait ends on
  the second tick). It is latency, not CPU; with the flip, frames still land on the next vblank.
- Bridge cost now, from RTX-16: ~4 ms CPU per frame, kernel_task ~37–48 % → ~0 CPU copies, kernel_task ~4 %.

## BL-2 prep — panel brightness from NMIntelFB
Plan: [knowledge/brightness.md](../knowledge/brightness.md). `intelfb-0020` (NMIntelFB `36afddf1`, on top of 0019):
before `IOFramebuffer::start()` NMIntelFB attaches `NMIntelFBBacklight`, an `IODisplayParameterHandler` named
"backlight" (nullmoth's NVRMFB handler, 60dc7c8, ported), and answers `getAppleSense()` with `kGenericLCD`, so
IOGraphics should make an `AppleBacklightDisplay` (keys + slider). Brightness 0–100 → `BXT_BLC_PWM_DUTY1` = period ×
level (floor 5 %, inverted polarity respected), from a thread call. Only when PWM 1 is running at start;
`nvram nullmoth-intelfb-backlight=0` leaves it out. Trail tokens `bl`, `bl-display`, `bl-off`.

## BL-2 — panel brightness — **works**
Installed NMIntelFB `36afddf1` (hash checked), rebooted. Lukas: brightness keys and slider work, first try.
- [measured, log] 12:04:16.689 `backlight: panel at 100% - brightness keys and slider through AppleBacklightDisplay`;
  12:05:18.002 `brightness parameters on AppleBacklightDisplay, panel at 100%`.
- [measured, ioreg] `AppleBacklightDisplay` registered, `IODisplayParameters` with `brightness {min 0, max 100}`.
- [measured, sysctl] brightness at half: `blc 80000000/00004b00/000024c0` (duty 9408 of 19200 = 49 %); at full
  `…/00004b00` — the duty follows the slider, through our handler.
- [unverified] the handler's `backlight: N% -> duty` lines did not show in `log show` although the duty changed.

## UPG-1 prep — nullmoth NVIDIA driver 2.1.0 → 2.3.6
Upstream 2.3.6 (released 10-18) changes Metal and NVAccel in ways the bridge uses: window drags no longer read the
whole window back to system memory each frame (PR #245), the cursor is moved off the cursor lock, a busy GPU no longer
disables Metal inside WindowServer (2.3.4), each swap waits at most one refresh period (2.3.4), Metal reports the
whole VRAM. Package `nullmoth-nvidia-2.3.6.tar.gz` `3855954d` (matches the release's SHA256SUMS; every inner file
matches the package's own SHA256SUMS) [measured], unpacked in `~/nmx-build/pkg-2.3.6/x/pkgroot`.
- **NVRM** `122b3994` (release) → `8c8873d5`: the RTX-25 patch ported. Same source (`nvrm_pageoff.c` unchanged), the
  compiler now counts down from 200001: `0x1b778` 200001 → 2001, `0x1b783` 10 → 1, `0x1b788` `osDelayUs` →
  `os_delay` (0x14160). `tools/nvrm/build.sh` takes either release by hash; 2.1.0 still gives `f5171d7b` [measured].
- **NVAccel** `2fc93637` (release) → `8166045f`: accel-0001..0003 rebased on v2.3.6 (branch `nmx-accel-236`,
  worktree `~/nmx-build/accel/src-236`, `source-fixes/accel/v2.3.6/`). One conflict, two sysctl registrations next
  to the new `svdiag` one; 0002/0003 applied clean. Recipe check: plain v2.3.6 built here has the release's symbols
  and strings identical, `__cstring/__const/__data` equal, `__text` +128 B [measured]. All sysctls `auto.sh` uses are
  present [measured].
- **NMIntelFB**: `kexts/NMIntelFB` and the headers it shares (`nvrm_vram_abi.h`, AGDC) are unchanged 2.1.0 → 2.3.6;
  built from v2.3.6 it is `36afddf1`, the installed binary [measured]. Not reinstalled.
- nullmoth's `install.sh` (does not touch the EFI or boot-args) backs up the four kexts, GPUBundles, the aux KC and
  `/Library/NullMoth/kexts` to `/Library/NullMoth/backup-…`, installs, and adds a fallback job (`lastgood.sh`) that
  restores that backup if the new boot guard trips. `nvrm610.conf` gets 2.3.6's defaults (`NVMTL_RES2_WS=1`, the
  two `NVMTL_NO_NVENC` lines gone); ours had no "my settings" block.
- Boot guard (new since 2.3.1): NVRM counts starts in `nullmoth-nv-starts`; NVRMFB clears it when a head lights or
  when NVKMS lists connectors and none has a display (`nvrm-fb.cpp:768`). On this laptop NVRMFB enumerates with
  `connected-displays = 0`, so it should clear [inferred]; two starts without that turn the driver off.
- Undo: `sudo bash tools/upgrade/rollback.sh /Library/NullMoth/backup-…` (nullmoth's `uninstall.sh <dir>` only
  removes the driver, it does not restore).

## UPG-1 — nullmoth 2.3.6 with our patches — **works**
Installed with nullmoth's `install.sh` (backup `/Library/NullMoth/backup-20261018-121651.SbZyeT`), then our NVRM and
NVAccel; checkpoint `~/nmx-checkpoints/20261018-121440-antes-2.3.6`. Lukas: desktop fine, "a bit cleaner overall";
some parts of the start felt slower.
- [measured, kmutil] loaded NVRM/NVRMFB/NVRMAGDC `2.3.6`; NVRM UUID `49375050…` and NVAccel `8D65D43B…` = ours
  (`8c8873d5`, `8166045f`), NMIntelFB `36afddf1`.
- [measured, log] boot guard: 12:19:36 `start 1 without a display so far`; 12:19:42 `ENUMERATED: 0 connected
  display(s) of 1 handle(s)` → `guard cleared: NVKMS lists this card's connectors and none has a display`.
  `nullmoth-nv-starts` gone, `nullmoth-nv-ok=1`, `debug.nvrmfb_guard_cleared 1`.
- [measured] bridge: `auto.sh` mode 2 / direct 2 at boot; ~10 min in `iop_ok 32859`, `iop_fail 0`, `iop_late 0`,
  `async_drop 0`, `nmintelfb_flips` = `iop_ram_frames`.
- [measured, log] boot timeline (from `kern.boottime`) is the same as the 2.1.0 boot at 08:17: login window +10 s
  (was +12 s), NVKMS enumeration +20 s (+20 s), `auto.sh` on +83 s (+85 s), first frames on the panel +129 s (+129 s).
- [measured] the installer said `aircache was writable by other users; starting it empty` (and `spvcache`): the
  shared shader caches were dropped, so this first start recompiled every WindowServer pipeline [inferred: the slower
  parts]. The new `aircache` (owner `_windowserver`, 755) was still empty ~5 min after boot [unverified whether it
  fills; check next boot].
- UPG-1 follow-up (10-18, after 3 boots) [measured]: the shared `/Library/GPUBundles/nvmtl/aircache` and `spvcache`
  stay empty, but WindowServer caches in its own Darwin user cache dir:
  `/private/var/folders/zz/…/C/WindowServer/nvmtl/aircache` = 70 MB (owner `_windowserver`), and user processes use
  `$(getconf DARWIN_USER_CACHE_DIR)/nvmtl` (42 MB). `nvmtl_aircache_dir()` falls back there when the shared folder
  is not writable for the process [read, `plugin/NVMTLLibraryLoad.m`]. The C dir persists across boots, so only the
  first boot after the install recompiled; nothing to fix.

## UPG-2 prep — nullmoth NVIDIA driver 2.3.6 → 2.5.0 (GPU-only route)
Releases read (`CHANGELOG.md` at v2.5.0, `git log v2.3.6..v2.5.0`, 53 commits) [measured]:
- **2.4**: hardware H.264/HEVC encode on RTX 20/30; security hardening (bounded caller values, each client
  serialised, no kernel addresses/registers/firmware published to user space); macOS 26 icons and glass; install from
  a root-owned private copy of the package; NVRM reports mains/battery to the GSP; stale shader cache cleared; a boot
  counts as good once the desktop is up (`com.nullmoth.bootguard` job: WindowServer up 45 s → clears
  `nullmoth-nv-starts`, sets `nullmoth-nv-ok`). **2.4.1/2.4.2**: black-screen fixes for 2.4 (outdated NVRMFB, missing
  display interface). **2.4.3**: NVRMFB runs vblank/cursor callbacks one at a time (thread_call cap panic, #295);
  AIR digest reused. **2.4.4**: GTX 16 encode; HEVC past frame 2; Metal offered ~8 s after start on Intel/AMD-screen
  laptops; WindowServer Vulkan crash on dead binding handles; app freeze on a lost completion mark (#322, Terminal);
  function-table shaders; WoW; wgpu apps. **2.5.0**: NVIDIA 615.78.08 RM/display/GSP (from 610.57.04); T400–T1200;
  GPU identity from the PDI; `nvregdwords=` boot-arg (NVIDIA's RegistryDwords); `nvmaxbpc=12`.
- What touches our route: (1) `0cd7c49` early Metal hand-off says in its message the Intel panel driver (NMIntelFB,
  published as a head of the accelerator) never takes the early path → no change for us [read]. (2) `1321113`
  security pass keeps `nvkms-kapi`/`gpu-id`/`phys-for-va` on the `NVRMDisplay` nub (`NVRM.cpp:78-80`); the
  `NVRM_GPUVA_FN_HANDLES`/`NVRM_VRAM_FN_*` calls NMIntelFB makes are unchanged [measured, git grep]. (3) the 615 move
  changes NVKMS's KAPI header (`checkLutNotifier` removed, new fields in layer/head configs) — NMIntelFB uses that
  function table. (4) the new boot-guard job may make our GUARD-1 stand-down moot [inferred].
Package `nullmoth-nvidia-2.5.0.tar.gz` `80f33166` (matches SHA256SUMS; inner files match) [measured], unpacked in
`~/nmx-build/pkg-2.5.0/x/pkgroot`; its `install.sh` equals `package/install.sh` at v2.5.0, touches no EFI/boot-args.
- **NVRM** `aca96ea6` (release) → `7da4dc21`: the RTX-25 patch ported. `nvrm_pageoff.c` unchanged v2.3.6 → v2.5.0;
  second `osDelayUs` in `_nvrm_ce_copy_to_pages`: `0x1bda8` 200001 → 2001, `0x1bdb3` 10 → 1, `0x1bdb8` `osDelayUs`
  (0x2df680) → `os_delay` (0x141f0, still `IOSleep(ms)`); `otool` shows `callq _os_delay` [measured].
- **NVAccel** `70e36f61` (release, `kexts/15`) → `410790ed`: accel-0001..0003 applied clean with `git am -3` on
  v2.5.0 (branch `nmx-accel-250`, worktree `~/nmx-build/accel/src-250`, `source-fixes/accel/v2.5.0/`, same diff
  content as v2.3.6). Recipe check: plain v2.5.0 built here `402ab903`: symbols and strings identical to the
  release, data sections equal, `__text` +144 B; built against `~/ogkm610` or `~/ogkm615` it is byte-identical
  [measured]. All `debug.nvaccel_*` sysctls `auto.sh` uses are present [measured].
- **NMIntelFB**: `kexts/NMIntelFB` unchanged; built from v2.5.0 with the 610 KAPI headers and with the 615 ones it is
  byte-identical, `241aff3d` = the installed binary [measured] → the KAPI members it uses did not move. Not
  reinstalled. `tools/intelfb/build.sh` now defaults to v2.5.0 / 615.78.08.
- Unknowns for the test: 615's GSP firmware and RM on this RTX 3050 (boot guard, display enumeration), the NVRMFB
  callback serialisation under our flip rate, and whether the shader cache is cleared again.

## UPG-2 — nullmoth 2.5.0 with our patches — **fails** (black flashes), rolled back
Installed 10-21 19:03 (backup `/Library/NullMoth/backup-20261021-190353.RdbhPk`), our NVRM `7da4dc21` and NVAccel
`410790ed` on top, rebooted 19:12. Lukas: many dropped frames, the screen blinks black. Rolled back with
`tools/upgrade/rollback.sh` (10-24: loaded NVRM/NVRMFB/NVRMAGDC `2.3.6`, NVRM `8c8873d5`, NVAccel `8166045f`) [measured].
- [measured, sysctl, ~minutes after boot] `iop_ok 11498`, `iop_fail 0`, `iop_late 0`, `async_drop 0`; but
  `iop_blank 141`, `iop_copy_skip 208`; `iop_copy_us / iop_direct_frames` = 33571428 / 11446 ≈ **2.93 ms per frame**
  (RTX-20/UPG-1: ~1.44 ms); `surface_gpu_timeouts 4`, `surface_gpu_wait_max_us 101108`; `nmintelfb_flips` =
  `iop_ram_frames` (11446), `flip_late 0`; `nvrmfb_guard_cleared 1`.
- [inferred] the blinks are the `iop_blank` frames and/or the 100 ms GPU-wait timeouts; the copy got twice as slow on
  615's RM. Not isolated (one boot).
- Before the reboot System Settings and `system_profiler` crashed (`KERN_MEMORY_ERROR` in AppleSystemInfo's text)
  for ~1 min right after `install.sh`; `system_profiler` ran fine minutes later [measured]; cause unknown.

## UPG-3 prep — nullmoth NVIDIA driver 2.3.6 → 2.5.4 (GPU-only route)
Goal: see whether 2.5.1–2.5.4 fix UPG-2's black blinks. Releases read (`CHANGELOG.md`, `git log v2.5.0..v2.5.4`,
23 commits) [measured]: **2.5.1** CPU-drawn surfaces uploaded from their own pages through the copy engine (#296,
Metal plugin), extended-range formats, HiDPI/scaled modes through the head scaler (615 viewport patch), sRGB writes,
GPU temperature in PerformanceStatistics (NVAccel reads BAR0 `0x20460` every 250 ms); **2.5.2** boot hold for slow
GSP bring-up (`nvrmholdcap`), opt-in deferred flip verification (`debug.nvrmfb_flip_latch=2`), per-allocation logs only
with `-nvaccelverbose`, HDMI audio codec association; **2.5.3** `nvregdwords=` no longer stops the boot; **2.5.4**
NVIDIA-only desktops with no head keep `MetalPluginName` withheld (the check exempts `owner == "NMIntelFB"`, so our
route is untouched [read, `nvrm-accel.cpp`]), Discord/ANGLE, sandboxed video decode, installer messages, licence texts.
Nothing names blank frames on an Intel-panel laptop; #296 is the only change near our copy path [inferred].
Package `nullmoth-nvidia-2.5.4.tar.gz` `648280be` (matches SHA256SUMS; inner SHA256SUMS all OK), `~/nmx-build/pkg-2.5.4`;
`install.sh` = `package/install.sh` at v2.5.4, only NullMoth NVRAM keys, no EFI [measured]. OGKM still 615.78.08.
- **NVRM** `4591c5bd` → `cb2748c5`: `nvrm_pageoff.c` unchanged since v2.5.0; same three patches 0x460 later
  (`0x1c208/0x1c213/0x1c218`, `_osDelayUs` 0x2dfae0, `_os_delay` 0x14650, same call bytes); `otool` shows
  `callq _os_delay` [measured].
- **NVAccel** `2e2bad29` (release, `kexts/15`) → `8a251750`: accel-0001..0003 apply clean with `git am -3`
  (branch `nmx-accel-254`, `~/nmx-build/accel/src-254`, `source-fixes/accel/v2.5.4/`, same diff content). Plain
  v2.5.4 built here `586c4117`: symbols and strings identical to the release, data sections equal, `__text` +128 B
  [measured].
- **NMIntelFB** unchanged, `241aff3d` from v2.5.4 [measured]; not reinstalled.
- If it blinks again: `sudo bash tools/accel/ab.sh ram` (A/B of the copy modes) separates our copy-into-RAM path
  from nullmoth's change before rolling back.

## UPG-3 — nullmoth 2.5.4 with our patches — blinks for the first minutes, then stops (first boot)
Installed 10-24, booted 09:04:56, desktop (NMIntelFB pipe A up) 09:05:24, login 09:06:30 [measured, kernel log].
Lukas: the black blinking started, then stopped by itself after a while.
- `ab.sh ram` 09:08:05–09:10:25 [measured]: direct=1 33 fps, 4619 us/frame, **blank 86**; direct=2 ram=1 71 fps,
  2612 us/frame, **blank 45**; fail 0 in both. So the blank frames are not our copy-into-RAM path: direct=1 has
  them too.
- Totals at 09:11 [measured]: `iop_blank 291` (≈160 before the A/B, 131 during), then **+0** over the next ~3 min
  (09:11:09, 09:11:29, +30 s sample); `iop_copy_skip 1135`, flat; `surface_gpu_timeouts 4` (early, flat),
  `surface_gpu_wait_max_us 101007`. Steady state after it stopped: ~72 fps at **~2.4 ms/frame** (2.3.6: ~1.44 ms).
- Load average at 09:11 was `6.07 17.80 10.36` (5-min 17.8): heavy start-up work during the blinking window; the
  kernel log has its burst of NVAccel/NMIntelFB lines at 09:06–09:07 (22 `surfvram pageoff` staged uploads, all ok)
  [measured]. Nothing in the log names a timeout or failure.
- [inferred] the blinks are tied to the first minutes after boot (start-up load: probably the shader cache that
  2.4+ clears being rebuilt, Spotlight), not to a copy mode. Not separated yet: the blinking stopped about when the
  A/B ended, which also left `nmintelfb_ram=1` (no flip) instead of auto.sh's `2`.
- Next (one variable, no reboot): `sudo sysctl -w debug.nmintelfb_ram=2` and watch `iop_blank` for 5 min; then
  one more reboot to see whether the blinking window repeats or was a first-boot cost.
- 09:11–09:16 with `nmintelfb_ram=2` (flip, auto.sh's mode) [measured]: `iop_blank` 291 → 294, `copy_skip`
  1135 → 1152, `surface_gpu_timeouts` still 4, `flip_late 0`; load `2.47 8.10 8.05`. Lukas: fewer blinks, but some
  remain. So the flip mode is not the cause; the residue is a 2.5.x regression (2.3.6: `iop_blank` ~100 at boot,
  then flat, nothing seen on screen — RTX-20/21).
- Reading the blank path [read, `nvrm-accel.cpp` v2.5.4 + accel series]: a copied frame first waits in
  `nvSurfWaitReady` for the surface's GPU work, and the direct path only copies when the resource's valid bit says
  the VRAM copy is current; a one-colour frame with the timeouts flat means the readiness signal said "ready" while
  the pixels were not there yet [inferred]. The one change between 2.5.0 and 2.5.4 near that is #296 (`8d6f418`,
  Metal plugin): CPU-drawn surfaces are now uploaded by the copy engine from their own pages instead of by the CPU;
  it has an env switch `NVMTL_SURFIN_UPLOAD=cpu` that restores the old CPU upload. 2.5.0 already blinked, so #296 is
  not the only cause, but it is the cheapest single variable to try [inferred].

## UPG-3b — WindowServer with `NVMTL_SURFIN_UPLOAD=cpu` (no rebuild)
`sudo launchctl setenv NVMTL_SURFIN_UPLOAD cpu`, then restart WindowServer so it inherits it; check the variable in
its environment (`ps eww`), note `iop_blank`, use the desktop 5 min, read it again. Undone by a reboot (or
`launchctl unsetenv`). If the blinks go, make it permanent in auto.sh; if not, the next step is in our kernel side:
skip a flip for a lone one-colour frame (ram=2 writes the back buffer first, so the check costs nothing).
- **Result (09:18) [measured]:** blinks continue; `iop_blank` 294 → 381 (+87, much of it presumably the
  WindowServer restart, as at boot) → 383; `surface_gpu_timeouts` 5. `ps eww` showed no environment for
  WindowServer at all (macOS hides it), so whether the variable reached it is **unverified**; the test is
  inconclusive and is not pursued (WindowServer's launchd plist is SIP-protected). Load at 09:18 was 34 (1-min):
  Claude 153 %, WindowServer 74 %, trustd 51 %, Steam helpers.

## UPG-4 prep — accel-0004: keep a short run of one-colour frames off the panel
In flip mode (`nmintelfb_ram=2`, auto.sh's default) NMIntelFB hands NVAccel the buffer that is **not** on screen
and flips to it only on `nmIntelFBRamFlip` (intelfb-0019) [read]. So a one-colour frame can simply not be flipped:
the panel keeps the last picture and the next frame rewrites the same buffer. `accel-0004-hold-blank-frames`
(branch `nmx-accel-254` `349a6e6`): the RAM path already samples 64 pixels (`nvIopVaried`); up to
`debug.nvaccel_iop_blank_hold` (default 3, RW) one-colour frames in a row are not flipped, counted in
`debug.nvaccel_iop_blank_held`; a longer run is a real one-colour screen and is shown; any varied frame resets the
run. `hold=0` is the old behaviour. With `nmintelfb_ram=1` the flip call is ignored anyway, so it changes nothing
there (the counter still counts). NVAccel `b56b0440`, both sysctl names in the binary [measured].
This hides the symptom; the cause (composites reported ready before their pixels are in VRAM on 2.5.x) stays open.
Expect: `blank_held` ≈ the new `iop_blank`, no blinks; a real black screen (e.g. a fade) shows ~40 ms late.
