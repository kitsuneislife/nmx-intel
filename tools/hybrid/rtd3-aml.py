#!/usr/bin/env python3
"""Write SSDT-NXRTD3.aml for RTD3-2: PowerResource \\_SB.PC00.PEG0.NXPR whose _ON_ and _OFF call the firmware's
\\_SB.PC00.PEG0.PXP_ methods and then Return (One).

Why: in RTD3-1 nullmoth's evaluateObject("\\_SB.PC00.PEG0.PXP_._OFF") returned 0xe00002c2 (kIOReturnBadArgument) at
once and the RTX answered right after, unchanged. PXP_._OFF returns no value (ACPI spec: _ON/_OFF return nothing);
this wrapper tests whether macOS rejects a method with no return value when the caller asks for a result object.
nvrtd3res=\\_SB.PC00.PEG0.NXPR then points nullmoth at the wrapper. Nothing else references NXPR, so no OS calls it
on its own (macOS does not manage power resources; Windows only follows _PR0/_PR3, which still name PXP_).

Hand-assembled AML (iasl is not installed): Scope (\\_SB.PC00.PEG0) { PowerResource (NXPR, 0, 0) {
Method (_STA) { Return (One) }  Method (_ON_) { \\_SB.PC00.PEG0.PXP_._ON_ () Return (One) }
Method (_OFF) { \\_SB.PC00.PEG0.PXP_._OFF () Return (One) } } }. The calls take no arguments, so they need no
External: a bare NameString in a method body is resolved when the method runs.

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
PEG0 = ("_SB_", "PC00", "PEG0")
BODY = b"\x10" + pkg(path(*PEG0) + b"\x5b\x84" + pkg(
    b"NXPR" + b"\x00" + b"\x00\x00"   # SystemLevel 0, ResourceOrder 0
    + method("_STA", RET_ONE)
    + method("_ON_", path(*PEG0, "PXP_", "_ON_") + RET_ONE)
    + method("_OFF", path(*PEG0, "PXP_", "_OFF") + RET_ONE)))


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
