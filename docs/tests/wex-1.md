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
