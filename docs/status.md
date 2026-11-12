# Status

> **Summary.** Last updated 2026-11-12. Daily setup is the **WhateverXe hybrid** (XE-8): the Iris Xe drives the
> desktop with Metal at 60 Hz, the RTX runs nullmoth headless and only apps listed by `ondemand.sh` open it. Lukas
> wants the newest drivers on both GPUs and then macOS Tahoe: three steps, one variable each. Now: UPG-6.

## Daily setup (how the machine boots now)

- OpenCore config from `sudo bash tools/hybrid/efi.sh wexrtx-keep`: WhateverXe `94698a29` (our wex-0001..0004),
  nullmoth NVRM 2.6.4 + NVAccel headless, NMIntelFB gated off (`-nmintelfboff`), `SSDT-PNLF.aml`.
- RTX for apps: `sudo bash tools/hybrid/ondemand.sh add NAME` (then reopen the app); list now `Roblox`,
  `RobloxPlayer`; `BOOST=0` (XE-10). After any nullmoth install: `on` + `add` again (pitfall).
- Wi-Fi: AirportMtkWlan `dd967442` (WIFI-9, no repeat of the 10-30 mbuf panic so far).
- Recovery: OpenCore Space → "Start once without NVIDIA driver"; `sudo bash tools/hybrid/efi.sh gpu-only` returns to
  the RTX-only route (NMIntelFB bridge; needs our NVRM/NVAccel patches, not ported to 2.9).
- Tests and evidence: [tests/wex-1.md](tests/wex-1.md); route background: [knowledge/hybrid-route.md](knowledge/hybrid-route.md).

## Upgrade plan (research.md, 2026-11-12 check)

1. **UPG-6** (prepared): nullmoth 2.6.4 → 2.9 release as is (NVIDIA 620, per-burst boost). Then UPG-7: `nvrtd3=1`
   (RTX deep sleep, needs `nvrtd3res=<ACPI path>`), which would close open problem 1.
2. **XE-11**: WhateverXe 0.8.2 + Graphics 0.4.3 on Sequoia, wex-0001..0004 rebased.
3. **TAHOE-1**: full backup, OpenCore check, AirportMtkWlan Tahoe build, Tahoe 26.7.x with the same stack.

## Open problems

1. RTX never powers off at runtime; 2.9 has an experimental RTD3 (`nvrtd3`), untested (UPG-7). XE-9 unmeasured.
2. Panic 2026-11-12 19:39: xnu spinlock timeout in WindowServer, a slow interrupt on CPU 0, driver unknown
   ([tests/wex-1.md](tests/wex-1.md)). Watch for a repeat.
3. 144 Hz only in fullscreen (macOS auto-switches only on ProMotion panels); 60 Hz accepted by Lukas.
4. Sleep: off; untested with WhateverXe.
5. `ASSERT(linkBW)` warning in the XE-7 log, harmless so far.

## Other areas

- RTX-only route (path B): works on nullmoth 2.3.6; 2.5.x/2.6.4 blink (UPG-2..5, parked),
  [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
- Wi-Fi MT7921 at the line's ceiling (WIFI-8), [knowledge/wifi.md](knowledge/wifi.md).
- Previous status text (verbatim): [archive/status-2026-10-29.md](archive/status-2026-10-29.md).
