# nmx-intel

Bringing the Intel display (`8086:a7a8`, Raptor Lake-P, Xe-LP) of an Acer Nitro V15 ANV15-51 to macOS through
**NMXGPU**, nullmoth's port of Linux i915 to xnu. The internal panel is wired to the Intel GPU and there is no MUX.

Base: nullmoth `nvidia-macos-driver` 2.0.2, macOS Sequoia 15.8.1, 1401 app. The RTX 3050 runs on the stock driver and
is not affected by anything here.

## Status

| | |
| --- | --- |
| i915 drives the panel (1920x1080 @ 144 Hz) through our IOFramebuffer | ✅ |
| Stable desktop, no glitches (with `tools/mirror`) | ✅ |
| ANV (Intel Vulkan) sees the GPU | ✅ |
| Accelerated desktop (WindowServer on the GPU) | ❌ software compositing |

Details: [docs/status.md](docs/status.md). Knowledge base: [docs/index.md](docs/index.md).

## Layout

```
build/          set up ~/nmx-build, apply fixes, build and install NMXGPU
source-fixes/   source patches: 00NN-*.patch (nullmoth and drm-kmod), intelfb/, libdrm/
tools/
  mirror/       mirrors the firmware's ghost display (LaunchAgent)
  libdrm/       builds and installs the fixed libdrm
  probe/        boot-time diagnostics (/Users/Shared/nmx-probe.txt)
  vram/         reads framebuffer memory, lists WindowServer displays
  intelfb/      nullmoth's NMIntelFB (RTX path, parked)
  binpatch/     legacy byte patches and restoring the original binary
  agent/        installs the Claude Code skills used here (graphify, ponytail, caveman)
docs/           status, test index and phase logs, knowledge articles, archived original log
```

## Build and install

```
bash build/setup.sh                # once: sources in ~/nmx-build
bash build/apply-fixes.sh          # applies source-fixes/ (skips what is already applied)
bash build/build-all.sh rt kext    # -> ~/nmx-build/out/NMXGPU.kext
sudo bash build/install.sh         # replaces the binary the 1401 app uses
```

Then: in the 1401 app, turn the **AMD / Intel** test driver off and on; `sudo bash tools/libdrm/install.sh`;
`sudo bash tools/mirror/install.sh` (once); reboot. After boot, `nvram nullmoth-gpu-trail` and
`nvram nullmoth-gpu-beat` show how far the driver got ([docs/knowledge/diagnostics.md](docs/knowledge/diagnostics.md)).

## Safety

- NMXGPU only runs with `nmxintel=1`, which the app sets and removes.
- An attach that never returns makes NMXGPU park the GPU on the next boot; toggling the driver in the app retries.
- OpenCore: **Space** → **Start once without NVIDIA driver** (`-nvoff`) also disables NMXGPU.
- `sudo bash tools/binpatch/apply.sh restore` returns to the release binary.
- From Recovery: delete `/Library/Extensions/NMXGPU.kext`.

## License

nullmoth's code is PolyForm Noncommercial 1.0.0 (personal and research use). This repository ships no binaries,
only scripts and diffs.
