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
| RTX-8 | 10-16 | `ca82df9d` | intelfb-0009 own controller | **no freeze**, full `open`, `alive`; NVAccel never registers head 4 | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-9 | 10-16 | `0d6239e0` | intelfb-0010 publish as head 0; `enable.sh` +iop | pipe registered; new WS hangs: no RM handles/VRAM | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-10 | 10-16 | `29893f31` | intelfb-0011 own NVKMS device answers NVAccel | **WS runs on RTX Metal**, VRAM ok; no frame reaches the panel (no VBL) | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-11 | 10-16 | `c07eb921` | intelfb-0012 VBL always + BAR1 size | VBL fires; CoreDisplay: "no display pipes" (fb on the Intel GPU) | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-12 | 10-16 | `b230f46f` | intelfb-0013 panel under NVRM (claim + nub) | fb now on the NVIDIA GPU; still "no display pipes": no AGDC | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-13 | 10-16 | `937ae0fa` | intelfb-0014 own AGDC lists the panel (0x980) | **"no display pipes" gone**, display online; "No plane indices" (0x921/0x711 unanswered) | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-14 | 10-16 | `a96fc475` | intelfb-0015 AGDC answers link config + plane scaler (K5) | **WS composites the desktop on the RTX**; plane 0 exists; every transaction submission fails | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-15 | 10-16 | `1d3ea017` | intelfb-0016 VRAM block as the pipe's scanout resource | **accelerated desktop on the panel** (frames copied, 0 failures; WS ~67 % CPU) | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-16 | 10-16 | `1d3ea017` | `tools/intelfb/auto.sh` enables at boot (LaunchDaemon) | **accelerated from the login window**, no restart needed | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-17 | 10-16 | NVAccel `29a7f015` | our build of nullmoth v2.1.0 NVAccel, unchanged (bridge stage 0) | **same as RTX-16** (0 failures, accelerated at login) |
| RTX-18 | 10-16 | NVAccel `41260d45` | accel-0001: `iop_memcpy` / `iop_direct` knobs, A/B at run time | **direct: −31 % per frame**, memcpy alone ±0; 0 failures | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-19 | 10-17 | NVAccel `41260d45` | `auto.sh` turns memcpy + direct on at boot | **works**: every frame direct, ~2.8 ms per frame, 0 failures | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-20 | 10-17 | NMIntelFB `6145a549`, NVAccel `a4d13738` | stage 4a: panel scans out of RAM, copy engine writes it (`ab.sh ram`) | **works**: 2.78 → 1.44 ms per frame, kernel_task per frame −46 %, no artefacts | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-21 | 10-17 | same + `auto.sh` | `auto.sh` turns the RAM scanout on at boot (direct=2) | **works**: every frame through RAM, 0 failures; but real sleep → black panel after wake (hard reboot) | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-22 | 10-17 | NMIntelFB `eaf67fa1` | display registers at sleep/wake (intelfb-0018), RAM scanout off | **black again**: every display register 0 after wake (S3 resets the display engine); not the RAM scanout | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-23 | 10-17 | NMIntelFB `59c98103`, NVAccel `659dfa20` | stage 4b: two RAM buffers flipped at vblank (`ab.sh flip`) | **works**: 3409 flips, 0 late, same CPU per frame, no artefacts | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-24 | 10-17 | same + `auto.sh` | `auto.sh` turns the flip (ram=2) on at boot | **works**: mode 2 at boot, 7840 flips, 0 late, 0 failures | [rtx-8](rtx-8-accelerated-desktop.md) |
| RTX-25 | 10-17 | NVRM `f5171d7b` (binary patch) | stage 4c: copy-engine wait sleeps instead of spinning | **works**: kernel_task 12 % → 4 %, per frame −57 %, 0 failures | [rtx-8](rtx-8-accelerated-desktop.md) |
| BL-2 | 10-17 | NMIntelFB `36afddf1` | panel brightness: backlight handler + PWM duty (intelfb-0020) | **works**: keys + slider, duty follows (49 % at half) | [rtx-8](rtx-8-accelerated-desktop.md) |
| WIFI-1 | 10-17 | SimpleMtkWlan (OverlordDev `5b791c9` + wifi-0001) | MT7921 Wi-Fi, Ethernet-type driver from source | **fails**: loads, firmware patch times out (`command 7`), no interface | [wifi-1](wifi-1-mt7921.md) |
| WIFI-2 | 10-17 | SimpleMtkWlan + wifi-0003 | dump MCU/DMA state when the patch download times out | **firmware up**: en2, scans ~22 BSSs; first MCU reply lost behind the workloop gate | [wifi-1](wifi-1-mt7921.md) |
| WIFI-3 | 10-17 | SimpleMtkWlan + wifi-0004 | MCU waits poll the interrupt; join the home network | **connects** (WPA2, DHCP); dies under load (`networkQuality`) | [wifi-1](wifi-1-mt7921.md) |
| WIFI-4 | 10-17 | SimpleMtkWlan + wifi-0005 | lost-interrupt rescue in the watchdog, silent-RX dump | **boot hang**: configd watchdog panic after link up; recovered with `-nvoff`; driver removed | [wifi-1](wifi-1-mt7921.md) |
| UPG-1 | 10-18 | nullmoth 2.3.6 + NVRM `8c8873d5`, NVAccel `8166045f` | upgrade the NVIDIA driver 2.1.0 → 2.3.6, our patches ported | **works**: guard cleared, bridge 0 failures, same boot timeline; shader cache restarted empty | [rtx-8](rtx-8-accelerated-desktop.md) |
| WIFI-5 | 10-18 | AirportMtkWlan (flxxxxddd v1.5.0 `9a9c2ea` + wifi5-0001/0002) | native Wi-Fi menu driver, Sequoia IO80211 build | **native Wi-Fi works** (menu, Keychain join, clean reboot); download 0.24 Mbit/s vs upload 18.6 (BA holes, TX ring full) | [wifi-1](wifi-1-mt7921.md) |
| WIFI-6 | 10-18 | AirportMtkWlan + wifi5-0003, NVRAM `nullmoth-wifi-band=5` | 5 GHz only (2.4 GHz at MCS 1: 4.9 down / 0.9 up) | **38 down / 5.1 up** (VHT80 ch 108); 2.4-only networks hidden; upload limited by TX queue | [wifi-1](wifi-1-mt7921.md) |
| WIFI-7 | 10-18 | AirportMtkWlan `6bb3765a` (+wifi5-0004), knob unset | prefer 5 GHz: 5 GHz scanned first, 2.4 GHz twins hidden, 2.4-only kept | **works**: all networks listed, Nardino on 5 GHz, 36.8 / 5.09 | [wifi-1](wifi-1-mt7921.md) |
| WIFI-8 | 10-18 | AirportMtkWlan `a7bfaa40` (+wifi5-0005) | data frames through firmware rate adaptation (was fixed 1/6 Mbit/s, BA off) | **works**: 37.1 down / 36.9 up (phone's ceiling); curl 38 up / 45 down | [wifi-1](wifi-1-mt7921.md) |
| SLEEP-1 | 10-19 | OpenCore HibernateMode=Auto, `hibernatemode 25` | hibernate instead of S3, so the GOP relights the panel | **fails**: sleep policy chose deep idle (S3), never hibernated | [sleep-1](sleep-1-hibernate.md) |
| SLEEP-2 | 10-19 | + HibernationFixup 1.5.4, `hbfx-ahbm=1` | force hibernation over the platform sleep policy | **fails**: still type 7 (S3), panel off at wake; sleep parked | [sleep-1](sleep-1-hibernate.md) |
| GUARD-1 | 10-19 | NMIntelFB `241aff3d` (intelfb-0021) | stand down when nullmoth's boot guard has NVRM off | pending | [sleep-1](sleep-1-hibernate.md) |
| HYB-1 | 10-21 | NootedGreen `356c818`+hybrid-0001, libxedrv `c37b5a4f` | hybrid H1: Iris Xe alone on Apple's TGL driver (`config-hybrid.plist`, `-nvoff`) | fail: panic, `IntelAccelerator+0x150` NULL when WindowServer opens it | [hybrid-1](hybrid-1.md) |
| HYB-2 | 10-21 | NootedGreen `9cf68511` (+hybrid-0002) | refuse the device open without the kernel task; `efi.sh hybrid` boots hybrid once | fail: same panic, guard silent; TGL accelerator probed the RTX; auto fallback worked | [hybrid-1](hybrid-1.md) |
| HYB-3 | 10-21 | NootedGreen `3f20738f` (+hybrid-0003) | injected IntelAccelerator personality limited to the iGPU (`IOPCIPrimaryMatch`); guard via `IGAccelDevice+0x108` | pass (match): desktop on the Iris Xe, heavy artifacts, BCS hang at ~30 s, no Wi-Fi (`-nvoff`) | [hybrid-1](hybrid-1.md) |
| HYB-4 | 10-21 | NootedGreen `3f20738f`, hybrid config without `-v` | drop the verbose console (it overwrites GGTT contexts, Julio 9.3) | fail: boots, same artifacts; WindowServer composited on the RTX (NVMTLDriver; NVRM/NVAccel ignore `-nvoff`) | [hybrid-1](hybrid-1.md) |
| HYB-5 | 10-21 | hybrid config without `nvaccel=1` | keep nullmoth's Metal device away from WindowServer | fail: no NVIDIA Metal device, same artifacts; NootedGreen's log is lost as "compose failure" | [hybrid-1](hybrid-1.md) |
| HYB-6 | 10-21 | HYB-5 config; one-boot daemon saves `dmesg` at 0/60/180 s | read NootedGreen's IOLog to see which fixes run on Sequoia | partial: init readable (all fixes hooked, V140 1/4); session <1 min, no runtime lines | [hybrid-1](hybrid-1.md) |
| HYB-7 | 10-21 | HYB-6; `dmesg-last` refreshed every 20 s for 10 min | runtime XeNG lines during the artifacts | BLITSCRATCH2 as on Tahoe, no hang/restart: kernel healthy, artifacts are rendering correctness | [hybrid-1](hybrid-1.md) |
| HYB-8 | 10-21 | HYB-7; boot-once runs Julio's headless Metal tests on the Iris Xe | which Metal operation renders wrong | all pass (RGBA16F atlas 1/8); glyph atlases not covered | [hybrid-1](hybrid-1.md) |
| HYB-9 | 10-21 | HYB-8 + `xe-a8test` (A8/R8 glyph-atlas replaceRegion) | are text glyphs lost in small-format atlas uploads | 0/12 wrong in all 32 cases: atlas theory disproved | [hybrid-1](hybrid-1.md) |
| HYB-10 | 10-21 | HYB-9 + NootedGreen topology from the fuses (hybrid-0004) | does the hard-coded 96-EU topology break rendering on our GT1 | no-op (hook not routed); fuses measured: 3 DSS, 48 EU | [hybrid-1](hybrid-1.md) |
| HYB-11 | 10-21 | HYB-9 + no NumSubSlices=12 patch (hybrid-0004 v2): driver uses 6 SS / 48 EU | does the real topology fix the artifacts | 6 SS / 48 EU reported; artifacts unchanged | [hybrid-1](hybrid-1.md) |
| HYB-12 | 10-21 | HYB-11 + `xe-catest` (16 CoreAnimation primitives via CARenderer, PNG) | which CoreAnimation path breaks on the Xe | bug reproduced offscreen: rotated quad loses a triangle, path stripes, text/icon/opacity missing; textures and axis-aligned quads fine | [hybrid-1](hybrid-1.md) |
| HYB-13 | 10-21 | HYB-12 + `xe-geomtest` (rotated square drawn 9 ways in plain Metal) | which geometry path breaks | inconclusive: all tiles dark (MSAA resolve was the only clear, test flaw); catest losses changed between boots (rotated now OK, corner radius now cut) | [hybrid-1](hybrid-1.md) |
| HYB-14 | 10-21 | HYB-13, geomtest with separate passes + catest ×3 | geometry path; in-boot variation | plain geometry = RTX; MSAA black and GPU restart; catest after the restart almost perfect (blur missing) | [hybrid-1](hybrid-1.md) |
| HYB-15 | 10-21 | HYB-14 + full GT reset before Apple's start (`-ngreenbootgdrst`) | firmware engine state | panic 25 s: divide error in fbTimingsWorker (link N = 0) | [hybrid-1](hybrid-1.md) |
| HYB-15b | 10-21 | HYB-15 + timings worker checks TRANS_LINK_N1 (hybrid-0006) | firmware engine state | pending | [hybrid-1](hybrid-1.md) |
| UPG-2 | 10-21 | nullmoth 2.5.0 + NVRM `7da4dc21`, NVAccel `410790ed` | upgrade the NVIDIA driver 2.3.6 → 2.5.0 (NVIDIA 615), our patches ported | **fails**: black blinks; iop_blank 141, copy 2.93 ms/frame (was 1.44), GPU-wait timeouts; rolled back | [rtx-8](rtx-8-accelerated-desktop.md) |
| UPG-3 | 10-24 | nullmoth 2.5.4 + NVRM `cb2748c5`, NVAccel `8a251750` | upgrade 2.3.6 → 2.5.4: did 2.5.1–2.5.4 fix UPG-2's black blinks? | partial: blinks for ~5 min after the first boot (both copy modes, iop_blank 291), then 0; copy ~2.4 ms/frame (2.3.6: 1.44) | [rtx-8](rtx-8-accelerated-desktop.md) |
| UPG-3b | 10-24 | 2.5.4, WindowServer with `NVMTL_SURFIN_UPLOAD=cpu` | does the 2.5.1 copy-engine surface upload (#296) cause the blinks? | inconclusive: blinks stay; env not visible in WindowServer | [rtx-8](rtx-8-accelerated-desktop.md) |
| UPG-4 | 10-24 | 2.5.4 + NVAccel `b56b0440` (accel-0004) | keep up to 3 one-colour frames in a row off the panel (skip the flip) | **no effect on the blinks**: held 3 (one boot run); the blinks are not one-colour frames | [rtx-8](rtx-8-accelerated-desktop.md) |
| UPG-5 | 10-29 | nullmoth 2.6.4 + NVRM `3d9325f1`, NVAccel `b8c1df32`, NMIntelFB `241aff3d` kept | upgrade 2.5.4 → 2.6.4 (NvGfx copy/drag fixes in 2.6.3): do the blinks and the 2.4 ms/frame copy change? | **still blinks** (Lukas, first boot); counters not read | [rtx-8](rtx-8-accelerated-desktop.md) |
| XE-0 | 10-29 | WhateverXe Graphics 0.3.2 pkg + nmx-wex gate | install the pkg (replaces NootedGreen's stack), GPU-only boot: does NMIntelFB keep the iGPU? | **works**: TGL kexts in the AuxKC but idle, NMIntelFB owns the iGPU | [wex-1](wex-1.md) |
| XE-1 | 10-29 | WhateverXe `e92b65b0`, AMFIPass Mod `2d36aeca` | `efi.sh wex`: Apple's TGL driver on the Iris Xe via WhateverXe, one boot | **framebuffer starts, accelerator fails**: WEX's register prerequisites refuse (no Metal device) | [wex-1](wex-1.md) |
| XE-2 | 10-29 | as XE-1 | same boot, registry root + IGPU saved at 35 s: which WEX prerequisite fails? | **sameProvider**: WEX refuses Apple's FB start (eDP boot handoff `NotReady`), controller drops off the IGPU; DVMT fine | [wex-1](wex-1.md) |
| XE-3 | 10-29 | WhateverXe `ab6f9989` (built here, wex-0001 diag) | XE-2 with a bit per failed eDP handoff condition | **0x20001**: the eDP port fails `display13SSTPort` before any AUX step | [wex-1](wex-1.md) |
| XE-4 | 10-29 | WhateverXe `fdc5b254` (wex-0001 + 0002) | XE-3 plus a bit per failed SST port condition | **0x102000**: only the port mode (`+0x550`) fails; SST hooks ready | [wex-1](wex-1.md) |

Adding a test: one row here, the entry at the end of the current phase file (start a new phase file when the goal
changes), then [../status.md](../status.md).
| XE-5 | 10-29 | WhateverXe `d080f93b` (wex-0001..0003) | boot handoff accepts mode 0 on the combo eDP port; mode recorded | **Metal works on the Iris Xe**, panel black: dual-output CDCLK set fails (gate busy), clock faulted, every SST modeset `NotReady` | [wex-1](wex-1.md) |
| XE-6 | 10-29 | WhateverXe `94698a29` (wex-0001..0004) | cold dual-output clock set (CDCLK stopped, no pipe) falls back to the single path | **works: accelerated desktop on the Iris Xe** (Metal, IntelAccelerator, panel lit at 60 Hz) | [wex-1](wex-1.md) |
| XE-7 | 10-29 | as XE-6, `efi.sh wexrtx` | the hybrid: nullmoth's NVIDIA driver on (headless), NMIntelFB off | **works**: panel on the Iris Xe, RTX headless with Metal 3; compute runs correctly on both GPUs | [wex-1](wex-1.md) |
