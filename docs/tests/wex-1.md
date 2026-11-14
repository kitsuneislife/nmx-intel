# WhateverXe route: Iris Xe on Apple's TGL driver via WhateverXe (XE-0…)

> **Summary.** Replaces NootedGreen (HYB-1…15b) with b00t0x's WhateverXe 0.6.1 + WhateverXe Graphics 0.3.2, which
> run Apple's Tiger Lake Metal driver on the Iris Xe and select RPL-P from the physical `a7a8` (no device-id spoof).
> The Iris Xe composites the desktop; the RTX stays off (`-nvoff`). Tools: `tools/hybrid/wex-install.sh`,
> `wex-config.py`, `efi.sh wex`, `log.sh`. Research: [../knowledge/research.md](../knowledge/research.md).

## Setup (prepared 2026-10-29)

- Downloads in `~/nmx-build/whateverxe/dl/`, SHA-256 equal to the GitHub digests [measured]: RELEASE zip `46c8cd68`,
  DEBUG zip `04e9f0ad`, `WhateverXe-Graphics-0.3.2.pkg` `7ac6c714`. Kexts: `WhateverXe.kext` 0.6.1 (`e92b65b0`),
  AMFIPass 1.4.1 Mod (`2d36aeca`, from the pkg repo's `extras/`) kept as `AMFIPassMod.kext`.
- **Gate.** The pkg's `AppleIntelTGLGraphicsFramebuffer` (personality `AppleIntelFramebufferController`, IOProbeScore
  80000, IOFramebuffer) and `AppleIntelTGLGraphics` (`Gen7`) list `0xa7a88086` [measured]. NMIntelFB scores 61000 in
  the same category, so under the GPU-only config Apple's unpatched framebuffer would take the iGPU [inferred].
  `wex-install.sh` adds `IOPropertyMatch {nmx-wex = <01>}` to both; only `config-wex.plist` injects that property.
- `wex-install.sh`: removes the NootedGreen stack (TGL kexts, HookCase, bundles, `xe.bundle`), runs the pkg, gates,
  rebuilds the AuxKC our way and checks nullmoth's kexts, AirportMtkWlan, TGLCompat and both TGL kexts are in it.
  Any failure after the pkg puts back `~/AuxiliaryKernelExtensions.kc.antes-wex`. `remove` undoes it.
- `wex-config.py` from `config-gpu-only.plist`, diff checked [measured]: `WhateverXe.kext` after Lilu,
  `AMFIPass.kext` → `AMFIPassMod.kext`, iGPU `nmx-wex=<01>`, boot-args drop `-v nvaccel=1`, add
  `-allow3d -disablegfxfirmware msgbuf=400000 -nvoff`. No DVMT property: 64 MiB stolen is a multiple of 32 MiB
  [inferred OK; only 60 MiB needs `-igfxdvmt`]. SIP `0xa43` contains the `0x803` WhateverXe asks for [inferred].
- `efi.sh wex` boots it once (same one-boot daemon, dmesg buffers and Metal tests as the hybrid route).

## XE-0 (prepared 2026-10-29): pkg + gate installed, GPU-only boot

Variable: `/Library/Extensions` and the AuxKC only; EFI unchanged. Expected: normal RTX desktop; `log.sh` shows
NMIntelFB on the iGPU and no `AppleIntelFramebufferController` / `IntelAccelerator` IOClass. If Apple's framebuffer
attaches, the gate failed: `sudo bash tools/hybrid/wex-install.sh remove`.

## XE-1 (prepared 2026-10-29): WhateverXe route, one boot

Variable: `efi.sh wex`. Expected: WhateverXe drives the eDP from the GOP (pipe A, PPS0, PWM0), the TGL accelerator
starts, WindowServer composites on the Iris Xe; compare the catest PNG with HYB-12 (text/icons missing on
NootedGreen). If the panel stays black: the next boot is GPU-only by itself; try `-wex-noaccel` (framebuffer only),
then the DEBUG build for logs. Panic before launchd: copy `config-gpu-only.plist` over `config.plist` from Windows or
Recovery.

### XE-0 result (2026-10-29 19:25): works, the gate holds

[measured] `~/hybrid.txt` (19:26) and the system: pkg receipts `org.b00t0x.WhateverXe.Common` and `.Sequoia`;
`/Library/Extensions` has `AppleIntelTGLCompat`, `AppleIntelTGLGraphics`, `AppleIntelTGLGraphicsFramebuffer`, and
no HookCase or `xe.bundle`. AuxKC (19:24) lists `com.apple.driver.AppleIntelTGLGraphics(Framebuffer)` 16.0.0 and
`org.b00t0x.AppleIntelTGLCompat` 0.6.1. Both personalities carry `IOPropertyMatch nmx-wex`. Boot: no TGL kext
loaded, the only IOClasses on the iGPU are `NMIntelFBClaim` and `NMIntelFB` (pipe A 1920x1080, 146.90 Hz), RTX
desktop as before, no panic. A `shutdown_stall` report at 19:24 is from the reboot itself [inferred, not read].

### XE-1 result (2026-10-29 19:29): WhateverXe's framebuffer starts, the accelerator does not

[measured] Booted with the WEX boot-args; the one-boot daemon put GPU-only back. dmesg-0:
- `AppleIntelTGLCompat: revision 0.5.0 started`; `IntelAccelerator::probe: Found device with ID 0xa7a88086`.
- Framebuffer: `Display13 native handoff status=2 writes=10`, `TGL330 resources native-return ddi=0 result=1`,
  `Display13 native controller start return=1` (one `[IGFB][ERROR] EFI using a different backlight frequency`).
- Accelerator: `stage=4 done=0` (WEX's `wrapTGLAcceleratorRegister`) with no `stage=4 done=1`, then
  `stage=3 result=200` (Apple's failure path, reason 0x200) and `TGL accelerator start returned 0`.
- Metal tests: `no Metal device` for all; carender all zero; `xe-tex-tests` `ERRO lib (null)`; 3 segfaults.
- No Wi-Fi: expected, `-nvoff` keeps our AirportMtkWlan off (pitfalls.md).

Reading of WEX 0.6.1 `kern_xe.cpp:13827`: on ADL-P/RPL-P (`adlnDetected`, set by `adlpRenderRequested`) the register
wrapper checks prerequisites first and returns false without calling Apple's function, and without logging
`stage=4 done=1`, when any fails [measured, source]. So one prerequisite failed: the shared Display13 controller, its
provider, `display13FBGTT` state, or the controller's reservation `0xDF8 >= stolen + 0x192000`. Which one is recorded
only in registry-root properties (`N97SharedRegisterCheck`), lost at reboot. Suspect: our 64 MiB stolen memory
(WEX asks for 96 MB DVMT) [unverified]. The dmesg buffers start at 1.2 s (131071 bytes), so WEX's early memory and
profile lines are missing.

## XE-2 (prepared 2026-10-29): XE-1 again, registry checks saved

No change to the route: `efi.sh boot-once` now saves `ioreg -l -d 1` of the registry root and the IGPU subtree at
~35 s (`/var/log/nmx-hybrid-ioreg-{root,igpu}.txt`), and `log.sh` prints them. Expected: `N97SharedRegisterCheck`
names the failing prerequisite (array: version, ready, controller match, callback, class size, same provider,
controller+0xC0, controller+0xDF8, GTT initialized, GTT faulted, memory faulted), plus WEX's `XELP*`/`TGL*` memory
records.

### XE-2 result (2026-10-29 19:40): the accelerator waits on a framebuffer handoff that failed

WhateverXe refuses Apple's framebuffer start, Apple's controller leaves the IGPU, and the accelerator's
`sameProvider` check fails. The 64 MiB DVMT is **not** the cause.

- `N97SharedRegisterCheck` = version 1, ready **0**, controller match 1, callback set, class size 0x1c80,
  **same provider 0**, +0xC0 0, **+0xDF8 0x4195000** (≥ stolen 64 MiB + 0x192000 = 0x4192000, so the reservation
  passes), GTT initialized 1, GTT fault 0, memory fault 0 [measured]. Only `sameProvider` fails.
- `N97FramebufferStartAccepted = No` [measured]: `kern_xe.cpp:8024`'s framebuffer-start wrapper returns `false` when
  not accepted, so IOKit drops Apple's `AppleIntelFramebufferController`. The saved IGPU subtree has
  `AppleIntelFramebuffer@0..2` and `.Display_boot` but no controller and no `IntelAccelerator` [measured]. The
  controller's provider is therefore not the IGPU when the accelerator registers [inferred].
- Why it is not accepted: `N97FBFirstPowerError` = `N97FBBootHandoff` = operation 7 (boot handoff, `kern_xe.cpp:8157`),
  status 1 (`NotReady`), result domain 0x13 (default, no domain), bridge faulted 1 [measured]. The init record
  `N97FBPower` (operation 0) is `Complete`, so `holdDPBootAUX` succeeded at init [measured].
- `N97FBBootHandoffCheck`: every IRQ, work-loop, surface, plane and path check passes (`check[35..37]` = 1), boot
  port 0 (DDI A, the eDP), plane control 0x94000008, stride 0x78, size 0x437077f (1920x1080) [measured]. The failure
  is after that, in the eDP adoption: `adoptDPBootAUX` (`kern_alderlake_n.hpp:304`), `display13SSTPort` or
  `adoptBootPath`. All three return `NotReady` with no detail [inferred from the code].
- WEX's README lists internal eDP on Alder/Raptor Lake-P as **experimental, "local CPU and donor replay coverage
  only"**: this is the first hardware run of that path that we know of [measured: README; no GitHub issues exist].

Wi-Fi on the normal boot after the cycle [measured]: AirportMtkWlan 1.5.0 loaded, firmware MT7921 up, power On, but
`en2` `status: inactive`, no scan results, "Network Service Inactive", country code 0. No AirportMtkWlan lines in
the unified log; dmesg needs sudo. Not explained yet; the cycle's two warm reboots (one with `-nvoff`, where the
kext does not load) are the suspect [unverified].

## XE-3 (prepared 2026-10-29): XE-2 with WhateverXe built here, telling which handoff condition fails

One variable: WhateverXe 0.6.1 built from source (`68a2427`) with `source-fixes/wex/0001-adopt-dp-boot-aux-diag.patch`.
The patch only adds diagnostics: every condition of `adoptDPBootAUX` is still required, but each failed one sets a
bit, and the result is published in `N97FBBootHandoff` word 5 (result domain):

- `0x1xxxx`: `adoptDPBootAUX` failed, mask bits 0 target, 1 ddi≥2, 2 activePipes≠1, 3 dpSource, 4 dpSourceUnchanged,
  5 bootPort≠ddi, 6 bootAdopted, 7 !bootPGProtected, 8 !bootDDIProtected, 9 !outputHeld, 10 !bootPending, 11 owner
  set, 12 port≠ddi, 13 lease owner, 14 lease domains, 15 !held.
- `0x2000x`: not linked without the AUX path (bit 0 = DP link, bit 1 = TC port), e.g. `display13SSTPort` false.
- `0x4000x`: `publishObject` failed. `0x8xxxx`: `adoptBootPath` failed (low 16 bits = its domain).

Build: `python3 tools/build.py --release --sdk MacKernelSDK --lilu Lilu.kext` (MacKernelSDK `master`, Lilu 1.7.2
source as `Lilu.kext/Contents/Resources`); CPU tests 158/158 pass. WhateverXe `ab6f9989` staged at
`~/nmx-build/whateverxe/kexts/wex/` (release `e92b65b0` moved to `kexts/wex-0.6.1-release/`). Lukas runs
`efi.sh wex` again; `log.sh` prints the root properties as in XE-2.

### XE-3 result (2026-10-29 19:58): the eDP port fails WEX's SST port check before any AUX step

- The diag build loaded: `N97FBBootHandoff` word 5 = **0x20001** [measured]. Only our patch writes that value. It
  means the boot port (DDI A) is a DP link (bit 0), not a TC port, and was not linked. `adoptDPBootAUX` never ran,
  because `display13SSTPort(port)` (`kern_xe.cpp:7274`) returned null [inferred from the code path].
- Everything else is as in XE-2: `N97SharedRegisterCheck` same provider 0, +0xDF8 0x4195000,
  `N97FramebufferStartAccepted = No`, handoff check `check[35..37]` = 1, accelerator `stage=3 result=200`
  [measured]. `WEXDisplay13BootHandoff` status 2 = `LinearStatus::Success` (the early GOP handoff is fine) [measured].
- `display13SSTPort` has 15 conditions and publishes none of them, including `display13FBSSTHooksReady`, which needs
  exact bytes at fixed offsets in Apple's TGL framebuffer.
- Wi-Fi after this cycle: `en2` active with an IPv4 address at 6 min uptime [measured]. XE-2's inactive Wi-Fi did not
  repeat. Cause still unknown [unverified].

## XE-4 (prepared 2026-10-29): XE-3 plus the SST port conditions

One variable on top of XE-3: `source-fixes/wex/0002-sst-port-mask-diag.patch` adds `display13SSTPortMask`, which is
read-only. When the SST check refuses, word 5 becomes `0x100000|mask`, with these bits:

| Bit | Failed condition |
|---|---|
| 0 | not `display13FramebufferRequested` |
| 1 | not XeLPD |
| 2 | `!display13FBSSTHooksReady` |
| 3 | port object or class size < 0x624 |
| 4 | no controller |
| 5 | controller ≠ topology controller |
| 6 | `!adlnWriterMappingBound` |
| 7 | clock, memory or panel fault, or clock stopped |
| 8 | wiring not described |
| 9 | `Topology::selected` false, or no config |
| 10 | DDI not a link |
| 11 | `port+0x117` set |
| 12 | `port+0x120` ≠ DDI |
| 13 | `port+0x550` ≠ 1 (combo) or 4 (TC) |
| 14 | `port+0x578` ≠ access |

WhateverXe `fdc5b254`, staged in `kexts/wex/`; CPU tests 158/158 pass. Same procedure: `efi.sh wex`, then `log.sh`.

### XE-4 result (2026-10-29 ~20:05): only the port mode fails

- `N97FBBootHandoff` word 5 = **0x102000** [measured]: `0x100000` (SST check refused) with only bit 13 set. The port
  mode at `port+0x550` is not 1 (the value expected for combo DDI A). The other 14 conditions pass, including
  `display13FBSSTHooksReady`, so the Sequoia framebuffer binary matches WEX's exact-byte checks [measured].
- Checks and accelerator are unchanged from XE-3 (`N97FramebufferStartAccepted = No`) [measured].
- WEX's own comment on `display13AUXReady` (`kern_xe.cpp` ~6986): "Probe may run before setPortMode, hence mode0 is
  allowed". The handoff runs in the controller start, before Apple's `setPortMode`, so the eDP port is most likely
  still in mode 0 there [inferred; the value itself was not recorded].
- Lukas ran `efi.sh wex` again by mistake after this log. That re-arms one WEX boot with the XE-4 kext. XE-5's
  `efi.sh wex` overwrites it, so no harm [inferred from efi.sh].

## XE-5 (prepared 2026-10-29): accept mode 0 on combo ports in the boot handoff

One behaviour change: `source-fixes/wex/0003-boot-mode0-sst-port.patch`. `display13SSTPort` takes a `bootMode0` flag,
and only the boot handoff passes it. With the flag set, a combo port (DDI < 3) in mode 0 passes, the same rule as
`display13AUXReady`. Every other caller still requires mode 1/4. It also records the port mode in bits 16-19 of the
SST mask.

Reading word 5:
- `0x1m....` means SST was still refused, and `m` is the port mode.
- `0x1xxxx` means SST passed and `adoptDPBootAUX` refused; the bits are as in XE-3.
- `0x8xxxx` means `adoptBootPath` failed.
- If the handoff completes, `N97FramebufferStartAccepted = Yes`, and the next question is the accelerator and Metal.

Risk: the adopted boot link may misbehave (black panel) on that one boot. The boot-once returns to the normal config
by itself.

WhateverXe `d080f93b` (`nm` shows `display13SSTPortEPvb`), staged in `kexts/wex/`; CPU tests 158/158 pass (the SST
fixture declaration was updated for the new parameter).

### XE-5 result (2026-10-29 ~21:00): Metal works, the panel stays black

Lukas: the Mac did not come up unaccelerated this time; it hung on a black screen. The log shows the GPU side works:

- `N97FramebufferStartAccepted = Yes`: the boot handoff now completes [measured].
- The accelerator starts and Metal sees the Iris Xe; every gputest passes [measured]. **First Metal on the Iris Xe
  through Apple's own driver.**
- The panel is black because the modeset fails: `FB0: Complete modeset` at 18.278 s, then `Hardware mode set failed,
  err = 0xe00002d8` (`kIOReturnNotReady`) three times between 18.30 and 18.42 s [measured].

Cause, read from WEX's records [measured unless tagged]:

1. `N97FBClockStop` status 12 (Complete): Apple's clock disable stopped CDCLK (`clockStopped`).
2. `N97FBClockChange` status 0 (NotReady): the re-enable to 652.8 MHz (`nativeHz` 0x4dd1e000) failed.
3. `N97FBClockWMAll` (u64 words): current clock 0, active pipes 0, workloop matches, gate functions present, caller not
   in the gate, **`tryCloseGate` failed**, ready false. `...FirstFailure` holds the same values.
4. The dual-output path runs because the panel is on DDI A and HDMI on DDI B (`multiOutputWiring`,
   `wrapAlderLakeNClockSet`). It needs the gate; another thread owns it [who: unverified], so it returns NotReady
   and sets `clockFaulted`.
5. With `clockFaulted`, `display13SSTPort` returns null, so every SST modeset hook returns NotReady: a permanent
   black panel.

Also seen, not yet followed: `AGDP ... ASSERT(linkBW) would fail`, `kAGDCRegisterLinkValidateModeTiming: none by
policy`, `ADLSPanelPWMReady = No`, `EFI using a different backlight frequency`.

Correction (added, see XE-4/XE-5 notes above): `N97FBPortProbeFirst1` decodes as u64 words `[1, 1, 0, 0, 0, 0, 3, 2,
1, 2]`: the eDP port's mode after the probe is **1**, result 2, `+0x554` = 2. An earlier reading in this session (one
word off) said mode 2; that was wrong. DDI B (HDMI) probes with result 0 (not connected).

## XE-6 (prepared 2026-10-29): cold dual-output clock set falls back to the single path

One behaviour change: `source-fixes/wex/0004-cold-dual-clock-fallback.patch`. In `adlnSetDualClock`, when the gate
cannot be taken, no pipe is active and the caller is not in the gate (Apple's cold modeset), it records
`N97FBClockDualColdFallback` (the evidence words) and returns false; `wrapAlderLakeNClockSet` then runs the
single-output path, which re-enables CDCLK by itself. With no active pipe there is no peer output to freeze, so the
dual path's extra work is not needed [inferred].

Expected if it works: `N97FBClockDualColdFallback` present, `N97FBClockChange` status 12, no `Hardware mode set
failed`, panel lit. If the single path also fails, `N97FBClockChange` names the new status.

WhateverXe `94698a29` (`nm`: `adlnSetDualClockEP9IOServicey`, string `N97FBClockDualColdFallback`), staged in
`kexts/wex/`; CPU tests 158/158 pass. Same procedure: `efi.sh wex`, then `log.sh`.


### XE-6 result (2026-10-29 ~20:38): accelerated desktop on the Iris Xe

Read live from the session, 2 min after boot (Lukas logged in; `log.sh` not run yet):

- `N97FBClockDualColdFallback` present (words: requested 0x4dd1e000, current 0, active 0, gate busy) and
  `N97FBClockChange` status 12 (Complete): the single path re-enabled CDCLK [measured].
- The panel is lit: `system_profiler` shows the `0xa7a8` GPU with Metal support driving the internal 1920x1080
  display, main display [measured]. `IOAccelerator` is `IntelAccelerator` with 569 textures in use [measured].
- WindowServer ~23 % CPU, load average 13 at 2 min (boot-time indexing; Lukas says the machine is still hot)
  [measured / inferred cause].
- Open: refresh is 60 Hz (the panel does 144 Hz), the RTX is off (`-nvoff` on the WEX boot), brightness/PWM not yet
  checked, and this was a boot-once: the next reboot returns to the normal config.

XE-6 log (`~/hybrid.txt`, 20:36 boot) [measured]: no `Hardware mode set failed` in this boot (the 20:18 lines in the
same file are XE-5's); `xe-catest` 16/16 layers draw (text, icons, opacity, rotation included, the losses NootedGreen
had in HYB-12 are gone); `xe-geomtest` all modes cover, MSAA 4x included (black under NootedGreen in HYB-14);
`ADLSPanelPWMReady = No` and `EFI using a different backlight frequency` remain (brightness untested). Lukas: the
boot is much faster than the RTX route (no 45 s NMIntelFB delay, no NVRM start) [inferred cause].

## XE-7 (prepared 2026-10-29): the hybrid, Iris Xe desktop + RTX headless

Goal (Lukas): desktop on the Iris Xe, the RTX on demand, less power. One change from XE-6: nullmoth's NVIDIA driver
stays on. `efi.sh wexrtx` builds `config-wex.plist` with `wex-config.py --rtx`: `-nmintelfboff` replaces `-nvoff`
(NMIntelFB would take the panel from Apple's framebuffer) and `nvaccel=1` is kept. NMXGPU stays off (no
`nmxintel=1`). Expected [inferred from nullmoth's source, hybrid-route.md]: NVAccel finds no NVIDIA head, after 60 s
sets `NVAccelHeadless`; `nvmtl-allow.txt` (`*`, `!WindowServer`) keeps WindowServer on the Iris Xe and lets other
apps pick the RTX.

Questions for the log: does the panel still light (two IOAccelerators, two framebuffer drivers)? `NVAccelHeadless`
and `debug.nvaccel_headless=1`? Does `system_profiler` list the RTX with Metal? WindowServer's GPU?

Power [measured, grep of nullmoth's kexts]: nullmoth has no runtime power-off (no RTD3/D3cold/GC6 code), so in the
hybrid the RTX stays powered at idle. Real battery saving needs either the RTX off for the whole boot (XE-6 style
plus an ACPI `_OFF`) or runtime power management written for it. Not measured yet.

Risk: the boot is slower (NVRM starts) and the RTX's framebuffer heads (`nvfb=1`) may add ghost displays. Boot-once
as before. `wex-config.py` checked on `~/config-antes-hybrid.plist`: both modes give the expected boot-args.

### XE-7 result (2026-10-29 ~20:52): the hybrid works

Read live 2 min after boot [measured]:

- Boot-args as planned (`nvaccel=1`, `-nmintelfboff`, no `-nvoff`). Loaded together: WhateverXe, Apple's TGL
  framebuffer and accelerator, NVRM/NVRMFB/NVRMAGDC 2.6.4, NVAccel. NMIntelFB loaded but stood down.
- The panel is lit on the Iris Xe (1920x1080 @ 60 Hz, main display); `N97FBClockDualColdFallback` fired again.
  `system_profiler` lists both GPUs: Iris Xe (Metal 2, internal display) and RTX 3050 (Metal 3, no display).
- `debug.nvaccel_headless = 1`, `NVAccelHeadless = Yes`; two `IOAccelerator`s (`IntelAccelerator`, `NVAccel`).
- A Metal compute test (1 M floats, every device): `MTLCreateSystemDefaultDevice` is the Iris Xe (`isLowPower`
  true); both the Iris Xe (2.50 ms) and the RTX (`NVMTL over ... NVK GA107-A`, 1.81 ms, `isLowPower` false) return
  correct results. So apps that ask for the high-power GPU get the RTX, the rest get the Iris Xe, as on Apple's
  two-GPU Macs [inferred for real apps; measured for the test].
- WindowServer ~15 % CPU. Load average 38 at 2 min (`trustd` ~85 %, boot work).
- Power: NVRM logs `b81 PERF_BOOST flags 0x12 INFINITE`, the RTX held at boost clocks for the whole boot, even when
  headless. On the hybrid this probably wastes power [inferred]; not measured.

XE-7 follow-up, same boot [measured]:

- Brightness unavailable (Lukas). The panel is an `AppleDisplay`, not an `AppleBacklightDisplay`, and the ACPI tree
  has no `PNLF` device. WhateverXe's README: "Add `SSDT-PNLF` to OpenCore to enable internal-display brightness
  control"; its backlight profile needs `_UID` 19 (`kern_backlight_profile.hpp`). `ADLSPanelPWMReady = No` is
  expected on this route: WEX moves the result into `display13PanelPWMReady` when display 13 is requested
  (`kern_xe.cpp` ~12861).
- Why the RTX runs hot: with nullmoth's allow-list (`*`), 16 processes loaded NVK (`lsof`: Finder, Spotlight,
  loginwindow, Claude, ghostty...). NVK's device open sends `NV2080_CTRL_CMD_PERF_BOOST` `BOOST_TO_MAX` with
  `DURATION_INFINITE` and clears it only when the device closes (`nvk-macos.patch` ~10708 and ~10820, knob `BOOST` in
  `/Library/GPUBundles/nvmtl/nvrm610.conf`). So the RTX sits at max clocks as long as any of those apps lives.
- `auto.sh` (NMIntelFB enable daemon) finds no NMIntelFB instance on this route and exits after its 5-minute wait;
  harmless.

## XE-8 (prepared 2026-10-29): the hybrid for keeps, brightness, RTX on demand

Lukas: keep the hybrid, optimise it; 60 Hz is fine (no gaming here). Three changes, each with its own evidence:

1. `efi.sh wexrtx-keep`: the XE-7 config without the one-boot daemon. Not a behaviour change.
2. `SSDT-PNLF.aml` (new `tools/hybrid/pnlf-aml.py`, the acidanthera table at `\_SB.PC00.GFX0`, `_UID` 19, OEM ID
   `NMX`), added by `wex-config.py` and written to `OC/ACPI` by `efi.sh` on both WEX modes; `gpu-only` removes it.
   Expected: an `AppleBacklightDisplay` and a brightness slider.
3. `tools/hybrid/ondemand.sh on`: `nvmtl-allow.txt` lists no app (nullmoth's list saved as `.nullmoth`), so no
   process opens the RTX and nothing boosts it; `ondemand.sh add NAME` gives it to one app. Expected: `ondemand.sh
   status` shows no process holding NVK; the machine runs cooler. This is a userspace file, undone with
   `ondemand.sh off`.

Not done: no runtime power-off of the RTX (nullmoth has none). 144 Hz only in fullscreen: macOS switches refresh rate
by itself only on ProMotion panels; left for later.

Recovery: there is no boot-once on `-keep`. If the panel stays black: OpenCore Space → "Start once without NVIDIA
driver" (`-nvoff`, the XE-6 setup, which worked), then `sudo bash tools/hybrid/efi.sh gpu-only`.

### XE-8 result (2026-10-29): works

- [measured] Boot-args as prepared (`... msgbuf=400000 -nmintelfboff`, no `-nvoff`); no boot-once daemon.
- [measured] Brightness works (Lukas); `AppleBacklightDisplay` registered, DisplayProductID 1858.
- [measured] `ondemand.sh status`: the allow list holds only the header and no process holds `libvulkan_nouveau`.
- [measured] Kernel log since boot: no panic, assert or GPU fault. NVRM-fb refuses to start (no display on the
  RTX, expected); NVAccel `createUserGPUTask` ×10 (Metal device enumeration, not NVK, so no boost).
- [measured] Idle on AC: 89 % CPU idle; WindowServer ~25 % while the Claude app streams. No new panic reports
  (the `xe-carender` reports and the 21:00 shutdown stall are from earlier boots and the reboot).
- [unverified] Heat: Lukas has not reported yet.

Next (XE-9): measure battery draw. `tools/hybrid/power.sh` (new) averages `InstantAmperage × Voltage` over 120 s on
battery and appends to `~/power.txt`. XE-9a: the hybrid, idle. XE-9b: one boot with OpenCore "Start once without
NVIDIA driver" (`-nvoff`, RTX without driver), same idle. The difference is what the idle RTX costs and decides
whether an RTX power-off (ACPI `_OFF` SSDT, Intel-only mode) is worth building. Sleep stays off (pitfall: S3 never
relit the panel on the old route; untested with WhateverXe).

## XE-10 (prepared 2026-10-30): no boost for apps on the RTX

Lukas (2026-10-30): the machine runs much cooler since XE-8. One boot after it panicked in the Wi-Fi driver
(WIFI-9, not the hybrid) and the next came up normally on the hybrid.

[measured, 6 min after boot] `ondemand.sh status`: Safari is on the RTX list and holds `libvulkan_nouveau` (pid 612).
NVK's device open sends `PERF_BOOST BOOST_TO_MAX` with an infinite duration unless `BOOST=0` is in
`/Library/GPUBundles/nvmtl/nvrm610.conf` (`nvrm610_on("BOOST")` in `nvk-macos.patch` ~8089 and ~10707; the default is
on). So while Safari is open the RTX sits at max clocks, the XE-7 heat source in a smaller form. WhatsApp at ~96 %
CPU and WindowServer at ~24 % were the other big users at that moment.

Change (one variable): `sudo bash tools/hybrid/ondemand.sh noboost` appends `BOOST=0`; `boost` removes it. Userspace,
no reboot; apps pick it up when reopened. Expected: Safari still renders on the RTX, the RTX's own clock policy
picks the clocks, less heat. Risk [unverified]: nullmoth may have turned the boost on because the clocks ramp slowly
without it (stutter in WebGL or video); then `boost` undoes it.

Not done: nullmoth 2.6.5 (user-space only, research.md) is left for its own step so this test changes one thing.
XE-9 (battery draw) is still open.


Results XE-10 / WIFI-9 [measured 2026-11-12, no notes from Lukas in between]: `BOOST=0` is in `nvrm610.conf`, the
RTX list is `Roblox`, `RobloxPlayer` (Safari was removed), `AirportMtkWlan dd967442` (WIFI-9) is installed. No
`freeing an already freed mbuf` panic since 10-30. One other panic, below.

## Panic 2026-11-12 19:39 (before UPG-6)

`Kernel-2026-11-12-193913.panic` [measured], uptime 78 min, Sequoia 24H32, the XE-8 hybrid:

```
NMIPI for spinlock acquisition timeout, spinlock owner == current_thread (CPU 0), pid 486: WindowServer
  CPU 0: _workq_thread_set_max_qos + 0x117a  <- _hndl_allintrs  <- _interrupt
  CPU 1: Ticket spinlock timeout @lock_ticket.c:386 <- _lck_ticket_lock <- _workq_thread_set_max_qos <- _kevt_getstat
         <- _kqueue_scan <- _kevent_id (WindowServer)
```

No third-party kext in either backtrace. The WindowServer thread on CPU 0 held the workqueue ticket lock and was
interrupted; the interrupt did not return for ~1.3 s, so a second WindowServer thread spun out on CPU 1. Cause: a
slow interrupt on CPU 0 [inferred]; which driver's interrupt is unknown [unverified] (candidates: NVRM, Apple's TGL
stack under WhateverXe, AirportMtkWlan). The previous boot's unified log was not kept. Watch for a repeat on UPG-6.

## UPG-6 (prepared 2026-11-12): nullmoth 2.6.4 → 2.9 on the hybrid

Lukas (2026-11-12) asked to move both GPUs to the newest drivers and then to Tahoe; step 1 of 3 (research.md,
2026-11-12 check). One variable: nullmoth's release package, unmodified.

Why the release as is [inferred from patches.md]: our NVRM byte patch (copy-engine wait sleeps, RTX-25) and the
NVAccel series (accel-0001..0004) only act on the RTX → NMIntelFB bridge, which is off on the hybrid
(`-nmintelfboff`). 2.9 moved NVIDIA's modules 615 → 620.70.06, so porting them is real work for a route that is
parked; it is left until the RTX-only route is needed again. NMIntelFB `241aff3d` stays: it links no NVRM symbol
(only Apple KPIs) and the 2.9 `nvrm_vram_abi.h` only adds a reply flag (`NVRM_VRAM_SCANOUT_30BIT`).

Package [measured]: `nullmoth-nvidia-2.9.tar.gz` `b624bf07` = the GitHub digest and `SHA256SUMS.txt`; inner
`SHA256SUMS` passes. NVRM `c1d62ff7`, NVAccel `b298771e`, NVRMFB `4890671d`, NVRMAGDC `97623c55` (all 2.9); NMXAudio
`17c4804d` is installed only on macOS 26. `install.sh` (726 lines) read: kexts NVRM/NVAccel/NVRMFB/NVRMAGDC, aux KC
rebuilt (a test KC first), GSP firmware fetched from `download.nvidia.com` with a pinned SHA-256, no EFI or boot-args
changes (it only prints notes), a backup in `/Library/NullMoth/backup-…`, a one-shot fallback job (lastgood) and a
boot-guard job that counts a start as good once the same WindowServer stays up 45 s, so a headless RTX passes.

It replaces `nvmtl-allow.txt` (back to `*`, `!WindowServer`) and `nvrm610.conf` (our `BOOST=0` is outside nullmoth's
"my settings" block, so it goes). 2.9 boosts per burst of work by default (`nvk-perf-boost-burst.patch`:
"unset or 1 = per burst, hold = for the device's life, 0 = never"), which replaces XE-10's `noboost`: do not set
`BOOST=0` again. `ondemand.sh on` + `add Roblox` + `add RobloxPlayer` restore the RTX list.

Expected: the hybrid boots as on XE-8 (panel on the Iris Xe, `debug.nvaccel_headless = 1`), the 40 s headless wait
is gone (#516), `bootguard.log` says the start counts as good, Roblox on the RTX without a permanent boost. Not in
this test: `nvrtd3=1` (RTX deep sleep; NVRM 2.9 logs "needs nvrtd3res=<ACPI path> to act") is UPG-7.

Undo: `sudo bash tools/upgrade/rollback.sh /Library/NullMoth/backup-…` (path from the install log), reboot; or
`tools/checkpoint.sh restore ~/nmx-checkpoints/<date>-antes-2.9`.

## UPG-6 result (2026-11-12): black screen after the login-window WindowServer restart

Lukas: one boot "did not start", one reached the desktop and went black after a few seconds; "Start once without
NVIDIA driver" (`-nvoff`) gave a desktop on the Iris Xe only. Boots in `log show` [measured]: 19:54:50, 19:57:44,
20:00:47 (all 2.9), 20:01:57 (`-nvoff`). No panic report; lastgood kept 2.9 (`driver-restored` absent).

What the RTX side did is the same as on 2.6.4 [measured]: NVRM 2.9 starts, NVKMS 620.70.06 loads, NVRMFB finds no
display on the RTX and stays off, NVAccel's headless check restores `MetalPluginName` without arming,
`NMIntelFB: off by boot-arg`. The first WindowServer (pid 161) does a "FB0: Complete modeset" on the Iris Xe.

The break is the WindowServer restart done by 1401's `com.nullmoth.wsreset` job (`/Library/NullMoth/nullmoth-wsreset.sh`,
dated 10-16, not part of the 2.9 package) at the login window, ~13 s after WindowServer starts:

- 2.9 boots: the restart takes at once (`wsreset.log`: AFTER pid 473 / 467 / 459). The new WindowServer asks for
  "Setting mode 0x0 ... Failed to obtain mode info", then the Intel framebuffer logs
  `FB0: This fb does not have FB memory`, `FB has no memory allocated, err = 0xe00002bc`,
  `Hardware mode set failed, err = 0xe00002d8`, and `FB0 is not enabled` every 2 s until power-off (71-487 per boot).
  That is the black screen (19:55:21, 19:58:14, 20:01:17).
- 2.6.4 boots (11-05, 11-12 19:39): the same job logged "restarted", but the AFTER capture still shows pid 161
  (TERM is ignored, pitfall RTX-9); the WindowServer was replaced only at 19:39:51, ~37 s after boot, and that one
  set "mode 0x80001000 ... 1920x1080" fine.
- `-nvoff` boot: no restart (job skipped: user already logged in), no `FB0 is not enabled`.

Cause [inferred]: Apple's TGL framebuffer under WhateverXe cannot rebuild FB0 when WindowServer is replaced within
seconds of its first modeset (no mode, no FB memory). With 2.9 the replacement lands right away; with 2.6.4 it landed
late or not at all. Why 2.9 lets the kill land sooner is [unverified]. Not the cause: NVRMFB/NVAccel/AGDC (same log
lines as 2.6.4), the boost, the app list.

Next (UPG-6b, one variable): turn the restart off with the job's own switch, `touch /Library/NullMoth/no-wsreset`
(the script exits on it; delete the file to undo). The job only fights a flicker on NVIDIA-driven panels, which the
hybrid does not have.

## UPG-6b result (2026-11-12): pass

[measured] Boot 20:12:36 with `/Library/NullMoth/no-wsreset` present. bootguard 20:13:35: "the desktop came up and
stayed up (WindowServer 161 for 45 s); this start counts as good". WindowServer still pid 161 afterwards,
`nullmoth-nv-ok=1`, no panic. Lukas: Roblox runs well on the RTX. A `shutdown_stall_2026-11-12-201229` report comes
from the restart before this boot (not analysed). Daily setup is now nullmoth 2.9 + `no-wsreset`.

Next: XE-11. The WhateverXe README (0.8.2, checked 2026-11-12) lists Sequoia 15.8.x and Tahoe 26.7+ as supported,
so 0.8.2 can be tested on Sequoia before Tahoe.

## XE-11 (prepared 2026-11-12): WhateverXe 0.8.2 + Graphics 0.4.3 on Sequoia

One variable: the iGPU driver pair 0.6.1/0.3.2 becomes 0.8.2/0.4.3. nullmoth 2.9 + `no-wsreset` (UPG-6b) stay.

- Upstream [measured, README and pkg 2026-11-12]: Sequoia 15.8.x and Tahoe 26.7+ are supported. The pkg's
  Distribution picks `Sequoia.pkg` for 15.8 ≤ version < 15.9. Same OpenCore needs as 0.6.1: Lilu, AMFIPass 1.4.1
  Mod, `-allow3d -disablegfxfirmware`, csr 0x803. RPL-P eDP is still not on the upstream tested list.
- Pkg 0.4.3 SHA-256 `bd17c737` (matches SHA256SUMS; unsigned, like 0.3.2). New personalities `N97Standalone` and
  `N97Display13` match only ADL-N IDs (`46d0..46d4`), so our `nmx-wex` gate on `Gen7` and
  `AppleIntelFramebufferController` still covers `a7a8`. TGLCompat 0.8.1 comes in the pkg. 0.4.3 no longer ships
  `XeMetalCompiler`, so `wex-install.sh` now removes the old pkg's files before it installs (`WEXG=0.3.2` = rollback).
- WhateverXe: our build `96545d6d` (patches.md, wex 0.8.2/0001..0005), staged in `kexts/wex/`; the XE-8 build
  `94698a29` moved to `kexts/wex-0.6.1-nmx/`. `efi.sh` takes `WEXDIR=` to pick one.
- Steps: checkpoint → `wex-install.sh` → `efi.sh wexrtx` (one boot) → reboot → `log.sh`; if good, `wexrtx-keep`.
  Rollback: `WEXG=0.3.2 wex-install.sh` and `WEXDIR=wex-0.6.1-nmx efi.sh wexrtx-keep`.

## XE-11 result (2026-11-12): pass, kept

[measured] Boot 20:25:50 on the wexrtx config; Lukas: all good, then `efi.sh wexrtx-keep`. Loaded: WhateverXe 0.8.2,
AppleIntelTGLCompat 0.8.1, the TGL framebuffer and accelerator 16.0.0, AMFIPass 1.4.1, nullmoth NVRM/NVRMFB/NVAccel/
NVRMAGDC 2.9. `no-wsreset` still present, `nullmoth-nv-ok=1`. WindowServer pid 161 up since 20:26:00, no restart.
Panel 1920x1080 on "Intel UHD Graphics" (Metal), RTX listed with Metal. Kernel log of this boot: no
`FB0 is not enabled`, no panic or underrun, 3 `[ERROR]` lines only (`Flip called without enabling VBL`,
`EFI using a different backlight frequency`, a launchd "Bad CPU type"); the first two also appear in earlier boots in
`~/hybrid.txt`. Registry: `N97FramebufferBackendReady`, `N97FBCommonABIReady` and the other N97 readiness flags = Yes.
The `FB has no memory` lines in `hybrid.txt` at 20:12:23 and 20:25:30 belong to the shutdowns of the previous boots.

Bug found (ours): `/var/log/nmx-hybrid.log` ends with `no /var/root/nmx-build/whateverxe/kexts/wex/WhateverXe.kext`.
The XE-11 `efi.sh` checked `$WEXDIR` for every command, and the boot-once job runs as root with HOMEU=/var/root, so it
exited before putting GPU-only back. No harm this time (the boot was good and was kept), but the one-boot safety net
was off for XE-11. Fixed: the check is gone (the route modes already check each kext). Pitfall added.

## XE-12 (prepared 2026-11-13): native refresh-rate menu for the internal panel

Lukas wants to switch 60/144 Hz from System Settings > Displays itself, nothing third-party. One variable: a display
override for our panel with `display-refresh-rate-policy` = 1. Takes effect at the next boot only.

- [measured] The 144 Hz modes are already there: CoreGraphics lists 60.0 and 144.0 Hz for every size on the main
  display (built-in = true); the current mode is 1920x1080 @ 60. EDID: LG Display `30e4:0742` (LP156WFJ-SPB4), range
  60-144 Hz. So 60 Hz is WindowServer's default pick, not a missing mode.
- [measured] Apple ships `display-refresh-rate-policy` = `0x0000000000000001` (8-byte data) in 21 overrides under
  `/System/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-610`: the "Color LCD" built-ins, among them
  `a044` (16" MacBook Pro 2019, which has a refresh menu without ProMotion), and the Pro Display XDR. There is no Apple
  override for vendor `30e4`.
- [inferred] That key is what makes System Settings show "Refresh Rate" for a built-in panel. Web search (2026-11-13)
  found nobody documenting it or doing this on a Hackintosh; the menu itself on Intel MacBook Pros is in Apple's
  support note HT210742 (there via Option-click on Scaled).
- `tools/hybrid/refresh.sh` (`e19df98f`): `probe` (144 Hz for 10 s through `kCGConfigureForAppOnly`, undone when it
  exits), `install` (writes `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-30e4/DisplayProductID-742`;
  the data matches Apple's byte for byte), `remove` (deletes it and moves `com.apple.windowserver.displays.plist` aside
  so the panel boots at 60), `status`. Reboot rather than restart WindowServer (pitfall, UPG-6).
- Expected: a "Refresh Rate" menu with 60 and 144 Hz; picking 144 gives `@ 144.00Hz` in `system_profiler`. Risk: 144 Hz
  has never run on the TGL framebuffer here (`ASSERT(linkBW)` seen in XE-7), so the probe goes first.
- Recovery if 144 leaves the panel black: from Recovery's Terminal, delete
  `/Volumes/<disk>/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-30e4` and
  `/Volumes/<disk>/Library/Preferences/com.apple.windowserver.displays.plist`.

### XE-12 run 1 (2026-11-13, before the reboot)

[measured] `status`: 1920x1080 @ 60, rates [60, 144], no override. `probe`: `switch to 144.0 Hz: ok`, `now: 144.0 Hz`;
Lukas: the panel ran perfectly at 144 Hz on the Iris Xe and came back to 60 by itself. First time 144 Hz runs on the
TGL framebuffer here; the `ASSERT(linkBW)` worry did not show. `install` wrote the override (`plutil -lint` OK).
Pending: the reboot and the System Settings menu.

## Slowness check (2026-11-13 21:36, after the XE-12 reboot)

Lukas: the system still feels slow and odd, both to use and to look at. Live check, no change made:

- [measured] Touchpad PIXA3848 (VoodooI2C 2.9.1) runs with `"Interrupt Mode" = "Polling"`; boot-args still carry
  `-vi2c-force-polling` ("polling first, GPIO interrupts tested later" in `make_config.py`, never tested). GPIO
  controller is `GPI0` = `INTC1055`; no VoodooGPIO instance in the registry [measured], so it does not match
  [inferred]. Most likely cause of the laggy feel of cursor and scrolling [inferred].
- [measured] Desktop still `1920x1080 @ 60.02 Hz` with the XE-12 override in place (rates 60 and 144 available).
  Whether the "Refresh Rate" menu appeared after the reboot: ask Lukas.
- [measured] `bluetoothd` restarts about every 30 s (WindowServer logs a bluetoothd disconnect every ~31 s; the
  process was 23 s old when checked). Controller: `BCM_4350C2`, Address NULL, State Off: no working Bluetooth.
- [measured] System Settings (20:36) and every `system_profiler` run crash with `KERN_MEMORY_ERROR` inside
  `AppleSystemInfo`, the framework RestrictEvents patches for `revpatch=cpuname` [inferred link, unverified].
- [measured] Iris Xe Metal (`AppleIntelTGLGraphicsMTLDriver`), `recoveryCount` = 0, no GPU hangs. GPU clock not
  measured (needs `sudo powermetrics`); `-disablegfxfirmware` is required by WhateverXe.

Lukas (21:50): the Refresh Rate menu appears, but System Settings crashes so often it is hard to use; and the
slowness feels odd even for 60 Hz.

## XE-13 (prepared 2026-11-13): no cpuname patch, touchpad on interrupts, 144 Hz without Settings

Two independent boot-args changes in `wex-config.py` (`bafe4cd0`), each with its own check, plus a no-reboot tool:

- `revpatch=sbvmm,cpuname` → `revpatch=sbvmm`. Check: System Settings opens Displays and About without crashing;
  no new `KERN_MEMORY_ERROR` report. Cost: About This Mac may show a generic CPU name.
- `-vi2c-force-polling` dropped. Check: `ioreg -r -c VoodooI2CDeviceNub -l` → `"Interrupt Mode"` (Polling or
  GPIO/APIC) and how the cursor feels. If GPI0 `INTC1055` has no VoodooGPIO match, VoodooI2C falls back to
  polling [unverified]; worst case the touchpad is dead (USB mouse, or add the arg back with `efi.sh`).
- `refresh.sh set 144` (`483d1979`): switches with `kCGConfigureForPermanently`, the same save the Settings menu does.
  Mode match now rounds (rates read 60.018 / 144.002). Tested: `set 60` ok, `set 99` usage.
- Baseline before the reboot: `sudo powermetrics --samplers gpu_power,cpu_power` while scrolling, to see the Iris Xe
  clock (is it stuck low?).

### GPU submission latency (2026-11-13 ~22:00, before XE-13 is installed)

Lukas: XE-13's 144 Hz feels lighter but not right; there is a visible delay even when typing. Typing is PS/2
(VoodooPS2), not the touchpad, so the cause is shared by every app [inferred]. Measured with no reboot:

- [measured] CPU timer wakeups fine (1 ms nanosleep overshoot p50 ~180 us, p99 ~390 us); CPU not throttled
  (`CPU_Speed_Limit` 100, 2e9-add loop 2.5-3.1 s).
- [measured] `tools/hybrid/xe-lattest.m` (`d229ed59`), 300 tiny compute jobs on the Iris Xe, busy desktop (Claude app open):
  `kernel->gpu` start p50 2.0-4.1 ms, p90 11.6-14.8 ms, p99 22-25 ms, max 33 ms; GPU execution 0.005 ms. The wait
  is the same with 0, 8 or 16 ms idle gaps, so it is not a GPU wake-up cost [inferred].
- [measured] GPU interrupts are delivered (`TGLIRQLive` host counters +1400/+1900 per s, ~490 submits/s). Long FMA
  run: ~711 GFLOPS, about 0.9 GHz on 48 EUs [inferred], so the clock is not stuck at its minimum.
- [inferred] Each app frame and each WindowServer composite queue behind other GPU work (or the host scheduler,
  GuC off with `-disablegfxfirmware`) for up to 1-2 frames: the input-to-screen delay and hitching Lukas feels.
  On a real Mac this wait is far below 1 ms [unverified here].
- Next measurement: the same test with only Terminal open, to separate "queued behind other apps" from "the
  driver's own scheduling".

### Clean run (2026-11-13 ~22:20, only Terminal open)

- [measured] Same `xe-lattest`, all other apps closed: `kernel->gpu` p50 0.01-0.06 ms, p99 0.12-0.24 ms, max
  0.5-1.0 ms; wall p50 0.09-0.32 ms, max 2.1 ms. Busy rerun right after (Claude app open): p50 1.47, p90 12.67 ms.
- [measured] `top` during the busy run: Claude Helper (Renderer) 73% CPU, Claude Helper (GPU) 68%, Claude 16%,
  WindowServer 20%.
- Lukas: "a sensacao é bem melhor com ele limpo" (feels much better clean).
- [inferred] The WhateverXe driver's own submit path is fine (sub-ms). The delay is queueing behind other GPU clients,
  chiefly the Claude desktop app (Electron, renders constantly). With the host scheduler (GuC off) one busy client
  delays every other app's frames and WindowServer's composite by up to 1-2 frames.
- Next: move the heavy Electron app to the RTX (`ondemand.sh add`), one app at a time, and rerun `xe-lattest`
  with it open.

### Claude app on the RTX, try 1 (2026-11-13 ~22:40)

- Listed `Claude` and `Claude Helper (GPU)` with `ondemand.sh add`. [measured] `ondemand.sh status`: only `Claude`
  (main process) holds the RTX. `xe-lattest` unchanged: `kernel->gpu` p50 0.9-6.6 ms, p90 10.6-13.6 ms, p99 15-18 ms.
- [measured] `ps`: Claude's GPU process is the plain `Claude Helper` (`--type=gpu-process`, 100% CPU); the
  `Claude Helper (GPU)` bundle is not used. Renderer at 112% CPU. Unlike Chrome (`... Helper (Aperitif)`), the name
  to list is `Claude Helper` (this also gives the RTX to Claude's utility processes; harmless, they do not use Metal
  [inferred]).
- Next: remove `Claude Helper (GPU)`, add `Claude Helper`, restart Claude, rerun.

### Claude app on the RTX, try 2 (2026-11-13 ~22:50)

- With `Claude Helper` listed: [measured] the GPU process (`--type=gpu-process`) now holds the RTX, yet `xe-lattest`
  is no better: `kernel->gpu` p50 3.5-5.7 ms, p90 10.5-15.8 ms, max 17-22 ms. The GPU process still holds 4 Intel
  user clients (Chromium opens every Metal device) [measured, ioreg `IOUserClientCreator`].
- [measured] Same desktop plus 12 `yes` CPU burners: `kernel->gpu` p50 0.09-4.1 ms, p99 7.4-8.4 ms, max 9 ms, i.e.
  better, not worse. So the wait is not CPU starvation of the submit path [inferred].
- [measured] Intel `PerformanceStatistics` utilization reads 0% (probably not filled by WhateverXe [unverified]).
- [inferred] New hypothesis: the max wait sits at about one 60 Hz frame (15-22 ms). With the host scheduler the ring
  is in order, so a WindowServer submit that waits for vblank/flip can hold every later job until the next frame.
  A constantly repainting window (Claude) keeps WindowServer compositing every frame; under the CPU burners the app
  draws less, so the wait drops. Test: same run at 144 Hz (`refresh.sh set 144`); if the max falls to ~7-8 ms
  (one 144 Hz frame) the hypothesis holds.
- Claude taken off the RTX list again (no gain). Also seen: a second Claude copy (`~/Applications/Claude 2.app`)
  running at ~116% CPU.

### 144 Hz run (2026-11-13 ~23:00)

- `refresh.sh set 144` → "switch to 144.0 Hz: ok"; Claude back on the Iris Xe, window visible. [measured]
  `kernel->gpu` p50 1.6-5.3 ms, p90 8.5-15 ms, max 17.8-19.6 ms: the same as at 60 Hz.
- The vblank/flip-wait hypothesis is **rejected** [inferred from measured]: the max wait does not follow the frame
  time. Still open: what fills 15-20 ms of the Iris Xe ring while a busy app is on screen (long composite batches
  at a low GPU clock, or the host scheduler's ordering) [unverified]. WhateverXe publishes no clock or busy-time
  telemetry (only `TGLHost*Count` counters), so the next probe needs a GPU clock read-out.
- Lukas: with Claude on the RTX the feel was better, although `xe-lattest` did not change (try 2). Claude goes back
  on the RTX list for daily use; 144 Hz stays set.

### Research and LAT-2 (2026-11-13 ~23:50)

- Research report: [../research/xe-latency.md](../research/xe-latency.md) (notes in `research/xe-latency-notes/`).
  Leading model [inferred]: Apple's host-preemptive scheduler (`GraphicsSchedulerSelect=5`) preempts only between
  priority bands, so equal-band work waits FIFO behind a busy client; WhateverXe also disables 3D object-level
  preemption. Clock (request pinned at 1400 MHz by WhateverXe host RPS, actual 1100 MHz), RC6, CPU and vblank ruled out
  or close to it.
- Correction to the 144 Hz entry: WhateverXe does publish clock data (`N97GTPowerSample`, 512 reads per boot).
- [measured] `sysctl debug.intel`: `schedPriCredits*` -1, `schedPriPreemption` 1, `schedPriElevatePID` -1.
- LAT-2 prepared: `tools/hybrid/lat-elevate.sh` (`850482c4`) runs `xe-lattest` normal, then with its PID in
  `debug.intel.schedPriElevatePID`, and puts -1 back on exit. If the elevated run's p90 falls to ~1 ms, the band model
  holds and the fix is priority (e.g. elevate WindowServer or lower background clients).

### LAT-2 result (2026-11-14 ~00:10)

- First run invalid: the pid file sat in root's `mktemp` dir, the probe could not write it, the sysctl got -1
  (fixed `89f0249`).
- [measured] Second run, Claude visible: normal `kernel->gpu` p90 13.6 / 14.1 / 6.4 ms (gaps 0/8/16), elevated
  (`schedPriElevatePID: -1 -> 4185`, read back) p90 13.6 / 13.6 / 6.5 ms. No change.
- [inferred] Either Apple's band priority is not the lever, or `schedPriElevatePID` is ignored on this path. Not
  conclusive for the band model as a whole. `-wex-adln-qtrace` (LAT-3) only installs when Alder Lake-N is detected
  (`adlnDetected`, kern_xe.cpp:11791), so it will not run on RPL-P without a fork change.
- Next: LAT-4, Apple's `-disablegfxpreemption`, added through the new `WEX_EXTRA` hook of `wex-config.py`
  (`d5fe0750`): `sudo WEX_EXTRA="-disablegfxpreemption" bash tools/hybrid/efi.sh wexrtx-keep`. XE-13 goes first on its
  own reboot, to get a new baseline.

### XE-13 result, part 1 (2026-11-14 ~00:00)

- [measured] boot-args active: no `cpuname`, no `-vi2c-force-polling`. `system_profiler SPHardwareDataType` returns
  rc=0 ("Processor Name: Unknown"): the AppleSystemInfo crash is gone.
- [measured] Touchpad dead. Kernel log: `Couldn't alloc class "VoodooGPIOTigerLakeLP"`; the PIXA3848
  `VoodooI2CDeviceNub` stays `!registered, !matched` and no VoodooI2CHID instance attaches. Without the GPIO
  controller and without force-polling, VoodooI2C does not fall back to polling (the `[unverified]` note above was
  wrong). Fix: `wex-config.py` (`fa63d59e`) keeps `-vi2c-force-polling`.

### XE-13 result, part 2 (2026-11-14, after the polling fix)

- [measured] boot-args carry `-vi2c-force-polling` again; PIXA3848 `"Interrupt Mode" = "Polling"`; Lukas: touchpad works.
- [measured] Lukas: System Settings opens About and Displays without crashing; no new `system_profiler` report.
  The `revpatch=cpuname` removal fixed the AppleSystemInfo crash [inferred link, now consistent with the evidence].
- [measured] `refresh.sh set 144`: ok.
- [measured] `xe-lattest` with Claude on screen, 144 Hz (`~/lat-xe13.txt`): kernel->gpu p90 7.8 / 13.9 / 6.2 ms and
  max 17.8 / 14.9 / 14.2 ms for gaps 0 / 8 / 16 ms. Same band as before XE-13, as expected (XE-13 did not touch
  the GPU). Next: LAT-4 `-disablegfxpreemption`.

### LAT-4: `-disablegfxpreemption` (2026-11-14 ~00:12)

Boot-args = XE-13 + `-disablegfxpreemption` (one-off through `WEX_EXTRA`). `debug.intel.schedPriPreemption` still
reads 1 and the registry shows no preemption key, so whether Apple's driver honoured the arg is [unverified] from
state; the latency says it did something. Three runs, Claude on screen, 144 Hz, uptime 2-3 min (load 21 -> 12):

| run | gap 0 p90 / max | gap 8 p50 / p90 / max | gap 16 p90 / max |
|-----|-----------------|-----------------------|------------------|
| XE-13 baseline (`lat-xe13.txt`) | 7.8 / 17.8 | 5.5 / 13.9 / 14.9 | 6.2 / 14.2 |
| LAT-4 a (`lat-lat4.txt`) | 3.5 / 27.6 | 13.4 / 19.8 / 25.4 | 15.9 / 28.7 |
| LAT-4 b (`lat-lat4b.txt`) | 24.1 / 31.1 | 11.8 / 18.2 / 25.4 | 20.3 / 28.8 |
| LAT-4 c (`lat-lat4c.txt`) | 1.8 / 29.2 | 13.1 / 19.0 / 26.5 | 18.8 / 26.5 |

- [measured] Worse in every run: max ~25-31 ms (was 14-18), gap-8 p50 doubles. kernel->gpu only; GPU exec ~0.
- [inferred] Host preemption is helping: with it, a waiting submit gets the engine after ~one 2 ms timer plus the
  busy client's batch; without it, it waits the batch out. So the wait is a lack of preemption granularity, not a
  cost of it. CPU load in the first minutes is a caveat, but earlier runs showed CPU load does not raise the wait.
- Next: undo LAT-4 (`efi.sh wexrtx-keep` without `WEX_EXTRA`). The research plan's LAT-8 (`-wex-objpreempt`: let
  object-level preemption stay on, so the busy batch can be cut mid-way) becomes the most promising change.

## LAT-8 (prepared 2026-11-14): object-level preemption on, knob `-wex-objpreempt`

LAT-4 says host preemption helps but is too coarse. WhateverXe turns 3D object-level preemption off (r135 clears
CS_CHICKEN1 bit0, r144 makes CS_DEBUG_MODE1 0x20EC bit0 the global selector, r145 writes 0x20EC = mask 0x3 value
0x2, so bit0 = 0). One variable: with `-wex-objpreempt` the r145 write becomes value 0x3 (bit0 = 1, object-level
preemption globally on). CS_CHICKEN1, FF DOP clock gating and compute mode are unchanged.

- Patch `source-fixes/wex/0.8.2/0006-lat8-objpreempt-knob.patch` (src-082 `aed59ac`, tag `lat-8`). Built with the
  XE-11 SDK `3f75008` and Lilu 1.7.2: WhateverXe `8dfa6775` (`strings` shows `-wex-objpreempt` and
  `TGLObjectPreemptionKnob`); CPU tests 216/216 (the boot-arg name added to `tests/fixtures/boot_argument_names.json`).
  Without the arg the build behaves as `96545d6d` [inferred: only that byte depends on the knob].
- Staged in `~/nmx-build/whateverxe/kexts/wex-lat8/`. Installed with the one-boot mode so a hang falls back to the
  GPU-only config on the next boot: `sudo WEXDIR=wex-lat8 WEX_EXTRA="-wex-objpreempt" bash tools/hybrid/efi.sh wexrtx`.
- Risk: the TGL B0 "object-preemption topology corruption" that r135 works around (RPL-P stepping unverified):
  rendering corruption or GPU hangs (`recoveryCount`).
- Checks: registry `TGLObjectPreemptionKnob` = Yes; `xe-lattest` with Claude on screen vs the XE-13 baseline
  (max 14-18 ms); no corruption; `recoveryCount` 0.
- Keep: run the same command with `wexrtx-keep`. Undo: `sudo bash tools/hybrid/efi.sh wexrtx-keep`.

### LAT-8 result, part 1 (2026-11-14 ~00:25)

- [measured] Booted with `-wex-objpreempt`; WhateverXe 0.8.2 loaded; registry `TGLObjectPreemptionKnob` = Yes (and
  the r135/r144/r145 flags still Yes); no `recoveryCount` property, no GPU reset seen. boot-once put GPU-only back
  for the next start, as designed.
- [measured] `xe-lattest`, three runs (`~/lat-lat8a..c.txt`), Claude app on screen, 144 Hz, uptime 2 min, load ~30:
  kernel->gpu p90 0.1-5.8 ms, p99 2.9-7.7 ms, max 6.2-10.1 ms (all gaps). XE-13 baseline: p90 6-14, p99 12-18,
  max 14-18 ms; LAT-4: max 25-31 ms.
- [inferred] The worst-case wait roughly halves: the busy client's long draw is now preempted at object
  granularity. This supports the queueing model. Still open: corruption over longer use (r135's TGL B0 erratum,
  RPL-P stepping unverified) and whether Lukas feels it.
- Lukas (~00:30), after a few minutes of use: the general feel improved; no artefacts reported. Kept as daily
  (`wexrtx-keep` with the same `WEXDIR`/`WEX_EXTRA`); longer soak still watches for corruption.

### LAT-8 soak, slow spell (2026-11-14 08:24)

- Lukas: the system feels slow again, uptime 16 min, `-wex-objpreempt` still in boot-args [measured].
- [measured] Three Claude desktop apps open at once (`Claude`, `Claude 2`, `Claude 3`), each with its GPU process at
  29-63 % CPU and its main renderer at 38-55 %; total CPU ~240 % of 1200 %, no thermal or speed limit; 320 MB free
  RAM, swap 45 MB. syspolicyd showed 76 % once, then idle (16 s CPU total).
- [measured] `xe-lattest`, two runs: kernel->gpu p50 3.5-5.9 ms, p90 12-15.7 ms, p99 17.5-19.1 ms, max 20-24 ms,
  back to the pre-LAT-8 level (part 1, one Claude app: max 6-10 ms).
- [inferred] Same queueing as before, scaled by the number of busy Metal clients: object preemption shortens each
  wait but three apps keep the render engine's queue full. Next check: hide or quit two of the apps and rerun.

## LAT-5 (prepared 2026-11-14): Apple scheduler Development keys from OpenCore

Lukas works with several busy apps open as a rule, so closing apps is not a fix; the goal is a stable desktop under
that load. Next lever from the ranked plan ([research/xe-latency.md](../research/xe-latency.md)): Apple's own
scheduler keys. Live `Development` dict [measured]: `PreemptionTimerIntervalUS=2000`, `PreemptionDelayIntervalUS=160`,
`SchedThrottleCapMS=100`, `MetalCoalesce=1`. The driver clamps the two preemption values and logs the range
("Constraining preemption ... in the range [%u,%u] us", strings in the TGL binary).

- Patch `source-fixes/wex/0.8.2/0007-lat5-wexdev-development-keys.patch` (src-082 `b80627d`, tag `lat-5`, on top of
  LAT-8). In `wrapTGLAcceleratorStart`, before the parent start: an iGPU property `wexdev-<Key>` (4 bytes, LE) for one
  of five allowed keys overrides that key in `Development`; registry root `WexDevOverrides` counts them and the kernel
  log says `LAT-5 Development <Key> = <n>`. No property, no change. WhateverXe `fa17909c`; CPU tests pass. Staged in
  `~/nmx-build/whateverxe/kexts/wex-lat5/`.
- `wex-config.py`: `WEX_DEV="Key=n ..."` writes those properties. No rebuild for later keys (LAT-6).
- First value: `PreemptionTimerIntervalUS=500` (one variable; LAT-8 object preemption stays on):
  `sudo WEXDIR=wex-lat5 WEX_EXTRA="-wex-objpreempt" WEX_DEV="PreemptionTimerIntervalUS=500" bash tools/hybrid/efi.sh wexrtx`
- Checks: `ioreg` Development shows 500 (or the clamp in the log); `xe-lattest` with the usual three Claude apps busy
  vs the 08:24 run (max 20-24 ms).
- On hold: Lukas first asked for one RTX-only boot (`efi.sh gpu-only`) to compare the feel. That route was last
  good on nullmoth 2.3.6 with our NVRM/NVAccel patches; on release 2.9 it is untested [unverified].

LAT-5 note (2026-11-14): deferred by Lukas, to be run later as prepared above (`wex-lat5` stays staged). It is
independent of NMH-1: after NMH-1's boot the daily LAT-8 config comes back by itself.

## NMH-1 (prepared 2026-11-14): RTX-only for one boot on nullmoth 3.0's own hybrid path

Lukas asked to see how the RTX-only route feels on nullmoth 3.0, for the next boot only. Since 2.9 nullmoth ships its
own path for laptops whose panel is on the iGPU: NVAccel presents WindowServer's frames on head 4, published by
nullmoth's `NMIntelFB` (`docs/HYBRID-LAPTOPS.md`, `docs/HYBRID-TESTER-PLAN.md` at `v3.0`). Off unless the boot-arg
`nmhybrid` is set; levels 1 copy, 2 import (GTT), 3 owned buffers, 4 copy engine; Intel display 12/13 for 2-4. Not
run on any hybrid laptop upstream [measured, doc text]. It replaces our own bridge (NMIntelFB fork + NVRM/NVAccel
patches, last good on 2.3.6), so none of our RTX patches are needed.

- Release 3.0 (2026-11-14) [measured]: `nullmoth-nvidia-3.0.tar.gz` matches `SHA256SUMS.txt`, inner `SHA256SUMS`
  passes. NVRM `ba6184e9`, NVAccel `d4ced924`, NVRMFB `4d3c4c02`, NVRMAGDC `97623c55` (unchanged), NMIntelFB
  `4b8afbcf` (in `/Library/NullMoth/kexts/`, not installed by `install.sh`). Changelog: fixes processes that lost the
  GPU right after login on 2.9 (command memory no longer GPU-cached), Displays pane hang, shutdown hang. `install.sh`
  now also adds `gfxrst=4` to NVRAM boot-args when WhateverGreen is loaded (our config sets boot-args, so it has no
  effect) and installs a backlight job.
- Upstream `NMIntelFB` returns at once on `-nmintelfboff` and declines without `nmhybrid` [measured, `intelfb.cpp`
  lines 443-445], so it is inert on the daily hybrid.
- Our `com.nmxintel.intelfb-auto` job (RTX-24) turns our old bridge's sysctls on; removed for this path.
- `nvmtl-allow.txt` goes back to nullmoth's list on install (`*`, `!WindowServer`), which is what this route wants;
  `ondemand.sh on` + `add` come after, on the way back to the hybrid.
- `efi.sh rtx` (new): `config-rtx.plist` = `config-gpu-only.plist` minus `-nmintelfboff`/`-nvoff`, plus
  `nmhybrid=${NMHYBRID:-1}`; saves the daily `config.plist` as `config-back.plist` and arms a daemon (`boot-back`)
  that puts it back early in that boot and removes itself. `NMHYBRID=2..4` for the next levels, one per boot.
- First level 1 (copy), as the upstream tester plan orders. Checks: `log show --last boot --predicate 'eventMessage
  CONTAINS "hybrid:"'` (S1 switch read, S2 provider NMIntelFB, S3 first frame), `sysctl debug.nmhybrid_frames
  debug.nmhybrid_words_skipped debug.nmintelfb_step`, and Lukas's feel vs the LAT-8 hybrid.
- All of the above in one command: `sudo bash tools/hybrid/rtx-prep.sh` (skips what is done; `NMHYBRID=2` for the next level).
- Rollback: the next boot is the daily config by itself; a frozen boot → OpenCore Space → "Start once without
  NVIDIA driver" (NMIntelFB stands down on `-nvoff`), the daemon then restores the daily config. Driver:
  `sudo bash tools/upgrade/rollback.sh /Library/NullMoth/backup-…`.

### NMH-1 result (2026-11-14): fail, the boot hung without a trace

- Boot 08:47 with `... -v nmhybrid=1` [measured, `/var/log/nmx-hybrid.log` boot-back line]. The one-boot daemon
  ran and evidently copied `config-back.plist` back (the next boot was the daily LAT-8 config), but its "put back"
  line never reached the log: the system hung right after.
- Unified log of that boot (08:47:11 to the forced reboot at 08:50:54) [measured]: no kernel line from NVRM, NVAccel,
  NVRMFB or NMIntelFB at all, no `hybrid:` line. The last activity is syspolicyd allowing the nullmoth kexts at
  08:47:32, then nothing. No panic report for that boot (only `shutdown_stall_2026-11-14-084652`, from the shutdown
  before it). `nvram nullmoth-ifb-step` absent, only `nullmoth-nv-ok 1` [measured].
- Lukas saw the system not start. Where it stopped is unknown: the hang came before (or took down) the log writer
  [inferred]. No simple fix with a guaranteed result, so by Lukas's rule (11-14) we go back to LAT-5; the route stays
  parked until upstream reports a working hybrid laptop.
- nullmoth 3.0 stays installed on the daily hybrid: the boot after NMH-1 works with it (NVRM "boot guard: start 1
  without a display so far" is its normal headless line) [measured]. NMIntelFB 3.0 is inert there (`-nmintelfboff`).

## LAT-5 (run 2026-11-14 after NMH-1): one command

- Bug found while preparing it: `efi.sh wexrtx` (one boot) armed `boot-once`, which puts `config-gpu-only.plist`
  back, i.e. the RTX-only bridge that does not work on nullmoth 2.9+. Fixed: when config.plist is already a route
  config (the daily `wexrtx-keep`), one boot saves it as `config-back.plist` and arms `boot-back` instead.
- `sudo bash tools/hybrid/lat5.sh`: checks wex-lat5 is `fa17909c`; `ondemand.sh on` + `add` Roblox, RobloxPlayer,
  Google Chrome, Google Chrome Helper (Aperitif) (the 3.0 install had put back `*`); then
  `WEXDIR=wex-lat5 WEX_EXTRA=-wex-objpreempt WEX_DEV=PreemptionTimerIntervalUS=500 efi.sh wexrtx` (one boot).
- Checks as planned above: `ioreg` Development shows 500 (or the clamp in the log); `xe-lattest` with the three
  Claude apps busy vs LAT-8 (max wait 6-10 ms).

### LAT-5 result, part 1 (2026-11-14 ~09:01): one busy Claude app

- [measured] Boot 08:58 with `-wex-objpreempt`; WhateverXe 0.8.2 loaded; registry root `WexDevOverrides` = 1, iGPU
  `wexdev-PreemptionTimerIntervalUS` = `f4010000`, live `Development` shows `PreemptionTimerIntervalUS=500`. No
  "Constraining preemption" line in `log show --last boot`, so 500 is inside the driver's range [inferred]. The
  `LAT-5 Development ...` kernel line did not show in `log show` either (the value itself is the proof).
  `recoveryCount` 0; boot-back put the daily LAT-8 config back for the next start (`/var/log/nmx-hybrid.log`).
- [measured] Desktop at 60 Hz this boot (`refresh.sh set 144` not rerun); LAT-8 part 1 was at 144 Hz, and the 144 Hz
  run showed refresh does not move the wait.
- [measured] `xe-lattest` three runs (`~/lat-lat5a..c.txt`), uptime 2-3 min, load ~25-58, only the main Claude app
  busy (Claude 2 and 3 open but idle, <1 % CPU): kernel->gpu p90 0.07-7.8 ms, p99 5.6-8.4 ms, max 5.7-9.6 ms.
  LAT-8 part 1 (one Claude app): p90 0.1-5.8, p99 2.9-7.7, max 6.2-10.1 ms.
- [inferred] No clear change in the one-app case: the worst wait stays one ~6-9 ms draw. The case LAT-5 is for (three
  busy Claude apps, LAT-8 max 20-24 ms) is not measured yet; next run needs Claude 2 and 3 busy on screen.
- Also seen: a `shutdown_stall` report on the reboot into LAT-5 (08:58), as on the two reboots before it; not new.

### LAT-5 result, part 2 (2026-11-14 ~09:03): Claude 2 and 3 open but not busy

- [measured] `xe-lattest` three runs (`~/lat-lat5d..f.txt`), uptime 4 min, load 9-16: kernel->gpu p90 0.07-6.2 ms,
  p99 5.3-9.1 ms, max 5.6-11.0 ms.
- [measured] During the runs Claude 2 and 3 main processes sat at ~6 % CPU and none of their helper (GPU/renderer)
  processes showed up busy; at 08:24 (LAT-8, max 20-24 ms) each app's GPU process ran 29-63 %. So this is not the
  three-busy-apps load; the comparison is still open [inferred].
- Next: rerun while Claude 2 and 3 are actually generating output, with a CPU snapshot of their helpers next to each run.

### LAT-5 result, part 3 (2026-11-14 ~09:05): three busy Claude apps

- [measured] `xe-lattest` three runs (`~/lat-lat5g..i.txt`), uptime 6-8 min, Claude 2 and 3 generating long answers,
  helper CPU snapshot before each run: GPU processes Claude 2 39-45 %, Claude 3 12-20 %, Claude 12-21 %; Claude 2
  renderer 46-126 %.
- [measured] kernel->gpu p50 1.9-14.3 ms, p90 28-34 ms, p99 42-62 ms, max 42-72 ms (all gaps). LAT-8 at 08:24 with
  three busy apps: p90 12-15.7, p99 17.5-19.1, max 20-24 ms.
- [inferred] `PreemptionTimerIntervalUS=500` makes the busy case 2-3x worse: a shorter timer seems to add switch cost
  (or preempts the compositor as well) rather than cut the wait. Caveat: the load today (one app streaming a long
  answer with its renderer at up to 126 %) may be heavier than at 08:24, so the LAT-8 control under the same load
  comes next, on the boot after this one (boot-back puts LAT-8 back by itself).
- Verdict: LAT-5 with 500 us rejected for now; final after the control run.

## Change of approach (2026-11-14 ~09:15): cut the Iris Xe's load instead of tuning its scheduler

Lukas: eight latency tests (LAT-2, LAT-4, LAT-5, LAT-8, XE-13, refresh, Claude on the RTX, priority) and the desktop
still feels slow under his normal load. Review of the evidence:

- The only lever that ever moved the busy wait a lot was **less work on the Iris Xe**: twelve CPU burners starved the
  Electron renderers and the wait fell to max ~9 ms; a clean desktop gives max <1 ms; three busy Claude apps give
  20-72 ms [measured, see above]. Scheduler knobs moved it by a factor of ~2 at best (LAT-8), or made it worse
  (LAT-4, LAT-5). The UHD (48 EU, ~1.1 GHz granted [measured]) is simply small for three Chromium compositors plus
  WindowServer [inferred].
- "Claude on the RTX" did not take the work off the Iris Xe: Chromium's GPU process still held 4 Intel user clients
  and WindowServer copies the frames back [measured, research/xe-latency.md].
- `PerformanceStatistics` "Device Utilization %" reads 0 at all times under WhateverXe [measured 09:10, six reads
  under load], so GPU busy time cannot be read from the registry (pitfall added).
- Web check (11-14): no WhateverXe release after 0.8.2 / Graphics 0.4.4 touches performance (0.4.4 fixes H.264
  encode only); NootedGreen's `-ngreenpm` is a CPU XCPM fix for macOS 26.7.1, not GPU. Claude Desktop accepts
  `--disable-gpu --disable-gpu-compositing` and renders correctly with them (anthropics/claude-code#26080). Reduce
  Transparency cut WindowServer load ~25 % on one AMD hackintosh (single report) [unverified for us].

## LAT-12 (prepared 2026-11-14): Claude 2 and 3 drawn on the CPU

One variable, no reboot, same boot as the LAT-5 baseline (part 3, max 42-72 ms): Claude 2 and 3 restarted with
`--disable-gpu --disable-gpu-compositing`. Chromium then rasterises and composites on the CPU (12 threads, ~80 % idle
under this load [measured 08:24]) and hands WindowServer one finished surface per window, so its own Metal work on
the Iris Xe goes away [inferred from Chromium's software compositor]. The main Claude app keeps its GPU (Claude Code
runs in it), so it is the remaining Electron load.

- `tools/hybrid/claude-gpu.sh off|on|status` (quits by bundle id `local.claude-instances.claude-N`, never the main
  app); `status` counts Intel GPU user clients per instance (baseline: 6 each).
- `tools/hybrid/lat-busy.sh TAG`: three `xe-lattest` runs, each after a CPU snapshot of the Claude processes.
- Checks: `status` shows "GPU off" and fewer Intel clients; Claude 2 and 3 windows render (risk: a blank window, seen
  with other Electron apps); same load as part 3 (long answers in 2 and 3); `lat-busy.sh lat12` vs part 3; Lukas's
  feel; CPU of the two apps.
- Keep: make the flags part of the clones' `launch` script (`~/.config/claude-instances/build.sh`). Undo:
  `claude-gpu.sh on`, or just quit and reopen the apps.

LAT-12 note (2026-11-14 ~09:25): **dropped by Lukas before it ran.** He does not accept apps drawn on the CPU: in his
experience it is very slow and costs more resources overall. `claude-gpu.sh off` never took effect (Claude ignored the
Apple Event quit while busy; the run was stopped), `status` afterwards: both apps "GPU on", 6 Intel clients each
[measured]. Rule from now on: fixes must keep apps on a GPU; reduce or move GPU work, never fall back to software.

### LAT-13 prepared (2026-11-14): all three Claude apps render on the RTX

Lukas chose this lever after the research in [../research/xe-alternatives.md](../research/xe-alternatives.md): move
the Metal work of every Claude app (main, 2 and 3) to the RTX through the hybrid allow-list, so the Iris Xe only
composites their windows. Every app stays on a GPU.

- Chromium's GPU work runs in `Claude Helper --type=gpu-process` in all three apps (pids 572, 733, 735) [measured,
  `ps`]. The clones use the same executable names, so two list entries cover the three apps: `Claude` and
  `Claude Helper` (same lesson as Chrome's Aperitif helper, pitfalls.md).
- `ondemand.sh add|remove` now takes several names (dry-run on a copy of the list: add, re-add, remove all
  behave) [measured].
- Steps: `sudo bash tools/hybrid/ondemand.sh add "Claude" "Claude Helper"`, then quit (Cmd+Q) and reopen all three
  apps. No reboot.
- Checks: `ondemand.sh status` lists the Claude processes as RTX holders; `claude-gpu.sh status` shows fewer Intel
  GPU clients than the 6 per app baseline; windows draw (risk: blank windows, as with Chrome's own GPU path on
  Julio's build); same load as LAT-5 part 3; `lat-busy.sh lat13` vs LAT-8 08:24 (max 20-24 ms) and LAT-5 (42-72).
  Unknown: whether Chromium picks the RTX or still the default Iris Xe device when both are visible [unverified].
- Undo: `sudo bash tools/hybrid/ondemand.sh remove "Claude" "Claude Helper"` and reopen the apps.
