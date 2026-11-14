# Iris Xe on macOS: alternatives to WhateverXe and community improvements (2026-11-14)

> **Summary.** This is a broad search for community drivers, forks and patches that could make the RPL-P iGPU
> faster than our WhateverXe hybrid. No project or patch targets UI latency under load. WhateverXe is still the only
> path that fits Sequoia 15.8.1 with the RTX kept. The remaining levers keep every app on a GPU: GT clock/power,
> fewer WindowServer effects, moving Claude 2/3 to the RTX, and the `tgl-stability` fork's fixes.

## Why this search

Scheduler knobs gave at most 2x (LAT-8) and sometimes made things worse (LAT-4, LAT-5: three busy apps reached
max 42-72 ms, against 20-24 ms on LAT-8) [measured, [../tests/wex-1.md](../tests/wex-1.md)]. Only removing GPU
work ever cut the wait a lot. Lukas rejects drawing apps on the CPU (LAT-12 was dropped).

## Drivers

| Project | Platform / macOS | Fit for us |
| --- | --- | --- |
| [WhateverXe](https://github.com/b00t0x/WhateverXe) 0.8.2 + [Graphics](https://github.com/b00t0x/WhateverXe-Graphics) 0.4.3 | TGL driver on RPL; Sequoia | **in use**. No perf release since: 0.4.4 only fixes H.264 encode [unverified beyond release notes] |
| NootedGreen (sgiammori) | RPL-P is its main dev platform; Sonoma 14.x listed | poor: needs the dGPU disabled (we keep the RTX), and its known issues include WindowServer freezes/hangs |
| NootedGreen forks ([XPS 13 Plus](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe), "ASUS V16") | Tahoe 26.7.1 | poor: Tahoe only; GT ~1300 MHz under load capped by PL4/IccMax; occasional hangs and panics |
| WTLIntelGfx (watchthelight-labs) | i915 + Mesa ANV on XNU, MTL/ARL | none: its own README sends TGL/ADL/RPL to WhateverXe/NootedGreen; same idea as our NMXGPU phase |
| VostroXe | ADL, NootedGreen + MGL OpenGL | none for this machine |

[inferred from the projects' READMEs and issues, read 2026-11-14]

## Patches and issues on WhateverXe

- No issue reports UI latency under GPU load [measured: issue search 2026-11-14].
- #109, SaqibAlMalik `tgl-stability` fork: `-wex-tgl-no-posh`, `-wex-mtl-poshfix`, `-wex-tgl-gpurec`; it also
  reports WindowServer memory growing ~200 MB/min. These are stability fixes, not speed fixes [inferred].
- Related open issues: #44 (checkForProgress stall), #72 (Stencil8/blit mix), #87 (DC6), #69 (Metal 3).

## Levers left (all keep apps on a GPU)

1. **GT clock / power limit.** GT was granted ~1100 MHz against a 1400 MHz RP0 request
   ([xe-latency.md](xe-latency.md)) [measured]. The forks above report PL4/IccMax capping the clock. Up to ~25%
   more throughput [inferred]. First step is to decode `N97GTPowerSample` under load (still undecoded).
2. **Fewer WindowServer effects** (Reduce Transparency). One AMD hackintosh report saw WindowServer load drop ~25%
   [unverified for Iris Xe]. It is a System Setting, so it needs Lukas's OK; it is undone with one toggle.
3. **Claude 2/3 rendered on the RTX** through the hybrid route (`ondemand.sh add`): their Metal work leaves the
   Iris Xe, and the Iris Xe only composites them ([../knowledge/hybrid-route.md](../knowledge/hybrid-route.md)).
4. **`tgl-stability` patches.** Worth trying only if hangs or WindowServer memory growth show up.
5. **RTX-only route.** NMH-1 failed on nullmoth 3.0; it stays parked.
