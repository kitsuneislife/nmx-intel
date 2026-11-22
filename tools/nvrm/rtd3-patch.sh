#!/bin/bash
# rtd3-patch.sh: RTD3-3, makes nullmoth 3.0's RTD3 call ACPI methods macOS accepts. Output ~/nmx-build/nvrm/out/NVRM.kext
# (not versioned: PolyForm); tools/nvrm/install.sh puts it in /Library/Extensions and rebuilds the aux collection.
# Why: AppleACPIPlatformExpert::evaluateObject returns kIOReturnBadArgument (0xe00002c2) when the object name is
# longer than 4 characters (BootKernelExtensions.kc, AppleACPIPlatform at 0x...71a4: OSSymbol getLength, cmp $4, ja
# -> 0xe00002c2) [measured by disassembly]. A name is one NameSeg relative to the device. nullmoth's evalMethod
# evaluates "%s.%s" (nvrtd3res + "_OFF") on the first IOACPIPlatformDevice above NVRM, which is \_SB.PC00
# [measured, ioreg], so every nvrtd3res fails (RTD3-1 and RTD3-2). Three patches (file offset = vm address here):
#   0x4fb78f "_OFF\0_ON\0" -> "NXOF\0NXO\0"   method names, not reserved ones (_ON/_OFF belong to power resources)
#   0x4fb81a "%s.%s"       -> "%s\0%s"        snprintf prints only its first argument
#   0x21222  leaq g_res(%rip),%rcx -> movq %r14,%rcx; nopl   that first argument is the method name
# So NVRM evaluates \_SB.PC00.NXOF / \_SB.PC00.NXO_, which SSDT-NXRTD3.aml (tools/hybrid/rtd3-aml.py) defines as calls
# to the RTX's \_SB.PC00.PEG0.PXP_._OFF / _ON_. Without nvrtd3=1 on the boot line evalMethod returns before any of
# this, so the patched kext is inert in the daily config. Each patch checks the bytes it replaces.
#   bash tools/nvrm/rtd3-patch.sh       (rtd3.sh arm runs it)
set -euo pipefail
HOMEU=$(eval echo "~${SUDO_USER:-$(id -un)}")
SRCK=${SRCK:-$HOMEU/NVRM.kext.original}; [ -d "$SRCK" ] || SRCK=/Library/Extensions/NVRM.kext
OUT=$HOMEU/nmx-build/nvrm/out; B=$OUT/NVRM.kext/Contents/MacOS/NVRM
[ "$(shasum -a 256 "$SRCK/Contents/MacOS/NVRM" | cut -d' ' -f1)" = \
  ba6184e9a092687692af1b9e16cff555c7c3f1d81c258c8c8b77273ed7cadf05 ] \
  || { echo "$SRCK is not nullmoth 3.0's NVRM (ba6184e9); nothing written"; exit 1; }
rm -rf "$OUT" && mkdir -p "$OUT" && ditto "$SRCK" "$OUT/NVRM.kext"
patch() {   # patch <offset> <old hex> <new hex>
  local have; have=$(xxd -p -s "$1" -l $(( ${#2} / 2 )) "$B")
  [ "$have" = "$2" ] || { echo "at $1: $have, expected $2; nothing installed"; rm -rf "$OUT"; exit 1; }
  printf '%s' "$3" | xxd -r -p | dd of="$B" bs=1 seek=$(( $1 )) conv=notrunc 2>/dev/null
}
patch 0x4fb78f 5f4f4646005f4f4e00 4e584f46004e584f00
patch 0x4fb81a 25732e257300 257300257300
patch 0x21222 488d0d97f6f300 4c89f10f1f4000
codesign -f -s - "$OUT/NVRM.kext" >/dev/null 2>&1 || true
[ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER" "$HOMEU/nmx-build/nvrm"
echo "NVRM $(shasum -a 256 "$B" | cut -c1-8) (nullmoth 3.0 + RTD3-3 names)"
otool -tV -p __ZL10evalMethodP20IOACPIPlatformDevicePKc "$B" | grep -A1 '^0000000000021222' | head -2
