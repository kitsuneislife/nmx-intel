# Hybrid route: Iris Xe composites, the RTX renders chosen apps

> **Summary.** Proposal (2026-10-21, nothing tested). Apple's Tiger Lake driver, made to run on Raptor Lake by
> JulioNectar's NootedGreen fork, would drive the panel and WindowServer. nullmoth's driver would run headless: apps on
> its allow-list get the RTX as their Metal device and hand finished frames to WindowServer through system memory.
> Julio's build runs on Tahoe 26.7.1 only. Lukas wants it on Sequoia 15.8.1 (24H32), and nothing in the approach
> requires Tahoe: see "Porting to Sequoia". It would be a second install route next to GPU-only, not a replacement.
> Plan: phases H0–H4 below.

## What exists today

### JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe (created 2026-10-21)

- [measured, read from the repo] Metal desktop on a Dell XPS 13 Plus 9320 (i7-1360P, Iris Xe `8086:A7A0`, 96 EU),
  macOS **Tahoe 26.7.1 (25G241) only**. The iGPU is spoofed as TGL `9A49`. Apple's GPUDriversIntel 16.0.32 TGL kexts
  load from `/Library/Extensions` and are patched in memory by a NootedGreen fork (`-ngreenxefix` and others). In user
  space, the TGL Metal driver is byte-patched, `libxedrv` converts Tahoe's Metal structures to the 2020 layout, and the
  old IGC shader compiler runs inside Tahoe's `MTLCompilerService` through an LLVM bridge. Needs
  `amfi_get_out_of_my_way=1`.
- Works there: desktop, Dock, Liquid Glass, 60 Hz animations, HEIC, icons, YouTube in Chrome (software decode), screen
  recording.
- Open problems there: a GPU hang after about an hour or heavy browser use (WindowServer watchdog, then reboot), a
  panic at shutdown, System Settings › Displays can panic, brightness keys do nothing, hardware video decode is off,
  and Chrome's own GPU path draws blank windows.
- The Tahoe offsets (`IOSurface +0x98/+0x80`), the Metal adapter and the LLVM 32023 bridge are all Tahoe-specific. The
  author's earlier Sequoia work was a separate, self-written stack that was abandoned.
- License: Thou Shalt Not Profit 1.0 (NootedGreen's). Apple binaries are not in the repo; install fetches them from
  NootedGreen's `sle_Internal` folders.
- Related: upstream NootedGreen (sgiammori, forks by CHN-Fancy and others) and issue sgiammori/NootedGreen#20, where
  real Tiger Lake reached Metal init on Sonoma. Nobody else reports a working Raptor Lake desktop.

### nullmoth already has the other half [measured, read from v2.3.6 source]

- **Headless mode**: `kexts/NVRM/accel/nvrm-accel.cpp` `armHeadlessCheck()`. If no NVIDIA display head appears 60 s
  after start, NVAccel restores `MetalPluginName` without arming, sets `NVAccelHeadless` and `debug.nvaccel_headless=1`.
  `-nvaccelnoheadless` turns this off.
- `plugin/NVMTLDevice.m` `nvmtl_process_is_allowed()`: when headless, WindowServer gets **no** NVIDIA device ("it
  composites on the GPU that owns the display, as on Apple's two-GPU Macs").
- `plugin/nvmtl_vk.c` `nvmtl_gpu_headless()`: when headless, IOSurfaces are copied out to system memory, so another
  GPU's WindowServer can read them.
- **Per-process routing already exists**: `/Library/GPUBundles/nvmtl-allow.txt`. One process name per line: `*` matches
  all, `!Name` means only while armed, `-Name` denies. Installed today: `*` and `!WindowServer`.
- Upstream issues nullmoth/nvidia-macos-driver#76 (muxless GTX 1650) and #106 (GTX 1660 Ti with the panel on a natively
  accelerated UHD 630) are about this layout. Both are still open. #106 is the closest public case to the hybrid; no
  report there shows an app rendering on the NVIDIA card while the Intel GPU composites.
- nullmoth is at 2.4.3 now (2026-10-20). 2.4 fixed macOS 26 icons and glass menus. Our patches are on 2.3.6.

## Porting to Sequoia (decided 2026-10-21: target Sequoia, not Tahoe)

Tahoe was Julio's choice, not a requirement: his HISTORY gives no technical reason, and his phase-0 work ran on
Sequoia. Upstream NootedGreen itself targets up to `KernelVersion::Sequoia` (tested on Sonoma 14.7.1); his fork had to
raise that limit for Tahoe. What carries over and what must be redone [inferred from reading his repo]:

| Layer | Sequoia status |
|---|---|
| TGL Metal driver byte patches (`mtl17-patches.json`) | offsets are inside Apple's 16.0.32 binary, OS-independent: carry over |
| TGL kext patches in NootedGreen (display 13, scheduler, CSB guard, GTFREQ, FBDPMS, BLITALIGN...) | same 16.0.32 kexts: carry over |
| IOSurface offsets (PLANES2 `+0x98`, XE-FMT `+0x80`) | Tahoe layout; Sequoia keeps the older one (`-ngreenplanesxor` path, `+0xb0`), to re-measure on 24H32 |
| IOAcceleratorFamily2 patches (XE-NOORPHAN, BLITSCRATCH2, pool, page-on) | byte patterns for Tahoe 25G241; `LookupPatchPlus` fails safely, so each must be re-found on Sequoia |
| `libxedrv` (463 lines) descriptor ABI | converts Tahoe's Metal structures (misc union at `0xe0`) to the 16.0.32 layout (`0xd0`). Sequoia sits between the two; its preflight refuses to convert on a layout it does not know, so it fails safely. The gap is likely smaller on Sequoia |
| Shader compiler adapter + LLVM bridge | Sequoia's compiler service is LLVM 32024 (his HISTORY quotes a Sequoia offset). `build-shader-compiler.sh` regenerates the libLLVM stub from the running system; the entry-point mapping needs checking |
| nullmoth | already runs here on Sequoia |

Most of the port can be done from the running GPU-only system without rebooting: disassemble Sequoia's IOSurface,
IOAcceleratorFamily2 and Metal (his `kcsyms.py`/`kcdis.py`), compare with his Tahoe values, and fill the table above
with measured values.

Coexistence on one disk: Apple's TGL kexts in `/Library/Extensions` match only the spoofed `9A49`. Without the spoof
and NootedGreen in the EFI they stay idle [inferred], so the switch between routes is the OpenCore config (a
`config-hybrid.plist` next to the current one), not the macOS install.

## How the routing would work

1. Process not on the allow-list (or denied with `-Name`): it sees only the Iris Xe Metal device, so it renders on
   the Iris Xe. Default for the system: WindowServer, Dock, Finder, menu extras.
2. Process on the list: it sees both devices. Which one it uses depends on the app [unverified on this setup]:
   - apps that enumerate devices (`MTLCopyAllDevices`: games, Blender, Chrome/ANGLE's high-performance choice) pick
     the RTX themselves;
   - apps that call `MTLCreateSystemDefaultDevice` get whatever macOS calls the default. On a hackintosh without
     Apple's GPU switching this has to be measured (H2);
   - Finder's per-app "Prefer External GPU" checkbox and the `GPUSelectionPolicy=preferRemovable` key only act on a
     GPU Metal calls removable. Tahoe's shared cache contains `IOPCITunnelled` next to the removable-GPU code
     [inferred], so marking the RTX as tunnelled may make it removable and bring back Apple's own per-app switch. To
     be tested; it may have side effects (eject UI, apps avoiding it).
3. Frames rendered on the RTX travel to WindowServer through system memory, as on an eGPU Mac. That costs one PCIe
   copy per frame of that app, which suits video, Discord and games, not tiny UI apps. That is why the desktop stays on
   the Iris Xe.

## Differences on our Acer to check first

- iGPU `8086:a7a8` is RPL-P **GT1** (UHD, fewer EUs); the XPS is GT2 `A7A0` with 96 EU. NootedGreen hard-codes the
  6-DSS topology, and its CATALOG lists a disabled GT1 override (`f3a/r3a`) [unverified for us].
- Panel: 1920x1080 at 144 Hz on eDP vs 3840x2400 at 60 Hz. The TGL framebuffer's link training on display 13 is
  fragile there, and it is also why XE-FBDPMS exists.
- The XPS runs with the E-cores off. The Acer runs with them on.
- NMIntelFB must not run in this route: the TGL framebuffer owns the panel. With the device spoofed to `9A49`,
  NMIntelFB's ID list no longer matches [inferred], but the hybrid install should remove it anyway.
- Battery: the RTX stays powered in both routes. nullmoth has no runtime power-off yet [inferred from the changelog].

## Plan

| Phase | Change (one variable) | Gate |
|---|---|---|
| H0 | Offline port, no reboot: measure Sequoia 24H32 offsets and patterns for every Tahoe-only row above; build NootedGreen, the patched Metal driver, `libxedrv` and the compiler for Sequoia | every Tahoe-only row has a measured Sequoia value; builds verified (hash, symbols) |
| H1 | Iris Xe alone: `config-hybrid.plist` (spoof `9A49`, NootedGreen, boot-args) with nullmoth off (`-nvoff`); first boots display-only, then the accelerator | Metal desktop on the Iris Xe, 1 h without a GPU hang |
| H2 | nullmoth on, headless (no NMIntelFB) | `debug.nvaccel_headless` reads 1; `system_profiler` lists both GPUs with Metal; a small test tool renders on the RTX and shows on the panel; measure which device `MTLCreateSystemDefaultDevice` returns |
| H3 | Routing: `tools/hybrid/route.sh` writes `nvmtl-allow.txt` from a short app list (browsers, Discord, video players, games → RTX); then try the `IOPCITunnelled` removable trick for Apple's own checkbox | YouTube and a game render on the RTX (`sysctl`/nvlog evidence) while WindowServer stays on the Iris Xe |
| H4 | Repo: README gets "Choose a route" (GPU-only: stable; Hybrid: experimental); `tools/hybrid/`, `docs/tests/hybrid-1.md` | a clean install from the README on the Acer |

Repo shape: we do not copy Julio's code or Apple's binaries. `tools/hybrid/` clones his repo at a pinned commit and
applies our Acer diffs from `source-fixes/hybrid/`, the same way `tools/intelfb/` builds NMIntelFB from nullmoth. Credit
and link him in the README, and send GT1 / Acer findings back upstream.

## Risks

- His stack is days old and moves daily. The GPU hang after about an hour would make the hybrid route worse than
  GPU-only for daily use until it is fixed.
- Porting to Sequoia means re-finding Julio's Tahoe-only fixes ourselves; any we miss show up as the same panics he
  hit (orphan pool, resolve, green YUV). His HISTORY is the map.
- The current route must stay one config swap away: H1 boots only from `config-hybrid.plist`.
- GT1 may not run at all with the GT2 topology NootedGreen assumes.
- Two IOAccelerator families in one session (Apple TGL plus nullmoth) have not been seen together on any machine.
