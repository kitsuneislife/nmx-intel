#!/bin/bash
# efi.sh: switches OpenCore between the GPU-only route and the hybrid route. Both configs stay on the ESP next to
# config.plist, so either one can be put back from Windows or from Recovery by copying it over config.plist.
#   sudo bash tools/hybrid/efi.sh hybrid     saves config.plist as config-gpu-only.plist (unless it already loads
#                                            NootedGreen), writes config-hybrid.plist from it (hybrid-config.py),
#                                            copies NootedGreen.kext to OC/Kexts and boots the hybrid config ONCE:
#                                            a LaunchDaemon puts GPU-only back early in that boot, so a freeze or
#                                            panic falls back to GPU-only on the next start by itself
#   sudo bash tools/hybrid/efi.sh hybrid-keep  the same, without the one-boot daemon (once hybrid is stable)
#   sudo bash tools/hybrid/efi.sh gpu-only   config-gpu-only.plist back as config.plist, NootedGreen.kext removed
#   sudo bash tools/hybrid/efi.sh status     which route config.plist is
#   boot-once (the daemon's job)             GPU-only back if config.plist is hybrid; logs to /var/log/nmx-hybrid.log
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-root}")
NGK=$HOMEU/nmx-build/hybrid/xps/build/NootedGreen.kext

ESP=$(diskutil info disk0s1 2>/dev/null | sed -n 's/^ *Mount Point: *//p')
# early in boot (boot-once) DiskArbitration may not be up yet: retry for a while
for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -n "$ESP" ] && break
    diskutil mount disk0s1 >/dev/null 2>&1 || sleep 2
    ESP=$(diskutil info disk0s1 2>/dev/null | sed -n 's/^ *Mount Point: *//p')
done
[ -n "$ESP" ] || { echo "could not mount the ESP (disk0s1)"; exit 1; }
OC=$ESP/EFI/OC; CFG=$OC/config.plist; GPU=$OC/config-gpu-only.plist; HYB=$OC/config-hybrid.plist
[ -f "$CFG" ] || { echo "no $CFG"; exit 1; }
is_hybrid() { grep -q '<string>NootedGreen.kext</string>' "$1"; }
# one-boot daemon: a copy of this script outside ~/Documents (TCC blocks launchd's bash there)
DAEMON=/Library/LaunchDaemons/com.nmx.hybrid-once.plist; ONCE=/usr/local/libexec/nmx-hybrid-efi.sh
arm_once() {
    mkdir -p "${ONCE%/*}" && cp "$HERE/efi.sh" "$ONCE" && chmod 755 "$ONCE" || return 1
    cat > "$DAEMON" <<EOP || return 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.nmx.hybrid-once</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$ONCE</string><string>boot-once</string></array>
<key>RunAtLoad</key><true/>
<key>StandardOutPath</key><string>/var/log/nmx-hybrid.log</string>
<key>StandardErrorPath</key><string>/var/log/nmx-hybrid.log</string>
</dict></plist>
EOP
    chown root:wheel "$DAEMON" && chmod 644 "$DAEMON" && plutil -lint "$DAEMON" >/dev/null
}
disarm_once() { rm -f "$DAEMON" "$ONCE"; }

case "${1:-}" in
hybrid|hybrid-keep)
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
    if [ "$1" = hybrid ]; then
        arm_once || { disarm_once; echo "could not install the one-boot daemon; nothing changed"; exit 1; }
    else disarm_once; fi
    cp "$HYB" "$CFG" || { cp "$GPU" "$CFG"; echo "could not switch config.plist; GPU-only put back"; exit 1; }
    sync
    [ "$1" = hybrid ] && echo "one boot only: that boot puts GPU-only back by itself (hybrid-keep to stay)"
    echo "route: hybrid (H1). NootedGreen $(shasum -a 256 "$OC/Kexts/NootedGreen.kext/Contents/MacOS/NootedGreen" | cut -c1-8)"
    echo "boot-args: $(/usr/libexec/PlistBuddy -c 'Print :NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args' "$CFG")"
    ;;
gpu-only)
    [ -f "$GPU" ] || { echo "no config-gpu-only.plist on the ESP; nothing changed"; exit 1; }
    is_hybrid "$GPU" && { echo "config-gpu-only.plist loads NootedGreen; nothing changed"; exit 1; }
    cp "$GPU" "$CFG" || { echo "could not restore config.plist"; exit 1; }
    rm -rf "$OC/Kexts/NootedGreen.kext"
    disarm_once; sync
    echo "route: GPU-only"
    ;;
boot-once)
    echo "$(date): boot-once, booted with: $(sysctl -n kern.bootargs)"
    is_hybrid "$CFG" || { echo "config.plist is GPU-only already"; exit 0; }
    [ -f "$GPU" ] && ! is_hybrid "$GPU" || { echo "no usable config-gpu-only.plist; left hybrid"; exit 1; }
    cp "$GPU" "$CFG" && sync && echo "GPU-only put back for the next start" || { echo "copy failed"; exit 1; }
    diskutil unmount "$ESP" >/dev/null 2>&1   # flushes the FAT volume before a possible panic
    exit 0
    ;;
status)
    is_hybrid "$CFG" && echo "route: hybrid" || echo "route: GPU-only"
    [ -f "$DAEMON" ] && echo "one-boot daemon: armed" || echo "one-boot daemon: off"
    ls -l "$OC"/config*.plist
    ;;
*) echo "usage: sudo bash $0 hybrid|hybrid-keep|gpu-only|status"; exit 1 ;;
esac
echo "Reboot for OpenCore to load it."
