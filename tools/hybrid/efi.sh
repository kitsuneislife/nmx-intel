#!/bin/bash
# efi.sh: switches OpenCore between the GPU-only route and the hybrid route. Both configs stay on the ESP next to
# config.plist, so either one can be put back from Windows or from Recovery by copying it over config.plist.
#   sudo bash tools/hybrid/efi.sh hybrid     saves config.plist as config-gpu-only.plist (unless it already loads
#                                            NootedGreen), writes config-hybrid.plist from it (hybrid-config.py),
#                                            copies NootedGreen.kext to OC/Kexts and boots the hybrid config ONCE:
#                                            a LaunchDaemon puts GPU-only back early in that boot, so a freeze or
#                                            panic falls back to GPU-only on the next start by itself
#   sudo bash tools/hybrid/efi.sh hybrid-keep  the same, without the one-boot daemon (once hybrid is stable)
#   sudo bash tools/hybrid/efi.sh wex        the same for the WhateverXe route: config-wex.plist (wex-config.py),
#                                            WhateverXe.kext and AMFIPassMod.kext to OC/Kexts, SSDT-PNLF.aml
#                                            (pnlf-aml.py) to OC/ACPI, boots it ONCE
#   sudo bash tools/hybrid/efi.sh wex-keep   the same, without the one-boot daemon
#   sudo bash tools/hybrid/efi.sh wexrtx     the WhateverXe route with nullmoth's NVIDIA driver on, headless (XE-7,
#                                            wex-config.py --rtx), boots it ONCE; wexrtx-keep to stay
#   sudo bash tools/hybrid/efi.sh rtx        RTX-only through nullmoth's own hybrid path (3.0+, NMH-1): config-rtx.plist
#                                            = config-gpu-only.plist minus -nmintelfboff/-nvoff plus nmhybrid=$NMHYBRID
#                                            (default 1, copy) and $RTX_EXTRA; ONE boot: the current config.plist is
#                                            saved as config-back.plist and a LaunchDaemon puts it back early in that
#                                            boot (boot-back). rtx-keep to stay. Needs nullmoth's NMIntelFB installed.
#   sudo bash tools/hybrid/efi.sh gpu-only   config-gpu-only.plist back as config.plist, the route kexts removed
#   sudo bash tools/hybrid/efi.sh plain      no GPU driver at all (firmware framebuffer, as for the first install):
#                                            config-gpu-only.plist plus -nvoff -v, the route kexts removed. Stays
#                                            across reboots (a macOS upgrade restarts several times); TAHOE-1
#   sudo NVOFF=0 bash tools/hybrid/efi.sh plain   the same without -nvoff, which also turns our Wi-Fi driver off
#                                            (TAHOE-2): for the Tahoe volume, which has no nullmoth kexts
#   sudo bash tools/hybrid/efi.sh status     which route config.plist is
#   boot-once (the daemon's job)             GPU-only back if config.plist is hybrid; logs to /var/log/nmx-hybrid.log
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
HOMEU=$(eval echo "~${SUDO_USER:-root}")
NGK=$HOMEU/nmx-build/hybrid/xps/build/NootedGreen.kext
WXK=$HOMEU/nmx-build/whateverxe/kexts   # AMFIPass 1.4.1 Mod as AMFIPassMod.kext; WhateverXe from $WXK/$WEXDIR:
# wex/ = XE-11 (0.8.2 + our 0001..0005), wex-0.6.1-nmx/ = XE-8 (0.6.1 + wex-0001..0004), wex-0.6.1-release/.
# Rollback: sudo WEXDIR=wex-0.6.1-nmx bash tools/hybrid/efi.sh wexrtx-keep
# Test args: sudo WEX_EXTRA="-disablegfxpreemption" bash tools/hybrid/efi.sh wexrtx-keep (run again without it to undo)
# Daily since LAT-8 (2026-11-14): sudo WEXDIR=wex-lat8 WEX_EXTRA="-wex-objpreempt" bash tools/hybrid/efi.sh wexrtx-keep
# LAT-5 test: sudo WEXDIR=wex-lat5 WEX_EXTRA="-wex-objpreempt" WEX_DEV="PreemptionTimerIntervalUS=500" bash tools/hybrid/efi.sh wexrtx
# no existence check here: boot-once runs as root (HOMEU=/var/root) and must not stop on it; the route modes check PUT
WEXDIR=${WEXDIR:-wex}

ESP=$(diskutil info disk0s1 2>/dev/null | sed -n 's/^ *Mount Point: *//p')
# early in boot (boot-once) DiskArbitration may not be up yet: retry for a while
for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -n "$ESP" ] && break
    diskutil mount disk0s1 >/dev/null 2>&1 || sleep 2
    ESP=$(diskutil info disk0s1 2>/dev/null | sed -n 's/^ *Mount Point: *//p')
done
[ -n "$ESP" ] || { echo "could not mount the ESP (disk0s1)"; exit 1; }
OC=$ESP/EFI/OC; CFG=$OC/config.plist; GPU=$OC/config-gpu-only.plist
[ -f "$CFG" ] || { echo "no $CFG"; exit 1; }
is_hybrid() { grep -qE '<string>(NootedGreen|WhateverXe)\.kext</string>' "$1"; }
# one-boot daemon: a copy of this script outside ~/Documents (TCC blocks launchd's bash there)
DAEMON=/Library/LaunchDaemons/com.nmx.hybrid-once.plist; ONCE=/usr/local/libexec/nmx-hybrid-efi.sh
TESTS=/usr/local/libexec/nmx-gputests   # Metal tests run on the Iris Xe in that boot (gputests.sh build makes them)
arm_once() {   # $1 = what the daemon runs at the next boot (boot-once by default)
    mkdir -p "${ONCE%/*}" && cp "$HERE/efi.sh" "$ONCE" && chmod 755 "$ONCE" || return 1
    rm -rf "$TESTS"
    [ -x "$HOMEU/nmx-build/hybrid/xps/build/tests/xe-miptest" ] && { cp -R "$HOMEU/nmx-build/hybrid/xps/build/tests" "$TESTS" \
        && cp "$HERE/gputests.sh" "$TESTS/" || return 1; }
    cat > "$DAEMON" <<EOP || return 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.nmx.hybrid-once</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$ONCE</string><string>${1:-boot-once}</string></array>
<key>RunAtLoad</key><true/>
<key>StandardOutPath</key><string>/var/log/nmx-hybrid.log</string>
<key>StandardErrorPath</key><string>/var/log/nmx-hybrid.log</string>
</dict></plist>
EOP
    chown root:wheel "$DAEMON" && chmod 644 "$DAEMON" && plutil -lint "$DAEMON" >/dev/null
}
disarm_once() { rm -f "$DAEMON" "$ONCE"; rm -rf "$TESTS"; }

case "${1:-}" in
hybrid|hybrid-keep|wex|wex-keep|wexrtx|wexrtx-keep)
    case $1 in
    hybrid*) HYB=$OC/config-hybrid.plist; GEN=(hybrid-config.py); PUT=("$NGK"); NAME=hybrid ;;
    wexrtx*) HYB=$OC/config-wex.plist; GEN=(wex-config.py --rtx); PUT=("$WXK/$WEXDIR/WhateverXe.kext" "$WXK/AMFIPassMod.kext"); NAME=wexrtx ;;
    *)       HYB=$OC/config-wex.plist; GEN=(wex-config.py); PUT=("$WXK/$WEXDIR/WhateverXe.kext" "$WXK/AMFIPassMod.kext"); NAME=wex ;;
    esac
    for k in "${PUT[@]}"; do [ -d "$k/Contents/MacOS" ] || { echo "no $k: build or download it first"; exit 1; }; done
    if is_hybrid "$CFG"; then
        [ -f "$GPU" ] || { echo "config.plist loads NootedGreen and there is no config-gpu-only.plist; nothing changed"; exit 1; }
    elif cmp -s "$CFG" "$OC/config-plain.plist"; then
        # the plain config is derived from config-gpu-only.plist: keep that one instead of saving plain over it
        [ -f "$GPU" ] || { echo "config.plist is plain and there is no config-gpu-only.plist; nothing changed"; exit 1; }
    else
        cp "$CFG" "$GPU" || { echo "could not save config-gpu-only.plist; nothing changed"; exit 1; }
        cp "$CFG" "$HOMEU/config-antes-hybrid.plist" && chown "${SUDO_USER:-root}" "$HOMEU/config-antes-hybrid.plist"
    fi
    /usr/bin/python3 -I "$HERE/${GEN[0]}" "${GEN[@]:1}" "$GPU" "$HYB" || { echo "could not write ${HYB##*/}; nothing changed"; exit 1; }
    plutil -lint "$HYB" >/dev/null || { echo "${HYB##*/} does not parse; nothing changed"; exit 1; }
    for k in "${PUT[@]}"; do
        rm -rf "$OC/Kexts/${k##*/}" && cp -R "$k" "$OC/Kexts/" || { echo "could not copy ${k##*/}; nothing changed"; exit 1; }
    done
    if [ "$NAME" != hybrid ]; then
        /usr/bin/python3 -I "$HERE/pnlf-aml.py" "$OC/ACPI/SSDT-PNLF.aml" || { echo "could not write SSDT-PNLF.aml; nothing changed"; exit 1; }
    fi
    if [ "$1" = "$NAME" ]; then
        arm_once || { disarm_once; echo "could not install the one-boot daemon; nothing changed"; exit 1; }
    else disarm_once; fi
    cp "$HYB" "$CFG" || { cp "$GPU" "$CFG"; echo "could not switch config.plist; GPU-only put back"; exit 1; }
    sync
    [ "$1" = "$NAME" ] && echo "one boot only: that boot puts GPU-only back by itself ($NAME-keep to stay)"
    for k in "${PUT[@]}"; do b=${k##*/}; echo "route: $NAME, ${b%.kext} $(shasum -a 256 "$OC/Kexts/$b/Contents/MacOS/"* | cut -c1-8)"; done
    echo "boot-args: $(/usr/libexec/PlistBuddy -c 'Print :NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args' "$CFG")"
    ;;
rtx|rtx-keep)
    [ -f "$GPU" ] || { echo "no config-gpu-only.plist on the ESP; nothing changed"; exit 1; }
    is_hybrid "$GPU" && { echo "config-gpu-only.plist loads a route kext; nothing changed"; exit 1; }
    [ -d /Library/Extensions/NMIntelFB.kext ] || { echo "no NMIntelFB in /Library/Extensions; nothing changed"; exit 1; }
    RTX=$OC/config-rtx.plist; BACK=$OC/config-back.plist; BA=':NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args'
    A=$(/usr/libexec/PlistBuddy -c "Print $BA" "$GPU") || { echo "no boot-args in config-gpu-only.plist; nothing changed"; exit 1; }
    N=""; for w in $A; do case $w in -nmintelfboff|-nvoff|nmhybrid=*) ;; *) N="$N${N:+ }$w" ;; esac; done
    N="$N nmhybrid=${NMHYBRID:-1}${RTX_EXTRA:+ $RTX_EXTRA}"
    cp "$GPU" "$RTX" && /usr/libexec/PlistBuddy -c "Set $BA $N" "$RTX" && plutil -lint "$RTX" >/dev/null \
        || { echo "could not write config-rtx.plist; nothing changed"; exit 1; }
    # keep the daily config to come back to; a second run while config.plist is already rtx keeps the first copy
    if ! grep -q 'nmhybrid=' "$CFG"; then cp "$CFG" "$BACK" || { echo "could not save config-back.plist; nothing changed"; exit 1; }; fi
    if [ "$1" = rtx ]; then
        [ -f "$BACK" ] || { echo "no config-back.plist to come back to; nothing changed"; exit 1; }
        arm_once boot-back || { disarm_once; echo "could not install the one-boot daemon; nothing changed"; exit 1; }
    else disarm_once; fi
    cp "$RTX" "$CFG" || { cp "$BACK" "$CFG"; echo "could not switch config.plist; the previous one put back"; exit 1; }
    sync
    [ "$1" = rtx ] && echo "one boot only: that boot puts config-back.plist back by itself (rtx-keep to stay)"
    echo "route: rtx, NMIntelFB $(shasum -a 256 /Library/Extensions/NMIntelFB.kext/Contents/MacOS/NMIntelFB | cut -c1-8)"
    echo "boot-args: $N"
    ;;
boot-back)
    echo "$(date): boot-back, booted with: $(sysctl -n kern.bootargs)"
    BACK=$OC/config-back.plist
    [ -f "$BACK" ] && plutil -lint "$BACK" >/dev/null || { echo "no usable config-back.plist; config.plist left as is"; exit 1; }
    cp "$BACK" "$CFG" && sync && echo "config-back.plist put back for the next start" || { echo "copy failed"; exit 1; }
    diskutil unmount "$ESP" >/dev/null 2>&1
    disarm_once   # one boot only; bash already holds this script open
    exit 0
    ;;
gpu-only)
    [ -f "$GPU" ] || { echo "no config-gpu-only.plist on the ESP; nothing changed"; exit 1; }
    is_hybrid "$GPU" && { echo "config-gpu-only.plist loads a route kext; nothing changed"; exit 1; }
    cp "$GPU" "$CFG" || { echo "could not restore config.plist"; exit 1; }
    rm -rf "$OC/Kexts/NootedGreen.kext" "$OC/Kexts/WhateverXe.kext" "$OC/Kexts/AMFIPassMod.kext" "$OC/ACPI/SSDT-PNLF.aml"
    disarm_once; sync
    echo "route: GPU-only"
    ;;
plain)
    [ -f "$GPU" ] || { echo "no config-gpu-only.plist on the ESP; nothing changed"; exit 1; }
    is_hybrid "$GPU" && { echo "config-gpu-only.plist loads a route kext; nothing changed"; exit 1; }
    PL=$OC/config-plain.plist; BA=':NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args'
    cp "$GPU" "$PL" || { echo "could not write config-plain.plist; nothing changed"; exit 1; }
    A=$(/usr/libexec/PlistBuddy -c "Print $BA" "$PL") || { echo "no boot-args in config-gpu-only.plist; nothing changed"; exit 1; }
    # -nvoff also keeps AirportMtkWlan off the card (wifi5-0001); NVOFF=0 leaves it out, for a volume without nullmoth
    OFF="-nvoff -v"; [ "${NVOFF:-1}" = 0 ] && { OFF="-v"; A=$(printf '%s' " $A " | sed 's/ -nvoff / /; s/^ //; s/ $//'); }
    for x in $OFF; do case " $A " in *" $x "*) ;; *) A="$A $x" ;; esac; done
    /usr/libexec/PlistBuddy -c "Set $BA $A" "$PL" && plutil -lint "$PL" >/dev/null || { echo "could not edit config-plain.plist; nothing changed"; exit 1; }
    cp "$PL" "$CFG" || { cp "$GPU" "$CFG"; echo "could not switch config.plist; GPU-only put back"; exit 1; }
    rm -rf "$OC/Kexts/NootedGreen.kext" "$OC/Kexts/WhateverXe.kext" "$OC/Kexts/AMFIPassMod.kext" "$OC/ACPI/SSDT-PNLF.aml"
    disarm_once; sync
    echo "route: plain (no GPU driver), boot-args: $A"
    ;;
boot-once)
    echo "$(date): boot-once, booted with: $(sysctl -n kern.bootargs)"
    is_hybrid "$CFG" || { echo "config.plist is GPU-only already"; exit 0; }
    [ -f "$GPU" ] && ! is_hybrid "$GPU" || { echo "no usable config-gpu-only.plist; left hybrid"; exit 1; }
    cp "$GPU" "$CFG" && sync && echo "GPU-only put back for the next start" || { echo "copy failed"; exit 1; }
    diskutil unmount "$ESP" >/dev/null 2>&1   # flushes the FAT volume before a possible panic
    # OpenCore-injected kexts (NootedGreen) reach the unified log only as "compose failure"; the kernel message
    # buffer (msgbuf=400000) keeps their text, but only until the next reboot. -0 is taken ~15 s into boot (before
    # the desktop); -last is refreshed every 20 s for 10 min, so a manual reboot still leaves the desktop's lines
    rm -rf /var/log/nmx-hybrid-dmesg-*.txt /var/log/nmx-hybrid-gputests.txt /var/log/nmx-hybrid-xedrv /var/log/nmx-hybrid-catest.png /var/log/nmx-hybrid-png /var/log/nmx-hybrid-ioreg-*.txt
    D=/var/log/nmx-hybrid-dmesg
    dmesg > "$D-0.txt" 2>&1; chmod 644 "$D-0.txt"; sync
    if [ -x "$TESTS/gputests.sh" ]; then (
        # wait for the login (console owned by a real user), then 30 s for the desktop to settle
        # (the login window owns it as _windowserver on Tahoe: TAHOE-3's tests ran there and hung)
        for i in $(seq 60); do U=$(stat -f %Su /dev/console); case $U in root|_windowserver) ;; *) break ;; esac; sleep 5; done
        case $U in root|_windowserver) exit 0 ;; esac
        sleep 30; G=/var/log/nmx-hybrid-gputests.txt; touch $G; chown "$U" $G; chmod 644 $G
        launchctl asuser "$(id -u "$U")" sudo -u "$U" /bin/bash "$TESTS/gputests.sh" run "$TESTS" $G
    ) & fi
    mkdir -p /var/log/nmx-hybrid-xedrv
    for i in $(seq 30); do
        sleep 20
        dmesg > "$D-last.tmp" 2>&1 && chmod 644 "$D-last.tmp" && mv -f "$D-last.tmp" "$D-last.txt"
        [ "$i" = 1 ] && cp "$D-last.txt" "$D-35s.txt"   # kept: accelerator start lines (after -0, gone from -last later)
        # WhateverXe records its startup checks (N97*, TGL*, XELP*) as registry-root properties, gone after a reboot
        [ "$i" = 1 ] && { ioreg -l -d 1 -w0 > /var/log/nmx-hybrid-ioreg-root.txt; ioreg -r -n IGPU -l -w0 > /var/log/nmx-hybrid-ioreg-igpu.txt; chmod 644 /var/log/nmx-hybrid-ioreg-*.txt; }
        cp /tmp/xedrv-*.log /var/log/nmx-hybrid-xedrv/ 2>/dev/null; mkdir -p /var/log/nmx-hybrid-png; cp /tmp/nmx-*.png /var/log/nmx-hybrid-png/ 2>/dev/null; chmod -R a+rX /var/log/nmx-hybrid-png; chmod -R a+rX /var/log/nmx-hybrid-xedrv; sync
    done
    exit 0
    ;;
status)
    if is_hybrid "$CFG"; then echo "route: hybrid"; elif grep -q 'nmhybrid=' "$CFG"; then echo "route: rtx (nmhybrid)"; else echo "route: GPU-only"; fi
    [ -f "$DAEMON" ] && echo "one-boot daemon: armed" || echo "one-boot daemon: off"
    ls -l "$OC"/config*.plist
    ;;
*) echo "usage: sudo bash $0 hybrid|hybrid-keep|wex|wex-keep|wexrtx|wexrtx-keep|rtx|rtx-keep|gpu-only|plain|status"; exit 1 ;;
esac
echo "Reboot for OpenCore to load it."
