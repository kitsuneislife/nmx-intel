#!/bin/bash
# claude-gpu.sh: LAT-12. Restarts Claude 2 and Claude 3 with Chromium's GPU off (--disable-gpu
# --disable-gpu-compositing): they draw on the CPU and send no Metal work to the Iris Xe; WindowServer still
# composites their windows. The main Claude app is never touched (Claude Code runs in it).
#   bash tools/hybrid/claude-gpu.sh off      restart 2 and 3 without GPU
#   bash tools/hybrid/claude-gpu.sh on       restart 2 and 3 normally
#   bash tools/hybrid/claude-gpu.sh status   per instance: GPU flag and Intel GPU user clients
# Flags last until the app is quit; a normal Dock launch is the GPU default again.
set -uo pipefail
mode=${1:-status}
case "$mode" in off|on|status) ;; *) echo "usage: $0 off|on|status"; exit 1 ;; esac

status() {
    local clients n app pids nc
    clients=$(ioreg -r -c IntelAccelerator -l -w0 | grep -o '"IOUserClientCreator" = "pid [0-9]*' | grep -o '[0-9]*$')
    for n in 2 3; do
        app="$HOME/Applications/Claude $n.app"
        pids=$(pgrep -f "$app/Contents/")
        [ -n "$pids" ] || { echo "Claude $n: not running"; continue; }
        nc=0
        for p in $pids; do nc=$((nc + $(grep -cx "$p" <<< "$clients"))); done
        if pgrep -f "$app/Contents/MacOS/Claude .*--disable-gpu" > /dev/null; then g="GPU off"; else g="GPU on"; fi
        echo "Claude $n: $g, $(wc -w <<< "$pids" | tr -d ' ') processes, $nc Intel GPU clients"
    done
}

if [ "$mode" != status ]; then
    for n in 2 3; do
        app="$HOME/Applications/Claude $n.app"
        [ -d "$app" ] || { echo "STOP: missing $app"; exit 1; }
        osascript -e "tell application id \"local.claude-instances.claude-$n\" to quit" > /dev/null 2>&1
        for _ in $(seq 30); do pgrep -f "$app/Contents/MacOS/Claude" > /dev/null || break; sleep 1; done
        pgrep -f "$app/Contents/MacOS/Claude" > /dev/null && { echo "STOP: Claude $n did not quit"; exit 1; }
        if [ "$mode" = off ]; then
            open -n "$app" --args --disable-gpu --disable-gpu-compositing || { echo "STOP: open Claude $n failed"; exit 1; }
        else
            open -n "$app" || { echo "STOP: open Claude $n failed"; exit 1; }
        fi
    done
    sleep 10
fi
status
