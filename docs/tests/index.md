# Test index

One row per test. Binary = first 8 hex of the SHA-256 of `NMXGPU` (or `NMIntelFB` for RTX tests). Details live in the
phase file; open only the row you need.

| Test | Date | Binary | Change under test | Result | Phase file |
| --- | --- | --- | --- | --- | --- |
| 0 | 10-15 | `33aa04a8` | stock 2.0.2 | i915 never probes (xe wins the ID match) | [00-05](00-05-binary-patches.md) |
| 1 | 10-15 | `10538014` | patch 1 | boot freeze, `PPS state mismatch` loop (no PCH) | [00-05](00-05-binary-patches.md) |
| 2 | 10-15 | `11c2f5bb` | patches 1–2 | boots; `Device initialization failed (-102)` | [00-05](00-05-binary-patches.md) |
| 3 | 10-15 | `8fda0afb` | + patch 3 (debug) | -102 = `intel_dp_tunnel_mgr_init` stub | [00-05](00-05-binary-patches.md) |
| 4 | 10-15 | `1378bc32` | + patch 4 | `Initial modeset failed, -102` (tunnel check stub) | [00-05](00-05-binary-patches.md) |
| 5 | 10-15 | `c55a4432` | patches 1–5 | **i915 drives the GPU**; bridge `vmap` -102 → DC6 black | [00-05](00-05-binary-patches.md) |
| 6 | 10-15 | `df90b1b5` | own build, 0001–0005 | shifted console image, freeze | [06-14](06-14-display-bridge.md) |
| 7 | 10-15 | `da43cdbb` | 0006 GOP takeover | black, freeze; GGTT 0 owned by error capture | [06-14](06-14-display-bridge.md) |
| 8 | 10-16 | `8e8a8f8e` | 0007–0008 hold GGTT | flag bit 0 in boot fb address; freeze after WS | [06-14](06-14-display-bridge.md) |
| 9 | 10-16 | `775e893a` | 0009 wakeref | attach returned, freeze later, no log | [06-14](06-14-display-bridge.md) |
| 10 | 10-16 | `06f83e7a` | 0010 NVRAM trail | freeze between `lit` and `published` | [06-14](06-14-display-bridge.md) |
| 11 | 10-16 | `157d5e78` | 0011 finer trail | attach completes; `tk-obj` | [06-14](06-14-display-bridge.md) |
| 12 | 10-16 | `821d791c` | 0012 beat | freeze < 2 s after IOFramebuffer registers | [06-14](06-14-display-bridge.md) |
| 13 | 10-16 | `6ebb4854` | 0013 per-call trail | stops inside `NMXGPUFB::start`; stolen `-ENOSPC` | [06-14](06-14-display-bridge.md) |
| 14 | 10-16 | `95984416` | 0014 hold stolen pages | **takeover works** (`took`); still freezes | [06-14](06-14-display-bridge.md) |
| 15 | 10-16 | `ff044b86` | 0015, `fb=2` | **no freeze**; panel image frozen (FBC/PSR) | [15-24](15-24-drm-userspace.md) |
| 16 | 10-16 | `8ce69ba8` | 0016 no FBC/PSR | panel live; ANV 0 devices | [15-24](15-24-drm-userspace.md) |
| 17 | 10-16 | `8ce69ba8` | `tools/probe` | every DRM open fails (no vnode) | [15-24](15-24-drm-userspace.md) |
| 18 | 10-16 | `47133df7` | 0017 vnode | **desktop via i915** (IONDRV); open → ENXIO | [15-24](15-24-drm-userspace.md) |
| 19 | 10-16 | `7a16c6ad` | 0018 ENXIO=ok | `driver i915 1.6.0`; libdrm/`GET_PCIINFO` fail | [15-24](15-24-drm-userspace.md) |
| 20 | 10-16 | `8f2b4b6f` | 0019 + libdrm-0001 | ANV reaches GPU; freeze (RCU) | [15-24](15-24-drm-userspace.md) |
| 21 | 10-16 | `5b738a60` | 0020 io log | RCU `synchronize_rcu` spin (panic TLB timeout) | [15-24](15-24-drm-userspace.md) |
| 22 | 10-16 | `9a361f0e` | 0021 RCU | freeze ~4 min, WS loops `RM refused` | [15-24](15-24-drm-userspace.md) |
| 23 | 10-16 | `2f1e7630` | 0022–0023 | macOS watchdog kills stuck WindowServer | [15-24](15-24-drm-userspace.md) |
| 24 | 10-16 | `7fd87526` | 0024 no NMXAccel w/o our fb | **desktop stable; ANV sees RPL-P** | [15-24](15-24-drm-userspace.md) |
| RTX-1 | 10-16 | `3b86a1e1` | NMIntelFB | boot freeze, no log | [rtx](rtx-1-7-nmintelfb.md) |
| RTX-2 | 10-16 | `9dbd6128` | intelfb-0002 | hang in `registerPowerDriver` | [rtx](rtx-1-7-nmintelfb.md) |
| RTX-3 | 10-16 | `261eca1c` | intelfb-0003 dep ID first | `start` ok; black + freeze later | [rtx](rtx-1-7-nmintelfb.md) |
| RTX-4 | 10-16 | `65901097` | intelfb-0004/5 | full `open`; freeze after `setInterruptState` | [rtx](rtx-1-7-nmintelfb.md) |
| RTX-5 | 10-16 | `bf5091eb` | intelfb-0006 beat | VBL blocks HIGH thread_call group | [rtx](rtx-1-7-nmintelfb.md) |
| RTX-6 | 10-16 | `2119d10f` | intelfb-0007 own threads | black; NVRAM stops recording ~20 s | [rtx](rtx-1-7-nmintelfb.md) |
| RTX-6b | 10-16 | `2119d10f` | `dep=0` | hang in `registerPowerDriver` | [rtx](rtx-1-7-nmintelfb.md) |
| RTX-7 | 10-16 | `e2c417e7` | intelfb-0008 delay 45 s | same freeze → path parked | [rtx](rtx-1-7-nmintelfb.md) |
| 25 | 10-16 | `483a5ae5` | 0025 VBL thread, `fb=1` | stops after `fb-started`: NULL `IOFBController` | [25-32](25-32-framebuffer.md) |
| 26 | 10-16 | `838aa8d3` | 0026 own dependent ID | **desktop on `NMXGPUFB` 144 Hz**; glitches | [25-32](25-32-framebuffer.md) |
| 27 | 10-16 | `3fc8feaf` | 0027 VBL on, drop IONDRV | VBL ok; `ndrv-none` | [25-32](25-32-framebuffer.md) |
| 28 | 10-16 | `d002eae8` | 0028 find via GFX0 children | freeze: terminate of unopened IONDRV | [25-32](25-32-framebuffer.md) |
| 29 | 10-16 | `a954ffc0` | 0029 terminate after open | panic in `AppleUpstreamUserClientDriver` | [25-32](25-32-framebuffer.md) |
| 30 | 10-16 | `52305765` | 0030 `IOService::terminate` | one IOKit fb, no freeze, same glitches | [25-32](25-32-framebuffer.md) |
| 31 | 10-16 | `c1445517` | 0031 no VBL | same glitches; aperture reads 2.6 MB/s | [25-32](25-32-framebuffer.md) |
| 32 | 10-16 | `9823079e` | 0032 shadow fb | stale 2nd WS display; **mirror → no glitches** | [25-32](25-32-framebuffer.md) |
| RTX-8 | 10-16 | `ca82df9d` | intelfb-0009 own controller | pending | [rtx-8](rtx-8-accelerated-desktop.md) |

Adding a test: one row here, the entry at the end of the current phase file (start a new phase file when the goal
changes), then [../status.md](../status.md).
