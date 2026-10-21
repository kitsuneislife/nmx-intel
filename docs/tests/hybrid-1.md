# Hybrid route: Iris Xe on Apple's Tiger Lake driver (HYB-1…)

> **Summary.** Tests of the hybrid route ([../knowledge/hybrid-route.md](../knowledge/hybrid-route.md)). H1 runs the
> Iris Xe alone: Apple's 16.0.32 TGL kexts, NootedGreen (JulioNectar's fork, our Sequoia patch) and the patched Metal
> driver, with nullmoth off (`-nvoff`). The GPU-only route stays one `tools/hybrid/efi.sh gpu-only` away. Tools:
> `tools/hybrid/` (build, install, efi, log).

## HYB-1: Iris Xe alone, first boot (H1, pending)

Change under test: OpenCore boots `config-hybrid.plist`, written by `tools/hybrid/hybrid-config.py` from the GPU-only
config. Exactly three differences, checked on a copy of the 10-19 config [measured]:

- `DeviceProperties` for `PciRoot(0x0)/Pci(0x2,0x0)` (`GFX0@2` here): Julio's set, device-id `9A49`, ig-platform-id
  `0x9A490000`.
- `Kernel/Add`: `NootedGreen.kext` right after Lilu (1.7.2; it needs 1.6.4), `MinKernel` empty (Julio's `25.0.0`
  would skip it on Sequoia).
- boot-args, added: `IGLogLevel=3 msgbuf=400000 -ngreentglwithgfx -allow3d -disablegfxfirmware ngreen-dmc=adlp
  -ngreenv189 -ngreenkeepefi -ngreenxefix -ngreenfixbootmode ngreenSched=4 ngreenV142=3 -nvoff`.

Kept from our config on purpose (differs from Julio's): no WhateverGreen (NootedGreen's WEG coexistence is off by
default, `isWEGCoexistMode()`), csr `0x0A43` (his `0x0A13` adds Apple-internal; `amfi_get_out_of_my_way=0x1` and
AMFIPass already let nullmoth's ad-hoc Metal bundles load), GOP resolution `Max` (native 1920x1080, which
`-ngreenkeepefi` keeps), no `ngreenblmax` (his panel's value, only used if Apple never writes the PWM period).
NootedGreen renames `GFX0` to `IGPU` itself.

macOS side (`tools/hybrid/install.sh`): Apple's TGL accelerator and framebuffer kexts plus the GL/VA/VAME/Shared/MTL
bundles in `/Library/Extensions`, the patched Metal driver and Shared bundle in `/Library/GPUBundles`, `xe.bundle` in
`/System/Library/Caches`, aux kext collection rebuilt (backup `~/AuxiliaryKernelExtensions.kc.antes-hybrid`; the
script refuses the new collection if nullmoth's kexts, NMIntelFB or the Wi-Fi kext are missing). The accelerator matches
only `9A49`, the framebuffer `FF20/9A49/A7A0`: nothing matches our `a7a8` under the GPU-only config [inferred].

Expected under `-nvoff`: no NVIDIA, no NMIntelFB, and no Wi-Fi (our MT7921 build honours `-nvoff`); Ethernet works.

Builds: `NootedGreen.kext` from `356c818` + 0001 (its hash changes on every build), `libxedrv` `c37b5a4f`, Metal driver
`8e36e035`.

Gate: login window and desktop on the panel; `system_profiler` shows the Iris Xe with Metal; then 1 h of use without a
GPU hang. If the panel stays black: hold Shift in the OpenCore picker for Safe Mode (the aux collection, so the TGL
kexts, is not loaded), then `sudo bash tools/hybrid/efi.sh gpu-only`.

Install steps given to Lukas (2026-10-21):

1. `zsh ~/Documents/Projetos/nmx-intel/tools/hybrid/build.sh`
2. `sudo bash ~/Documents/Projetos/nmx-intel/tools/hybrid/install.sh`
3. `sudo bash ~/Documents/Projetos/nmx-intel/tools/hybrid/efi.sh hybrid`
4. Reboot.
5. After the boot (or the next boot back on GPU-only): `sudo bash ~/Documents/Projetos/nmx-intel/tools/hybrid/log.sh`
   → `~/hybrid.txt`.

Note (2026-10-21, first install attempt): `install.sh` stopped at `kmutil create` with KMErrorDomain 71, "'com.xxxxx.
driver.AppleIntelTGLGraphicsFramebuffer' names a dependency on 'org.smichaud.HookCase', which was not found"; the
collection was left unchanged [measured]. Both TGL kexts list `org.smichaud.HookCase 1.0` in `OSBundleLibraries`, and the
framebuffer imports 11 symbols from it (`AppleIntelBaseController::{Read,Write}Register{32,64}`, `hwSetupDSBMemory`,
`getPMTNow`, `AppleIntelPortHAL::probePortMode`, `AppleIntelDisplayPath::DSBEngineBusyStatus`, `strnstr`, plus
`gpu_accumulate_time`/`gpu_describe` from the accelerator) [measured, `nm -u`]. HookCase is NootedGreen's symbol
library (its `kern_start` does nothing); Julio's installer copies it from `le/` when present, his `build-hookcase.sh` is
not in the public repo. Fix: `build.sh` now builds `HookCase.kext` from NootedGreen's `HookCase-master` without Xcode,
with no IOKit personality, and with `source-fixes/hybrid/ng/0001` (`probePortMode` dereferenced the never-assigned
`callback`; it now reads `0x1638a0` through the controller, the same `ReadRegister32` the framebuffer imports).
`install.sh` copies it to `/Library/Extensions` and refuses a collection without `org.smichaud.HookCase`. A non-root
`kmutil libraries --undef-symbols` resolves every kernel symbol of the three kexts; the HookCase link itself is only
checked by `kmutil create` as root [inferred]. HookCase `2034240a`.

## Result (2026-10-21): fail, deterministic panic when WindowServer opens the accelerator

Lukas: after the install the hybrid boot showed the Apple logo and loading bar, then froze and restarted, about three
times; every start used the hybrid `config.plist` again, so he had to put the GPU-only plist back from macOS Recovery.

Evidence [measured]: two panic reports, `/Library/Logs/DiagnosticReports/Kernel-2026-10-21-085600.panic` and
`…-085756.panic` (the third boot left none). Both: page fault, CR2 `0x288`, uptime ~37 s and ~41 s, process
WindowServer (pid 416). Backtrace: `IntelAccelerator::getStampMemory+0x11` ← `IOAccelDevice2::deviceStart+0x20` ←
`IGAccelDevice::deviceStart+0x16` ← NootedGreen `Gen11::deviceStart+0x10` ← `IOAccelDevice2::start` ←
`IOGraphicsAccelerator2::newUserClient` ← `is_io_service_open_extended`. Loaded: `org.smichaud.HookCase 8.0.1`,
`com.xxxxx.driver.AppleIntelTGLGraphics 16.0.2`, so HookCase and both TGL kexts loaded and the framebuffer reached the
login phase. No unified log of those boots survived (kernel lines stop at 08:51).

`getStampMemory` is `movq 0x150(%rdi),%rax; movq 0x288(%rax),%rdi`: `IntelAccelerator+0x150` was NULL. That field is
the accelerator's kernel `IGAccelTask` (`IntelAccelerator::start` calls `IGAccelTask::getStamps` on it after
`initHardwareStatusPageMemory`) [measured, disassembly]. So the accelerator was published without its kernel task, and
the first user client crashed inside Apple's code, before NootedGreen's V111 "force deviceStart true" could act.
Why the task is missing (start failed part-way, or skipped it with `ngreenSched=4`) is unknown [unverified]; the
logs that would say (NootedGreen's V221 `start() complete ret=`, Apple's `encodeFailureStack`) died with the panic.
Safe Mode was not a practical way back.

## HYB-2 (prepared 2026-10-21): survive the boot to read why, and fall back by itself

One variable on the driver: `source-fixes/hybrid/0002` makes NootedGreen record the accelerator in its
`IntelAccelerator::start` hook (logging `ret` and the `+0x150` pointer) and makes its `IGAccelDevice::deviceStart`
hook refuse the open, without calling Apple's code, when that pointer is NULL. Expected: no panic; WindowServer gets an
error and runs without Metal (software or black panel), and the logs say why the task is missing. NootedGreen
`9cf68511` (HookCase `2034240a`, libxedrv `c37b5a4f`, Metal driver `8e36e035` unchanged). Strings checked.

Safety net (not a driver variable): `efi.sh hybrid` now boots hybrid **once**. It installs a LaunchDaemon
(`com.nmx.hybrid-once`, a copy of `efi.sh` in `/usr/local/libexec`) that, early in the hybrid boot, copies
`config-gpu-only.plist` back over `config.plist` and unmounts the ESP (flushes FAT). A freeze or panic after launchd
starts therefore restarts into GPU-only with no key presses. `efi.sh hybrid-keep` skips the daemon once hybrid is
stable; `efi.sh gpu-only` removes it. Log: `/var/log/nmx-hybrid.log`. Checked on a fake ESP (arm, status, boot-once);
not yet on the real boot. A panic before launchd (during kext load) is not covered: Recovery, or Windows, as before.

Steps (the macOS side is on disk from HYB-1; NootedGreen `9cf68511` is already built, `efi.sh` copies it to the ESP):

1. `sudo bash ~/Documents/Projetos/nmx-intel/tools/hybrid/efi.sh hybrid`
2. Reboot; wait 2–3 minutes even if the panel is black, then hold the power button if needed.
3. Back on GPU-only: `sudo bash ~/Documents/Projetos/nmx-intel/tools/hybrid/log.sh` → `~/hybrid.txt`.

### HYB-2 result (2026-10-21): fail, same panic; the fallback worked

The once-only daemon worked [measured]: after the panic the Mac restarted into GPU-only by itself, no Recovery.
The driver variable did not help: `Kernel-2026-10-21-092659.panic` is the HYB-1 panic again (uptime ~40 s, WindowServer
pid 434, `getStampMemory+0x11` ← `IOAccelDevice2::deviceStart+0x20` ← `IGAccelDevice::deviceStart+0x16` ←
NootedGreen `Gen11::deviceStart+0x2a`). RDI = the accelerator, RAX = 0 [measured]. The guard did not fire: it relied on
a pointer set in the `IntelAccelerator::start` hook, which was evidently not set for this accelerator [inferred].
None of NootedGreen's SYSLOG lines (V-numbered or "nmx HYB-2") are in the unified log, while Apple's `[IGPU]` IOLogs are
[measured], so that hook's logging is invisible here.

The kernel log of the hybrid boot (read with an explicit `--start/--end` window) shows why [measured]:

    09:25:11.868 (AppleIntelTGLGraphics) [IGPU] IntelAccelerator::probe: Found device with ID 0x9a498086 ... at PCI 0:2:0
    09:25:11.984 (AppleIntelTGLGraphics) [IGPU] IntelAccelerator::probe: Found device with ID 0x25ac10de ... at PCI 1:0:0
    09:25:11.984 (NVAccel) NVAccel: probe(PEGP) score 100 ... claiming
    09:25:11.988 (AppleIntelTGLGraphics) [IGPU] Detecting Pre-Si/Si Mode ... [Si]

The Intel accelerator probed the RTX 3050. The only start line ("Pre-Si/Si", early in `IntelAccelerator::start`) is on
that thread. NootedGreen's `injectAcceleratorPersonality` adds an IntelAccelerator personality with
`IOPCIClassMatch 0x03000000&0xff000000` and `IOProbeScore 1000` but no `IOPCIPrimaryMatch` [measured, source], so it
matches every VGA device and beats NVAccel (100) on the RTX. The working theory is that an IntelAccelerator was
started on NVIDIA hardware, never built its kernel task, and WindowServer opened that one [inferred]. Whether the iGPU
instance started too is unknown. `log.sh` missed all of this: it read only the current (GPU-only) boot, and its
`kern.boottime` parse took `usec` instead of `sec` (greedy sed), so its "since boot" report filter matched everything.

## HYB-3 (prepared 2026-10-21): the accelerator matches the iGPU only

Variable: `source-fixes/hybrid/0003` adds `IOPCIPrimaryMatch "0x9a498086 0xa7a88086"` to the injected personality.
Safety net in the same patch (it only acts where HYB-2 would have panicked): the `deviceStart` guard now reads the
accelerator from the device itself (`IGAccelDevice+0x108`, as `get_vram_size` and `get_hw_caps` do) and refuses the
open when its `+0x150` is NULL. The start hook and the guard log with `IOLog` ("nmx HYB-3: ..."), which does reach the
unified log; the start line names the provider (`IGPU` or `PEGP`). NootedGreen `3f20738f`; HookCase, libxedrv and the
Metal driver unchanged. Strings checked. `log.sh` now also reads the 20 minutes before the current boot and keeps
only panic and WindowServer reports.

Expected: no IntelAccelerator probe line for `0x25ac10de`; one "nmx HYB-3: IntelAccelerator::start on IGPU" line with a
non-NULL kernel task. If the iGPU task is NULL too, the guard should refuse the open and the boot should survive.

Steps: as HYB-2 (`efi.sh hybrid`, reboot, wait, `log.sh`).

### HYB-3 result (2026-10-21): pass for the match, first desktop on the Iris Xe

Lukas: the hybrid boot reached the desktop, with very many visual bugs; network did not work, so he rebooted (the
daemon had already put GPU-only back). No panic [measured: no new `.panic`].

Evidence (kernel log 09:38:40–09:42:04) [measured]:
- `IntelAccelerator::probe` ran only for `0x9a498086` at PCI 0:2:0; the RTX line is gone. "Pre-Si/Si" and the HWCAPS
  block ("TGL GT2 LP", 96 EU, Host Preemptive scheduler, "Graphics firmware disabled via NVRAM") follow on the same
  thread, so the accelerator started on the iGPU.
- The "nmx HYB-3" IOLog lines are absent, both start and guard. The guard did not need to act. Why the start line is
  missing is open [unverified].
- `Kernel_2026-10-21-093915….gpuRestart` (~30 s after the accelerator start): "Intel GPU Hang Summary", hardware
  context 6. BCS "busy - in the ring, Appears hung" (HEAD `0xd4`, TAIL `0xd8`, START `0x402e8000`). RCS, CCS, VCS0 and
  VECS0 were "NOT enabled".
- Framebuffer: "Insufficient stolen memory", repeated "FB0: Insufficient link bandwidth to support bpc 24", "Flip
  called without enabling VBL", "DBUF 2 power down timeout".
- Network: the boot-args carry `-nvoff`, which also keeps our AirportMtkWlan off the card by design (wifi patches). So
  no Wi-Fi in hybrid is expected. `en0` (RTL8111) shows "Has Wired Ethernet Link: false" in this boot and in the
  GPU-only one, i.e. no cable link either time.

Cause of the artifacts, best candidate [inferred]: the hybrid config keeps `-v` from the GPU-only config. Julio found
that the verbose console draws into the boot framebuffer at the start of the GGTT, the same range as the accelerator's
contexts and rings. Booting without `-v` gave his first executed GPU work, and he banned `-v` from the accelerated
config (`docs/HISTORY.md` 9.3 in his repo). His own boot-args have no `-v`.

## HYB-4 (prepared 2026-10-21): the same hybrid boot without `-v`

Variable: `hybrid-config.py` drops `-v` from the hybrid boot-args (everything else as in HYB-3; NootedGreen `3f20738f`
unchanged). `efi.sh hybrid` regenerates `config-hybrid.plist`, so no rebuild is needed. Checked: the generated
boot-args have no `-v` and still have `-vi2c-force-polling`. Wi-Fi stays off (`-nvoff`). Fixing it means letting
AirportMtkWlan ignore `-nvoff` in hybrid, which is a separate change to an installed kext.

Expected: far fewer artifacts, or none; the BCS hang may remain. Steps: as HYB-2 (`efi.sh hybrid`, reboot, wait,
`log.sh`). The boot shows the Apple logo instead of text.

### HYB-4 result (2026-10-21): boots, same artifacts; `-v` was not the cause

Lukas: the boot was clean (Apple logo, desktop), but the artifacts were the same. His 16 s screen recording shows
Terminal text with missing characters, black triangles and polygons over the wallpaper, and missing menu bar icons
and Dock items [measured: frames from the video]. No gpuRestart, no panic [measured].

Evidence (all-process log 09:49:03–09:50:49) [measured]:
- The framebuffer errors are as in HYB-3. libxedrv reports every texture path "-> ok" and "PIPE sync ok … falhas=0".
- **nullmoth's NVIDIA driver was running.** NVRM 2.3.6 started on `10de:25ac`, resized BAR1 and noted "boot guard:
  start 1 without a display so far". NVAccel logged "NVIDIA display device 10de:25ac … claiming". NVRMFB refused to
  start (no connected display), but NVAccel published the accelerator anyway.
- **WindowServer used it.** `WindowServer[161:326] (NVMTLDriver) NullMoth: …` lines (reflection, `vkAllocateMemory`
  refused imported host pointers). Kernel thread `0:326`, the same WindowServer thread, logged ~580 each of NVAccel
  `newVidMemory`/`newSysMemory`/`newResource` and ~480 "REAL VRAM" allocations. `com.apple.WebKit.GPU` and
  `mediaanalysisd` also touched the NVIDIA device.
- `-nvoff` reached the kernel: "NMIntelFB: off: -nvoff" and AirportMtkWlan stayed off. NVRM and NVAccel ignore it in
  this build. The "Boot args:" kernel log line stops at 227 characters, which is a log line limit; the flags at the
  end (`-disablegfxfirmware`, `-nvoff`) took effect.
- No NootedGreen IOLog line appears at all (no `XeNG …`, no `nmx HYB-3`), although the kext loaded
  (`com.StezzaPilot.NootedGreen`). Still unexplained [unverified].

Correction to HYB-3's analysis: `-v` was not the cause of the artifacts [measured: same artifacts without it]. It
stays dropped, as in Julio's config.

New best candidate [inferred]: WindowServer ran Metal work on the RTX through NVMTLDriver while the panel and the
compositor's IOSurfaces lived on the Iris Xe. Content rendered on one GPU and shown by the other would explain
missing glyphs, missing icons and black shapes. Julio's machine has no second GPU, so his stack never met this.

## HYB-5 (prepared 2026-10-21): the same hybrid boot without `nvaccel=1`

Variable: `hybrid-config.py` also drops `nvaccel=1` (commit `b58f5c0`). NVAccel has its own guard ("boot-arg
nvaccel=1 absent: NOT starting"), so no NVIDIA Metal device is published and WindowServer has only the Iris Xe. NVRM
still starts (no display, no Metal device). The GPU-only config is unchanged. Checked: the generated boot-args keep
`-vi2c-force-polling`, `nvfb=1` and `-nvoff`, and have neither `-v` nor `nvaccel=1` [measured, self-test].

Expected: no `NVAccel` or `NVMTLDriver` lines; text, icons and the Dock drawn correctly, or a different artifact
pattern. Steps: as HYB-2 (`efi.sh hybrid`, reboot, wait, `log.sh`).

### HYB-5 result (2026-10-21): the RTX is out, the artifacts stay

Lukas: no change on screen, the same artifacts. Boot at 10:01:48, boot-args without `nvaccel=1` [measured].

Evidence (all-process log 10:01:40–10:03:10) [measured]:
- NVAccel only probed and claimed the card; no allocations, no user clients. Zero `NVMTLDriver` lines. WindowServer had
  no NVIDIA Metal device.
- WindowServer: "Metal compositor activated"; libxedrv loaded with "layout: bits Sequoia (iguais ao driver, sem
  conversão)", "sem compressão: dev=1 ios=1 heap=1", "nocopyfix: 1 1".
- The shader compiler works: `MTLCompilerService (libMTLIGCCompilerPlugin) xe-adapter: parse bitcode -> bad=0` and
  `old BuildRequestWithOptions -> 0` for iconservicesagent.
- **Why NootedGreen never shows in our logs:** OpenCore-injected kexts have no uuidtext on disk, so the unified log
  stores their lines as `(missing UUID) <compose failure [missing precomposed log]>` (2035 such lines in this boot).
  Every `XeNG …` and `nmx HYB-3` IOLog was there, unreadable. This also explains HYB-3's missing start line.

Conclusion: the RTX Metal device was not the cause [measured]. The artifacts come from the Intel side. Without
NootedGreen's own log we cannot tell which of its fixes run on Sequoia (POOL, POOLALIGN, BLITSCRATCH2, FMT, PLANES,
CSBGUARD…), and several were written against Tahoe's IOSurface/IOAF2 layout.

## HYB-6 (prepared 2026-10-21): the same boot, with NootedGreen's log saved

Variable: none on the GPU side (config as HYB-5). The one-boot daemon (`efi.sh boot-once`, commit `262429d`) now
writes `dmesg` to `/var/log/nmx-hybrid-dmesg-{0,60,180}.txt` after putting GPU-only back. `msgbuf=400000` keeps the
text of NootedGreen's IOLog lines there until the reboot. `log.sh` prints their `XeNG`/`NGreen`/`Lilu` lines. Both
scripts pass `bash -n`.

Expected: `XeNG POOL`, `XeNG BLITSCRATCH2 … [0x4c0] … -> 2420005b`, flip counters, or their absence, which says which
fixes run on Sequoia. Steps: as HYB-2; stay on the desktop at least 3 minutes before rebooting.

### HYB-6 result (2026-10-21 10:10): NootedGreen's init is readable; the desktop part was not captured

Timeline [measured]: boot-once ran at 10:10:27 (kernel ~15 s), put GPU-only back, wrote `dmesg-0`. The next boot's
daemon ran at 10:11:43, so the hybrid session lasted under a minute; no `dmesg-60`, no panic, no gpuRestart report
[measured]. A manual reboot is the likely cause [inferred]. `dmesg-0` ends at 15.4 s, before WindowServer.

What `dmesg-0` proves runs on Sequoia [measured]: IOAF2 hooks (`IOAccelF2 f2 (fixed): OK`, V221 waitForStamp,
`XeNG BLITSCRATCH2: lock/unlockForCPUAccess hooked`, NOORPHAN, `XeNG POOL: hook IOAccelCommandBufferPool2::init OK`,
FLIP diag, V500); framebuffer (`TGL FB routes applied`, Path E, `XE-VALD … fmtBGRA=1`, keepefi kept
`TRANS_DDI_FUNC_CTL_A=0x8a010106`, PSR off, ADL-P DMC 2.16, cdclk 0x164 sanitised); accelerator (V165 28 symbols, V111
deviceStart, XE-FMT BGRA, XE-NOCCS3, XE-NODEPTH, NOTCF/NOTCF2, PLANES2 at IOSurface+0x98, BLITALIGN, BLIT16, NOAUX,
V141 1/1, **V140 1/4 signatures**, V52, "Loaded AppleIntelTGLGraphics! … totalEU=96"). GAMMA_MODE_A is forced to 0
by the xefix register filter (`kern_gen11.cpp:3565`), so the HISTORY line-138 fix is in [measured, source].

Not seen yet: the runtime lines (BLITSCRATCH2 `[0x4c0]` value, POOL sizes, flip/CSB counters, hangs). They are
written after the desktop starts.

## HYB-7 (prepared 2026-10-21): HYB-6 again, with the dump refreshed during the whole session

Variable: none on the GPU side. `efi.sh boot-once` now deletes old dumps, writes `dmesg-0` at boot and refreshes
`dmesg-last.txt` every 20 s for 10 min (written to a temp file, then moved), so a manual reboot after 1 minute still
leaves the desktop's lines. `log.sh` prints the tail of `-last`. Both pass `bash -n`.

Expected: the runtime `XeNG` lines while the artifacts are on screen. Steps: as HYB-2; stay on the desktop at least
1 minute, open Finder and Safari, then reboot.

### HYB-7 result (2026-10-21 10:18): the kernel side looks healthy; the desktop's runtime lines are readable

Session 10:18:24 → reboot ~10:19:35 (a `shutdown_stall` report at 10:19:33; no panic, no gpuRestart) [measured].
`dmesg-last` (kernel 73 s, 807 lines) holds the desktop's NootedGreen lines [measured]:
- `XeNG BLITSCRATCH2: … size=0xd240 routed=1 ok=1 [0x4c0] 00000000 -> 2420005b (esperado 2420005b)`: the Blit3D
  kernels are uploaded exactly as on Julio's Tahoe machine.
- `XeNG BLIT #N … saida=L7701` every 64 blits up to #1536; `XeNG CS t=200 … (push 4625 exec 4074) … to=8 …
  pgfix=0 resfix=0`; POSHCTX clears POSH on each new context; V509 contexts valid ("no repair needed").
- V194 "getBlit3DContext ctx changed … (restart recovery)" alternates between a few contexts; with no gpuRestart
  report this is per-client contexts, not restarts [inferred].
- 210× V212 isGpuIdle override, no hang, no CSB/ring error.

Conclusion [inferred]: the kernel fixes all run and the GPU executes work without hangs. The artifacts (missing
glyphs, black triangles, missing icons) are a rendering-correctness problem: user-space Metal driver, shader
compiler, or a texture/surface layout difference on Sequoia. Julio's headless Metal tests can tell which.

## HYB-8 (prepared 2026-10-21): Julio's Metal tests run by themselves on the Iris Xe

Variable: none on the GPU side. New `tools/hybrid/gputests.sh` builds Julio's headless tests (xe-miptest, xe-f16test,
xe-atlastest, xe-icontest, xe-carender, xe-tex-tests minus `wu_ios`, which hung his GPU) into
`~/nmx-build/hybrid/xps/build/tests` (not committed). `efi.sh hybrid` copies them to `/usr/local/libexec/nmx-gputests`;
`boot-once` waits for the login, 30 s more, then runs them as the console user (15 s limit each, sync per test) into
`/var/log/nmx-hybrid-gputests.txt`. It also copies libxedrv's `/tmp/xedrv-*.log` to `/var/log/nmx-hybrid-xedrv/`
every 20 s. `log.sh` prints both. All scripts pass `bash -n`.

Baseline on the RTX (GPU-only, 10:26) [measured]: every test OK (mips, f16 rows, atlas blocks, icons opaque,
tex-tests OK), except `xe-carender` "ícone NSImage/CGImage … linhas brancas=36/37", which is therefore not an Intel
defect. Expected on the Iris Xe: a failing test names the broken operation.

### HYB-8 result (2026-10-21 10:28): Julio's Metal tests pass on the Iris Xe

The daemon ran the tests at 10:29:50 as `lukas` (so `launchctl asuser` works) [measured]. On the Iris Xe:
- xe-miptest: every level correct (CPU and GPU mips, GPU→GPU). xe-f16test: 0 wrong rows at every size.
- xe-atlastest: BGRA8, RGBA16Unorm, RGBA32Float 0 of 8 wrong; RGBA16Float 1 of 8 ("nível 2 pos (50,10) 10x10:
  ERRADO", printed value equals the expected one, so another pixel of the block differs) [measured]. Minor.
- xe-icontest: same opacity and colours as on the RTX. xe-tex-tests: all OK.
- xe-carender: layer centres BGRA (254,0,82) against (255,51,4) on the RTX; icon rows as on the RTX. A different
  display colour profile per GPU may explain it [unverified].
- libxedrv logs (`/var/log/nmx-hybrid-xedrv/`): every texture and pipeline "-> ok", "falhas=0", in WindowServer,
  Terminal, ghostty, ControlCenter. NOCOPY realigned four small RG8 textures in WindowServer.

Not covered by those tests: the glyph atlases. Terminal creates an A8Unorm 576x576 managed texture and ghostty an
R8Unorm 512x512 shared one [measured: libxedrv TEX lines]; glyphs are written into them as small CPU `replaceRegion`
blocks at odd offsets. Missing characters in both terminals point there [inferred].

## HYB-9 (prepared 2026-10-21): glyph-atlas test

Variable: none on the GPU side. New `tools/hybrid/xe-a8test.m` (ours): A8/R8/RG8/BGRA8, shared and managed,
512 and 576 wide; 12 blocks of 14x20 written by `replaceRegion` at odd offsets, read back by a compute shader (read
and nearest sample) and checked, including the row below each block. `gputests.sh` builds it and runs it first.
RTX baseline [measured]: 0 of 12 wrong in all 32 cases.
