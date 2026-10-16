# Tests 15–24: without our framebuffer (`fb=2`) — panel live, DRM opens, ANV sees the GPU

> **Summary.** With our IOFramebuffer disabled (`nullmoth-gpu-fb=2`) the Mac stops freezing at attach, which pinned
> those freezes on `NMXGPUFB`. Then, one by one: FBC/PSR froze the panel image (0016); every DRM open failed (no
> vnode, 0017; ENXIO convention, 0018); libdrm could not match clone nodes (libdrm-0001) and `GET_PCIINFO` failed
> (0019); a port RCU bug froze the Mac on `close` (0021); WindowServer looping on NMXAccel triggered the userspace
> watchdog (0024). Test 24: **desktop through i915, stable, ANV sees "Intel(R) Graphics (RPL-P)"**.

## Test 15 — `fb=2` — **no freeze**

`ff044b86…`. Trail `… lit client-reg hotplug registered fb-skip no-fb @91637`, beat `ms=91658 pub=91278 open=0`.
- Mac lived 91 s after attach (attach takes ~0.4 s); boot log saved; WindowServer and loginwindow came up.
- [measured] **The freezes of tests 10–14 come from `NMXGPUFB`.**
- Panel frozen on the modeset frame. [inferred] FBC/PSR: macOS writes with the CPU through the aperture, which i915
  frontbuffer tracking never sees.
- `open=0`: nothing opened the DRM node. WindowServer opened the IONDRV of GFX0 (`Creating FB 1 of 1`).

### 0016 (drm-kmod)
`intel_display_params.h`: `enable_fbc` and `enable_psr` default to 0 under `NMXKPI`. `8ce69ba8…`.

## Test 16 — 0016, `fb=2` — **panel updates, Mac alive**

Lived 141 s; console live until WindowServer starts (36 s after `lit`) → 0016 confirmed. No desktop:
- NVMTL: `GPU vendor 8086 (Intel, ANV)` / `headless GPU: no device for WindowServer`.
- SecurityAgent, loginwindow… load ANV; `vkEnumeratePhysicalDevices` → **0 devices**; `open=0`.

### `tools/probe`
LaunchDaemon `com.kitsune.nmxprobe` at 45 s and 120 s → `/Users/Shared/nmx-probe.txt`: `/dev/dri`, libdrm
`drmGetDevices2`, `renderD128`/`card0` open + `drmGetVersion`, an ANV instance, IOAccelerator/IOFramebuffer,
WindowServer. `sudo bash tools/probe/install.sh [remove]`.

## Test 17 — probe, `fb=2`

```
/dev/dri/renderD128 mode 666 dev 22,268
drmGetDevices2: 0 device(s)
open /dev/dri/renderD128: Operation not supported by device
ANV: vkEnumeratePhysicalDevices -> 0, 0 device(s)
```
Beat `open=2`: the opens reach NMXGPU and fail inside.
- [measured] Port bug (`override/src/nmx_linux_cdev.c`): `nmx_cdev_open` builds the `struct file` without
  `f_vnode`; `drm_stub_open` uses `iminor(inode)` = -1 → `-ENODEV`. **No DRM open could ever work.**

### 0017
`struct cdev` gets `nmx_vnode` (created on first open, `VCHR`, `v_rdev`); `fp->f_vnode` points to it. Struct change →
full build. `47133df7…`.

## Test 18 — 0017 — **desktop on the panel through i915**

`fb=2`. i915 drives the panel showing the GOP fb; macOS draws via IONDRV. `system_profiler`: Intel `0xa7a8`, "Metal:
Supported" (NMXAccel), 1920x1080, main, online.
- Probe: `open … Device not configured` (ENXIO now, not ENODEV).
- [measured] FreeBSD `linux_dev_fdopen` ends with `finit(...)` + `return (ENXIO)` meaning "I installed my fileops";
  the port treats it as failure and leaks the `drm_file`.

### 0018
`nmx_cdev_open`: with `d_fdopen` and `fp->f_ops` installed, ENXIO → 0. `7a16c6ad…`.

## Test 19 — 0018 — DRM opens; libdrm does not find the GPU

Desktop again; beat `open=2 ioctl=4`. Probe: `open /dev/dri/renderD128: driver i915 1.6.0` (first userspace talk to
i915), but `drmGetDevices2: 0`, ANV 0. Two more bugs:
1. **libdrm**: NMXGPU nodes are devfs clones; every lookup gets a new minor (30,256 → 30,356 → 30,388), and the
   nullmoth Darwin libdrm matches by `st_rdev`. Fix `source-fixes/libdrm/libdrm-0001`: inside libdrm,
   `stat`/`fstat` of `/dev/dri/cardN|renderDN` return `makedev(226, N)` (fd name via `F_GETPATH`). Live test:
   `drmGetNodeTypeFromFd` -1 → 2. `tools/libdrm/{build,install}.sh` (backup `~/libdrm.2.dylib.nullmoth`). NVK does
   not use libdrm (RTX unaffected).
2. **`DRM_IOCTL_GET_PCIINFO`** → ENODEV: `dev_is_pci()` looks at the DRM child; **0019** walks up to the PCI
   function. `8f2b4b6f…`, libdrm `719cb625…`.

## Test 20 — 0019 + libdrm — **ANV reaches the GPU, Mac freezes**

Beat `ms=38755 open=2 ioctl=1 cmd=0x40106415` (`GET_PCIINFO`, returned). Froze ≤ 0.5 s later as macOS processes load
ANV. Panic saved later (see test 21).

### 0020
`nullmoth-gpu-io`: every `open` (`o<pid>`), `close` (`c`), ioctl (`d<nr>`, then `+` or `-<errno>`); newest 470 chars.
`build-all.sh` now stops on a failed file (nullmoth scripts only print `FAIL` and continue; one build silently lacked
`nmx_devfs.o`). `5b738a60…`.

## Test 21 — 0020 — **the port's RCU**

Text screen, no desktop. Beat `ms=208167 open=56 ioctl=314 in=0` — froze outside an ioctl.
- io log: full ANV conversation (`GETPARAM`, `QUERY`, `GEM_CONTEXT_*`, `SYNCOBJ_*`, `GEM_CREATE`, `REG_READ`…), mostly
  `+`; failing: `GEM_USERPTR` (-22), `PRIME_HANDLE_TO_FD` (-102), some `GETPARAM`.
- [measured] Test-20 panic `Kernel-2026-10-16-104230.panic`: `NMIPI for unresponsive processor: TLB flush timeout`,
  SecurityAgent closing the node: `nmx_close → nmx_cdev_close → linux_file_close → linux_synchronize_rcu`, RIP in
  `ck_epoch_synchronize_wait`, interrupts off (RFLAGS 0x93).
- Cause: LinuxKPI RCU pins the reader (`sched_pin`, implemented in the port by disabling interrupts, per-CPU count).
  A reader that sleeps (SRCU readers can; port spinlocks can block) resumes on another CPU → the section ends on the
  wrong record, the first CPU keeps interrupts off, `synchronize_rcu` spins forever → TLB shootdowns fail → freeze.

### 0021
`override/src/linux_rcu.c`: readers increment one of two global counters per type (no pinning, no interrupt
changes); `synchronize_rcu` waits for the old counter, flips, waits for the other, sleeping (`mi_switch`/`pause`).
Beat gets `rcu=`; io log keeps the tail after 400 tokens. nullmoth v2.1.0 only adds PCI logs. `9a361f0e…`.

## Test 22 — 0021 — another freeze, no panic

Beat `ms=263427 open=66 ioctl=377 rcu=0` — no RCU waiter. Log ends 34 s before the freeze.
- WindowServer uses NMXAccel on the Intel GPU and every surface fails (`NVTask::allocate: RM refused 8294400 bytes`,
  ~1,100/min): `nvAccelRmHandles: no framebuffer has published yet`.

### 0022 / 0023
0022: beat every 1 s to 10 min (0.5 s in minute 1) with `irq=` and `iot=` (ms of newest io token); trail rewritten
only every 10 s after minute 1. 0023 (drm-kmod): `Gu`/`Gp` (GT unpark/park), `Rs`/`Rr` (runtime suspend/resume),
`D<state>` (DC state) in the io log. `2f1e7630…`.

## Test 23 — **WindowServer stuck → macOS watchdog**

Beat `ms=267714 ioctl=251 irq=109 iot=127647`: the GPU had been idle for 140 s; no IRQ storm; no power events.
- [measured] Freeze always ~225 s after WindowServer `enrolling watchdog endpoints` (11:08:05 → ~11:11:50;
  13:56:57 → ~14:00:43). WindowServer's main thread loops on `RM refused 8294400` /
  `IOAccelLegacySurface::surface_flush: failed to prepare buffers` (~19/s). With `fb=2` IOAccel pairs the firmware
  IONDRV with NMXAccel (same PCI). `watchdogd` takes the kernel down; no panic saved.

### 0024
`nmxgpu-claimed` (lets NMXAccel start) only when our IOFramebuffer is published; otherwise trail `noaccel`.
Knob `nullmoth-gpu-accel`. `7fd87526…`.

## Test 24 — 0024 — **desktop, stable, ANV sees the GPU**

Desktop through i915, alive past 330 s, no `RM refused`. Probe (120 s):
```
drmGetDevices2: 1 device(s)   device 0: bustype 0, nodes mask 0x5, pci 8086:a7a8
open /dev/dri/renderD128: driver i915 1.6.0
ANV: vkEnumeratePhysicalDevices -> 0, 1 device(s)   0: Intel(R) Graphics (RPL-P), 8086:a7a8, api 1.4
```
Confirmed: tests 21–23 were the watchdog over WindowServer stuck in NMXAccel.
Research: WhateverXe (b00t0x, 2026-10-09) — Lilu plugin adapting Apple's Tiger Lake drivers; Big Sur 20G1443,
TGL/ADL-N, external displays only. Not usable here.
