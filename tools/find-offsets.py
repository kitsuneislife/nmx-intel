#!/usr/bin/env python3
"""find-offsets.py NMXGPU - locate the three patch sites in an NMXGPU binary (any nullmoth release).

Needs `nm` (macOS) or `llvm-nm` (Linux) for the symbol table. Prints, for each patch, the file offset, the bytes
there now and the bytes the patch writes, in the form patches/apply.sh uses. Prints NOT FOUND when the code no longer
looks the way the patch expects (the driver changed: re-read the function before patching anything).
Run with python3 -I.
"""
import shutil, struct, subprocess, sys

path = sys.argv[1]
data = open(path, 'rb').read()

# Mach-O 64 segments: vmaddr -> file offset
ncmds = struct.unpack_from('<I', data, 16)[0]
segs, off = [], 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', data, off)
    if cmd == 0x19:  # LC_SEGMENT_64
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', data, off + 24)
        segs.append((vmaddr, vmsize, fileoff, filesize))
    off += size
def fo(va):
    for vmaddr, vmsize, fileoff, filesize in segs:
        if vmaddr <= va < vmaddr + filesize:
            return va - vmaddr + fileoff
    raise ValueError(hex(va))

nm = shutil.which('llvm-nm') or 'nm'
syms = {}
for line in subprocess.run([nm, path], capture_output=True, text=True).stdout.splitlines():
    p = line.split()
    if len(p) == 3:
        syms.setdefault((p[2], p[1]), int(p[0], 16))
def sym(name, kinds='TtDdSs'):
    for k in kinds:
        if (name, k) in syms:
            return syms[(name, k)]
    return None
def rel32(body, at, va):  # target address of the rel32 operand at body[at], whose instruction ends at va
    return va + struct.unpack_from('<i', body, at)[0]
def show(name, o, new):
    print(f'{name}: offset {o} ({o:#x}) now {data[o:o + len(new)].hex()} -> {new.hex()}')

# 1: xe's PCI id table - zero the first entry's vendor so xe matches nothing
xe = sym('_xe_pci_driver')
if xe is None:
    print('patch 1: NOT FOUND (_xe_pci_driver)')
else:
    table = struct.unpack_from('<Q', data, fo(xe) + 24)[0]   # list_head (16), name (8), id_table
    o = fo(table)
    if data[o:o + 4] == b'\x86\x80\x00\x00':
        show('patch 1', o, b'\0\0\0\0')
    else:
        print(f'patch 1: NOT FOUND (xe table at {o:#x} does not start with vendor 8086)')

# 2: intel_detect_pch (i915's global copy): the "No PCH found" branch stores PCH_ADP / 0x5180 and returns
f, get_class = sym('_intel_detect_pch', 'T'), sym('_lkpi_pci_get_class')
try:
    o = fo(f)
    body = data[o:o + 0x300]
    # movl $0x403 (PCH_LNL), <pch_type>(%rbx) and the jmp after it to the epilogue
    i = body.index(b'\xc7\x83')
    while body[i + 6:i + 10] != b'\x03\x04\x00\x00':
        i = body.index(b'\xc7\x83', i + 1)
    pch_type_off = struct.unpack_from('<I', body, i + 2)[0]
    j = i + 10
    if body[j] == 0xeb:
        epilogue = f + j + 2 + struct.unpack_from('<b', body, j + 1)[0]
    else:
        epilogue = f + j + 5 + struct.unpack_from('<i', body, j + 1)[0]
    # first call to lkpi_pci_get_class, then the je (0f 84) that is taken when it returned NULL
    k = 0
    while True:
        k = body.index(b'\xe8', k + 1)
        if rel32(body, k + 1, f + k + 5) == get_class:
            break
    m = body.index(b'\x0f\x84', k)
    nopch = rel32(body, m + 2, f + m + 6)
    code = (b'\xc7\x83' + struct.pack('<I', pch_type_off) + struct.pack('<I', 8) +          # PCH_ADP
            b'\x66\xc7\x83' + struct.pack('<I', pch_type_off + 4) + struct.pack('<H', 0x5180))
    code += b'\xeb' + struct.pack('<b', epilogue - (nopch + len(code) + 2))
    show('patch 2', fo(nopch), code)
except (ValueError, TypeError, struct.error) as e:
    print(f'patch 2: NOT FOUND ({e})')

# 3: __drm_dev_dbg: "testl %edx, __drm_debug(%rip)" -> "testl $0x6, %edx" (DRIVER | KMS always on)
f, dbg = sym('___drm_dev_dbg', 'T'), sym('___drm_debug')
try:
    o = fo(f)
    body = data[o:o + 0x100]
    k = -1
    while True:
        k = body.index(b'\x85\x15', k + 1)
        if rel32(body, k + 2, f + k + 6) == dbg:
            break
    show('patch 3', o + k, b'\xf7\xc2\x06\x00\x00\x00')
except (ValueError, TypeError) as e:
    print(f'patch 3: NOT FOUND ({e})')

# 4: intel_dp_tunnel_mgr_init returns drm_dp_tunnel_mgr_create()'s stub error (-EOPNOTSUPP, -102 on xnu) -> return 0
f = sym('_intel_dp_tunnel_mgr_init', 'T')
try:
    o = fo(f)
    k = data[o:o + 0x80].index(b'\xb8\x9a\xff\xff\xff')   # movl $-102, %eax
    show('patch 4', o + k, b'\x31\xc0\x90\x90\x90')         # xorl %eax, %eax; nop x3
except (ValueError, TypeError) as e:
    print(f'patch 4: NOT FOUND ({e}) - the tunnel helper may be built in now; check the function before patching')

# 5: intel_dp_tunnel_atomic_check_link returns drm_dp_tunnel_atomic_check_stream_bws()'s stub error -> return 0
f = sym('_intel_dp_tunnel_atomic_check_link', 'T')
try:
    o = fo(f)
    k = data[o:o + 0x40].index(b'\xb8\x9a\xff\xff\xff')
    show('patch 5', o + k, b'\x31\xc0\x90\x90\x90')
except (ValueError, TypeError) as e:
    print(f'patch 5: NOT FOUND ({e}) - the tunnel helper may be built in now; check the function before patching')
