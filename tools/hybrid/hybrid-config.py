#!/usr/bin/env python3
"""Derive the hybrid route's OpenCore config from the GPU-only one (phase H1: Iris Xe alone, nullmoth off).

Usage: hybrid-config.py GPU_ONLY_PLIST OUT_PLIST

Only these change, everything else stays as in the GPU-only config:
- DeviceProperties for the iGPU at PciRoot(0x0)/Pci(0x2,0x0) (GFX0@2 here): Julio's set, which presents the
  Raptor Lake iGPU as Tiger Lake 9A49 so Apple's 16.0.32 TGL kexts match.
- Kernel/Add: NootedGreen.kext after Lilu. MinKernel is left empty: Julio's 25.0.0 would skip it on Sequoia (24.x).
- boot-args: Julio's NootedGreen arguments minus ngreenblmax (his panel's value), plus -nvoff so nullmoth and
  NMIntelFB stay off. -v is dropped: the verbose console draws into the boot framebuffer at the start of the GGTT,
  where the accelerator keeps contexts and rings (Julio's HISTORY 9.3; HYB-3 desktop full of artifacts).
  nvaccel=1 is dropped too: nullmoth's NVRM and NVAccel ignore -nvoff, so without this WindowServer composited
  through the RTX Metal driver (NVMTLDriver) while the panel was on the Iris Xe (HYB-4). NVAccel does not start
  without nvaccel=1.
  amfi_get_out_of_my_way, csr-active-config and AMFIPass are already in the GPU-only config.
"""
import plistlib
import sys

APPLE_BOOT = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
IGPU = "PciRoot(0x0)/Pci(0x2,0x0)"
IGPU_PROPS = {
    "AAPL,ig-platform-id": bytes.fromhex("0000499a"),
    "AAPL,slot-name": "built-in",
    "built-in": bytes.fromhex("00"),
    "complete-modeset": bytes.fromhex("01000000"),
    "device-id": bytes.fromhex("499a0000"),
    "enable-max-pixel-clock-override": bytes.fromhex("01000000"),
    "force-online": bytes.fromhex("01000000"),
    "framebuffer-patch-enable": bytes.fromhex("01000000"),
    "hda-gfx": "onboard-1",
    "model": "Intel Iris Xe Graphics",
    "rps-control": bytes.fromhex("01000000"),
}
DROP_ARGS = {"-v", "nvaccel=1"}
HYBRID_ARGS = ("IGLogLevel=3 msgbuf=400000 -ngreentglwithgfx -allow3d -disablegfxfirmware ngreen-dmc=adlp -ngreenv189 "
               "-ngreenkeepefi -ngreenxefix -ngreenfixbootmode ngreenSched=4 ngreenV142=3 -nvoff -ngreenbootgdrst").split()
NG_ENTRY = {
    "Arch": "x86_64", "BundlePath": "NootedGreen.kext", "Comment": "hybrid route: Apple TGL driver on the Iris Xe",
    "Enabled": True, "ExecutablePath": "Contents/MacOS/NootedGreen", "MaxKernel": "", "MinKernel": "",
    "PlistPath": "Contents/Info.plist",
}


def make(c: dict) -> dict:
    if any(e.get("BundlePath") == "NootedGreen.kext" for e in c["Kernel"]["Add"]):
        sys.exit("the input already loads NootedGreen: give the GPU-only config")
    paths = [e.get("BundlePath") for e in c["Kernel"]["Add"]]
    if "Lilu.kext" not in paths:
        sys.exit("no Lilu.kext in Kernel/Add")
    c["DeviceProperties"]["Add"][IGPU] = dict(IGPU_PROPS)
    c["Kernel"]["Add"].insert(paths.index("Lilu.kext") + 1, dict(NG_ENTRY))
    boot = c["NVRAM"]["Add"][APPLE_BOOT]
    args = [a for a in boot["boot-args"].split() if a not in DROP_ARGS]
    boot["boot-args"] = " ".join(args + [a for a in HYBRID_ARGS if a not in args])
    return c


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], "rb") as f:
        c = plistlib.load(f)
    out = make(c)
    with open(sys.argv[2], "wb") as f:
        plistlib.dump(out, f, sort_keys=True)


if __name__ == "__main__":
    main()
