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
- `intelfb-0012` (fix/knob, RTX-11) — VBL always fires once registered (`nullmoth-intelfb-vbl=0` = old); BAR1 size as
  NVRMFB measures it.
- `intelfb-0013` (fix/knob, RTX-12) — `NMIntelFBClaim` holds GFX0 and publishes an Intel-panel `NVRMDisplay` nub under
  NVRM; NMIntelFB runs on it (`nullmoth-intelfb-nvparent=0` = on GFX0).
- `intelfb-0014` (fix, RTX-13) — `NMIntelFBAGDC` answers AGDC 1 and 0x980 with the panel; `sysctl debug.nmintelfb_agdc=1`.
- `intelfb-0015` (fix, RTX-14) — `NVRMTiming` from the Intel timing; AGDC answers 0x921 (link config) and 0x711
  (plane scaler) with nullmoth's `nvk5_answer`.
- `intelfb-0016` (fix/knob, RTX-15) — a VRAM block of our own stands for the scanout (`phys`), kva stays the Intel
  surface; `nullmoth-intelfb-scanres=0` = phys 0.
- `intelfb-0017` (knob, RTX-20) — `sysctl debug.nmintelfb_ram=1`: the panel scans out of a RAM buffer (GGTT entries of
  the scanout repointed, picture copied first; `=0` restores them); page list offered as `nmIntelFBRamPages`.
- `intelfb-0018` (diag, RTX-22) — display registers (TRANSCONF, PLANE_CTL/SURF, PP_STATUS/CONTROL, BLC PWM 1/2, PTE 0)
  logged at each power change and readable as `sysctl debug.nmintelfb_regs`.
- `intelfb-0019` (knob, RTX-23) — `debug.nmintelfb_ram=2`: second RAM buffer at GGTT 0x800000, NVAccel writes the one
  off screen (after `PLANE_SURFLIVE` shows the last flip landed), `nmIntelFBRamFlip` sets `PLANE_SURF` to it.
- `intelfb-0020` (BL-2) — panel brightness: "backlight" `IODisplayParameterHandler` + `getAppleSense` LCD (NVRMFB's,
  ported); level → `BXT_BLC_PWM_DUTY1`. `nvram nullmoth-intelfb-backlight=0` turns it off.
- `intelfb-0021` (GUARD-1) — stand down when nullmoth's boot guard has NVRM off (`nullmoth-remove` set, or
  `nullmoth-nv-starts` ≥ 2, and no NVRM instance attached): no claim, so IONDRVFramebuffer gives the firmware desktop.
  Log `off: nullmoth's boot guard turned NVRM off`, trail `guard: NVRM off`. `nvram nullmoth-intelfb-guard=0` undoes it.
- `source-fixes/accel/accel-0001` (knob/diag, RTX-18) — NVAccel (branch `nmx-accel` from nullmoth v2.1.0, worktree
  `~/nmx-build/accel/src`, tag `accel-0001`, built by `tools/accel/build.sh`): `debug.nvaccel_iop_memcpy=1` copies
  frames to a CPU scanout with `memcpy` rows; `debug.nvaccel_iop_direct=1` puts the copy engine's staging buffer on
  the panel without writing the IOSurface's pages (pending mark kept); counters `nvaccel_iop_direct_frames`,
  `nvaccel_iop_copy_us`. Both off by default.
- `source-fixes/accel/accel-0002` (knob, RTX-20) — `debug.nvaccel_iop_direct=2`: the copy engine writes into the
  panel's RAM pages from `nmIntelFBRamPages` (no CPU copy); falls back to direct=1. Counter `nvaccel_iop_ram_frames`.
- `source-fixes/accel/accel-0003` (RTX-23) — after each RAM frame NVAccel calls `nmIntelFBRamFlip` with the pages written.
- `source-fixes/libdrm/libdrm-0001` — Darwin node numbers from names (clone nodes). Built by `tools/libdrm/build.sh`.
- `build/nmx-src-paths.patch` — source paths for building on this Mac (applied by `build/setup.sh`).

Making a new fix: edit in the clone, `git commit`, `git tag -f fix-00NN`, `git format-patch -1 --stdout >
source-fixes/00NN-<slug>.patch`, add an `apply` line to `build/apply-fixes.sh` (and its header range), add a row here.
- `tools/nvrm/build.sh` (binary patch, RTX-25) — NVRM `12fcabf3` → `f5171d7b`: the copy-engine wait in
  `nvrm_ce_copy_to_pages` sleeps 1 ms (`os_delay`) instead of spinning 10 µs (`osDelayUs`), limit 2000. NVRM cannot
  be rebuilt from the published source (needs a Darwin RM build nullmoth does not publish).
- UPG-1 (nullmoth 2.3.6): NVRM `122b3994` → `8c8873d5` (same three patches at `0x1b778/0x1b783/0x1b788`);
  `source-fixes/accel/v2.3.6/accel-0001..0003` = the accel series rebased on v2.3.6 (branch `nmx-accel-236`), NVAccel
  `8166045f`. NMIntelFB unchanged (`36afddf1` from either tag).
- `source-fixes/wifi/wifi-0001` (WIFI-1) — SimpleMtkWlan (OverlordDev fork): `probe` leaves the card alone on
  `-nvoff` or `-mtkwlanoff`. Applied by `tools/wifi/build.sh` with `git am`.
- `source-fixes/wifi/wifi-0002` (WIFI-1) — the ring log stops with public `thread_call_cancel` + wait instead of
  private `thread_call_cancel_wait`, which kmutil refuses to link into a third-party kext.
- `source-fixes/wifi/wifi-0003` (WIFI-2) — log interrupt and MCU/FWDL ring state when an MCU command times out
  (diagnostics only).
- `source-fixes/wifi/wifi-0004` (WIFI-3) — MCU waits poll the interrupt handler every 2 ms (guarded `mwx_intr`), so a
  reply that arrives while `start`/`enable` hold the workloop gate is not lost.
- `source-fixes/wifi/flx-v1.5.0/wifi5-0001` (WIFI-5) — AirportMtkWlan (flxxxxddd v1.5.0): `IOPCIEDeviceWrapper::probe`
  leaves the card alone on `-nvoff` or `-mtkwlanoff`. Applied by `tools/wifi/build-airport.sh`.
- `source-fixes/wifi/flx-v1.5.0/wifi5-0002` (WIFI-5) — `taskq_quiesce` waits on an in-flight counter instead of private
  `thread_call_cancel_wait` (kmutil refused the kext); host test stub follows xnu's ONCE rules.
- `source-fixes/wifi/flx-v1.5.0/wifi5-0003` (WIFI-6, knob) — NVRAM `nullmoth-wifi-band=5`: no 2.4 GHz channels
  (scans, macOS list and joins on 5 GHz only).
- `source-fixes/wifi/flx-v1.5.0/wifi5-0004` (WIFI-7) — prefer 5 GHz by default: scan 5 GHz first, hide a 2.4 GHz
  beacon whose SSID is on 5 GHz within 15 RSSI points; `nullmoth-wifi-band=2` = upstream. Host scan test covers both.
- `source-fixes/wifi/flx-v1.5.0/wifi5-0005` (WIFI-8) — TXWI: compare the unshifted frame type, so data uses firmware
  rate adaptation instead of the fixed basic rate with BA disabled (luzility `110c92c`); EAPOL keeps the basic rate.
- `source-fixes/wifi/dropped-wifi-0005` (WIFI-4, **dropped**: hung the boot) — the 1 s watchdog runs the interrupt handler when `HOST_INT_STA` has
  pending bits (lost MSI) and dumps the RX DMA state after 3 s without frames.
