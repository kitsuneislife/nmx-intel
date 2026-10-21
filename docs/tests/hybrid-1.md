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
