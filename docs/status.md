# Status

> **Summary.** Last updated 2026-11-13. Daily setup is the **WhateverXe hybrid** (XE-8): the Iris Xe drives the
> desktop with Metal at 60 Hz, the RTX runs nullmoth headless and only apps listed by `ondemand.sh` open it. Drivers
> are the newest (UPG-6b, XE-11). **Staying on Sequoia 15.8.1**: the Tahoe trial (TAHOE-0..3 passed, TAHOE-4 not run)
> is recorded in [tests/tahoe-1.md](tests/tahoe-1.md) and removed with `sudo bash tools/tahoe/tahoe.sh remove`.

## Daily setup (how the machine boots now)

- OpenCore config from `sudo bash tools/hybrid/efi.sh wexrtx-keep`: WhateverXe 0.8.2 `96545d6d` (our wex 0.8.2/0001..0005) + Graphics 0.4.3,
  nullmoth NVRM 2.9 + NVAccel headless, `/Library/NullMoth/no-wsreset` (UPG-6b), NMIntelFB gated off (`-nmintelfboff`), `SSDT-PNLF.aml`.
- RTX for apps: `sudo bash tools/hybrid/ondemand.sh add NAME` (then reopen the app); list now `Roblox`,
  `RobloxPlayer`, `Google Chrome`, `Google Chrome Helper (Aperitif)` (Chrome 157's GPU process) [measured 11-13];
  boost back to nullmoth's per-burst default (`BOOST=0` gone after the 2.9 install). After any nullmoth install: `on` + `add` again (pitfall).
- Wi-Fi: AirportMtkWlan `dd967442` (WIFI-9, no repeat of the mbuf panic); WIFI-10 `274f4c6a` built (Disconnect
  mid-scan left Wi-Fi stuck busy), install pending.
- Recovery: OpenCore Space → "Start once without NVIDIA driver"; `sudo bash tools/hybrid/efi.sh gpu-only` returns to
  the RTX-only route (NMIntelFB bridge; needs our NVRM/NVAccel patches, not ported to 2.9).
- Tests and evidence: [tests/wex-1.md](tests/wex-1.md); route background: [knowledge/hybrid-route.md](knowledge/hybrid-route.md).

## Upgrades (research.md, 2026-11-12 check)

1. **UPG-6b** passed: nullmoth 2.9 with `no-wsreset`. Optional later: UPG-7: `nvrtd3=1` (RTX deep sleep).
2. **XE-11** passed: WhateverXe 0.8.2 + Graphics 0.4.3 on Sequoia.
3. Tahoe: not pursued (Lukas, 2026-11-13); removed and the hybrid back [measured: Metal
   `AppleIntelTGLGraphicsMTLDriver`]. Test leftovers: `sudo bash tools/cleanup.sh` (logs packed, ~4.5 GB freed). Before any future macOS major upgrade, see the PCCI pitfall.

## Open problems

1. RTX never powers off at runtime; 2.9 has an experimental RTD3 (`nvrtd3`), untested (UPG-7). XE-9 unmeasured.
2. Panic 2026-11-12 19:39: xnu spinlock timeout in WindowServer, a slow interrupt on CPU 0, driver unknown
   ([tests/wex-1.md](tests/wex-1.md)). Watch for a repeat.
3. Refresh: desktop at 60 Hz though the panel does 144 (modes present [measured]). XE-12 (`refresh.sh`): native
   "Refresh Rate" menu via `display-refresh-rate-policy`, pending.
4. Sleep: off; untested with WhateverXe.
5. `ASSERT(linkBW)` warning in the XE-7 log, harmless so far.
6. Feels slow (11-13): touchpad in VoodooI2C polling mode, desktop still 60 Hz, bluetoothd restart loop
   ([tests/wex-1.md](tests/wex-1.md), slowness check). XE-13 pending: no cpuname, touchpad interrupts, `refresh.sh set 144`.
   Iris Xe submit latency p90 12-15 ms [measured, `xe-lattest`]: likely the main cause.

## Other areas

- RTX-only route (path B): works on nullmoth 2.3.6; 2.5.x/2.6.4 blink (UPG-2..5, parked),
  [tests/rtx-8-accelerated-desktop.md](tests/rtx-8-accelerated-desktop.md).
- Wi-Fi MT7921 at the line's ceiling (WIFI-8), [knowledge/wifi.md](knowledge/wifi.md).
- Previous status text (verbatim): [archive/status-2026-10-29.md](archive/status-2026-10-29.md).
