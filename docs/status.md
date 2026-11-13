# Status

> **Summary.** Last updated 2026-11-12. Daily setup is the **WhateverXe hybrid** (XE-8): the Iris Xe drives the
> desktop with Metal at 60 Hz, the RTX runs nullmoth headless and only apps listed by `ondemand.sh` open it. Lukas
> wants the newest drivers on both GPUs and then macOS Tahoe. Drivers done (UPG-6b, XE-11). Now: TAHOE-1a, Tahoe on a
> separate APFS volume (no backup disk; Sequoia stays as rollback). Tahoe installed on its own volume, boots plain; Wi-Fi works there (TAHOE-2, plain with `NVOFF=0`); next TAHOE-3: WhateverXe inside Tahoe (tahoe-1.md).

## Daily setup (how the machine boots now)

- OpenCore config from `sudo bash tools/hybrid/efi.sh wexrtx-keep`: WhateverXe 0.8.2 `96545d6d` (our wex 0.8.2/0001..0005) + Graphics 0.4.3,
  nullmoth NVRM 2.9 + NVAccel headless, `/Library/NullMoth/no-wsreset` (UPG-6b), NMIntelFB gated off (`-nmintelfboff`), `SSDT-PNLF.aml`.
- RTX for apps: `sudo bash tools/hybrid/ondemand.sh add NAME` (then reopen the app); list now `Roblox`,
  `RobloxPlayer`; `BOOST=0` (XE-10). After any nullmoth install: `on` + `add` again (pitfall).
- Wi-Fi: AirportMtkWlan `dd967442` (WIFI-9, no repeat of the 10-30 mbuf panic so far).
- Recovery: OpenCore Space → "Start once without NVIDIA driver"; `sudo bash tools/hybrid/efi.sh gpu-only` returns to
  the RTX-only route (NMIntelFB bridge; needs our NVRM/NVAccel patches, not ported to 2.9).
- Tests and evidence: [tests/wex-1.md](tests/wex-1.md); route background: [knowledge/hybrid-route.md](knowledge/hybrid-route.md).

## Upgrade plan (research.md, 2026-11-12 check)

1. **UPG-6** failed: 2.9 itself is fine, but 1401's wsreset restart of WindowServer now lands and the Intel panel
   goes black (pitfall). **UPG-6b** passed with `no-wsreset`. Optional later: UPG-7: `nvrtd3=1` (RTX deep sleep).
2. **XE-11** passed: WhateverXe 0.8.2 + Graphics 0.4.3 on Sequoia (README: Sequoia 15.8.x, Tahoe 26.7+), wex-0001..0004 rebased.
3. **TAHOE-0/1** ([tests/tahoe-1.md](tests/tahoe-1.md)): `bash tools/tahoe/tahoe.sh check` lists what is missing.
   OpenCore 1.0.8 ok, Wi-Fi Tahoe build `3b22cfa5` ok. The four PCCI CPU patches stop at Darwin 24 (pitfall):
   `tahoe.sh kc` + `patch` must pass before the upgrade. Then `prepare` (plain boot) and the 26.7.3 installer.

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
