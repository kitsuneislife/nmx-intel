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
| `tools/intelfb/auto.sh` | LaunchDaemon: `enable.sh` + WindowServer restart at the login window every boot; `nullmoth-intelfb-auto=0` off; log: `log show --last boot --predicate 'process == "logger"'` (the tag is not in eventMessage; the old `eventMessage CONTAINS "nmx-intelfb-auto"` finds nothing) RTX-19: after enabling it sets `debug.nvaccel_iop_memcpy=1`, `debug.nvaccel_iop_direct=1` when the NVAccel has them; `nvram nullmoth-accel-fast=0` skips that. RTX-21: then `debug.nmintelfb_ram=1` + `iop_direct=2` (`nvram nullmoth-accel-ram=0` skips that). |
| `tools/sleep/hibernate.sh` | SLEEP-1: `on` = OpenCore HibernateMode=Auto + `hibernatemode 25` (backup `~/config-antes-hibernate.plist`), `off` = back to sleep disabled, `log` = sleep/wake evidence into `~/sleep.txt` (pmset log, NMIntelFB/NVRM kernel lines, reports) |
| `tools/accel/build.sh`, `install.sh` | build NVAccel from branch `nmx-accel-236` (v2.3.6; `SRC=~/nmx-build/accel/src` = 2.1.0 branch `nmx-accel`) with `~/ogkm610`; install into `/Library/Extensions` + aux KC; `install.sh restore` puts nullmoth's back (`~/NVAccel.kext.original`). The 1401 app may copy its own NVAccel back when the driver is toggled |
| `tools/nvrm/build.sh`, `install.sh` | RTX-25 copy-engine sleep patch on nullmoth's NVRM, 2.1.0 (`f5171d7b`) or 2.3.6 (`SRCK=…/pkgroot/Library/Extensions/NVRM.kext` → `8c8873d5`) |
| `tools/upgrade/rollback.sh <backup>` | puts back what nullmoth's `install.sh` backed up in `/Library/NullMoth/backup-…` (kexts, GPUBundles, aux KC); reboot after |
| `tools/wifi/build-airport.sh`, `install.sh airport` | WIFI-5 native Wi-Fi driver (AirportMtkWlan); `install.sh restore` removes any Wi-Fi driver. Log: `bash ~/nmx-build/wifi5/out/mtklog.sh > ~/mtk.txt`. Boot-arg `-mtkwlanoff` (or `-nvoff`) keeps it off the card; NVRAM `nullmoth-wifi-band`: unset = prefer 5 GHz (WIFI-7), `5` = 5 GHz only (WIFI-6), `2` = upstream |
| `debug.nmintelfb_ram` (RW, root), `debug.nvaccel_iop_direct=2`, `debug.nvaccel_iop_ram_frames` | RTX-20 (intelfb-0017, accel-0002): `nmintelfb_ram=1` puts the panel's scanout in RAM (1 on, 0 off, < 0 refused: -1 no registers/surface, -2 BAR0 too small, -3 no buffer, -4 bad pages, -5 GGTT entry did not read back); with `iop_direct=2` the copy engine writes it (`iop_ram_frames` counts). `sudo bash tools/accel/ab.sh ram` compares direct=1 with it. Undo: `sudo sysctl -w debug.nmintelfb_ram=0`. From RTX-21 `auto.sh` turns it on at boot unless `nvram nullmoth-accel-ram=0`; from RTX-24 in mode 2 (flip) unless `nullmoth-accel-ram=1` |
| `debug.nmintelfb_ram=2`, `debug.nmintelfb_flips` / `_flip_waits` / `_flip_wait_us` / `_flip_late` | RTX-23 (intelfb-0019): two RAM buffers flipped at vblank; waits = frames that found the last flip not yet on the panel, late = gave up after 20 ms. `sudo bash tools/accel/ab.sh flip` compares ram=1 with ram=2 |
| `debug.nmintelfb_regs`, log `NMIntelFB: power N:` | intelfb-0018: `trans` (TRANSCONF, bit 31 = pipe on), `plane` (PLANE_CTL, bit 31), `surf` (PLANE_SURF), `pp` (PP_STATUS 0xC7200 / PP_CONTROL 0xC7204; status bit 31 = panel on), `blc`/`blc2` (BXT PWM CTL/FREQ/DUTY of controllers 1/2), `pte0` (first scan-out GGTT entry) |
| `tools/nvrm/build.sh`, `install.sh` | RTX-25: patched NVRM (CE wait sleeps) into `~/nmx-build/nvrm/out`; `sudo bash tools/nvrm/install.sh` installs it, `… restore` puts nullmoth's back (`~/NVRM.kext.original`). `tools/accel/install.sh` takes `KX=NVRM` for this |
| `tools/checkpoint.sh` | before every install: `save <name>` (no sudo) copies NV*/NM* kexts, the aux KC and nullmoth-* knobs to `~/nmx-checkpoints/<date>-<name>` with a verified SHA256 list; `sudo … restore <dir>` puts them back (reboot after). First one: `20261016-233841-rtx16-funcionando` (NMIntelFB 1d3ea017, NVAccel f0edef4e, NVRM 12fcabf3, NVRMFB 0a75504b, NVRMAGDC 223a327f) |
| `top -o cpu`, `ps -M <pid>` | WindowServer CPU and per-thread load (`sample` needs root) |

## Recovering
- Freeze: power off, boot with OpenCore **Space → Start once without NVIDIA driver** (`-nvoff` disables NMXGPU too),
  read the variables above.
- nullmoth boot guard (2.3.1+): `nvram 7C436110-AB2A-4BBB-A880-FE41995C9F82:nullmoth-nv-starts` (starts not yet good; 2 = driver off next boot) and `…:nullmoth-nv-ok` (set once a start was good). Log: `NVRM: boot guard`.
- `attaching=1` parks the GPU: toggle the AMD/Intel test driver in the 1401 app to retry.
- Original binary: `sudo bash tools/binpatch/apply.sh restore`. Recovery: delete `/Library/Extensions/NMXGPU.kext`.
