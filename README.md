# nmx-intel

Hardware acceleration on a hackintosh laptop whose internal panel is wired to the Intel iGPU, with no MUX switch.

macOS has no driver for Intel iGPUs newer than Ice Lake, so on a laptop like this the panel normally runs on the
firmware framebuffer: no Metal, software compositing, choppy animations. This repo uses the NVIDIA card instead. The
RTX runs on [nullmoth's driver](https://github.com/nullmoth/nvidia-macos-driver) and composites the whole desktop with
Metal, and NMIntelFB (a small framebuffer kext from nullmoth's tree, with our patches) shows each frame on the Intel
panel.

Tested on one machine: Acer Nitro V15 ANV15-51, i5-13420H (iGPU `8086:a7a8`, Raptor Lake-P), RTX 3050 Laptop,
macOS Sequoia 15.8.1, nullmoth's driver 2.3.6. There, wallpaper, transparency, animations and YouTube are smooth;
WindowServer dropped from about 225 % CPU to 67 %, and copying a frame to the panel takes 1.4 ms. Brightness keys
work too.

## Will it work on my laptop?

You need all of these:

- An NVIDIA GPU that nullmoth's driver supports. Check its README first; if the driver doesn't run on your card,
  nothing here helps.
- The internal panel on the Intel iGPU. If your HDMI or USB-C port is wired to the NVIDIA card, an external monitor
  already works with nullmoth's driver alone.
- An Intel iGPU with display version 12 or 13 (Alder Lake, Raptor Lake). The accepted device IDs are in
  `kexts/NMIntelFB/display_ids.inc` in nullmoth's repo, generated from Linux's `pciids.h`. Anything outside that
  list is ignored.
- macOS Sequoia already booting with OpenCore, with the panel working on the firmware framebuffer.
- Xcode Command Line Tools (`xcode-select --install`), git, and internet access during the build (it downloads a
  few NVIDIA headers).
- nullmoth's driver 2.3.6. The patches are built and tested against that release; for a newer one, see
  [docs/knowledge/nullmoth-upgrade.md](docs/knowledge/nullmoth-upgrade.md).

To see your iGPU's device ID:

```bash
system_profiler SPDisplaysDataType > ~/gpus.txt
```

Look for the Intel entry and its "Device ID". Only `0xa7a8` has been tested. Other Alder Lake-P and Raptor Lake IDs
use the same display registers and should behave the same, but nobody has tried yet.

## Install

1. Install nullmoth's NVIDIA driver with its 1401 app and reboot. Keep the app's "AMD / Intel" test driver off.
   Before going on, check that the NVIDIA card shows up in System Information with Metal support.

2. Get the sources. The build script expects nullmoth's repo in `~/nmx-build`:

   ```bash
   git clone https://github.com/kitsuneislife/nmx-intel ~/nmx-intel
   ```

   ```bash
   git clone https://github.com/nullmoth/nvidia-macos-driver ~/nmx-build/nvidia-macos-driver
   ```

3. Build NMIntelFB. It ends by printing the kext's hash and size:

   ```bash
   bash ~/nmx-intel/tools/intelfb/build.sh
   ```

4. Install it. This copies the kext to `/Library/Extensions` and rebuilds the auxiliary kext collection, keeping a
   backup of the old one in your home folder:

   ```bash
   sudo bash ~/nmx-intel/tools/intelfb/install.sh
   ```

5. Make NMIntelFB wait 45 seconds before taking the panel. That is how it has always run here; booting without the
   wait froze once and hasn't been retested since.

   ```bash
   sudo nvram nullmoth-intelfb-delay=45
   ```

6. Install the boot job that switches the accelerated desktop on at every boot:

   ```bash
   sudo bash ~/nmx-intel/tools/intelfb/auto.sh install
   ```

7. Turn sleep off. After S3 the Intel display engine comes back with every register at zero and nothing relights the
   panel yet.

   ```bash
   sudo pmset -a disablesleep 1
   ```

8. Reboot. The boot logo stays about 45 seconds longer than usual, then the login window appears on the panel.

To check that frames are going through NMIntelFB, this number should keep growing while something moves on screen:

```bash
sysctl debug.nvaccel_iop_ok
```

## If something goes wrong

- Black screen at boot: pick "Start once without NVIDIA driver" in the OpenCore picker, or add `-nvoff` to the
  boot-args for one boot. NMIntelFB stays off too, and the firmware framebuffer gives you a desktop.
- `-nmintelfboff` in boot-args, or `sudo nvram nullmoth-intelfb=0`, turns NMIntelFB off without removing it.
- If a start of NMIntelFB never returns, the next boot skips it on its own. Run
  `sudo nvram -d nullmoth-intelfb-attaching` to let it try again.
- nullmoth's driver turns itself off after two starts that never lit a display. If that happens after forced
  power-offs, clear the counter with `sudo nvram -d nullmoth-nv-starts`.
- `nvram nullmoth-intelfb-trail` shows the last step NMIntelFB reached, even when a boot froze before the log was
  saved. More tokens and logs: [docs/knowledge/diagnostics.md](docs/knowledge/diagnostics.md).
- `sudo bash ~/nmx-intel/tools/upgrade/rollback.sh <backup dir>` puts back the NVIDIA driver that nullmoth's
  installer backed up in `/Library/NullMoth/backup-*` before an upgrade.
- To remove everything: `sudo bash ~/nmx-intel/tools/intelfb/auto.sh remove`, then
  `sudo bash ~/nmx-intel/tools/intelfb/install.sh remove`, then reboot.

## Known limits

- Sleep breaks the panel (see step 7). Two attempts with hibernation failed:
  [docs/tests/sleep-1-hibernate.md](docs/tests/sleep-1-hibernate.md).
- One display only, the internal panel at its native mode.
- The NVIDIA card stays on all the time. Battery cost hasn't been measured.
- The 45-second wait adds that much to every boot.

## Faster copies (optional)

Two more changes cut the per-frame cost on the test machine: a patched NVAccel that has the RTX copy engine write straight
into the panel's memory, and a byte patch that makes NVRM sleep instead of spin while it waits for that copy. They
need a more involved build (NVIDIA's open-gpu-kernel-modules sources and a worktree of nullmoth's repo) and must be
redone for each nullmoth release. `auto.sh` turns them on when it finds them. Runbook:
[docs/knowledge/nullmoth-upgrade.md](docs/knowledge/nullmoth-upgrade.md); background:
[docs/knowledge/bridge-optimization.md](docs/knowledge/bridge-optimization.md).

## The i915 experiment

Before the NVIDIA route, this repo ported Linux's i915 to macOS through nullmoth's NMXGPU (its drm-kmod port, enabled
by the 1401 app's "AMD / Intel" test driver). i915 drives the panel at 1920x1080, 144 Hz, and the desktop is stable,
but WindowServer still composites in software, so it is parked. Build steps and history are in
[docs/index.md](docs/index.md); the sources live in `build/` and `source-fixes/`.

## Repo layout

```
tools/intelfb/   build, install and boot job for NMIntelFB (the route above)
tools/accel/     patched NVAccel (optional speedup)
tools/nvrm/      NVRM byte patch (optional speedup)
tools/sleep/     hibernation experiment (parked)
tools/upgrade/   nullmoth driver upgrade, with rollback.sh
tools/wifi/      MediaTek MT7921 Wi-Fi (native menu, 5 GHz, ~37 Mbit/s up and down)
tools/mirror/, libdrm/, probe/, vram/, binpatch/   i915 port helpers and diagnostics
tools/agent/     installs the Claude Code skills used here
source-fixes/    our patches: intelfb/, accel/, and the i915 port
build/           i915 port: set up ~/nmx-build, apply fixes, build NMXGPU
docs/            status, test logs, knowledge base (start at docs/status.md)
```

## License

nullmoth's code is PolyForm Noncommercial 1.0.0 (personal and research use). This repo ships only scripts and diffs,
never binaries, so you build the kexts yourself.

<div align="center">
  <img src="claude.png" width="300" height="300">
  <p>kitsuneislife, 2026</p>
</div>
