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
