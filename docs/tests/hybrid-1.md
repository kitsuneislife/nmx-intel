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
