#!/bin/bash
# hibernate.sh: SLEEP-1. S3 blanks the Intel display engine and nothing relights it (RTX-22). Hibernation (pmset
# hibernatemode 25) powers the machine off instead: on wake the firmware runs its GOP again, which lights the panel,
# OpenCore hands the saved image to boot.efi, and NMIntelFB re-adopts (it rewrites its GGTT entries at power-on,
# intelfb-0017). OpenCore needs Misc/Boot/HibernateMode=Auto to pass the hibernation data on.
# SLEEP-1 showed that is not enough: the MacBookPro16,1 sleep policy (X86PlatformPlugin, IOPlatformSystemSleepPolicy)
# answers type 7 (deep idle = plain S3) even with hibernatemode 25 ("PMRD: hibernateMode 0x0"). SLEEP-2 adds
# acidanthera's HibernationFixup with hbfx-ahbm=1 ("hibernate instead of regular sleep"); it also writes the image key
# to NVRAM for boot.efi and skips restoreMachineState on PCI devices at resume.
#   sudo bash tools/sleep/hibernate.sh on      OpenCore HibernateMode=Auto (+ skip the picker), HibernationFixup with
#                                              hbfx-ahbm=1, sleep allowed, hibernatemode 25 (safe to run again)
#   sudo bash tools/sleep/hibernate.sh off     back to the saved config.plist, sleep off again (the state before SLEEP-1)
#   sudo bash tools/sleep/hibernate.sh log     evidence of the last sleep/wake into ~/sleep.txt
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HOMEU=$(eval echo "~${SUDO_USER:-root}")
BACKUP=$HOMEU/config-antes-hibernate.plist
PB=/usr/libexec/PlistBuddy
HBFX_ZIP=$HOMEU/nmx-build/sleep/HibernationFixup-1.5.4-RELEASE.zip
HBFX_SHA=89f50c5118e664d981d36b8f2b61e02c91ee6f33a7dfb089be890a4231e3b8ae   # GitHub release asset digest
BA=":NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args"

mount_esp() {
    ESP=$(diskutil info disk0s1 2>/dev/null | sed -n 's/^ *Mount Point: *//p')
    if [ -z "$ESP" ]; then diskutil mount disk0s1 >/dev/null || { echo "could not mount the ESP (disk0s1)"; exit 1; }
        ESP=$(diskutil info disk0s1 | sed -n 's/^ *Mount Point: *//p'); fi
    CFG=$ESP/EFI/OC/config.plist
    [ -f "$CFG" ] || { echo "no $CFG"; exit 1; }
}
setkey() {  # setkey <path> <type> <value>: Set, or Add when the key is missing
    "$PB" -c "Set $1 $3" "$CFG" 2>/dev/null || "$PB" -c "Add $1 $2 $3" "$CFG" || { echo "could not set $1"; exit 1; }
}

case "${1:-}" in
on)
    mount_esp
    if [ ! -f "$BACKUP" ]; then cp "$CFG" "$BACKUP" && chown "${SUDO_USER:-root}" "$BACKUP" || { echo "backup failed; nothing changed"; exit 1; }; fi
    echo "backup of config.plist: $BACKUP"
    setkey :Misc:Boot:HibernateMode string Auto
    setkey :Misc:Boot:HibernationSkipsPicker bool true
    # SLEEP-2: HibernationFixup (after Lilu: appended to Kernel/Add) and hbfx-ahbm=1
    [ "$(shasum -a 256 "$HBFX_ZIP" 2>/dev/null | cut -c1-64)" = "$HBFX_SHA" ] || { cp "$BACKUP" "$CFG"; echo "$HBFX_ZIP missing or wrong SHA-256; backup restored"; exit 1; }
    T=$(mktemp -d) && unzip -q "$HBFX_ZIP" -d "$T" && rm -rf "$ESP/EFI/OC/Kexts/HibernationFixup.kext" \
        && cp -R "$T/HibernationFixup.kext" "$ESP/EFI/OC/Kexts/" || { cp "$BACKUP" "$CFG"; echo "could not copy the kext; backup restored"; exit 1; }
    rm -rf "$T"
    n=0; have=0
    while "$PB" -c "Print :Kernel:Add:$n" "$CFG" >/dev/null 2>&1; do
        [ "$("$PB" -c "Print :Kernel:Add:$n:BundlePath" "$CFG")" = HibernationFixup.kext ] && have=1; n=$((n+1)); done
    if [ $have = 0 ]; then
        "$PB" -c "Add :Kernel:Add:$n dict" -c "Add :Kernel:Add:$n:Arch string Any" -c "Add :Kernel:Add:$n:BundlePath string HibernationFixup.kext" \
              -c "Add :Kernel:Add:$n:Comment string 'hibernate instead of S3 (SLEEP-2)'" -c "Add :Kernel:Add:$n:Enabled bool true" \
              -c "Add :Kernel:Add:$n:ExecutablePath string Contents/MacOS/HibernationFixup" -c "Add :Kernel:Add:$n:MaxKernel string" \
              -c "Add :Kernel:Add:$n:MinKernel string" -c "Add :Kernel:Add:$n:PlistPath string Contents/Info.plist" "$CFG" \
            || { cp "$BACKUP" "$CFG"; echo "could not add the Kernel/Add entry; backup restored"; exit 1; }
    fi
    args=$("$PB" -c "Print $BA" "$CFG") || { cp "$BACKUP" "$CFG"; echo "no boot-args in config.plist; backup restored"; exit 1; }
    case " $args " in *" hbfx-ahbm=1 "*) ;; *) "$PB" -c "Set $BA '$args hbfx-ahbm=1'" "$CFG" || exit 1 ;; esac
    plutil -lint "$CFG" >/dev/null || { cp "$BACKUP" "$CFG"; echo "config.plist broken after the edit; backup restored"; exit 1; }
    echo "OpenCore: HibernateMode=$("$PB" -c 'Print :Misc:Boot:HibernateMode' "$CFG"), HibernationSkipsPicker=$("$PB" -c 'Print :Misc:Boot:HibernationSkipsPicker' "$CFG")"
    echo "HibernationFixup: $(ls -d "$ESP/EFI/OC/Kexts/HibernationFixup.kext" 2>/dev/null) entry $(grep -c HibernationFixup.kext "$CFG")"
    echo "boot-args: $("$PB" -c "Print $BA" "$CFG")"
    pmset -a hibernatemode 25 || exit 1
    pmset -a standby 0 powernap 0 || exit 1
    pmset -a disablesleep 0 || exit 1
    pmset -a sleep 0 || exit 1          # no automatic sleep yet: only "pmset sleepnow" while testing
    echo "pmset: $(pmset -g | grep -E 'hibernatemode|SleepDisabled' | tr -s ' \t' ' ' | tr '\n' ';')"
    echo "ready. Reboot once so OpenCore loads the new config, then: sudo pmset sleepnow"
    ;;
off)
    mount_esp
    [ -f "$BACKUP" ] && { cp "$BACKUP" "$CFG" || { echo "could not restore $BACKUP"; exit 1; }; echo "config.plist restored from $BACKUP"; }
    rm -rf "$ESP/EFI/OC/Kexts/HibernationFixup.kext"
    pmset -a hibernatemode 3 standby 1 powernap 1 sleep 0 || exit 1
    pmset -a disablesleep 1 || exit 1
    echo "sleep off again (hibernatemode 3, SleepDisabled 1). Reboot for OpenCore to load the restored config."
    ;;
log)
    OUT=$HOMEU/sleep.txt
    {
        echo "== pmset -g"; pmset -g
        echo "== pmset -g log (sleep/wake)"; pmset -g log | grep -E "Sleep|Wake|Hibernat|DarkWake|Failure|slow" | tail -40
        echo "== kernel log, last 2 h"
        /usr/bin/log show --last 2h --predicate 'process == "kernel"' 2>/dev/null \
            | grep -E "NMIntelFB|NVRM|NVAccel|IOHibernate|hibernate|HBFX|HibernationFixup|PMRD: (sleep params|hibernateMode)|AppleACPIPlatform.*[Ww]ake|AirportMtk|Wake reason" | tail -300
        echo "== NMIntelFB registers now"; sysctl debug.nmintelfb_regs 2>/dev/null
        echo "== WindowServer / panic reports since yesterday"
        find /Library/Logs/DiagnosticReports -newermt "$(date -v-1d +%Y-%m-%d)" -type f 2>/dev/null
    } > "$OUT" 2>&1
    chown "${SUDO_USER:-root}" "$OUT"
    echo "written $OUT ($(wc -l < "$OUT") lines)"
    ;;
*) echo "usage: sudo bash tools/sleep/hibernate.sh on | off | log"; exit 1 ;;
esac
