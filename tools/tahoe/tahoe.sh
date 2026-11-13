#!/bin/bash
# tahoe.sh: TAHOE-1, the in-place upgrade from Sequoia 15.8.1 to Tahoe 26.7.x with the hybrid stack
# (docs/tests/tahoe-1.md). Each command stops at the first problem and says what is missing.
#   bash tools/tahoe/tahoe.sh check          what is ready and what is not (no sudo, changes nothing)
#   bash tools/tahoe/tahoe.sh kc             takes BootKernelExtensions.kc out of the downloaded installer into
#                                            ~/nmx-build/tahoe/ and checks the PCCI CPU patches against its kernel
#   sudo bash tools/tahoe/tahoe.sh patch     adds Darwin 25 copies of the PCCI patches to the ESP configs (only
#                                            after kc passed; Sequoia ignores them: MinKernel 25.0.0)
#   sudo bash tools/tahoe/tahoe.sh volume    TAHOE-1a, the test route with no backup disk: a new APFS volume "Tahoe" in
#                                            the same container (Sequoia stays untouched and bootable) and the plain
#                                            config for the installer; then the installer is pointed at "Tahoe"
#   bash ".../tahoe.sh" link                 on the Tahoe volume (no sudo): links ~/nmx-build and
#                                            ~/Documents/Projetos/nmx-intel to the Sequoia volume's copies, so the
#                                            install scripts find the builds without copying them
#   sudo bash tools/tahoe/tahoe.sh prepare   right before an in-place upgrade: takes the Sequoia-only drivers out of
#                                            /Library (WhateverXe Graphics, AirportMtkWlan) and boots the plain
#                                            config (efi.sh plain: no GPU driver, -nvoff -v), which stays through
#                                            the installer's reboots
#   sudo bash tools/tahoe/tahoe.sh undo      back to the daily Sequoia setup if the upgrade was not started
#   sudo bash tools/tahoe/tahoe.sh remove    staying on Sequoia (2026-11-13): deletes the Tahoe volume group, the
#                                            installer and the Tahoe build files, takes the Darwin 25 PCCI patches
#                                            out of the ESP configs and boots the daily hybrid (efi.sh wexrtx-keep)
set -uo pipefail
HERE=$(cd "$(dirname "$0")/../.." && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-$(id -un)}")
VER=${TAHOE_VER:-26.7.3}
APP="/Applications/Install macOS Tahoe.app"
WD=$HOMEU/nmx-build/tahoe; KCF=$WD/BootKernelExtensions.kc
ESP=$(diskutil info disk0s1 2>/dev/null | sed -n 's/^ *Mount Point: *//p')
OC=$ESP/EFI/OC
free_gb() { df -g /System/Volumes/Data | awk 'NR==2{print $4}'; }
root() { [ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }; }
esp() { [ -n "$ESP" ] && [ -f "$OC/config-gpu-only.plist" ] || { echo "ESP not mounted or no config-gpu-only.plist (sudo diskutil mount disk0s1)"; exit 1; }; }

case "${1:-}" in
check)
    bad=0; say() { printf '%-4s %s\n' "$1" "$2"; [ "$1" = NO ] && bad=1; }
    [ "$(sw_vers -productVersion)" = 15.8.1 ] && say ok "running Sequoia 15.8.1" || say "--" "running $(sw_vers -productVersion)"
    [ "$(sysctl -n hw.model)" = MacBookPro16,1 ] && say ok "SMBIOS MacBookPro16,1 (Tahoe supports it)" || say NO "SMBIOS $(sysctl -n hw.model)"
    OCV=$(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version 2>/dev/null | awk '{print $2}')
    case "$OCV" in *-10[5-9]-*|*-1[1-9][0-9]-*) say ok "OpenCore $OCV (Tahoe needs 1.0.5+)" ;; *) say NO "OpenCore '$OCV'" ;; esac
    F=$(free_gb)
    if [ -d "$APP" ]; then
        [ "$F" -ge 30 ] && say ok "installer present, ${F} GB free (30 needed for the upgrade)" || say NO "installer present, only ${F} GB free (30 needed)"
    else
        [ "$F" -ge 50 ] && say ok "${F} GB free (installer 18 GB + upgrade 30 GB)" || say NO "only ${F} GB free: free about $((50 - F)) GB, then download the installer"
        say NO "no installer: softwareupdate --fetch-full-installer --full-installer-version $VER"
    fi
    [ -f "$WD/kc-check.txt" ] && grep -q '^ok   cores per package' "$WD/kc-check.txt" && ! grep -q '^FAIL' "$WD/kc-check.txt" \
        && say ok "PCCI patches checked against the Tahoe kernel ($(sed -n 1p "$WD/kc-version.txt" 2>/dev/null))" || say NO "PCCI patches not checked on Tahoe yet: tahoe.sh kc"
    if [ -n "$ESP" ]; then
        grep -q 'PCCI topo:.*(Tahoe)' "$OC/config-gpu-only.plist" && say ok "config-gpu-only.plist has the Darwin 25 PCCI patches" || say NO "ESP configs lack Darwin 25 PCCI patches: sudo tahoe.sh patch"
    else say NO "ESP not mounted (sudo diskutil mount disk0s1)"; fi
    [ -f "$HOMEU/nmx-build/wifi5/out-tahoe/AirportMtkWlan.kext/Contents/MacOS/AirportMtkWlan" ] && say ok "Wi-Fi Tahoe build present" || say NO "no Wi-Fi Tahoe build: AIRPORT_OS=tahoe bash tools/wifi/build-airport.sh"
    [ -f "$HOMEU/nmx-build/whateverxe/dl/g043/WhateverXe-Graphics-0.4.3.pkg" ] && say ok "WhateverXe Graphics 0.4.3 pkg present (has Tahoe.pkg)" || say NO "no WhateverXe Graphics 0.4.3 pkg"
    LB=$(tmutil latestbackup 2>/dev/null)
    [ -n "$LB" ] && say ok "Time Machine: $LB" || say "--" "no Time Machine backup: use the volume route (tahoe.sh volume), not prepare"
    diskutil info Tahoe >/dev/null 2>&1 && say "--" "APFS volume Tahoe exists" || say "--" "no APFS volume Tahoe yet (tahoe.sh volume)"
    [ "$bad" = 0 ] && echo "ready: sudo bash tools/tahoe/tahoe.sh volume" || echo "not ready yet"
    exit $bad
    ;;
kc)
    SS="$APP/Contents/SharedSupport/SharedSupport.dmg"
    [ -f "$SS" ] || { echo "no $SS: softwareupdate --fetch-full-installer --full-installer-version $VER"; exit 1; }
    mkdir -p "$WD"; M=$(mktemp -d)
    hdiutil attach -nobrowse -readonly -noverify -mountpoint "$M" "$SS" >/dev/null || { echo "could not mount SharedSupport.dmg"; exit 1; }
    trap 'hdiutil detach "$M" >/dev/null 2>&1' EXIT
    X="$M/com_apple_MobileAsset_MacSoftwareUpdate/com_apple_MobileAsset_MacSoftwareUpdate.xml"
    /usr/bin/python3 -I -c 'import plistlib,sys; a=plistlib.load(open(sys.argv[1],"rb"))["Assets"][0]; print(a.get("OSVersion"), a.get("Build"))' "$X" > "$WD/kc-version.txt" 2>/dev/null
    echo "installer: $(cat "$WD/kc-version.txt" 2>/dev/null)"
    Z=$(ls "$M"/com_apple_MobileAsset_MacSoftwareUpdate/*.zip 2>/dev/null | head -1)
    [ -n "$Z" ] || { echo "no update zip in SharedSupport.dmg"; exit 1; }
    unzip -Z1 "$Z" > "$WD/zip-list.txt" 2>/dev/null
    E=$(grep -E 'AssetData/boot/.*BootKernelExtensions\.kc$' "$WD/zip-list.txt" | head -1)
    [ -n "$E" ] || { grep -i -E 'kernel|\.kc' "$WD/zip-list.txt" > "$WD/zip-kernel.txt"; echo "no BootKernelExtensions.kc in the zip; names with kernel/.kc are in $WD/zip-kernel.txt"; exit 1; }
    echo "extracting $E"
    unzip -p "$Z" "$E" > "$KCF.tmp" && mv -f "$KCF.tmp" "$KCF" || { echo "extract failed"; exit 1; }
    echo "BootKernelExtensions.kc $(shasum -a 256 "$KCF" | cut -c1-8)"
    esp
    /usr/bin/python3 -I "$HERE/tools/tahoe/kpatch.py" check "$KCF" "$OC/config-gpu-only.plist" | tee "$WD/kc-check.txt"
    [ "${PIPESTATUS[0]}" = 0 ] && echo "all PCCI patches match the Tahoe kernel: sudo bash tools/tahoe/tahoe.sh patch" || { echo "a patch does not match: do not upgrade, send $WD/kc-check.txt"; exit 1; }
    ;;
patch)
    root; esp
    [ -f "$KCF" ] || { echo "no $KCF: bash tools/tahoe/tahoe.sh kc first"; exit 1; }
    B=$HOMEU/config-antes-tahoe; mkdir -p "$B" && cp "$OC"/config*.plist "$B/" && chown -R "${SUDO_USER:-root}" "$B" || { echo "could not back up the configs; nothing changed"; exit 1; }
    for c in config-gpu-only.plist config.plist config-wex.plist; do
        [ -f "$OC/$c" ] || continue
        grep -q 'PCCI topo:.*(Tahoe)' "$OC/$c" && { echo "$c: already has them"; continue; }
        /usr/bin/python3 -I "$HERE/tools/tahoe/kpatch.py" add "$KCF" "$OC/$c" "$OC/$c.new" >/dev/null \
            && plutil -lint "$OC/$c.new" >/dev/null && mv -f "$OC/$c.new" "$OC/$c" \
            || { rm -f "$OC/$c.new"; echo "$c: failed; configs backed up in $B"; exit 1; }
        echo "$c: Darwin 25 PCCI patches added"
    done
    sync; echo "backup of the previous configs: $B"
    ;;
volume)
    root; esp
    grep -q 'PCCI topo:.*(Tahoe)' "$OC/config-gpu-only.plist" || { echo "run tahoe.sh patch first; nothing changed"; exit 1; }
    [ -d "$APP" ] || { echo "no installer; nothing changed"; exit 1; }
    CONT=$(diskutil info /System/Volumes/Data | sed -n 's/^ *APFS Container: *//p')
    [ -n "$CONT" ] || { echo "could not find the APFS container; nothing changed"; exit 1; }
    if diskutil info Tahoe >/dev/null 2>&1; then echo "volume Tahoe already exists"
    else diskutil apfs addVolume "$CONT" APFS Tahoe || { echo "addVolume failed; nothing changed"; exit 1; }; fi
    bash "$HERE/tools/hybrid/efi.sh" plain || { echo "efi.sh plain failed; stopped"; exit 1; }
    echo "ready: reboot once into Sequoia (plain) to check it boots, then open \"$APP\" and pick the disk Tahoe"
    echo "back to the daily boot: sudo bash tools/hybrid/efi.sh wexrtx-keep"
    ;;
link)
    [ "$(sw_vers -productVersion | cut -d. -f1)" = 26 ] || { echo "run this on the Tahoe volume"; exit 1; }
    SEQ="/Volumes/macOS - Data/Users/$(id -un)"
    [ -d "$SEQ/nmx-build" ] || { echo "no $SEQ/nmx-build (Sequoia data volume not mounted, or another user name); nothing changed"; exit 1; }
    for p in nmx-build Documents/Projetos/nmx-intel; do
        if [ -e "$HOME/$p" ] || [ -L "$HOME/$p" ]; then echo "~/$p exists, left as is"; continue; fi
        mkdir -p "$(dirname "$HOME/$p")" && ln -s "$SEQ/$p" "$HOME/$p" && echo "~/$p -> $SEQ/$p"
    done
    ;;
prepare)
    root; esp
    grep -q 'PCCI topo:.*(Tahoe)' "$OC/config-gpu-only.plist" || { echo "run tahoe.sh patch first; nothing changed"; exit 1; }
    [ -d "$APP" ] || { echo "no installer; nothing changed"; exit 1; }
    bash "$HERE/tools/hybrid/wex-install.sh" remove || { echo "wex-install.sh remove failed; stopped"; exit 1; }
    bash "$HERE/tools/wifi/install.sh" restore || { echo "wifi install.sh restore failed; stopped"; exit 1; }
    bash "$HERE/tools/hybrid/efi.sh" plain || { echo "efi.sh plain failed; stopped"; exit 1; }
    echo "ready: reboot once into Sequoia (plain) to check it boots, then open \"$APP\""
    ;;
undo)
    root
    bash "$HERE/tools/hybrid/wex-install.sh" && bash "$HERE/tools/wifi/install.sh" airport && bash "$HERE/tools/hybrid/efi.sh" wexrtx-keep
    ;;
remove)
    root; esp
    [ "$(sw_vers -productVersion | cut -d. -f1)" = 15 ] || { echo "run this on Sequoia; nothing changed"; exit 1; }
    G=$(diskutil info Tahoe 2>/dev/null | sed -n 's/^ *APFS Volume Group: *//p')
    MINE=$(diskutil info / | sed -n 's/^ *APFS Volume Group: *//p')
    if [ -n "$G" ]; then
        [ "$G" != "$MINE" ] || { echo "Tahoe is in the running system's volume group?! nothing changed"; exit 1; }
        diskutil apfs deleteVolumeGroup "$G" || { echo "deleteVolumeGroup $G failed; nothing else changed"; exit 1; }
    else echo "no volume Tahoe (already deleted)"; fi
    B=$HOMEU/config-antes-remove-tahoe; mkdir -p "$B" && cp "$OC"/config*.plist "$B/" && chown -R "${SUDO_USER:-root}" "$B" \
        || { echo "could not back up the configs; stopped before touching them"; exit 1; }
    bash "$HERE/tools/hybrid/efi.sh" wexrtx-keep || { echo "efi.sh wexrtx-keep failed; configs backed up in $B"; exit 1; }
    for c in "$OC"/config*.plist; do
        grep -q 'PCCI topo:.*(Tahoe)' "$c" || continue
        /usr/bin/python3 -I "$HERE/tools/tahoe/kpatch.py" strip "$c" "$c.new" && plutil -lint "$c.new" >/dev/null \
            && mv -f "$c.new" "$c" || { rm -f "$c.new"; echo "${c##*/}: strip failed; configs backed up in $B"; exit 1; }
    done
    grep -l 'PCCI topo:.*(Tahoe)' "$OC"/config*.plist && { echo "Tahoe patches still there"; exit 1; }
    rm -rf "$APP" "$WD" "$HOMEU/nmx-build/wifi5/out-tahoe" "$HOMEU/config-antes-tahoe"
    sync; bash "$HERE/tools/hybrid/efi.sh" status
    echo "Tahoe removed; daily hybrid config written (backup of the previous configs: $B). Reboot into macOS."
    ;;
*) sed -n 2,22p "$0"; exit 1 ;;
esac
