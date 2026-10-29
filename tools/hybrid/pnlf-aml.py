#!/usr/bin/env python3
"""Write SSDT-PNLF.aml for the WhateverXe route: Device \\_SB.PC00.GFX0.PNLF, _HID APP0002, _CID "backlight",
_UID 19 (WhateverXe's brightness profile, kern_backlight_profile.hpp), _STA 0x0B on Darwin only.
The same table as acidanthera's SSDT-PNLF for Coffee Lake and newer; the IGPU is at \\_SB.PC00.GFX0 here.

Usage: pnlf-aml.py OUT.aml
"""
import sys

BODY = bytes.fromhex(
    "a0140015 5c2f035f 53425f50 43303047 46583006 005b8242 055c2f04 5f53425f"
    "50433030 47465830 504e4c46 085f4849 440c0610 0002085f 4349440d 6261636b"
    "6c696768 7400085f 5549440a 13141b5f 535441 00a0105f 4f53490d 44617277"
    "696e00a4 0a0ba103 a400".replace(" ", ""))


def table() -> bytes:
    head = b"SSDT" + (36 + len(BODY)).to_bytes(4, "little") + b"\x02\x00" + b"NMX   " + b"PNLF\x00\x00\x00\x00" \
        + (0).to_bytes(4, "little") + b"INTL" + (0x20251212).to_bytes(4, "little")
    t = bytearray(head + BODY)
    t[9] = (-sum(t)) & 0xFF
    return bytes(t)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], "wb") as f:
        f.write(table())
