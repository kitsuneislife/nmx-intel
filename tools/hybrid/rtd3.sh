#!/bin/bash
# rtd3.sh: RTD3-0, find the RTX's ACPI power resource for nullmoth's opt-in D3cold (nvrtd3=1 nvrtd3res=<path>).
# macOS does not expose the ACPI tables, so the DEBUG OpenCore dumps them once (SysReport):
#   sudo SYSREPORT=1 HWP=off bash tools/cpu/cpufriend.sh arm    one boot of the daily config plus the dump
#   sudo bash tools/hybrid/rtd3.sh acpi                         in that boot: copy the dump, list _PR3 and power resources
# The RTX is \_SB.PC00.PEG0.PEGP [measured, ioreg acpi-path]; the resource we want is the one in PEG0/PEGP's _PR3.
set -uo pipefail
HOMEU=$(eval echo "~${SUDO_USER:-$USER}")
DST=$HOMEU/nmx-build/acpi
die() { echo "STOP: $*"; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"

case "${1:-}" in
acpi)
    ESP=$(diskutil info disk0s1 2>/dev/null | sed -n 's/^ *Mount Point: *//p')
    [ -n "$ESP" ] || { diskutil mount disk0s1 >/dev/null 2>&1; ESP=$(diskutil info disk0s1 | sed -n 's/^ *Mount Point: *//p'); }
    [ -d "$ESP/SysReport/ACPI" ] || die "no SysReport/ACPI on the ESP ($ESP): boot the SYSREPORT=1 arm first"
    rm -rf "$DST" && mkdir -p "$DST" && cp -R "$ESP/SysReport/." "$DST/" || die "could not copy the dump"
    chown -R "${SUDO_USER:-root}" "$DST"
    OUT=$HOMEU/rtd3-acpi.txt
    /usr/bin/python3 -I - "$DST/ACPI" > "$OUT" <<'EOF' || die "the AML scan failed"
import os, re, sys
# AML: PowerResource = 5B 84 PkgLength NameString; a _PR3 is Name(_PR3, Package(){...}) = 08 "_PR3" 12 PkgLength n ...
def pkglen(b, i):
    lead = b[i]; n = lead >> 6
    return (i + 1 + n) if n else i + 1
seg = rb"[A-Z_][A-Z0-9_]{3}"
name = rb"\\?\^*(?:\x2e" + seg + seg + rb"|\x2f[\x01-\x0a](?:" + seg + rb")+|" + seg + rb")"
def show(raw):   # \_SB_.PC00.PEG0.PXP_ style
    pre = re.match(rb"[\\^]*", raw).group()
    body = re.sub(rb"^[\x2e]|^\x2f[\x01-\x0a]", b"", raw[len(pre):])
    return (pre + b".".join(body[i:i + 4] for i in range(0, len(body), 4))).decode("latin1")
d = sys.argv[1]
for f in sorted(os.listdir(d)):
    b = open(os.path.join(d, f), "rb").read()
    if b[:4] not in (b"DSDT", b"SSDT"):
        continue
    oem = b[16:24].decode("latin1").strip()
    hits = []
    for m in re.finditer(rb"\x5b\x84", b):
        j = pkglen(b, m.end()); n = re.match(name, b[j:j + 40])
        if n: hits.append(f"  PowerResource {show(n.group())} at 0x{m.start():x}")
    for m in re.finditer(rb"\x08_PR3\x12", b):
        j = pkglen(b, m.end()) + 1; n = re.match(name, b[j:j + 40])
        ctx = re.findall(rb"[A-Z_][A-Z0-9_]{3}", b[max(0, m.start() - 200):m.start()])[-6:]
        hits.append(f"  _PR3 -> {show(n.group()) if n else '?'} at 0x{m.start():x} (names before: {b' '.join(ctx).decode()})")
    if hits or b"PEG0" in b:
        print(f"{f} {b[:4].decode()} '{oem}' {len(b)} bytes, mentions PEG0: {b'PEG0' in b}")
        print("\n".join(hits))
EOF
    chown "${SUDO_USER:-root}" "$OUT"
    cat "$OUT"
    echo "saved $OUT and the dump in $DST"
    ;;
*) die "usage: sudo bash $0 acpi" ;;
esac
