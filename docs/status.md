# Status

> **Summary.** Last updated 2026-11-22. Daily setup is the **WhateverXe hybrid** (XE-8): the Iris Xe drives the
> desktop with Metal, the RTX runs nullmoth 3.0 headless and only apps listed by `ondemand.sh` open it. Staying on
> Sequoia 15.8.1 (Tahoe trial in [tests/tahoe-1.md](tests/tahoe-1.md)). Next: make XE-14b permanent (`xe14.sh keep`), then XE-15.

## Daily setup (how the machine boots now)

- OpenCore config from `sudo WEXDIR=wex-daily WEX_EXTRA=-wex-objpreempt bash tools/hybrid/efi.sh wexrtx-keep`:
  WhateverXe 0.8.2 `fa17909c` on the ESP [measured 11-22] (the LAT-5 build; with no `wexdev` property it runs LAT-8's
  code) + Graphics 0.4.3, nullmoth NVRM/NVAccel 3.0 headless, `no-wsreset`, NMIntelFB
  gated off (`-nmintelfboff`), `SSDT-PNLF.aml`.
- RTX for apps: `sudo bash tools/hybrid/ondemand.sh add NAME` (then reopen the app). List: Roblox, Chrome (+ its
  Aperitif helper), `Claude`, `Claude Helper` (all three Claude apps, LAT-13), Horizon. After any nullmoth install:
  `on` + `add` again (pitfall).
- Wi-Fi: AirportMtkWlan `dd967442` (WIFI-9); WIFI-10 `274f4c6a` built, install pending.
- Recovery: OpenCore Space → "Start once without NVIDIA driver". Tests: [tests/wex-1.md](tests/wex-1.md); route
  background: [knowledge/hybrid-route.md](knowledge/hybrid-route.md).
- `~/nmx-build` was lost on 11-22 and rebuilt for WhateverXe only (clone, SDK, Lilu); nullmoth/drm-kmod trees not yet.
- Disk: 17 GiB free on `/` (under 10%) [measured 11-22]: cleanup due.

## Lag work (main open problem)

- Iris Xe submit wait grows when busy apps are on screen. LAT-8 (object preemption) cut max wait to 6-10 ms; LAT-4 and
  LAT-5 were worse; CPU drawing is ruled out (Lukas). Details: [research/xe-latency.md](research/xe-latency.md),
  [research/xe-alternatives.md](research/xe-alternatives.md).
- Radar 11-22 ([research/radar-2026-11-22.md](research/radar-2026-11-22.md)): 20 iGPU hangs on 11-20/21, 19 on the CCS
  ring (`mediaanalysisd`, WhateverXe #163). Hangs may leave compositing slow until reboot [inferred for us]. Without
  GuC the CPU drives submission, so CPU load raises iGPU latency (#182) [inferred]; take runs with the CPU idle.
- **XE-14b** `b2bb8e95` kept on the ESP (`xe14.sh keep`, 14:27 boot): knob works, no hang; p50 ~0.5 ms.
- **Lag cause (LAT-15, 11-22)**: Claude Desktop's chat **wallpaper** kept its gpu-process at 90-93 % of the Iris Xe
  (`tools/hybrid/gpu-top.sh`). Off: 0.1 %. Keep `/wallpaper default off`. Typing in Ghostty was smooth.
- **XE-15** built: `1c70dbd2` (with the XE-14b fix), same changes on WhateverXe 0.8.3 (recovery fix; upstream covers our 0003/0004). After
  XE-14's verdict, with a kext rollback. **XE-16** (#182 144 Hz fixes) dropped: not our failure.

## Other open problems

1. RTX never powers off at runtime; 3.x RTD3 (`nvrtd3`) untested (UPG-7).
2. Panic 2026-11-12 19:39, WindowServer spinlock timeout, driver unknown. Watch for a repeat.
3. Refresh: 144 Hz works through `refresh.sh` (XE-13); WindowServer still defaults to 60 Hz after boot.
4. Sleep: off; untested with WhateverXe. `ASSERT(linkBW)` warning in the XE-7 log, harmless so far.
5. RTX-only route: NMH-1 (nullmoth 3.0 `nmhybrid=1`) hung the boot; parked.
6. Wi-Fi MT7921 at the line's ceiling (WIFI-8), [knowledge/wifi.md](knowledge/wifi.md).

Previous status text (verbatim): [archive/status-2026-10-29.md](archive/status-2026-10-29.md); the 11-14..11-22
version is in git history (`git show 1c7768c:docs/status.md`).
