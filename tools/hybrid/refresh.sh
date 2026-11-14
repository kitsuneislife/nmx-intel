#!/bin/bash
# refresh.sh: let System Settings > Displays offer the internal panel's refresh rates (60 / 144 Hz) natively.
# macOS hides the "Refresh Rate" menu on built-in panels unless the panel's display override carries
# display-refresh-rate-policy = 1, as Apple's own overrides do for the 16" MacBook Pro 2019 (DisplayVendorID-610/
# DisplayProductID-a044) and the Pro Display XDR. Our panel (LG Display LP156WFJ-SPB4, EDID 30e4:0742) has no Apple
# override, so this writes one in /Library (the system one in /System is untouched).
#   bash tools/hybrid/refresh.sh probe          switch to 144 Hz for 10 s, then back by itself (no root, no file)
#   sudo bash tools/hybrid/refresh.sh install   write the override; the menu appears after a reboot
#   sudo bash tools/hybrid/refresh.sh remove    delete it (and the saved mode) so the panel goes back to 60 Hz
#   bash tools/hybrid/refresh.sh status         current mode, available modes, override present or not
#   bash tools/hybrid/refresh.sh set 144        pick 144 (or 60) Hz for good, as the Settings menu would (no root)
# Do not restart WindowServer to apply it early on the WhateverXe panel (pitfall, UPG-6): reboot instead.
set -uo pipefail
VID=30e4; PID=742   # IODisplayPrefsKey ...IGPU@2-30e4-742-...; DisplayVendorID 12516, DisplayProductID 1858
DIR=/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-$VID
FILE=$DIR/DisplayProductID-$PID
WSPREFS=/Library/Preferences/com.apple.windowserver.displays.plist
need_root() { [ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }; }
modes() {   # $1 = "" to list, or a refresh rate to switch to for 10 s (kCGConfigureForAppOnly: undone on exit)
    local t; t=$(mktemp -t nmxhz).swift || return 1
    cat > "$t" <<'EOF'
import CoreGraphics
import Foundation
let d = CGMainDisplayID()
let cur = CGDisplayCopyDisplayMode(d)!
let all = CGDisplayCopyAllDisplayModes(d, nil) as! [CGDisplayMode]
let want = Double(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "") ?? 0
if want == 0 {
    print("current: \(cur.width)x\(cur.height) @ \(cur.refreshRate) Hz, built-in: \(CGDisplayIsBuiltin(d) != 0)")
    print("rates at this size:", all.filter { $0.width == cur.width && $0.height == cur.height }.map { $0.refreshRate })
    exit(0)
}
guard let m = all.first(where: { $0.width == cur.width && $0.height == cur.height && $0.refreshRate.rounded() == want }) else {
    print("no \(want) Hz mode at \(cur.width)x\(cur.height)"); exit(1)
}
var cfg: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&cfg)
CGConfigureDisplayWithDisplayMode(cfg, d, m, nil)
let keep = CommandLine.arguments.count > 2   // "set": saved in WindowServer's display prefs like the Settings menu
let err = CGCompleteDisplayConfiguration(cfg, keep ? .permanently : .forAppOnly)
print("switch to \(want) Hz: \(err == .success ? "ok" : "error \(err.rawValue)")")
if keep { exit(err == .success ? 0 : 1) }
Thread.sleep(forTimeInterval: 1)
print("now: \(CGDisplayCopyDisplayMode(d)!.refreshRate) Hz; back to \(cur.refreshRate) Hz in 10 s")
Thread.sleep(forTimeInterval: 10)
EOF
    swift "$t" "$@"; local rc=$?
    rm -f "$t"; return $rc
}
case "${1:-}" in
probe)
    modes 144
    ;;
set)
    case "${2:-}" in 60|144) modes "$2" keep ;; *) echo "usage: refresh.sh set 60|144"; exit 1 ;; esac
    ;;
install)
    need_root
    mkdir -p "$DIR" || exit 1
    cat > "$FILE" <<EOF || exit 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>DisplayProductID</key>
	<integer>$((16#$PID))</integer>
	<key>DisplayVendorID</key>
	<integer>$((16#$VID))</integer>
	<key>display-refresh-rate-policy</key>
	<data>AAAAAAAAAAE=</data>
</dict>
</plist>
EOF
    chmod 644 "$FILE"
    plutil -lint "$FILE" || { rm -f "$FILE"; exit 1; }
    plutil -p "$FILE"
    echo "installed: reboot, then System Settings > Displays > Refresh Rate"
    ;;
remove)
    need_root
    rm -f "$FILE"; rmdir "$DIR" 2>/dev/null
    # The chosen mode lives in WindowServer's display prefs; without it the panel boots at its default (60 Hz).
    [ -f "$WSPREFS" ] && mv -f "$WSPREFS" "$WSPREFS.nmx-bak" && echo "saved mode reset ($WSPREFS.nmx-bak)"
    echo "removed: reboot"
    ;;
status)
    modes
    if [ -f "$FILE" ]; then echo "override: $FILE"; plutil -p "$FILE"; else echo "override: none"; fi
    ;;
*)
    sed -n '2,12p' "$0"; exit 1
    ;;
esac
