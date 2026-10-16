#!/bin/bash
# apply.sh [fix|debug|restore] - patch the cached NMXGPU (nullmoth 2.0.2) used by the 1401 app's Intel test driver.
#   fix (default) = patches 1, 2, 4 and 5 (the fixes)
#   debug         = the fixes plus patch 3 (drm debug messages DRIVER+KMS in the log)
#   restore       = put back the original binary from the backup
# After applying: in the 1401 app turn the Intel test driver off and on again, then restart.
# Every patch checks the bytes it replaces first, so running it twice or on another version changes nothing.
set -u
BIN=${NMX_BIN:-/Library/NullMoth/kexts/15/NMXGPU.kext/Contents/MacOS/NMXGPU}
# sudo may reset HOME: the backup lives in the home of the user who ran sudo
UH=$(eval echo "~${SUDO_USER:-$(id -un)}")
BK=${NMX_BACKUP:-"$UH/NMXGPU.original"}
ORIG_SHA=33aa04a8681223e56228223491c8205ec3023289a49187d8668c0458eda61c77
LEVEL="${1:-fix}"
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo bash $0 $LEVEL"; exit 1; }
[ -f "$BIN" ] || { echo "not found: $BIN (is the 1401 app / nullmoth 2.0.2 installed?)"; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

if [ "$LEVEL" = restore ]; then
  [ -f "$BK" ] || { echo "no backup at $BK"; exit 1; }
  [ "$(sha "$BK")" = "$ORIG_SHA" ] || { echo "backup is not the original 2.0.2 binary"; exit 1; }
  cp "$BK" "$BIN" && echo "restored the original ($(sha "$BIN"))"; exit $?
fi
case "$LEVEL" in fix|debug) ;; *) echo "usage: sudo bash $0 [fix|debug|restore]"; exit 1;; esac

# back up the original once (only if the file still is the original)
if [ ! -f "$BK" ]; then
  if [ "$(sha "$BIN")" = "$ORIG_SHA" ]; then cp "$BIN" "$BK" && echo "backup: $BK"
  else echo "warning: no backup and the binary is not the original 2.0.2 - continuing, each patch checks its bytes"; fi
fi

hexfile() { printf "$(echo "$1" | sed 's/../\\x&/g')" > "$2"; }
# patch <name> <offset> <original hex> <new hex>
patch() {
  local n=$1 off=$2 old=$3 new=$4 len=$(( ${#3} / 2 ))
  hexfile "$old" "$T/old"; hexfile "$new" "$T/new"
  dd if="$BIN" of="$T/cur" bs=1 skip="$off" count="$len" 2>/dev/null
  if cmp -s "$T/cur" "$T/new"; then echo "$n: already applied"; return 0; fi
  if ! cmp -s "$T/cur" "$T/old"; then echo "$n: unexpected bytes at $off - wrong version? not touching it"; return 1; fi
  dd if="$T/new" of="$BIN" bs=1 seek="$off" conv=notrunc 2>/dev/null && echo "$n: applied"
}

ok=0
patch "patch 1 (xe stops claiming i915 GPUs)" 13212864 86800000 00000000 || ok=1
patch "patch 2 (assume the Alder/Raptor Lake-P PCH)" 8378636 \
  488b7308488d0dfae83e004c8d0512d4400031ffba c783f02500000800000066c783f42500008051ebde || ok=1
if [ "$LEVEL" = debug ]; then
  patch "patch 3 (drm debug: DRIVER+KMS)" 4387952 851552559300 f7c206000000 || ok=1
fi
patch "patch 4 (no DP tunnel manager is not an error)" 7847302 b89affffff 31c0909090 || ok=1
patch "patch 5 (no DP tunnel helpers: link check passes)" 7846980 b89affffff 31c0909090 || ok=1
echo "sha256: $(sha "$BIN")"
echo "expected: fix=3a879558...  debug=c55a4432..."
[ $ok = 0 ] && echo "now: 1401 app -> Intel test driver off, on again -> restart"
exit $ok
