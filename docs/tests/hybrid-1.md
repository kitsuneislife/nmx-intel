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
