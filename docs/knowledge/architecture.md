# Architecture: how a frame reaches the panel

> **Summary.** i915 (inside NMXGPU) owns the Intel display engine and scans out the GOP framebuffer pages in stolen
> memory. macOS sees our IOFramebuffer `NMXGPUFB`; WindowServer composites **in software** into a shadow buffer in
> RAM, and a kernel thread copies changed rows to those pages through the GGTT aperture. The firmware's IONDRV display
> survives as a ghost screen in WindowServer and is mirrored away. NMXAccel/ANV give Metal to apps only (unfinished).

```
 WindowServer (software compositor, ~225 % CPU)
   │  draws into VRAM range published by NMXGPUFB  ──────────────►  shadow: 8 MB contiguous RAM (0032)
   │                                                                  │ copyThread, changed rows, ~60/s, WC + sfence
   │  (ghost) firmware display .Display_boot, mirrored (tools/mirror) ▼
   │        └── draws straight into the aperture ───────────►  GGTT aperture 0x4000000000 (BAR2, uncached, slow reads)
   │                                                                  │ GGTT PTEs 0..0x7e9000
   ▼                                                                  ▼
 NMXGPUFB (xnu/nmx_fb.cpp)                                     stolen memory 0x3e800000+0 (GOP fb pages, held: 0014)
   IOFBDependentID 'NMXI'<<32|id (0026), no VBL (0031)                │ scanned by
   │                                                                  ▼
 display bridge (override/src/nmx_fb_bridge.c,                 i915 display engine: pipe A, plane 1A, eDP 1920x1080
   override/i915/nmx_i915_fb.c): takes over the GOP fb (0006–0008, 0014), keeps a wakeref (0009), FBC/PSR off (0016)
   │
 NMXGPU.kext = i915 (drm-kmod, Linux 6.14) on xnu via FreeBSD LinuxKPI ("xkpi")
   │  /dev/dri/card0, renderD128 (devfs clones; vnode 0017, ENXIO 0018, GET_PCIINFO 0019, RCU 0021)
   ▼
 libdrm (nullmoth + libdrm-0001) → Mesa ANV → nvmtl plugin → Metal for apps (NMXAccel; off by default, 0024/0026)
```

## Components

| Component | Where | Role here |
| --- | --- | --- |
| NMXGPU | nullmoth `gpu-port/xkpi`, built in `~/nmx-build` | amdgpu/i915/xe on xnu; attaches from a thread once firmware files mount |
| i915 | drm-kmod `c16de0f9fa` | probes `a7a8` (0001), PCH guess (0002), no DP tunnel (0003) |
| Display bridge | `override/src/nmx_fb_bridge.c`, `override/i915/nmx_i915_fb.c` | lights the panel with the GOP fb, publishes it to xnu |
| `NMXGPUFB` | `xnu/nmx_fb.cpp` | the IOFramebuffer WindowServer opens (one mode, 144 Hz) |
| IONDRVFramebuffer `.Display_boot` | Apple, on `GFX0@2` | firmware screen; terminated after open (0029/0030) but stays in WindowServer |
| NMXAccel | `kexts/NVRM/accel/nvrm-accel.cpp` with `NMX_ACCEL` | IOAccelerator for AMD/Intel; `fFB` never set → cannot serve WindowServer |
| nvmtl plugin | `plugin/nvmtl_vk.c` | Metal on Vulkan; picks ANV for `8086` accelerators; app-only for AMD/Intel |
| NVIDIA stack | NVRM, NVRMFB, NVAccel (app 1401) | RTX works; `NMIntelFB` path would composite on it (parked) |

## Boot sequence (healthy, test 32)

`attach` (NMXGPU thread) → `hold`/`shold` (GGTT + stolen held in `init_ggtt`) → `attached` (i915 up) → `publish` →
`take-pin took` (GOP fb taken) → `commit lit` (bridge modeset) → `client-reg hotplug registered` → `fb-new fb-dep
fb-start fb-shadow fb-started fb-pm fb-reg` → `published` → WindowServer opens it (`fb-con … fb-setmode fb-ap
fb-vram`) → `fb-copy` → `ndrv-term ndrv-gone` (firmware fb leaves IOKit ~45 s in) → `tools/mirror` mirrors the ghost.
