#!/bin/bash
# ondemand.sh: on the hybrid (efi.sh wexrtx), only the apps named here get the RTX as a Metal device; every other app
# stays on the Iris Xe. With nullmoth's default list ("*"), every process that lists Metal devices (Finder, Spotlight,
# loginwindow...) opens the RTX and NVK boosts it to max clocks until that process exits (PERF_BOOST INFINITE, XE-7).
#   sudo bash tools/hybrid/ondemand.sh on            the RTX for nobody (default on the hybrid)
#   sudo bash tools/hybrid/ondemand.sh add NAME      also give the RTX to NAME (the process name, as in Activity Monitor)
#   sudo bash tools/hybrid/ondemand.sh remove NAME   take it back
#   sudo bash tools/hybrid/ondemand.sh off           nullmoth's list back (* and !WindowServer), for the RTX route
#   bash tools/hybrid/ondemand.sh status             the list and which processes hold the RTX now
# Apps pick up a change when they restart. The 1401 app may rewrite the list when it reinstalls the driver.
set -uo pipefail
LIST=/Library/GPUBundles/nvmtl-allow.txt
HDR="# nmx on-demand (tools/hybrid/ondemand.sh): only the apps below get the RTX"
holders() { lsof -n 2>/dev/null | awk '/libvulkan_nouveau/ {print $1, $2}' | sort -u; }
need_root() { [ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }; }
case "${1:-}" in
on)
    need_root
    [ -f "$LIST.nullmoth" ] || cp "$LIST" "$LIST.nullmoth" || { echo "could not back up $LIST; nothing changed"; exit 1; }
    grep -q "^$HDR" "$LIST" || { printf '%s\n' "$HDR" > "$LIST" || exit 1; }
    echo "on: RTX only for:"; grep -v '^#' "$LIST"
    ;;
add|remove)
    need_root
    [ -n "${2:-}" ] || { echo "usage: $0 $1 NAME"; exit 1; }
    grep -q "^$HDR" "$LIST" || { echo "on-demand is off: run '$0 on' first"; exit 1; }
    grep -vxF -- "$2" "$LIST" > "$LIST.tmp"
    [ "$1" = add ] && printf '%s\n' "$2" >> "$LIST.tmp"
    mv -f "$LIST.tmp" "$LIST" && chmod 644 "$LIST" || exit 1
    echo "RTX for:"; grep -v '^#' "$LIST"
    ;;
off)
    need_root
    if [ -f "$LIST.nullmoth" ]; then mv -f "$LIST.nullmoth" "$LIST"; else printf '*\n!WindowServer\n' > "$LIST"; fi
    echo "off: nullmoth's list back"; cat "$LIST"
    ;;
status)
    cat "$LIST"; echo "--- processes holding the RTX:"; holders
    ;;
*) echo "usage: sudo bash $0 on|add NAME|remove NAME|off|status"; exit 1 ;;
esac
