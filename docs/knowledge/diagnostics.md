# Diagnostics: reading a boot, knobs, tools

> **Summary.** After any test boot (or the `-nvoff` boot after a freeze) read three NVRAM variables, then panics, then
> logs. Behaviour can be bisected with NVRAM knobs without rebuilding.

## After a test boot

```
nvram nullmoth-gpu-trail      # steps; ends with " @<ms since attach>" from the beat
nvram nullmoth-gpu-beat       # last heartbeat
nvram nullmoth-gpu-io         # userspace requests and GPU power events
nvram nullmoth-gpu-attaching  # 1 = the attach never returned (NMXGPU parks the GPU next boot)
ls -lt /Library/Logs/DiagnosticReports | head   # Kernel-*.panic (JSON; the panic string is "macOSPanicString")
/usr/bin/log show --last boot --predicate 'sender == "NMXGPU"'          # if the boot did not freeze
/usr/bin/log show --last boot --predicate 'process == "WindowServer"'
```
Lukas cannot type `|`: when he runs commands, write to a file and `grep`/`tail` the file.

## Trail tokens (`nullmoth-gpu-trail`)

| Token | Meaning |
| --- | --- |
| `attach` `beat` | attach thread started; heartbeat thread started |
| `hold` / `hold-fail` | GGTT range of the boot fb held in `init_ggtt` (0007) |
| `shold` / `shold-fail st<start>+<size>` / `shold-none` | GOP stolen pages held (0014) |
| `attached` / `no-driver` | i915 attach done |
| `noaccel` | NMXAccel not claimed (0024/0026) |
| `publish` / `publish-nofb` / `nopub` | display publishing per `nullmoth-gpu-fb` |
| `probe` `i915-fb` | bridge probe; i915 path chosen |
| `take-pin` `took` / `fallback` | GOP fb takeover; `tk-<reason>` on failure (`tk-obj<err>@<off>+<size>` etc.) |
| `fb-pin` `iomap` `commit` `lit` / `commit-fail` | bridge buffer pinned, mapped, modeset done |
| `client-reg` `hotplug` `registered` | DRM client registered |
| `fb-new` `fb-dep` `fb-start` `fb-shadow`/`fb-noshadow` `fb-started` `fb-pm` `fb-reg` | `NMXGPUFB` creation |
| `ndrv-c<children>-<found>` `ndrv-wait` `ndrv-term` `ndrv-gone` `ndrv-timeout` | firmware fb removal (0028–0030) |
| `published` / `no-fb` | attach finished (attaching cleared) |
| `fb-con` `fb-ap` `fb-cur` `fb-tim` `fb-irq` `fb-novbl` `fb-ga` `fb-gac` `fb-sa` `fb-sac` `fb-pix` `fb-inf` `fb-modes` `fb-cf` `fb-gam` `fb-clut` `fb-ps0/1` `fb-en` | first call of each IOFramebuffer method (0013) |
| `fb-vram` `fb-setmode` | WindowServer took the VRAM / set the mode |
| `fb-vbl` `fb-vbl-on` `fb-vbl-off` | VBL delivered / enabled / throttled |
| `fb-copy` | first shadow → aperture copy (0032) |
| `ws-on/off`, `fb-pwr-on/off` | WindowServer attribute, power attribute |

## Heartbeat (`nullmoth-gpu-beat`)
`ms` since attach · `open` DRM opens · `ioctl` count · `in` ioctls in flight · `cmd` last ioctl · `rcu` waiters in
`synchronize_rcu` · `irq` GPU interrupts so far · `iot` ms of the newest io token. Every 0.5 s in minute 1, then 1 s to
10 min. If it stops early, the machine (or the NVRAM path) died then.

## Request log (`nullmoth-gpu-io`)
`o<pid>` open · `c` close · `<g><nr>` ioctl start (`d` = DRM, `N` = port mmap) · `+` ok · `-<errno>` failed ·
`Gu`/`Gp` GT unpark/park · `Rs`/`Rr` runtime suspend/resume · `D<n>` DC state. Newest ~470 chars.

## Knobs (`sudo nvram <name>=N`; `sudo nvram -d <name>` restores the default)

| Knob (boot-arg) | Default | Effect |
| --- | --- | --- |
| `nullmoth-gpu-fb` (`nmxfb`) | 1 | 1 publish `NMXGPUFB`; 2 light the panel only (IONDRV draws); 0 no bridge |
| `nullmoth-gpu-con` (`nmxcon`) | 1 | `NMXGPUFB` claims to be the console |
| `nullmoth-gpu-accel` (`nmxaccel`) | 0 | 1 claims the GPU for NMXAccel (WindowServer then loops; see pitfalls) |
| `nullmoth-gpu-fbdep` (`nmxfbdep`) | 1 | own `IOFBDependentID` before start |
| `nullmoth-gpu-ndrv` (`nmxndrv`) | 1 | remove the firmware IONDRV after it opens |
| `nullmoth-gpu-vbl` (`nmxvbl`) | 0 | 1 offers the timer VBL |
| `nullmoth-gpu-shadow` (`nmxshadow`) | 1 | shadow framebuffer in RAM |
| `nullmoth-intelfb*` | — | NMIntelFB only: `=0`, `-dep` (1 own controller, 2 NVRM's group, 0 plain), `-head` (0 default, 4), `-kapi` (1, 0 = no NVKMS device), `-vbl` (1 always, 0 follow `setInterruptState`), `-nvparent` (1 under NVRM, 0 on GFX0), `-scanres` (1 VRAM scanout resource, 0 phys 0), `-pm`, `-delay` |

## Tools

| Tool | Use |
| --- | --- |
| `tools/probe` | LaunchDaemon; at 45 s and 120 s writes DRM/libdrm/ANV/IOKit state to `/Users/Shared/nmx-probe.txt` |
| `tools/vram/dump.c` | maps `NMXGPUFB` VRAM like WindowServer (shared client type 1, memory type 110), writes a PPM |
| `tools/vram/watch.c` | samples VRAM tiles over time (flip-flopping regions); slow on the aperture |
| `tools/vram/displays.c` | CoreGraphics online/active displays, bounds, mirroring, cursor position |
| `sysctl debug.nmintelfb_agdc` | NMIntelFB's AGDC: write 1 to start (enable.sh); reads 1 up, 2 starting, < 0 failed |
| `tools/mirror` | LaunchAgent mirroring the ghost firmware display (with `NMXGPUFB` or `NMIntelFB`); log: `log show --last 1h --predicate 'process == "nmx-mirror"'` |
| `tools/intelfb/auto.sh` | LaunchDaemon: `enable.sh` + WindowServer restart at the login window every boot; `nullmoth-intelfb-auto=0` off; log: `log show --last 10m --predicate 'eventMessage CONTAINS "nmx-intelfb-auto"'` |
| `tools/accel/build.sh`, `install.sh` | build NVAccel from branch `nmx-accel` (v2.1.0) with `~/ogkm610`; install into `/Library/Extensions` + aux KC; `install.sh restore` puts nullmoth's back (`~/NVAccel.kext.original`). The 1401 app may copy its own NVAccel back when the driver is toggled |
| `tools/checkpoint.sh` | before every install: `save <name>` (no sudo) copies NV*/NM* kexts, the aux KC and nullmoth-* knobs to `~/nmx-checkpoints/<date>-<name>` with a verified SHA256 list; `sudo … restore <dir>` puts them back (reboot after). First one: `20261016-233841-rtx16-funcionando` (NMIntelFB 1d3ea017, NVAccel f0edef4e, NVRM 12fcabf3, NVRMFB 0a75504b, NVRMAGDC 223a327f) |
| `top -o cpu`, `ps -M <pid>` | WindowServer CPU and per-thread load (`sample` needs root) |

## Recovering
- Freeze: power off, boot with OpenCore **Space → Start once without NVIDIA driver** (`-nvoff` disables NMXGPU too),
  read the variables above.
- `attaching=1` parks the GPU: toggle the AMD/Intel test driver in the 1401 app to retry.
- Original binary: `sudo bash tools/binpatch/apply.sh restore`. Recovery: delete `/Library/Extensions/NMXGPU.kext`.
