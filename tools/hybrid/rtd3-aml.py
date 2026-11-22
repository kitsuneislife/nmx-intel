#!/usr/bin/env python3
"""Write SSDT-NXRTD3.aml: Methods \\_SB.PC00.NXOF and \\_SB.PC00.NXO_ that call the firmware's RTX power resource
\\_SB.PC00.PEG0.PXP_ (_OFF / _ON_) and then Return (One).

Why (RTD3-3): macOS's evaluateObject only takes a name of at most 4 characters, relative to the device it is called on
(AppleACPIPlatformExpert::evaluateObject returns 0xe00002c2 otherwise) [measured by disassembly]. nullmoth evaluates
on \\_SB.PC00, the first ACPI device above NVRM, so tools/nvrm/rtd3-patch.sh makes it evaluate "NXOF" / "NXO" (padded
to NXO_ by ACPICA) there, and these methods forward to PXP_. Custom names, not _ON_/_OFF, because those are reserved
for power resources; nothing else calls NXOF/NXO_. RTD3-2's PowerResource wrapper (NXPR, absolute path) failed the same
length check and is gone.

Hand-assembled AML (iasl is not installed): Scope (\\_SB.PC00) { Method (NXOF) { \\_SB.PC00.PEG0.PXP_._OFF ()
Return (One) }  Method (NXO_) { \\_SB.PC00.PEG0.PXP_._ON_ () Return (One) } }. The calls take no arguments, so they
need no External: a bare NameString in a method body is resolved when the method runs.

Usage: rtd3-aml.py OUT.aml
"""
import sys


def pkg(body: bytes) -> bytes:
    """PkgLength (it counts its own bytes) followed by body."""
    for n in range(1, 5):
        total = len(body) + n
        if n == 1 and total <= 0x3F:
            return bytes([total]) + body
        if n > 1 and total < 1 << (4 + 8 * (n - 1)):
            lead = ((n - 1) << 6) | (total & 0x0F)
            rest = (total >> 4).to_bytes(n - 1, "little")
            return bytes([lead]) + rest + body
    raise ValueError("package too long")


def path(*segs: str) -> bytes:
    """Absolute NameString \\A.B.C... (all segments 4 chars)."""
    assert all(len(s) == 4 for s in segs)
    raw = b"".join(s.encode() for s in segs)
    if len(segs) == 1:
        return b"\\" + raw
    if len(segs) == 2:
        return b"\\\x2e" + raw
    return b"\\\x2f" + bytes([len(segs)]) + raw


def method(name: str, body: bytes) -> bytes:
    return b"\x14" + pkg(name.encode() + b"\x00" + body)   # MethodOp, 0 args, NotSerialized


RET_ONE = b"\xa4\x01"   # Return (One)
PC00 = ("_SB_", "PC00")
PXP = (*PC00, "PEG0", "PXP_")
BODY = b"\x10" + pkg(path(*PC00)
                     + method("NXOF", path(*PXP, "_OFF") + RET_ONE)
                     + method("NXO_", path(*PXP, "_ON_") + RET_ONE))


def table() -> bytes:
    head = b"SSDT" + (36 + len(BODY)).to_bytes(4, "little") + b"\x02\x00" + b"NMX   " + b"NXRTD3\x00\x00" \
        + (0).to_bytes(4, "little") + b"INTL" + (0x20251212).to_bytes(4, "little")
    t = bytearray(head + BODY)
    t[9] = (-sum(t)) & 0xFF
    return bytes(t)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], "wb") as f:
        f.write(table())
