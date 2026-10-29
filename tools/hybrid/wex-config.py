#!/usr/bin/env python3
"""Derive the WhateverXe route's OpenCore config from the GPU-only one (Iris Xe alone, nullmoth off).

Usage: wex-config.py [--rtx] GPU_ONLY_PLIST OUT_PLIST

--rtx (XE-7, the hybrid): nullmoth's NVIDIA driver stays on. -nmintelfboff replaces -nvoff (NMIntelFB must leave
the panel to Apple's framebuffer) and nvaccel=1 is kept, so NVAccel starts, finds no NVIDIA head and goes headless:
WindowServer composites on the Iris Xe, other apps may pick the RTX (nvmtl-allow.txt).

Only these change, everything else stays as in the GPU-only config:
- Kernel/Add: WhateverXe.kext after Lilu; AMFIPass.kext replaced by AMFIPassMod.kext (b00t0x's Mod build, which
  trusts the WhateverXe Graphics signatures; same bundle ID, so only one may load, and a separate folder lets the
  GPU-only config keep the upstream one).
- DeviceProperties for the iGPU: nmx-wex=<01> only, the gate wex-install.sh puts on the TGL kexts' personalities. No
  device-id spoof: WhateverXe selects RPL-P from the physical a7a8. No DVMT properties: our 64 MiB is a multiple of
  32 MiB, which Apple's formula handles (only 60 MiB needs -igfxdvmt).
- boot-args: WhateverXe's -allow3d -disablegfxfirmware, msgbuf=400000 (efi.sh boot-once saves dmesg), -nvoff so
  NMXGPU and NMIntelFB stay off; -v and nvaccel=1 dropped as in hybrid-config.py (HYB-4: without nvaccel=1 NVAccel
  does not start, so WindowServer cannot pick the RTX Metal driver).
- ACPI/Add: SSDT-PNLF.aml (pnlf-aml.py, efi.sh writes it to OC/ACPI): WhateverXe's README asks for it for panel
  brightness; without it the panel is an AppleDisplay with no brightness (XE-7).
csr-active-config 0xa43 already contains the 0x803 WhateverXe asks for; amfi flags stay (not required, harmless).
"""
import plistlib
import sys

APPLE_BOOT = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
IGPU = "PciRoot(0x0)/Pci(0x2,0x0)"
DROP_ARGS = {"-v", "nvaccel=1"}
WEX_ARGS = "-allow3d -disablegfxfirmware msgbuf=400000 -nvoff".split()
PNLF_ENTRY = {"Comment": "WhateverXe route: panel brightness (PNLF, UID 19)", "Enabled": True, "Path": "SSDT-PNLF.aml"}
WEX_ENTRY = {
    "Arch": "x86_64", "BundlePath": "WhateverXe.kext", "Comment": "WhateverXe route: Apple TGL driver on the Iris Xe",
    "Enabled": True, "ExecutablePath": "Contents/MacOS/WhateverXe", "MaxKernel": "", "MinKernel": "",
    "PlistPath": "Contents/Info.plist",
}


def make(c: dict, rtx: bool = False) -> dict:
    add = c["Kernel"]["Add"]
    paths = [e.get("BundlePath") for e in add]
    for bad in ("NootedGreen.kext", "WhateverXe.kext", "WhateverGreen.kext"):
        if bad in paths:
            sys.exit(f"the input loads {bad}: give the GPU-only config")
    if "Lilu.kext" not in paths or "AMFIPass.kext" not in paths:
        sys.exit("no Lilu.kext or AMFIPass.kext in Kernel/Add")
    add[paths.index("AMFIPass.kext")]["BundlePath"] = "AMFIPassMod.kext"
    add.insert(paths.index("Lilu.kext") + 1, dict(WEX_ENTRY))
    acpi = c["ACPI"]["Add"]
    if not any(e.get("Path") == PNLF_ENTRY["Path"] for e in acpi):
        acpi.append(dict(PNLF_ENTRY))
    c["DeviceProperties"]["Add"].setdefault(IGPU, {})["nmx-wex"] = b"\x01"
    boot = c["NVRAM"]["Add"][APPLE_BOOT]
    drop, extra = (DROP_ARGS - {"nvaccel=1"}, WEX_ARGS[:-1] + ["-nmintelfboff"]) if rtx else (DROP_ARGS, WEX_ARGS)
    args = [a for a in boot["boot-args"].split() if a not in drop]
    boot["boot-args"] = " ".join(args + [a for a in extra if a not in args])
    return c


def main() -> None:
    argv = sys.argv[1:]
    rtx = argv[:1] == ["--rtx"]
    argv = argv[rtx:]
    if len(argv) != 2:
        sys.exit(__doc__)
    with open(argv[0], "rb") as f:
        c = plistlib.load(f)
    out = make(c, rtx)
    with open(argv[1], "wb") as f:
        plistlib.dump(out, f, sort_keys=True)


if __name__ == "__main__":
    main()
