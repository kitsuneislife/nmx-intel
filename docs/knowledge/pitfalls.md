# Pitfalls (lessons that cost a test)

> **Summary.** Each entry: symptom → cause → fix → evidence. Read the one that matches a new symptom before
> theorising. Tags: [measured] seen in logs/panics/code; [inferred] reasoned, consistent with data; [unverified].

## IOGraphics

### IOFramebuffer without `IOFBDependentID` has no controller until `open()`
- Symptom: freeze right after `fb-started` / hang in `registerPowerDriver` / WindowServer panic `CR2 0x170` in
  `IOFramebuffer::extGetAttribute + 0x111`.
- Cause [measured, `IOFramebuffer.cpp`]: `start` creates the `IOFBController` only with a dependent ID; before
  `open()` `__private->controller` is NULL, and `setPowerState`, `terminate`, `stop`, `extGetAttribute` use it
  (`FBGATEGUARD`/`FBWL`). With a dependent ID whose index 0 never opens, `kIOFBWSStartAttribute` reads a NULL
  `fFbs[0]`.
- Fix: set `IOFBDependentID` (unique) + `IOFBDependentIndex 0` **before** `IOFramebuffer::start` (0026). Tests 13, 25,
  RTX-2/6b, the three NMIntelFB panics.

### A dependent group is walked from index 0 to the first NULL
- [measured, `IOFramebuffer.cpp`] `open()` stores `controller->fFbs[IOFBDependentIndex] = this` (the only read of the
  index); `FOREACH_FRAMEBUFFER` loops `fFbs[i]` until a NULL; `kIOFBWSStartAttribute` dereferences `fFbs[0]`.
- [measured, ioreg, 10-16] On this laptop NVRMFB never starts: NVRM `nvrm-display = heads 0x0`, the four
  `NVRMDisplay` nubs have no framebuffer (`connected-displays = 0`). So NMIntelFB at index 4 of NVRM's group was alone
  with `fFbs[0..3]` NULL — the RTX-1..7 freezes [inferred].
- Fix: a group of its own, index 0 at `open()` (intelfb-0009). NVAccel reads the index only at publish.

### NVAccel registers pipes only through head 0 (`fFB`)
- [measured, RTX-8] `fbPublished` makes only `IOFBDependentIndex 0` the primary `fFB`; `registerFramebufferLocked`
  needs `fFB`; with no `fFB` after 60 s the headless check withholds WindowServer from the NVIDIA Metal device.
  NVRM's auto-go arms `nvaccelfb` and `nvaccel_iop` only when heads publish within ~20 s. Fix: NMIntelFB publishes as
  head 0 (intelfb-0010) and `enable.sh` writes `nvaccel_iop=1`.

### NVAccel's primary framebuffer must own an NVKMS device
- [measured, RTX-9] WindowServer on NVAccel needs `fFB` to answer `nvRmHandles` and `nvAllocVram`; without them
  `NVTask::allocate: RM refused 8294400 bytes` and WindowServer hangs (screen stays on the `-v` console). Fix:
  intelfb-0011.

### `killall WindowServer` (TERM) is ignored; `killall -9` restarts it
- [measured, RTX-9] TERM left the same pid running; `-9` relaunched it (loginwindow + LaunchAgents came back).

### `ioreg -c Class -d1` finds nothing below the root; `log` in zsh is a builtin
- Use `ioreg -r -c Class -d1`. In scripts run by zsh, call `/usr/bin/log show` (the builtin says "too many arguments").

### A LaunchAgent for LoginWindow and Aqua must not log to one fixed file
- [measured, 10-16] `tools/mirror` never ran in the session: the login-window instance (root) created
  `/tmp/nmx-mirror.log`; the user instance could not open it → launchd `last exit code = 78: EX_CONFIG`, 156 respawns.
  Fix: no `StandardOutPath`; log with `syslog`.

### Never `terminate` a foreign IOFramebuffer that is not open yet
- Same NULL controller (test 28). Wait for its `IODisplayConnect` child (created in `open()`) first (0029).

### `IOFramebuffer::terminate` panics `AppleUpstreamUserClientDriver`
- [measured] `kIOFBNotifyTerminated` → `fbNotificationOccurred + 0x1e`, `CR2 0` (test 29). `IOService::terminate`
  avoids it (0030) **but then WindowServer never drops the display** (test 32). Mirror it instead (`tools/mirror`).

### WindowServer keeps a display IOKit already removed
- Symptom: cursor wraps from the right edge to the left, white squares, flicker, missing Dock, parts redrawn only
  under the cursor. Check with `tools/vram/displays.c` (online displays and bounds). Fix: mirror (test 32).

### VBL
- IOGraphics treats a registered VBL interrupt as enabled and calls `setInterruptState` only to throttle; registering
  and never firing breaks frame pacing (test 26). A timer is not a real vblank; currently VBL is not offered (0031).
- [measured, RTX-10] NMIntelFB waited for `setInterruptState(on)`, which never came (NVAccel's registration sent
  `off`): `vbl=0` always, and WindowServer on the RTX sent no display-pipe transaction. NVRMFB ignores
  `setInterruptState` and always fires (intelfb-0012 does the same).

### CoreDisplay pairs a framebuffer with the GPU above it
- [measured, RTX-11] NMIntelFB under GFX0 → CoreDisplay put it on the Intel GPU and found no display pipe ("System set
  to use IOP but no display pipes are present"); NVAccel's pipes are on the NVIDIA GPU. A framebuffer composited by
  NVAccel must sit under the NVIDIA PCI device (intelfb-0013, as nullmoth's virtual build).

### WindowServer builds display pipes from the GPU's AGDC (command 0x980)
- [measured, RTX-12] With the framebuffer under the NVIDIA GPU but no AGDC there: `IOPresentment: Unable to get AGDC
  information … Unable to acquire map` → "no display pipes are present". NVRMAGDC lists only NVRMFB framebuffers.
  Fix: NMIntelFB's own AGDC (intelfb-0014), started before `nvaccel_iop=1`.

### No plane without AGDC link config (0x921) and plane-scaler capability (0x711)
- [measured, RTX-13] With 0x980 answered the pipe exists, but unanswered 0x921/0x711 give "Attempting to get
  capabilities … with no devices" and "No plane indices": no frame is presented. NVRMAGDC's K5 answers them from the
  framebuffer's `NVRMTiming` (intelfb-0015).

### `getDeviceMemoryWithRegister` is stale for the NVIDIA BAR1
- [measured, RTX-10] NVRM replaces the device memory list when it places BAR1; the register lookup returned 64 MB of
  8 GB. Take the first range ≥ 256 MB (NVRMFB's `surveyBar1`).

### `thread_call_allocate` lands in the kernel HIGH group (one thread)
- A callback that blocks (e.g. into IOFramebuffer) stalls every HIGH thread_call → slow full freeze (RTX-5). Use a
  dedicated `kernel_thread_start` thread (intelfb-0007, 0025).

## i915 / memory

### The GGTT aperture is uncached and very slow to read
- [measured] ~2.6 MB/s (8 MB frame in ~3.2 s, test 31). Never let WindowServer read from it: shadow in RAM + row copy
  (0032). Linux fbdev uses a shadow for the same reason.

### Who owns GGTT 0 and the GOP stolen pages
- `init_ggtt` reserves GGTT 0..8 KiB for error capture (test 7); i915 first-fit allocates its own objects in the GOP
  stolen pages (test 13, `-ENOSPC`) while the console still writes there. Hold both ranges before anything else
  (0007, 0014). `nop_clear_range` (Gen8+) leaves GOP PTEs valid (test 6).

### The boot framebuffer address carries flag bits
- `v_baseAddr` = `0x4000000001`; use `(v_baseAddr & ~0xfff) + v_offset` (0009).

### FBC / PSR with CPU writes
- i915 frontbuffer tracking never sees CPU stores through the aperture → panel frozen on an old frame. Off (0016).

### Build defects in the nullmoth binary
- DP tunnel helpers compiled out while i915 expects them → two functions always return -102 (patches 4/5, 0003).
- `__drm_debug` uses bit numbers in 6.14 (`BIT(DRM_UT_*)`), not masks (0005).

## LinuxKPI port

### DRM opens need a vnode, and ENXIO from `finit` means success
- No `f_vnode` → `iminor` -1 → ENODEV (0017). FreeBSD `linux_dev_fdopen` returns ENXIO after `finit` = success (0018).

### Clone device nodes break libdrm's `st_rdev` matching
- Each lookup gets a new minor; libdrm-0001 derives `makedev(226, N)` from the node name.

### RCU readers that sleep
- Port `sched_pin` disables interrupts per CPU; a sleeping reader migrates and `synchronize_rcu` spins with
  interrupts off → TLB shootdown timeout (test 21). Global two-counter RCU (0021).

## macOS behaviour

### WindowServer stuck in NMXAccel → userspace watchdog
- `RM refused 8294400` loop; `watchdogd` kills the kernel ~225 s after WindowServer enrols (test 23). NMXAccel off
  unless forced (0024, 0026). Under `NMX_ACCEL` `fFB` is never set, so this is unsolved upstream.

### Logs vanish on a freeze
- `logd` buffers are lost; use the NVRAM trail/beat/io (synced writes). With DRM debug on, macOS drops kext lines —
  build `nodebug` when `NullMoth display:` lines matter. NVRAM writes from some contexts stop landing ~20 s into a
  failing boot (RTX-6). Panics are saved only sometimes (not with i915 wedged).

### The 1401 app re-copies things
- Toggling the AMD/Intel test driver copies `/Library/NullMoth/kexts/15/NMXGPU.kext` and the nvmtl bundle (libdrm).
  Install our libdrm **after** toggling. An app update may restore the release NMXGPU: rerun `build/install.sh`.
- [inferred, UPG-1 prep] Since 2.3.6 `/Library/NullMoth/kexts/15/NVAccel.kext` is nullmoth's plain 2.3.6 NVAccel; a toggle
  or the macOS-version switcher can copy it over ours (`8166045f`): rerun `sudo bash tools/accel/install.sh`.

### nullmoth's boot guard and uninstall (2.3.1+)
- [read, `kexts/NVRM/nvrm_off.h` v2.3.6] NVRM counts each start in NVRAM `nullmoth-nv-starts`; NVRMFB clears it (and
  sets `nullmoth-nv-ok`) when a head lights or NVKMS lists connectors with no display. Two uncleared starts in a row
  switch the whole driver off like `-nvoff`, and the install's `lastgood.sh` restores the pre-install backup and reboots.
  After an upgrade, check that `nullmoth-nv-starts` is gone after the first boot.
- [measured, 10-19 sleep tests] Forced power-offs (black wake) can leave `nullmoth-nv-starts` at 2; the guard then
  turns NVRM off, but NMIntelFB still claims the panel and WindowServer loops on `CGXMappedDisplayStart`
  (`IOServiceOpen failed(0xe00002c7)`). Black boot with the drivers on file intact: check `nvram -p` for
  `nullmoth-nv-starts`, then `sudo nvram -d nullmoth-nv-starts`. Since `intelfb-0021` (GUARD-1) NMIntelFB stands down
  in that case. Reading the counter alone races NVRM's own increment (written in its `start` after its check): only
  trust a 2 when no `NVRM` instance is attached yet.
- [read, `uninstall.sh` v2.3.6] `uninstall.sh <backup dir>` only checks the directory exists and removes the driver; it
  restores nothing. Our restore: `tools/upgrade/rollback.sh`.
- `tools/accel/install.sh` and `tools/nvrm/install.sh` keep nullmoth's original in `~/<kext>.kext.original` only if
  none is there: before installing a new release, move the old originals away (2.1.0's are in `~/nmx-2.1.0/`).
- [measured, UPG-1] zsh has a builtin `log`: in scripts and tool calls use `/usr/bin/log show`, or it prints nothing.
- [measured, UPG-1] nullmoth's 2.3.x installer drops a shader cache (`/Library/GPUBundles/nvmtl/aircache`) that other
  users could write; the first boot then recompiles WindowServer's pipelines and feels slower.
  The shared folder then stays empty: WindowServer caches in its own `/private/var/folders/zz/…/C/WindowServer/nvmtl`
  (root to read), which persists, so later boots are not slower.

### S3 sleep blanks the Intel display engine (RTX-22)
- After `pmset sleepnow` and wake, TRANSCONF, PLANE_CTL, PP_STATUS/PP_CONTROL and the backlight PWM all read 0; only
  the GGTT (in stolen memory) survives. Firmware resume does not relight the panel, and NMIntelFB only adopts the
  firmware's mode, so the panel stays black and WindowServer stalls waiting for it (watchdog after 40 s).
- Until NMIntelFB can light the panel itself, avoid system sleep on the RTX path (display sleep is fine).

## kmutil refuses private KPI in third-party kexts (WIFI-1)
A kext that works when OpenCore injects it can still fail `kmutil create` for the auxiliary collection: kmutil binds
only against the libraries in `OSBundleLibraries`, and `com.apple.kpi.private` is closed to third-party kexts (adding
it makes kmutil drop the kext). Check with `kmutil libraries -p <kext> --arch x86_64 --xml` before installing in
`/Library/Extensions`: the list must not contain `com.apple.kpi.private`.

- [measured, WIFI-5] Check a third-party kext before installing: `kmutil libraries -p <kext> --arch x86_64` lists
  where each undefined symbol binds; anything from `com.apple.kpi.private` (or missing) makes kmutil refuse it.
  `thread_call_cancel_wait` and `thread_call_isactive` are both unavailable; grep in zsh needs quoted `--include`.

## A network driver that blocks configd hangs the whole boot (WIFI-4)
If an interface driver stalls an ioctl, `configd` stops checking in and the userspace watchdog panics after 180 s;
until then the login window never appears (looks like a graphics hang). Recovery: OpenCore Space → "Start once
without NVIDIA driver" (`-nvoff`), which our Wi-Fi build honours, then `sudo bash tools/wifi/install.sh restore`.
Never call the interrupt handler from another workloop (watchdog) without proving the locking.


## Shifted vs unshifted 802.11 frame type (WIFI-8)
[measured] flxxxxddd's `mt7921_mac_write_txwi_80211` shifts the frame type to 0..3 for the TXD fields, then compared
it with `IEEE80211_FC0_TYPE_DATA` (0x08): never equal, so every data frame got the fixed basic rate (1 / 6 Mbit/s) with
block ack off. Symptom: download fine, upload stuck at ~5 Mbit/s on 5 GHz and ~1 on 2.4 GHz, TXWI pool empty while
the DMA ring is empty. When a Wi-Fi port's upload is far below its download, read the TX descriptor code first.

## `hibernatemode 25` is ignored on this SMBIOS (SLEEP-1)
[measured] With `hibernatemode 25` the kernel still logged `PMRD: sleep params v2, type 7` and `hibernateMode 0x0`
and woke with "Wake from Normal Sleep": plain S3. [inferred] On x86 the sleep type comes from the platform policy
handler (X86PlatformPlugin, `IOPlatformSystemSleepPolicy` in the board plist); MacBookPro16,1's table has no
hibernate entry. Check `PMRD: sleep params` in the kernel log before trusting `pmset`; HibernationFixup's
`hbfx-ahbm=1` is the usual override, but it did not help here (SLEEP-2: still `type 7` with the kext loaded).

- **Apple's TGL kexts from NootedGreen need HookCase.kext** (hybrid route, 2026-10-21). `sle_Internal/le`'s
  `AppleIntelTGLGraphics{,Framebuffer}.kext` depend on `org.smichaud.HookCase`, which exports the framebuffer's register
  and DSB helpers; without it `kmutil create` fails with KMErrorDomain 71 [measured]. Built by `tools/hybrid/build.sh`.
  Upstream HookCase's `probePortMode` dereferences a NULL `callback`: patched in `source-fixes/hybrid/ng/0001`.

## A hybrid config left in `config.plist` locks you out (HYB-1)

`efi.sh hybrid` made the hybrid config the default, so a deterministic panic repeated on every start and only macOS
Recovery got back to GPU-only [measured, HYB-1]. Safe Mode was not practical. Boot experimental configs once: since
HYB-2 `efi.sh hybrid` installs a LaunchDaemon that restores `config-gpu-only.plist` early in the hybrid boot.

## Apple's TGL accelerator can publish without its kernel task on RPL (HYB-1)

`IntelAccelerator+0x150` (kernel `IGAccelTask`) was NULL; WindowServer's first `IOServiceOpen` faulted in
`getStampMemory` (CR2 `0x288`) inside Apple's `deviceStart`, before NootedGreen's V111 force-true runs [measured]. A
guard must run before the original `deviceStart` (HYB-2). The cause of the missing task is open [unverified].

## `grep -q` on a pipe under `pipefail` fails at random (build.sh)

`grep -q` exits at the first match and closes the pipe; the writer (`nm`) gets SIGPIPE, and `set -o pipefail` turns
that into a failure, so `nm … | grep -q sym` can report a present symbol as missing [measured, HYB-2 build]. Capture
the output once into a variable and match on it.

## NootedGreen's injected accelerator personality matches the NVIDIA dGPU (HYB-2)

`injectAcceleratorPersonality` matches on `IOPCIClassMatch 0x03000000&0xff000000` with `IOProbeScore 1000` and no
`IOPCIPrimaryMatch`, so Apple's `IntelAccelerator` probes every VGA device, including the RTX `10de:25ac` [measured,
HYB-2 log]. Any personality we inject on this two-GPU machine needs a vendor/device match.

## Lilu plugin SYSLOG lines do not reach the unified log here; use IOLog

NootedGreen's `SYSLOG("ngreen", ...)` lines never appear in `log show`, while Apple's kext IOLogs do [measured, HYB-2].
Diagnostics we add to Lilu plugins must call `IOLog` directly.

## Reading the previous boot: `--last boot` is the current one; parse `kern.boottime` carefully

After a panic the evidence is in the boot before the current one: use `log show --start ... --end <boottime>`. In zsh,
`log` is a builtin: call `/usr/bin/log`. `sed 's/.*sec = ...'` on `kern.boottime` matches `usec` (greedy); anchor it:
`sed 's/^{ sec = \([0-9]*\).*/\1/'` [measured].

## No `-v` with Apple's accelerated Intel driver; `-nvoff` also turns off our Wi-Fi

The verbose console draws into the boot framebuffer at the start of the GGTT, where Apple's TGL accelerator places
contexts and rings: corrupted contexts and screen artifacts (Julio's HISTORY 9.3) [measured there; HYB-3 artifacts
match, inferred]. `hybrid-config.py` drops `-v`. `-nvoff` is honoured by AirportMtkWlan too, so a hybrid boot with it
has no Wi-Fi [measured, HYB-3].

Correction (HYB-4, 2026-10-21): without `-v` the artifacts were the same, so `-v` was not their cause here [measured].
It stays dropped, following Julio.

## `-nvoff` does not stop nullmoth's NVRM and NVAccel; drop `nvaccel=1` for a hybrid boot

Only our NMIntelFB and AirportMtkWlan honour `-nvoff`. NVRM 2.3.6 and NVAccel start anyway, and NVAccel publishes a
Metal device that WindowServer uses (`NVMTLDriver` lines) even when the panel runs on another GPU [measured, HYB-4].
NVAccel refuses to start without `nvaccel=1`, so the hybrid config drops that argument. Also, the kernel's
"Boot args:" log line is cut at ~227 characters; check that a late flag took effect before concluding it was lost.

## Logs of OpenCore-injected kexts are unreadable in the unified log; use `dmesg` in the same boot

An injected kext (NootedGreen, Lilu) has no uuidtext on disk, so its IOLog lines show up as
`(missing UUID) <compose failure [missing precomposed log]>` [measured, HYB-5: 2035 lines, no `XeNG` text]. The text
survives in the kernel message buffer (`msgbuf=400000`): `sudo dmesg` in that boot, before rebooting. The hybrid
one-boot daemon saves it to `/var/log/nmx-hybrid-dmesg-*.txt`. Kexts from `/Library/Extensions` (NMIntelFB, NVAccel)
log normally.

## NootedGreen's getGPUInfo hook does not run in WEG-coexist mode; the topology comes from binary patches

`IntelAccelerator::getGPUInfo` is only routed when `isWEGCoexistMode()` is false. On our hybrid boot it is true, so
code added to the hook never runs [measured, HYB-10: no log line from it]. The 96-EU topology comes from the V52
binary patches in the RPL group (`f3b` L3 banks, `f3bb` EU/SS, `f3bbb` NumSubSlices=12). The TGL driver logs the
real fuses and its result in the unified log: `[IGPU] HWCAPS - NumSubSlices:12 DualSubSliceCountFuse:0x7`,
`MaxEUPerSubSlice:8 EUDisableFuses:0x0 ExecutionUnitCount:96` (`log.sh` kernel section).

## Apple's TGL driver never resets the GT at boot; a GPU restart does not rebuild the safe image

Linux i915 resets every engine at load on Gen11+ (`intel_gt_sanitize`, to scrub BIOS state). Apple's
`IntelAccelerator::start` does not, and NootedGreen's pre-start GDRST (V55G) only runs when `ERROR_GEN6 != 0`.
On our boot the firmware's engine state survives: at the HYB-14 hang RCS still had `CCID=0x80` and BCS (never enabled
by Apple) was "busy" with HEAD 0xdc0 ≠ TAIL 0xe48 [measured, dmesg-last]. The golden "safe image" that every new
context copies is built only in `startGraphicsEngine` (`accel+0x1268`, freed only in `stop`); the restart path
(`IGHardwareRingBuffer::resetGraphicsEngine` 0x435xx: save list, `GDRST = ring mask`, restore the 11-register list
from `populateResetRegisterList`, scheduler re-init) does not rebuild it [measured, disassembly]. So whatever a
restart fixes is hardware state outside the context image, not the image itself [inferred]. NootedGreen's
`V194 ... (restart recovery)` lines are noise: its Blit3D cache is global while Apple's context is per task.

## NootedGreen's timings worker must check TRANS_LINK_N1, not the cached p->0x164

[measured, HYB-15 panic] `hwCRTCToIODetailedTimingInformation` re-reads `TRANS_LINK_M1/N1` (`0x60040/0x60044 +
transcoder << 12`) into `p->0x160/0x164` and then divides by `p->0x164`. A guard on the cached field misses a register
that reads 0 early in boot (link not trained yet) → divide error panic. Check the register for the transcoder the
function uses (0xf when `port->0x548->0x8 == 0`, else `p->0x3640`). Fixed in hybrid-0006.

## WhateverXe Graphics' TGL kexts match our a7a8 and outrank NMIntelFB

The pkg's `AppleIntelFramebufferController` personality (IOProbeScore 80000, category IOFramebuffer) and the `Gen7`
accelerator list `0xa7a88086` [measured, Info.plist]. NMIntelFB scores 61000 in the same category, so with the pkg
installed and WhateverXe not loaded (GPU-only config), Apple's unpatched driver would take the iGPU [inferred].
NootedGreen's stack was safe only because it matched the spoofed 9A49. `wex-install.sh` gates both personalities with
`IOPropertyMatch nmx-wex=<01>`, injected only by `config-wex.plist`. Re-run it after any pkg reinstall.

## WhateverXe: "accelerator start returned 0" is a framebuffer handoff failure, not a memory one

When WhateverXe rejects Apple's framebuffer start (`N97FramebufferStartAccepted = No`), its wrapper returns `false`,
IOKit drops `AppleIntelFramebufferController` from the IGPU, and the accelerator later fails `sameProvider` in
`N97SharedRegisterCheck` [measured, XE-2]. Read `N97FBFirstPowerError` / `N97FBBootHandoff` (operation 7 = boot
handoff) before suspecting DVMT: on our 64 MiB stolen, `controller+0xDF8` = 0x4195000 passes WEX's minimum
(stolen + 0x192000) [measured]. WEX's handoff returns bare `NotReady` for several conditions; the wex-0001 diag patch
names them. Internal eDP on ADL-P/RPL-P is experimental in WEX 0.6.1 (no hardware coverage, README).
