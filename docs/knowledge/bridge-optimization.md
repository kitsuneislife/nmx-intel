# Optimising the RTX → Intel panel bridge

> **Summary.** Each frame crosses memory three times today: the NVIDIA copy engine (CE) moves it from VRAM into a
> staging buffer, the CPU copies staging → IOSurface pages, then the CPU copies IOSurface → the Intel aperture with a
> `volatile` word loop. About 4 ms of CPU per frame at ~90–100 frames/s ≈ one third of a core, plus a tracing daemon
> that costs ~20 %. The target is Windows' CASO shape: the CE writes each frame straight into a system-memory buffer
> that the Intel display scans out, and the CPU touches no pixel. Stage 0 (build NVAccel from source) unlocks
> everything except stage 1. Written 2026-10-16 after RTX-16.

## Where the cost is today (2026-10-16, ~1 h after boot, Safari/Discord/Claude open)

| Step per frame | Who | Measured | Source |
| --- | --- | --- | --- |
| VRAM → contiguous staging (8,355,840 B) | NVIDIA CE (GPU), caller waits | 1.37–1.42 ms | [measured] log `surfvram pageoff: … on the copy engine -> 0 in 1419 us (staged)` |
| staging → IOSurface pages (`md->writeBytes`) | CPU, cached → cached | 1.25 ms | [measured] same line, `+ cpu 1252 us` |
| IOSurface → Intel aperture (`performTransaction`, `volatile` 4-byte loop, WC BAR2) | CPU | not timed | [measured, source] `nvrm-accel.cpp` ~line 1015 |
| frames per second while busy | | 89–98 | [measured] `debug.nvaccel_iop_ok` delta over 10 s |
| `kernel_task` / `WindowServer` CPU | | ~37–48 % / ~43–67 % | [measured] `top` |
| `log` + `diagnosticd` (nullmoth's `displaytrace` daemon, two `log stream`s) | | ~10 % + ~12 % | [measured] `top`, `ps` (parent `/Library/NullMoth/nullmoth-displaytrace.sh`) |

Other facts that shape the plan:
- [measured] `pageoff` runs once per frame (`nvrm_pageoff_coalesced` ≈ `iop_ok`), always staged (one 8 MB run).
- [measured, intelfb.cpp] NMIntelFB's `kva` is a write-combined map of the GOP surface in the aperture (stolen memory
  behind the GGTT); the VBL is a software timer at the measured refresh (144 Hz), not the pipe's real vblank.
- [measured] `surface_gpu_wait_max_us` ~101 ms and `timeouts` ~148 since boot: the stalls when apps open.
- [inferred] the two CPU copies (~1.25 ms + ~2–3 ms) at ~95 frames/s are most of `kernel_task`'s ~35 %; the per-frame
  CE wait (1.4 ms, more under load) is latency rather than CPU.
- [measured] `~/ogkm610` (NVIDIA `open-gpu-kernel-modules` tag 610.57.04, built for Darwin) is **not on this Mac**;
  `build/accel_build.sh` needs it (headers and `_out/Darwin_x86_64/compile_cmds.sh`). NMIntelFB we already build.

## The target: the CASO shape

Windows 11 "cross-adapter scan-out" (CASO) cut hybrid presentation from two copies to one: the render GPU copies its
frame into a cross-adapter surface in system memory and the display GPU scans out of that surface directly
([Microsoft: supporting CASO](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/supporting-caso),
[DirectX blog](https://devblogs.microsoft.com/directx/optimizing-hybrid-laptop-performance-with-cross-adapter-scan-out-caso/)).
Linux PRIME does the same with a shared system-memory buffer, and needs explicit sync between the two drivers to avoid
tearing ([NVIDIA forum: PRIME and PRIME sync](https://forums.developer.nvidia.com/t/prime-and-prime-synchronization/44423),
[Arch wiki: PRIME](https://wiki.archlinux.org/title/PRIME)).

Here that means:
1. NMIntelFB allocates two panel-sized buffers in ordinary RAM (wired, 4 KiB pages; contiguous is not needed) and
   points GGTT entries at them: `pte = phys | GEN8_PAGE_PRESENT`, written through the GTT alias at BAR0 + 8 MiB,
   then `GFX_FLSH_CNTL_GEN6` (0x101008) as `gen8_ggtt_invalidate` does (drm-kmod `gt/intel_ggtt.c`, `intel_gtt.h`;
   [12th-gen datasheet: GTTMMADR](https://edc.intel.com/content/www/it/it/design/publications/12th-generation-core-processor-datasheet-volume-2-of-2/graphics-translation-table-memory-mapped-range-address-gttmmadr0-0-2-0-pci-offse)).
2. NMIntelFB answers the scanout request with the back buffer's page list instead of a `kva` to copy into.
3. NVAccel's `pageoff` already takes a page list (`NVRMSurfPageoff.pages`, `nvrm_ce_copy_to_pages`): give it the
   Intel back buffer's pages and the CE writes the frame there. No staging, no `writeBytes`, no CPU loop.
4. When the CE completes, NMIntelFB writes the back buffer's GGTT offset to `PLANE_SURF` (latched at the next vblank)
   and swaps front/back. The transaction completes on the real vblank.

CPU per frame drops from ~4 ms to a few µs; PCIe traffic stays 8.3 MB per frame (same as today's CE copy).

## Work map

Each stage is one test (one variable), with a knob to undo it without a rebuild.

| # | Change | Where | Needs | Expected gain | Risk |
| --- | --- | --- | --- | --- | --- |
| 1 | Stop nullmoth's `displaytrace` (`launchctl bootout` + keep the plist aside) | system config | nothing | ~20 % of a core [measured] | none; loses nullmoth's display trace for bug reports |
| 0 | Build NVAccel from source; install it identical in behaviour, compare hash/symbols | `~/ogkm610` @ 610.57.04, `accel_build.sh` | Darwin RM build of ogkm (`compile_cmds.sh`), same ABI as the installed NVRM | none by itself; unlocks 2–6 | ABI mismatch → black desktop (README: rebuild both accelerators when the ABI headers change); keep the release kext to restore |
| 2 | Replace the `volatile` word loop with a plain row copy (`memcpy`, or non-temporal stores for the WC target) | `performTransaction` | 0 | the 3rd copy several times faster [unverified] | low |
| 3 | Copy staging → Intel `kva` directly; skip `writeBytes` into the IOSurface when the frame goes to a CPU scanout | `pageoff` / `performTransaction` | 0, 2 | −1.25 ms CPU per frame [measured cost] | the IOSurface's system copy goes stale: anything reading it on the CPU (screenshots?) would need the old path; keep a knob |
| 4 | **CASO**: CE writes into Intel scanout pages; double buffer + `PLANE_SURF` flip | NMIntelFB (GGTT, flip) + NVAccel (page list, completion) | 0 | CPU copies gone (~35 % of a core) and no tearing | GGTT writes wrong = garbage or a GPU hang; display not coherent with CPU caches (never write those pages through a cached map); the CE copy must finish before the flip |
| 5 | Real vblank: arm the pipe's vblank interrupt (or poll `PIPE_FRMCOUNT`) instead of the 144 Hz timer; complete transactions on it | NMIntelFB | 4 | frames paced to the panel, fewer wasted frames | interrupt wiring under NVRM; timer stays as fallback |
| 6 | Damage only: copy just the changed rectangle (CE 2D copy) when the transaction carries one | NVAccel | 4, plus finding whether `IOAccelDisplayPipeTransaction2` exposes dirty regions [unverified] | little traffic when only a cursor or a caret moves | unknown API |
| 7 | Measure power: battery draw (`ioreg` `AppleSmartBattery` amperage/voltage) idle and busy, before/after | — | on battery | numbers for the README | none |

Not in scope here: the GPU wait spikes (~100 ms, `surface_gpu_timeouts`) are an NVRM/NVMTL matter seen before this
bridge existed; stage 4 removes the bridge's share of them (no lock-and-wait for the system copy). The RTX stays
powered while it composites; lower idle power belongs to path A (Intel Metal).

## Stage 0 status (2026-10-16)

Builds: `tools/accel/build.sh` (branch `nmx-accel` at nullmoth v2.1.0, the installed release) reproduces the
installed binary's strings, symbols and data sections; `__text` differs by 112 B [inferred: compiler]. Note that the
swap wait behind `surface_gpu_wait_max_us` ~101 ms is v2.1.0's `nvaccel_surface_gpu` (commit `e75be1e`), so it is in
reach too. RTX-17 runs the unchanged build on the Mac before any change.

## Order

1 now (config only) → 0 (the gate) → 2 and 3 (small, prove the build works and halve the CPU) → 4 (the real fix) →
5 → 7. 6 only if 4–5 leave a measurable cost.
