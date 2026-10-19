# nmx-intel

Getting a smooth macOS desktop on the internal panel of an Acer Nitro V15 ANV15-51. The panel is wired only to the Intel
GPU (`8086:a7a8`, Raptor Lake-P, Xe-LP) and there is no MUX, so there are two paths:

- **Path B (the one in daily use):** the RTX 3050 composites the desktop with Metal and **NMIntelFB** puts each frame on
  the Intel-wired panel. It starts by itself at boot (`tools/intelfb/auto.sh`).
- **Path A (parked, fallback):** the Intel GPU through **NMXGPU**, nullmoth's port of Linux i915 to xnu. It gives a
  stable software desktop; Intel Metal is not working yet.

Base: nullmoth `nvidia-macos-driver` 2.3.6 (with our patches), macOS Sequoia 15.8.1, 1401 app.

## Status

| | |
| --- | --- |
| Accelerated desktop on the internal 1080p 144 Hz panel (RTX 3050, Metal, path B) | ✅ |
| Wallpaper, animations, transparency, YouTube | ✅ (one short stall when the session starts) |
| Automatic at boot | ✅ |
| Brightness | ✅ |
| Wi-Fi (MT7921, native menu, 5 GHz, ~37 Mbit/s up and down) | ✅ |
| i915 drives the panel through our IOFramebuffer (path A, software desktop with `tools/mirror`) | ✅ |
| ANV (Intel Vulkan) sees the GPU | ✅ |
| Intel Metal (WindowServer on the Intel GPU) | ❌ parked |
| Sleep | ❌ S3 resets the Intel display engine and nothing relights it; sleep is disabled |

Open: cost per frame, booting without the 45 s delay, `Invalid display` messages in WindowServer, battery cost of
keeping the RTX on.

Details: [docs/status.md](docs/status.md). Knowledge base: [docs/index.md](docs/index.md).

## Layout

```
build/          set up ~/nmx-build, apply fixes, build and install NMXGPU (path A)
source-fixes/   source patches: 00NN-*.patch (nullmoth and drm-kmod), intelfb/, libdrm/
tools/
  intelfb/      NMIntelFB: shows the RTX-rendered frames on the Intel panel (path B); auto.sh enables it at boot
  accel/        NVAccel build and install (direct copy path)
  nvrm/         NVRM build and install
  upgrade/      nullmoth NVIDIA driver upgrade, with rollback.sh
  wifi/         MT7921 Wi-Fi driver build and install
  sleep/        sleep and hibernate experiments (hibernate.sh)
  mirror/       mirrors the firmware's ghost display (LaunchAgent, path A)
  libdrm/       builds and installs the fixed libdrm
  probe/        boot-time diagnostics (/Users/Shared/nmx-probe.txt)
  vram/         reads framebuffer memory, lists WindowServer displays
  binpatch/     legacy byte patches and restoring the original binary
  agent/        installs the Claude Code skills used here (graphify, ponytail, caveman)
docs/           status, test index and phase logs, knowledge articles, archived original log
```

## Build and install (path A, NMXGPU)

```
bash build/setup.sh                # once: sources in ~/nmx-build
bash build/apply-fixes.sh          # applies source-fixes/ (skips what is already applied)
bash build/build-all.sh rt kext    # -> ~/nmx-build/out/NMXGPU.kext
sudo bash build/install.sh         # replaces the binary the 1401 app uses
```

Then: in the 1401 app, turn the **AMD / Intel** test driver off and on; `sudo bash tools/libdrm/install.sh`;
`sudo bash tools/mirror/install.sh` (once); reboot. After boot, `nvram nullmoth-gpu-trail` and
`nvram nullmoth-gpu-beat` show how far the driver got ([docs/knowledge/diagnostics.md](docs/knowledge/diagnostics.md)).

Path B (NMIntelFB, NVAccel, NVRM) has its own installers under `tools/`; the current install state and the steps are in
[docs/status.md](docs/status.md).

## Safety

- NMXGPU only runs with `nmxintel=1`, which the app sets and removes.
- An attach that never returns makes NMXGPU park the GPU on the next boot; toggling the driver in the app retries.
- Forced power-offs can trip nullmoth's boot guard; `sudo nvram -d nullmoth-nv-starts` clears it.
- OpenCore: **Space** → **Start once without NVIDIA driver** (`-nvoff`) also disables NMXGPU.
- `sudo bash tools/binpatch/apply.sh restore` returns to the release binary; `tools/upgrade/rollback.sh` undoes the
  NVIDIA driver upgrade.
- From Recovery: delete `/Library/Extensions/NMXGPU.kext`.

## License

nullmoth's code is PolyForm Noncommercial 1.0.0 (personal and research use). This repository ships no binaries,
only scripts and diffs.

<div align="center">
  <img src="claude.png" width="300" height="300">
  <p>kitsuneislife, 2026</p>
</div>
