#!/bin/bash
# hibernate.sh: SLEEP-1. S3 blanks the Intel display engine and nothing relights it (RTX-22). Hibernation (pmset
# hibernatemode 25) powers the machine off instead: on wake the firmware runs its GOP again, which lights the panel,
# OpenCore hands the saved image to boot.efi, and NMIntelFB re-adopts (it rewrites its GGTT entries at power-on,
# intelfb-0017). OpenCore needs Misc/Boot/HibernateMode=Auto to pass the hibernation data on.
#   sudo bash tools/sleep/hibernate.sh on      OpenCore HibernateMode=Auto (+ skip the picker), sleep allowed, hibernatemode 25
#   sudo bash tools/sleep/hibernate.sh off     back to the saved config.plist, sleep off again (the state before SLEEP-1)
#   sudo bash tools/sleep/hibernate.sh log     evidence of the last sleep/wake into ~/sleep.txt
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HOMEU=$(eval echo "~${SUDO_USER:-root}")
BACKUP=$HOMEU/config-antes-hibernate.plist
PB=/usr/libexec/PlistBuddy

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
    plutil -lint "$CFG" >/dev/null || { cp "$BACKUP" "$CFG"; echo "config.plist broken after the edit; backup restored"; exit 1; }
    echo "OpenCore: HibernateMode=$("$PB" -c 'Print :Misc:Boot:HibernateMode' "$CFG"), HibernationSkipsPicker=$("$PB" -c 'Print :Misc:Boot:HibernationSkipsPicker' "$CFG")"
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
            | grep -E "NMIntelFB|NVRM|NVAccel|IOHibernate|hibernate|AppleACPIPlatform.*[Ww]ake|AirportMtk|Wake reason" | tail -300
        echo "== NMIntelFB registers now"; sysctl debug.nmintelfb_regs 2>/dev/null
        echo "== WindowServer / panic reports since yesterday"
        find /Library/Logs/DiagnosticReports -newermt "$(date -v-1d +%Y-%m-%d)" -type f 2>/dev/null
    } > "$OUT" 2>&1
    chown "${SUDO_USER:-root}" "$OUT"
    echo "written $OUT ($(wc -l < "$OUT") lines)"
    ;;
*) echo "usage: sudo bash tools/sleep/hibernate.sh on | off | log"; exit 1 ;;
esac
