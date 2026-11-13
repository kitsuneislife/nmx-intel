#!/usr/bin/python3 -I
"""kpatch.py: checks the PCCI topology patches (OpenCore Kernel > Patch, identifier "kernel") against a kernel inside
a BootKernelExtensions.kc, and writes Tahoe copies of them once they match.

Without these four patches the i5-13420H kernel divides by zero in smp_init() or panics in x86_validate_topology
(hackintosh repo, tests J..L). They carry MinKernel 24.0.0 / MaxKernel 24.99.99, so on Tahoe (Darwin 25) OpenCore
would skip them all.

  kpatch.py check KC CONFIG          for every kernel patch in CONFIG: hits of Find in the kernel of KC (from the
                                     Base symbol on, like OpenCore), whether the first Count hits are inside that
                                     function, and which OpenCore "cores per package" variant this kernel has
  kpatch.py add KC CONFIG OUT        the same check; if all four match, OUT = CONFIG plus copies of them for
                                     Darwin 25 (MinKernel 25.0.0, MaxKernel 25.99.99), with the cores-per-package
                                     Find/Replace of the variant this kernel has. Nothing is written otherwise.
  kpatch.py strip CONFIG OUT         OUT = CONFIG without the Darwin 25 copies (back to Sequoia only)

The KC may be the running system's (/System/Library/KernelCollections/BootKernelExtensions.kc, a Sequoia self-test)
or one taken out of the Tahoe installer (tahoe.sh kc). Exit 0 only if every patch matches as OpenCore needs.
"""
import bisect, copy, plistlib, struct, sys

TAHOE_MIN, TAHOE_MAX = "25.0.0", "25.99.99"
# OpenCore 1.0.8 CpuidPatches.c "core per package" variants; we write 64 (0x40), not OpenCore's 128: the i5-13420H
# reports 64 logical IDs in CPUID leaf 1, and 64/128 = 0 threads per core is the divide by zero (hackintosh test L).
CPP = {
    "V1":   (bytes.fromhex("c1e81affc089"), None, bytes.fromhex("b84000000089"), None),
    "V1_5": (bytes.fromhex("c1ea1affc289"), None, bytes.fromhex("ba4000000089"), None),
    # shr eax/edx,0x1a; add eax/edx,1 -> shr; nop; mov al/dl,0x40 (edx's high bits are 0 after the shift)
    "V2":   (bytes.fromhex("c1e81a83c00189"), bytes.fromhex("fffdfffffdffff"),
             bytes.fromhex("c1e81a90b04089"), bytes.fromhex("fffdfffffdffff")),
}


def kernel_image(kc):
    ncmds = struct.unpack_from("<I", kc, 16)[0]
    p = 32
    for _ in range(ncmds):
        c, s = struct.unpack_from("<II", kc, p)
        if c == 0x80000035:  # LC_FILESET_ENTRY
            _, fo, eo = struct.unpack_from("<QQI", kc, p + 8)
            if kc[p + eo:kc.index(b"\0", p + eo)] == b"com.apple.kernel":
                return fo
        p += s
    sys.exit("no com.apple.kernel entry in this KC (not a kernel collection?)")


def load(path):
    kc = open(path, "rb").read()
    hdr = kernel_image(kc)
    segs, syms = [], {}
    ncmds = struct.unpack_from("<I", kc, hdr + 16)[0]
    p = hdr + 32
    for _ in range(ncmds):
        c, s = struct.unpack_from("<II", kc, p)
        if c == 0x19:  # LC_SEGMENT_64
            name = kc[p + 8:p + 24].rstrip(b"\0").decode()
            vm, vs, fo, fs = struct.unpack_from("<QQQQ", kc, p + 24)
            segs.append((name, vm, vs, fo, fs))
        elif c == 2:  # LC_SYMTAB
            symoff, nsyms, stroff, _ = struct.unpack_from("<IIII", kc, p + 8)
            for i in range(nsyms):
                strx, typ, _, _, val = struct.unpack_from("<IBBhQ", kc, symoff + 16 * i)
                if typ & 0x0E == 0x0E and val:
                    syms.setdefault(kc[stroff + strx:kc.index(b"\0", stroff + strx)].decode(errors="replace"), val)
        p += s
    # in a fileset the kernel's own code segment is __TEXT (the KC's __TEXT_EXEC wraps it)
    text = [s for s in segs if s[0] == "__TEXT_EXEC"] or [s for s in segs if s[0] == "__TEXT"]
    if not text or not syms:
        sys.exit("kernel has no code segment or no symbols")
    _, vm, _, fo, fs = text[0]
    return kc[fo:fo + fs], vm, syms


def hits(code, find, mask, start=0):
    out, i, n = [], start, len(find)
    first = find[0] if not mask or mask[0] == 0xFF else None
    while i <= len(code) - n:
        if first is not None:
            i = code.find(bytes([first]), i)
            if i < 0:
                break
        w = code[i:i + n]
        if (w == find) if not mask else all((a & m) == (b & m) for a, b, m in zip(w, find, mask)):
            out.append(i)
        i += 1
    return out


def check(kcpath, cfgpath):
    code, base_vm, syms = load(kcpath)
    addrs = sorted(set(syms.values()))
    cfg = plistlib.load(open(cfgpath, "rb"))
    pcci = [p for p in cfg["Kernel"]["Patch"] if p.get("Comment", "").startswith("PCCI topo:")]
    if len(pcci) != 4:
        print(f"expected 4 'PCCI topo:' patches in {cfgpath}, found {len(pcci)}")
        return False, None, pcci
    ok = True
    for p in pcci:
        base, find, cnt = p.get("Base", ""), p.get("Find", b""), p.get("Count", 0)
        mask = p.get("Mask") or None
        start = end = None
        if base:
            if base not in syms:
                print(f"FAIL {p['Comment']}: symbol {base} not in this kernel"); ok = False; continue
            start = syms[base] - base_vm
            j = bisect.bisect_right(addrs, syms[base])
            end = (addrs[j] - base_vm) if j < len(addrs) else len(code)
        if not find:
            print(f"ok   {p['Comment']}: {base} at {syms[base]:#x} (Replace at the symbol)")
            continue
        if "cores per package" in p["Comment"]:
            continue  # judged by variant below
        h = hits(code, find, mask, start or 0)
        inside = [x for x in h[:cnt] if end is None or x < end]
        good = len(h) >= cnt and len(inside) == cnt
        ok &= good
        where = f" in {base} [{start:#x},{end:#x})" if base else ""
        print(f"{'ok  ' if good else 'FAIL'} {p['Comment']}: {len(h)} hits{where}, first {cnt}: "
              f"{[hex(x + base_vm) for x in h[:cnt]]}, inside: {len(inside)}")
    found = {k: hits(code, f, m) for k, (f, m, _, _) in CPP.items()}
    for k, h in found.items():
        print(f"     cores-per-package {k}: {len(h)} hits {[hex(x + base_vm) for x in h[:4]]}")
    # OpenCore order on Monterey+: V2, then V1_5. One unique hit is what we can trust.
    variant = next((k for k in ("V2", "V1_5") if len(found[k]) == 1), None)
    if variant is None:
        print("FAIL cores per package: neither V2 nor V1_5 has exactly one hit"); ok = False
    else:
        print(f"ok   cores per package: variant {variant}")
    return ok, variant, pcci


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "strip":
        cfg = plistlib.load(open(sys.argv[2], "rb"))
        old = cfg["Kernel"]["Patch"]
        cfg["Kernel"]["Patch"] = [p for p in old if not (p.get("Comment", "").startswith("PCCI topo:")
                                                         and p.get("MinKernel") == TAHOE_MIN)]
        with open(sys.argv[3], "wb") as fh:
            plistlib.dump(cfg, fh)
        print(f"wrote {sys.argv[3]}: {len(old) - len(cfg['Kernel']['Patch'])} Darwin 25 PCCI patches removed")
        return
    if len(sys.argv) < 4 or sys.argv[1] not in ("check", "add") or (sys.argv[1] == "add" and len(sys.argv) != 5):
        sys.exit(__doc__)
    ok, variant, pcci = check(sys.argv[2], sys.argv[3])
    if sys.argv[1] == "check":
        sys.exit(0 if ok else 1)
    if not ok:
        sys.exit("not all patches match this kernel; nothing written")
    cfg = plistlib.load(open(sys.argv[3], "rb"))
    patches = cfg["Kernel"]["Patch"]
    if any(p.get("MinKernel") == TAHOE_MIN and p.get("Comment", "").startswith("PCCI topo:") for p in patches):
        sys.exit("config already has Darwin 25 PCCI patches; nothing written")
    for p in pcci:
        t = copy.deepcopy(p)
        t["MinKernel"], t["MaxKernel"] = TAHOE_MIN, TAHOE_MAX
        t["Comment"] = p["Comment"] + " (Tahoe)"
        if "cores per package" in p["Comment"]:
            f, m, r, rm = CPP[variant]
            t.update(Find=f, Mask=m or b"", Replace=r, ReplaceMask=rm or b"", Base="", Count=1)
            t["Comment"] = f"PCCI topo: cores per package 64 {variant} (Tahoe)"
        patches.append(t)
    with open(sys.argv[4], "wb") as fh:
        plistlib.dump(cfg, fh)
    print(f"wrote {sys.argv[4]}: 4 Darwin 25 PCCI patches added (cores per package {variant})")


if __name__ == "__main__":
    main()
