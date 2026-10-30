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
