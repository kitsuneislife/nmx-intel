# Source fixes catalogue

> **Summary.** All our changes live in `source-fixes/` and are applied by `build/apply-fixes.sh` (each tagged
> `fix-00NN` in its clone; already-applied patches are skipped). Repo: **N** = nullmoth (`~/nmx-build/nvidia-macos-driver`,
> branch `nmx-intel-build`), **D** = drm-kmod (`~/nmx-build/gpu-src/kpi/drm-kmod`, branch `nmx-intel`).
> Kind: **fix** (behaviour), **diag** (diagnostics only), **knob** (switch). Test = where it was first exercised.

| # | Repo | Kind | Test | What it does |
| --- | --- | --- | --- | --- |
| 0001 | N | fix | 6 | `linux_pci_find` matches only the probing driver's table (i915 gets `a7a8`, xe intact) |
| 0002 | D | fix | 6 | no visible PCH → guess `PCH_ADP` (correct PPS base) |
| 0003 | D | fix | 6 | no DP tunnel manager / tunnel is not an error |
| 0004 | N | fix | 6 | i915 display bridge (`override/i915/nmx_i915_fb.c`), aperture address published |
| 0005 | D | diag | 6 | `-DNMX_DRM_DEBUG` → `__drm_debug = 0x6` (`build-all.sh debug`) |
| 0006 | N | fix | 7 | take over the GOP framebuffer (`nmx_xnu_boot_fb`, stolen object at its GGTT offset) |
| 0007 | D | fix | 8 | `init_ggtt` holds the boot fb GGTT range before error capture |
| 0008 | N | fix | 8 | takeover pins exactly in the held range |
| 0009 | N | fix | 9 | boot fb flag bits masked; runtime-PM wakeref while the fb exists |
| 0010 | N | diag | 10 | NVRAM trail `nullmoth-gpu-trail` |
| 0011 | N | diag | 11 | finer trail, takeover failure reasons |
| 0012 | N | diag | 12 | heartbeat; drain freed objects before takeover |
| 0013 | N | diag/knob | 13 | per-method trail, earlier beat, `nmxcon`/`nmxfb` |
| 0014 | N | fix | 14 | hold the GOP stolen pages in the stolen allocator; beat stamped in the trail |
| 0015 | N | knob | 15 | `nmx_xnu_knob`: NVRAM test switches |
| 0016 | D | fix | 16 | FBC and PSR off by default on xnu |
| 0017 | N | fix | 18 | one vnode per device node (DRM opens work) |
| 0018 | N | fix | 19 | ENXIO from `fdopen` after `finit` is success |
| 0019 | N | fix | 20 | `GET_PCIINFO` walks up to the PCI function |
| 0020 | N | diag | 21 | `nullmoth-gpu-io` request log; build stops on failed files |
| 0021 | N | fix | 22 | RCU readers may block (`override/src/linux_rcu.c`) |
| 0022 | N | diag | 23 | 1 s heartbeat with `irq`/`iot` |
| 0023 | D | diag | 23 | GPU power events in the io log |
| 0024 | N | fix/knob | 24 | no NMXAccel claim without our framebuffer (`nullmoth-gpu-accel`) |
| 0025 | N | fix | 25 | `NMXGPUFB` VBL on its own thread, only when enabled |
| 0026 | N | fix/knob | 26 | own `IOFBDependentID` before start (`nullmoth-gpu-fbdep`); NMXAccel off by default |
| 0027 | N | fix/knob | 27 | VBL enabled at registration; remove the firmware IONDRV (`nullmoth-gpu-ndrv`) |
| 0028 | N | fix | 28 | find the firmware fb among GFX0's children |
| 0029 | N | fix | 29 | remove it only after WindowServer opened it (thread) |
| 0030 | N | fix | 30 | `IOService::terminate` (avoids the AppleUpstreamUserClient panic) |
| 0031 | N | fix/knob | 31 | no VBL by default (`nullmoth-gpu-vbl`) |
| 0032 | N | fix/knob | 32 | shadow framebuffer in RAM + row copy (`nullmoth-gpu-shadow`) |

Other series:
- `source-fixes/intelfb/intelfb-0001..0008` — NMIntelFB (RTX path): `-nvoff` exit, NVRAM trail/guard/knobs, dependent
  ID before start, first-call trail, 2-min guard, heartbeat, own-thread VBL/beat, optional delay. Built by
  `tools/intelfb/build.sh` from nullmoth `v2.1.0`.
- `intelfb-0009` (fix/knob, RTX-8) — own `IOFBDependentID` (`0x4E4D494E00000001`); index 4 at publish (NVAccel's head
  number), index 0 set in `open()` (IOGraphics' `fFbs[]` slot). `nullmoth-intelfb-dep=2` = old NVRM group.
- `intelfb-0010` (fix/knob, RTX-9) — publish as NVAccel head 0 (its only possible `fFB`); `nullmoth-intelfb-head=4` = RTX-8.
- `intelfb-0011` (fix/knob, RTX-10) — own NVKMS device; answers `nvRmHandles`, `nvAllocVram`, `nvFreeVram` for NVAccel;
  `nullmoth-intelfb-kapi=0` turns it off.
- `source-fixes/libdrm/libdrm-0001` — Darwin node numbers from names (clone nodes). Built by `tools/libdrm/build.sh`.
- `build/nmx-src-paths.patch` — source paths for building on this Mac (applied by `build/setup.sh`).

Making a new fix: edit in the clone, `git commit`, `git tag -f fix-00NN`, `git format-patch -1 --stdout >
source-fixes/00NN-<slug>.patch`, add an `apply` line to `build/apply-fixes.sh` (and its header range), add a row here.
