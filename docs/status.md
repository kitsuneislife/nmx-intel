# Status

> **Summary.** Last updated 2026-11-22. Daily setup is the **WhateverXe hybrid** (XE-8): the Iris Xe drives the
> desktop with Metal, the RTX runs nullmoth 3.0 headless and only apps listed by `ondemand.sh` open it. Staying on
> Sequoia 15.8.1 (Tahoe trial in [tests/tahoe-1.md](tests/tahoe-1.md)). Daily is XE-15 (0.8.3), kernel->gpu max 0.2-2 ms. Next: AGPM-1 kept as daily.

## Daily setup (how the machine boots now)

- OpenCore config from `xe15.sh keep` (11-22): WhateverXe 0.8.3 `8516faf3` (XE-15c) with `-wex-objpreempt -wex-noccs
  -wex-hostrps-max`; rollback `WEXDIR=wex-xe14b WEX_EXTRA="-wex-objpreempt -wex-noccs" efi.sh wexrtx-keep`.
  + Graphics 0.4.3, nullmoth NVRM/NVAccel 3.0 headless, `no-wsreset`, NMIntelFB
  gated off (`-nmintelfboff`), `SSDT-PNLF.aml`.
- **RTD3 daily since 11-22** (`rtd3.sh keep`, after AGPM + CPUFriend hwp off): patched NVRM `986b14bc`,
  `SSDT-NXRTD3.aml`, `nvrtd3=1 nvrtd3res=\_SB.PC00`: RTX off after 60 s idle, on for ondemand apps. First keep boot
  not yet checked. Rollback `sudo HWP=off bash tools/cpu/cpufriend.sh keep`, then `rtd3.sh restore`.
- RTX for apps: `sudo bash tools/hybrid/ondemand.sh add NAME` (then reopen the app). List: Roblox, Chrome (+ its
  Aperitif helper), Horizon (Claude moved back to the Iris Xe, LAT-14). After any nullmoth install:
  `on` + `add` again (pitfall).
- Wi-Fi: AirportMtkWlan `dd967442` (WIFI-9); WIFI-10 `274f4c6a` built, install pending.
- Recovery: OpenCore Space → "Start once without NVIDIA driver". Tests: [tests/wex-1.md](tests/wex-1.md).
- Disk: 65.7 GB free [measured 11-22] after removing cargo `target/`s, magic-rush `tools/` + `private/`, a NixOS ISO.

## Lag work (main open problem)

- Iris Xe submit wait grows when busy apps are on screen. LAT-8 (object preemption) cut max wait to 6-10 ms; LAT-4 and
  LAT-5 were worse; CPU drawing is ruled out (Lukas). Details: [research/xe-latency.md](research/xe-latency.md),
  [research/xe-alternatives.md](research/xe-alternatives.md).
- Radar 11-22 ([research/radar-2026-11-22.md](research/radar-2026-11-22.md)): 20 iGPU hangs on 11-20/21, 19 on the CCS
  ring (`mediaanalysisd`, WhateverXe #163). Hangs may leave compositing slow until reboot [inferred for us]. Without
  GuC the CPU drives submission, so CPU load raises iGPU latency (#182) [inferred]; take runs with the CPU idle.
- **Lag cause (LAT-15, 11-22)**: Claude Desktop's chat **wallpaper** kept its gpu-process at 90-93 % of the Iris Xe
  (`tools/hybrid/gpu-top.sh`). Off: 0.1 %. Keep `/wallpaper default off`. Typing in Ghostty was smooth.
- **AGPM-1 (11-22)**: AGPM profile without `RCxControl`/`CPGControl` → **GT RC6 0 → 99 %**, idle package
  11.7 → 6.6 W, PC2 ~51 %. wxe study ([research/wxe-study-2026-11-22.md](research/wxe-study-2026-11-22.md)): macOS
  now ~55-60 % of Windows; no fork. Still no all-core turbo (12 threads ~2.4 GHz / 16 W).
  AGPM kept as daily (11-22). **CPUFRIEND-2 (11-22): `hwp` off in the vector → P-cores 4.5 GHz**:
  12 threads 23.6 → 45.4 GHz-equiv, 1 thread 2.4 → 4.45 GHz; idle 7.2 → 10.8 W. Kept (11-22). **RTD3-4 (11-22): RTX off after 60 s idle and back on for Chrome** (RESUME 0x0, 844 ms). Second cycle OK; same boot RTX idle-on 30.9 W → off 25.3 W (~-5.5 W). Kept as daily (11-22).
  **FENCE-0 (11-22)**: WhateverXe #130 100 ms fence stall absent (2700 completions, max 3.3 ms); patch not built.

## Other open problems

1. RTX never powers off at runtime; 3.x RTD3 (`nvrtd3`) nullmoth's ACPI call refused (RTD3-1/2), RTD3-4 works, ~5.5 W saved; armed for one boot only.
2. Panic 2026-11-12 19:39, WindowServer spinlock timeout, driver unknown. Watch for a repeat.
3. Refresh: 144 Hz works through `refresh.sh` (XE-13); WindowServer still defaults to 60 Hz after boot.
4. Sleep: off; untested with WhateverXe. `ASSERT(linkBW)` warning in the XE-7 log, harmless so far.
5. Wi-Fi MT7921 at the line's ceiling (WIFI-8), [knowledge/wifi.md](knowledge/wifi.md).

Older status: [archive/status-2026-10-29.md](archive/status-2026-10-29.md), `git log docs/status.md`.
