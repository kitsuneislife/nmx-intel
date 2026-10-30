# Status

> **Summary.** Last updated 2026-10-30. Daily setup is the **WhateverXe hybrid** (XE-8 works, much cooler per
> Lukas): the Iris Xe drives the desktop with Metal at 60 Hz, the RTX runs nullmoth headless and only apps listed by
> `ondemand.sh` open it. Brightness works. Now: WIFI-9 (boot panic fix) and XE-10 (`noboost`); then XE-9 battery.

## Daily setup (how the machine boots now)

- OpenCore config from `sudo bash tools/hybrid/efi.sh wexrtx-keep`: WhateverXe `94698a29` (our wex-0001..0004),
  nullmoth NVRM 2.6.4 + NVAccel headless, NMIntelFB gated off (`-nmintelfboff`), `SSDT-PNLF.aml`.
- RTX for apps: `sudo bash tools/hybrid/ondemand.sh add NAME` (then reopen the app); `status` lists holders;
  `off` restores nullmoth's list (every app boosts the RTX to max clock, pitfall); `noboost` stops the max-clock boost
  for listed apps (XE-10), `boost` undoes it. Re-run `on` and `noboost` after any nullmoth update.
- Wi-Fi: AirportMtkWlan with wifi5-0001..0006 (`dd967442` once WIFI-9 is installed).
- Recovery: OpenCore Space → "Start once without NVIDIA driver"; `sudo bash tools/hybrid/efi.sh gpu-only` returns to
  the RTX-only route (NMIntelFB bridge, 144 Hz).
- Tests and evidence: [tests/wex-1.md](tests/wex-1.md); route background: [knowledge/hybrid-route.md](knowledge/hybrid-route.md).

## Next step

Install WIFI-9 (`bash tools/wifi/build-airport.sh`, `sudo bash tools/wifi/install.sh airport`, reboot) and run
`ondemand.sh noboost` (XE-10); watch for a repeat of the 2026-10-30 Wi-Fi panic. Upstream (2026-10-30): only
nullmoth 2.6.5 is new, user-space only ([knowledge/research.md](knowledge/research.md)); install it as its own step.

XE-9: `bash tools/hybrid/power.sh` on battery, idle — (a) the hybrid, (b) one boot `-nvoff`. The gap is the idle
RTX cost; if large, build an RTX power-off (ACPI `_OFF` SSDT / Intel-only mode).

## Open problems

1. RTX never powers off at runtime (nullmoth has no RTD3/GC6); cost unmeasured (XE-9).
2. 144 Hz only in fullscreen: macOS auto-switches only on ProMotion panels; 60 Hz accepted by Lukas.
3. Sleep: off. S3 never relit the panel on the old route (SLEEP-1/2, [tests/sleep-1-hibernate.md](tests/sleep-1-hibernate.md));
   untested with WhateverXe.
4. The 1401 app may rewrite `/Library/GPUBundles/nvmtl-allow.txt`; re-run `ondemand.sh on` if holders reappear.
5. `ASSERT(linkBW)` warning in the XE-7 log, harmless so far.

## Other areas

- RTX-only route (path B, NMIntelFB bridge): works on nullmoth 2.3.6; 2.5.x/2.6.4 blink (UPG-2..5, parked),
  [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
- NootedGreen hybrid (HYB-1..15) replaced by WhateverXe, [tests/hybrid-1.md](tests/hybrid-1.md).
- Wi-Fi MT7921 works at the line's ceiling (WIFI-8), [knowledge/wifi.md](knowledge/wifi.md).
- Previous status text (verbatim): [archive/status-2026-10-29.md](archive/status-2026-10-29.md).
