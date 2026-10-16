# Tests 6–14: building NMXGPU and the i915 display bridge

> **Summary.** NMXGPU now builds on the Mac and matches the release. A new i915 display bridge was written (0004),
> then changed to **take over the GOP framebuffer** in stolen memory (0006–0008, 0014) so the console, WindowServer
> and the display engine share one buffer. Freezes without logs led to the NVRAM trail/heartbeat (0010–0015).
> Test 14: takeover works (`took`, console visible through i915). Every boot with our IOFramebuffer still froze —
> later explained by the NULL `IOFBController` (test 25) — see [25-32-framebuffer.md](25-32-framebuffer.md).

## First build, no changes (2026-10-15)

Tree in `~/nmx-build` (`build/setup.sh`), built with `build/build-all.sh`. Revisions:
- nullmoth 2.0.2 `d96eaca`, local branch `nmx-intel-build` + `build/nmx-src-paths.patch` (`$NMX_SRC` instead of
  `/Volumes/MiniData/build/gpu-src`, `python3` instead of `/opt/homebrew/bin/python3`).
- drm-kmod `master` `c16de0f9fa` (2026-10-08). freebsd-src `bbfd52d` (nullmoth does not record it; `override/src`
  matches anything from `d7e7397` to `bbfd52d`; `9d82546` already changes `linux_pci.c`). Linux `v6.14` (xe + uapi).
- Apple clang 17.0.0 (CLT, SDK 15.5).
- Missing from the nullmoth repo and added by setup: `fbroot/` links, `amd.flags` (`gen_flags.py`), `xe_drm.h` link;
  `rt.sh` also builds `nmx_npu_kext.cpp`, which duplicates `kmod_info` — `build-all.sh` drops that object.

Result: amd 900/900, runtime 76/76, i915 274/274, xe 193/193 → `NMXGPU 16b0a4d6`, 15,236,184 B.
[measured] vs release (15,368,736 B): `__text` −0.03 %, same named symbols (28,296), 11 differing statics (inlining
by a different compiler). **The build matches the release.**

## Source fixes and the new bridge (compiled, not installed)

- `0001` (nullmoth): `linux_pci_find` only looks at the probing driver's table (patch 1 without disabling xe).
- `0002` (drm-kmod): no visible PCH → same guess as a VM; RPL-P is an ADL-P subtype → `0x7A80` = `PCH_ADP`.
- `0003` (drm-kmod): no DP tunnel manager is not an error; no tunnel → no bandwidth to check (patches 4+5).
- `0004` (nullmoth): **i915 display bridge** (`override/i915/nmx_i915_fb.c`), modelled on `intel_fbdev`: stolen
  object (shmem fallback), `intel_framebuffer_create` XRGB8888 linear, `intel_fb_pin_to_ggtt`, `i915_vma_pin_iomap`
  (WC via aperture). Published address = `ggtt->gmadr.start + offset` (the aperture, like Linux `smem_start`), not
  the stolen physical address. `nmx_fb_bridge.c` only diverts when `drm->driver->name == "i915"`.
- Build `cf8b2a2c…`.
- `0005` (drm-kmod `drm_print.c`): with `-DNMX_DRM_DEBUG`, `__drm_debug = BIT(DRIVER)|BIT(KMS) = 0x6` (in 6.14
  `DRM_UT_*` are bit numbers; a first try gave 3). `build-all.sh debug kext`. Test-6 binary `df90b1b5…`.

## Test 6 — compiled NMXGPU (0001–0005, debug)

Installed with `build/install.sh`; `kextstat` size `0xc1bffa` confirms our build loaded.
- `-v` console shows i915 debug up to `DRRS type: none` → 0005 works.
- Panel stays lit by Intel but **glitched**: old console text only in a right-hand band, left half black.
- No log saved (Mac froze before `logd` flushed). Use `/usr/bin/log` in zsh.
- [inferred] Gen8+ uses `nop_clear_range`: GOP GGTT entries stay valid, so the console keeps writing to
  `0x4000000000` = the GOP pages in stolen. Our new stolen object landed **on top of** those pages, offset by half a
  line → the shifted console image. Scan-out works; the buffer location is wrong. Unowned GGTT 0..8 MiB may also put
  GPU objects under console writes (freeze suspect).

### 0006 — take over the GOP framebuffer
Like `intel_plane_initial.c`: `nmx_xnu_boot_fb` (new, `xnu/nmx_platform.cpp`, from `getConsoleInfo`); if it is in the
aperture and matches the mode, GGTT offset = `phys - gmadr.start`; check the PTEs point to one stolen run;
`i915_gem_object_create_region_at(stolen, …)` + `i915_vma_pin(PIN_OFFSET_FIXED)`; framebuffer with the GOP pitch,
not cleared; publish `0x4000000000` again. Fallback: shmem + reserved console GGTT range. Build `da43cdbb…`.

nullmoth 2.0.3 (`20f1974`, 2026-10-16): no change in `gpu-port/`. After an app update, rerun `build/install.sh`.

## Test 7 — 0006

`da43cdbb…`. **Black screen, no glitch**, Mac frozen (video `VIDEO_BOOT_HACKINTOSH_4.mp4`). Logs (21:56, 22:02): i915
inits fully (`Initialized i915 1.6.0 for drmn0 on minor 0`); attach thread stops at `intel_didl_outputs`; logs are
truncated on a freeze, so missing bridge lines prove nothing.
- [measured] `init_ggtt` reserves GGTT 0..8 KiB for error capture (`drm_mm_reserve_node` at 0) → our
  `PIN_OFFSET_FIXED | 0` fails → shmem fallback (zeroed) → black. The rest of the console range (8 KiB–8 MiB) is
  unowned while PTEs still point at the GOP stolen pages. [inferred] freeze suspect.

### 0007 (drm-kmod) + 0008 (nullmoth)
`init_ggtt` calls `nmx_i915_reserve_boot_fb(ggtt)` **before** error capture (range held `I915_COLOR_UNEVICTABLE`);
the takeover releases it and pins the stolen object exactly there. Log: `holding GGTT 0x0+0x7e9000 for the boot
framebuffer (1920x1080)`. Build `8e8a8f8e…`.

## Test 8 — 0007+0008

`8e8a8f8e…`. Black screen; Caps Lock worked for a while, then stopped.
- [measured] `the boot framebuffer 0x4000000001 is not in the GGTT aperture`: `v_baseAddr` carries a flag in bit 0
  → no hold, no takeover, shmem fallback.
- `NMXAccel: NMXGPU drives 8086:a7a8 - starting`: attach returned. With DRM debug on, macOS drops some kext lines.
- WindowServer found the framebuffer on GFX0: `Setting offline display`, `Failed to obtain mode info`; NVMTL:
  `headless GPU: no device for WindowServer`. Login window reached at 22:19:03; log ends ~9 s after WindowServer
  started using the framebuffer. `Bad frame buffer index` spam is noise (seen in healthy boots too).
- [inferred] Hypothesis: writes to the aperture while the GPU is runtime-suspended (Linux revokes GGTT mmaps before
  suspend). README of nullmoth: this display path "has not been loaded on hardware".

### 0009
`nmx_xnu_boot_fb` = `(v_baseAddr & ~0xfff) + v_offset`; the bridge **keeps a runtime-PM wakeref** while the
framebuffer exists (`GPU kept awake while it is shown`). Build without DRM debug. `775e893a…`.

Research: WhateverGreen (Apple drivers ≤ Ice Lake), NootedBlue (≤ Gen11) — no use. NootedGreen loads Apple's
**Tiger Lake** drivers on RPL-P (macOS 14.7.1): fragmented image, WindowServer hang ~200 ms after activation —
different path, confirms display↔WindowServer is the hard part.

## Test 9 — 0009, no debug

`775e893a…`. Black screen, frozen, **no log**. `nullmoth-gpu-attaching` was **absent** → attach returned and the
framebuffer was published; the freeze came later. [measured] Keeping the GPU awake was not enough (wakeref kept: it is
correct for aperture writes).

### 0010 — NVRAM trail
Each step appended to `nullmoth-gpu-trail` with an immediate `sync` (survives freezes): `attach`, `hold`, `attached`,
`publish`, `probe`, `i915-fb`, `take-pin`, `took`/`fallback`, `fb-pin`, `iomap`, `commit`, `lit`, `published`,
plus `fb-vram`, `fb-setmode`, `ws-on/off`, `fb-pwr-on/off`. Read after a `-nvoff` boot. Build `06f83e7a…`.

## Test 10 — 0010

Frozen, no log. Trail `attach hold attached publish probe i915-fb fallback fb-pin iomap commit lit`, attaching=1.
- `hold` works (0009 fixed the address); takeover still `fallback`. `commit lit`: **bridge modeset works**.
- Freeze between `lit` and `published` (DRM client register + hotplug, `IOFramebuffer::start`,
  `registerPowerDriver`, `registerService`).

### 0011 — finer trail
`client-reg`, `hotplug`, `registered`, `fb-new`, `fb-start`, `fb-started`, `fb-pm`, `fb-reg`; takeover failure reasons
`tk-noboot|geom|nomem|pte|run|obj|vma|range|pin`. Build `157d5e78…`.

## Test 11 — 0011

Trail `… tk-obj fallback … lit client-reg hotplug registered fb-new fb-start fb-started fb-pm fb-reg published`,
attaching **cleared**. **The whole attach completes**; no `fb-vram`/`fb-setmode`/`ws-on` — macOS had not used our
framebuffer yet. [inferred] The freeze point varies → something asynchronous. `tk-obj`: the stolen range already has
an owner.

### 0012
`nullmoth-gpu-beat` every 2 s for 5 min after `published` (`t open ioctl in cmd`); `i915_gem_drain_freed_objects`
before the takeover. Build `821d791c…`.

## Test 12 — 0012

Frozen. Same trail as 11; **no beat at all** → [measured] freeze < 2 s after the IOFramebuffer registers.
Research: since 2.0.0 `NVRMFBClaim` only takes NVIDIA, so the firmware **`IONDRVFramebuffer` (`.Display_boot`) stays
on the Intel GPU** — two "console" framebuffers on one GPU. nullmoth 2.0.3/2.0.4: app only.

### 0013
First call of each `NMXGPUFB` method in the trail (`fb-con fb-ap fb-cur fb-boot fb-tim fb-irq fb-ps0/1 fb-gac fb-sac
fb-ga fb-sa fb-pix fb-gam fb-inf fb-vbl fb-modes fb-fmt fb-en fb-cf fb-clut`); trail 480 chars/80 steps;
`tk-obj<err>@<off>+<size>`; beat from attach start, 0.5 s; boot-args `nmxcon=0`, `nmxfb=2`, `nmxfb=0`. `6ebb4854…`.

## Test 13 — 0013

Trail ends `… fb-new fb-start fb-started`, attaching=1, no beat.
- Stopped **inside `NMXGPUFB::start`**, between `IOFramebuffer::start` and `registerPowerDriver` (root cause found in
  test 25: NULL controller).
- [measured] `tk-obj-28@0+7e9000` = `-ENOSPC`: i915 already put its own objects (e.g. GT scratch) in the GOP stolen
  pages (first-fit allocator), while the console and IONDRV still draw there through the aperture.

### 0014
`init_ggtt` also reserves the GOP pages in the stolen allocator (`shold`, `shold-fail st<start>+<size>`,
`shold-none`); takeover releases it just before creating the object. Beat stamped at the end of the trail (` @ms`).
`95984416…`.

## Test 14 — 0014 — **takeover works**

Trail `attach hold shold attached publish probe i915-fb take-pin took fb-pin iomap commit lit client-reg hotplug
registered fb-new fb-start fb-started fb-pm fb-reg published`.
- **`took`**: the bridge owns the GOP framebuffer; the panel shows the macOS console through i915 (photo).
- Attach completes, then the Mac freezes. The beat never appears.

### 0015 — test knobs in NVRAM
`nmx_xnu_knob(bootarg, nvvar, default)`: boot-arg, else NVRAM variable, else default.
`sudo nvram nullmoth-gpu-fb=2` (light the panel, do not publish our IOFramebuffer), `=0` (no bridge),
`nullmoth-gpu-con=0`; delete with `sudo nvram -d …`. `ff044b86…`.
