#!/bin/bash
# efi.sh: switches OpenCore between the GPU-only route and the hybrid route. Both configs stay on the ESP next to
# config.plist, so either one can be put back from Windows or from Recovery by copying it over config.plist.
#   sudo bash tools/hybrid/efi.sh hybrid     saves config.plist as config-gpu-only.plist (unless it already loads
#                                            NootedGreen), writes config-hybrid.plist from it (hybrid-config.py),
#                                            copies NootedGreen.kext to OC/Kexts and boots the hybrid config
#   sudo bash tools/hybrid/efi.sh gpu-only   config-gpu-only.plist back as config.plist, NootedGreen.kext removed
#   sudo bash tools/hybrid/efi.sh status     which route config.plist is
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-root}")
NGK=$HOMEU/nmx-build/hybrid/xps/build/NootedGreen.kext

ESP=$(diskutil info disk0s1 2>/dev/null | sed -n 's/^ *Mount Point: *//p')
if [ -z "$ESP" ]; then diskutil mount disk0s1 >/dev/null || { echo "could not mount the ESP (disk0s1)"; exit 1; }
    ESP=$(diskutil info disk0s1 | sed -n 's/^ *Mount Point: *//p'); fi
OC=$ESP/EFI/OC; CFG=$OC/config.plist; GPU=$OC/config-gpu-only.plist; HYB=$OC/config-hybrid.plist
[ -f "$CFG" ] || { echo "no $CFG"; exit 1; }
is_hybrid() { grep -q '<string>NootedGreen.kext</string>' "$1"; }

case "${1:-}" in
hybrid)
    [ -f "$NGK/Contents/MacOS/NootedGreen" ] || { echo "no $NGK: run zsh tools/hybrid/build.sh first"; exit 1; }
    if is_hybrid "$CFG"; then
        [ -f "$GPU" ] || { echo "config.plist loads NootedGreen and there is no config-gpu-only.plist; nothing changed"; exit 1; }
    else
        cp "$CFG" "$GPU" || { echo "could not save config-gpu-only.plist; nothing changed"; exit 1; }
        cp "$CFG" "$HOMEU/config-antes-hybrid.plist" && chown "${SUDO_USER:-root}" "$HOMEU/config-antes-hybrid.plist"
    fi
    /usr/bin/python3 -I "$HERE/hybrid-config.py" "$GPU" "$HYB" || { echo "could not write config-hybrid.plist; nothing changed"; exit 1; }
    plutil -lint "$HYB" >/dev/null || { echo "config-hybrid.plist does not parse; nothing changed"; exit 1; }
    rm -rf "$OC/Kexts/NootedGreen.kext" && cp -R "$NGK" "$OC/Kexts/" || { echo "could not copy NootedGreen.kext; nothing changed"; exit 1; }
    cp "$HYB" "$CFG" || { cp "$GPU" "$CFG"; echo "could not switch config.plist; GPU-only put back"; exit 1; }
    echo "route: hybrid (H1). NootedGreen $(shasum -a 256 "$OC/Kexts/NootedGreen.kext/Contents/MacOS/NootedGreen" | cut -c1-8)"
    echo "boot-args: $(/usr/libexec/PlistBuddy -c 'Print :NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args' "$CFG")"
    ;;
gpu-only)
    [ -f "$GPU" ] || { echo "no config-gpu-only.plist on the ESP; nothing changed"; exit 1; }
    is_hybrid "$GPU" && { echo "config-gpu-only.plist loads NootedGreen; nothing changed"; exit 1; }
    cp "$GPU" "$CFG" || { echo "could not restore config.plist"; exit 1; }
    rm -rf "$OC/Kexts/NootedGreen.kext"
    echo "route: GPU-only"
    ;;
status)
    is_hybrid "$CFG" && echo "route: hybrid" || echo "route: GPU-only"
    ls -l "$OC"/config*.plist
    ;;
*) echo "usage: sudo bash $0 hybrid|gpu-only|status"; exit 1 ;;
esac
echo "Reboot for OpenCore to load it."
