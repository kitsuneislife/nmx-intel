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
Return (One) }  Method (NXO_) { \\_SB.PC00.PEG0.PXP_._ON_ () If (NVID != 0x10DE) { ...see FALLBACK } Return (One) } }. The calls take no arguments, so they
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
PEG0 = (*PC00, "PEG0")
PXP = (*PEG0, "PXP_")
NVID = path(*PEG0, "PEGP", "NVID")
NOT_NV = b"\x92\x93" + NVID + b"\x0b\xde\x10"   # LNotEqual (PEGP.NVID, 0x10DE)


def store(src: bytes, dst: bytes) -> bytes:
    return b"\x70" + src + dst


def sleep(arg: bytes) -> bytes:
    return b"\x5b\x22" + arg


# RTD3-4: PXP_._ON_ returned at once in RTD3-3 and the RTX stayed off the bus. _ON_ does Return (0) before PON_ when
# \_SB.PC00.PEG0.GSTA (the PEGP.PWGD power-good GPIO) is not 0, and POFF only cuts the rail when GPPR returns 1, so
# the GPU can sit in reset with power-good still high [inferred]. If NVID is not NVIDIA's after _ON_, NXO_ runs the
# rest of _ON_'s normal branch itself (SSDT-12 0x4b6e): PON_ (power, release reset), L23D (retrain the link),
# CMDR = 7, D0ST = 0, wait for NVID (bounded here to 1000 x 1 ms), LREN = PEGP.LTRE, CEDR = 1, PEGP.SSSV = DSSV,
# Sleep (100), then EC0_.VGAF = 1 as _ON_ does at its end. Returns 2 when it took that path.
FALLBACK = (path(*PEG0, "PON_") + path(*PEG0, "L23D")
            + store(b"\x0a\x07", path(*PEG0, "CMDR"))
            + store(b"\x00", path(*PEG0, "D0ST"))
            + store(b"\x00", b"\x60")
            + b"\xa2" + pkg(b"\x90" + NOT_NV + b"\x95\x60\x0b\xe8\x03" + sleep(b"\x01") + b"\x75\x60")
            + store(path(*PEG0, "PEGP", "LTRE"), path(*PEG0, "LREN"))
            + store(b"\x01", path(*PEG0, "CEDR"))
            + store(path(*PC00, "DSSV"), path(*PEG0, "PEGP", "SSSV"))
            + sleep(b"\x0a\x64")
            + store(b"\x01", path(*PC00, "LPCB", "EC0_", "VGAF"))
            + b"\xa4\x0a\x02")
BODY = b"\x10" + pkg(path(*PC00)
                     + method("NXOF", path(*PXP, "_OFF") + RET_ONE)
                     + method("NXO_", path(*PXP, "_ON_") + b"\xa0" + pkg(NOT_NV + FALLBACK) + RET_ONE))


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
