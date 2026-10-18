#!/bin/bash
# build.sh: makes NVRM with the copy-engine wait asleep instead of spinning (bridge stage 4c, RTX-25), from nullmoth's
# 2.1.0 NVRM (sha256 12fcabf3…) or 2.3.6 NVRM (122b3994…). In nvrm_ce_copy_to_pages' contiguous-run path (nvrm_pageoff.c), the wait for
# the copy engine is `while (progress < workId) { if (++spins > 200000) timeout; osDelayUs(10); }`: IODelay, a spin,
# ~1.4 ms per frame under RM's locks. Three patches (file offset = vm address in this kext):
#   0x1aec1  movl $200000,%r15d  -> $2000   (the timeout stays ~2 s with 1 ms steps)
#   0x1aecd  movl $10,%edi       -> $1
#   0x1aed2  callq _osDelayUs    -> callq _os_delay (0x13900: IOSleep(ms)); RM's GPU lock waiters sleep on a
#            semaphore, so sleeping while holding it is allowed (RM does it itself)
# 2.3.6 (same source; the compiler counts down from 200001 instead): 0x1b778 movl $200001,%r15d -> $2001,
#   0x1b783 movl $10,%edi -> $1, 0x1b788 callq _osDelayUs (0x2b4640) -> callq _os_delay (0x14160).
# SRCK picks the input: ~/NVRM.kext.original (2.1.0) by default, or e.g. the 2.3.6 package's
#   SRCK=~/nmx-build/pkg-2.3.6/x/pkgroot/Library/Extensions/NVRM.kext bash tools/nvrm/build.sh
# Each patch checks the bytes it replaces. Output: ~/nmx-build/nvrm/out/NVRM.kext (not versioned: PolyForm).
#   bash tools/nvrm/build.sh
set -euo pipefail
SRCK=${SRCK:-$HOME/NVRM.kext.original}; [ -d "$SRCK" ] || SRCK=/Library/Extensions/NVRM.kext
OUT=$HOME/nmx-build/nvrm/out; B=$OUT/NVRM.kext/Contents/MacOS/NVRM
case "$(shasum -a 256 "$SRCK/Contents/MacOS/NVRM" | cut -d' ' -f1)" in
  12fcabf397812974cd3e1c4f61b53ceb73aceb10a1332ccb1a0196b641a3e639) V=2.1.0;;
  122b3994729c8dd9ba17b21cdccb46723edb7ab5a34a224c7de61d6f721d0d35) V=2.3.6;;
  *) echo "$SRCK is not nullmoth 2.1.0's or 2.3.6's NVRM"; exit 1;;
esac
rm -rf "$OUT" && mkdir -p "$OUT" && ditto "$SRCK" "$OUT/NVRM.kext"
patch() {   # patch <offset> <old hex> <new hex>
  local have; have=$(xxd -p -s "$1" -l $(( ${#2} / 2 )) "$B")
  [ "$have" = "$2" ] || { echo "at $1: $have, expected $2; nothing written"; exit 1; }
  printf '%s' "$3" | xxd -r -p | dd of="$B" bs=1 seek=$(( $1 )) conv=notrunc 2>/dev/null
}
if [ "$V" = 2.1.0 ]; then
  patch 0x1aec1 41bf400d0300 41bfd0070000
  patch 0x1aecd bf0a000000 bf01000000
  patch 0x1aed2 e8b98e2900 e8298affff; AT=1aec1
else
  patch 0x1b778 41bf410d0300 41bfd1070000
  patch 0x1b783 bf0a000000 bf01000000
  patch 0x1b788 e8b38e2900 e8d389ffff; AT=1b778
fi
codesign -f -s - "$OUT/NVRM.kext" >/dev/null 2>&1 || true
echo "NVRM $(shasum -a 256 "$B" | cut -c1-8)  (nullmoth $V, from $SRCK)"
otool -tV -p _nvrm_ce_copy_to_pages "$B" | grep -A4 "$AT" | head -5
