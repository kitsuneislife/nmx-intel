#!/bin/bash
# lat-elevate.sh (LAT-2): does Apple's priority band explain the Iris Xe submit wait?
# Runs /tmp/xe-lattest twice with the busy app on screen: once as is, once with its PID elevated through Apple's
# debug.intel.schedPriElevatePID sysctl. The sysctl is put back to -1 on exit, even on Ctrl-C.
#   sudo bash tools/hybrid/lat-elevate.sh            results in ~/lat-elevate.txt
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
user=${SUDO_USER:?run with sudo from your own account}
if [ ! -x /tmp/xe-lattest ]; then   # build the probe as the user, next to this script's source
    sudo -u "$user" clang -fobjc-arc -O2 -framework Metal -framework Foundation -o /tmp/xe-lattest \
        "$(dirname "$0")/xe-lattest.m" || { echo "could not build /tmp/xe-lattest"; exit 1; }
fi
home=$(eval echo "~$user")
out="$home/lat-elevate.txt"
pidf=$(mktemp /tmp/lat-elevate.XXXXXX); chown "$user" "$pidf"
trap 'sysctl -q debug.intel.schedPriElevatePID=-1 >/dev/null; rm -f "$pidf"' EXIT

run() {   # run the probe as the user; $1 = elevate or not
    sudo -u "$user" bash -c 'echo $$ > "$1"; sleep 1; exec /tmp/xe-lattest' _ "$pidf" >> "$out" &
    local job=$!
    sleep 0.5
    if [ "$1" = yes ]; then
        sysctl debug.intel.schedPriElevatePID="$(cat "$pidf")" >> "$out" || echo "sysctl failed" >> "$out"
    fi
    wait "$job"
    sysctl -q debug.intel.schedPriElevatePID=-1
}

: > "$out"; chown "$user" "$out"
echo "=== normal ===" >> "$out"; run no
echo "=== elevated ===" >> "$out"; run yes
echo "done: $out"
