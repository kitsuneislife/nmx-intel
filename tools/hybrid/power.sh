#!/bin/bash
# Average battery draw in watts over N seconds (default 120), sampled every 5 s from AppleSmartBattery.
# Run it on battery with the machine idle (screen on, apps closed): bash tools/hybrid/power.sh [SECONDS]
# Writes the result to ~/power.txt as well.
set -eu
SECS=${1:-120}
OUT="$HOME/power.txt"
/usr/bin/python3 -I - "$SECS" "$OUT" <<'PY'
import plistlib, subprocess, sys, time

secs, out = int(sys.argv[1]), sys.argv[2]

def battery():
    raw = subprocess.run(["/usr/sbin/ioreg", "-rn", "AppleSmartBattery", "-a"],
                         capture_output=True, check=True).stdout
    return plistlib.loads(raw)[0]

if battery().get("ExternalConnected"):
    sys.exit("on AC power: unplug the charger first, then run this again")

samples = []
for _ in range(max(1, secs // 5)):
    b = battery()
    amps = b["InstantAmperage"]
    if amps >= 1 << 63:          # the registry stores the signed mA as u64
        amps -= 1 << 64
    samples.append(-amps * b["Voltage"] / 1e6)
    time.sleep(5)

b = battery()
line = (f"{time.strftime('%Y-%m-%d %H:%M')} avg {sum(samples)/len(samples):.2f} W "
        f"min {min(samples):.2f} max {max(samples):.2f} over {len(samples)} samples, "
        f"charge {b['CurrentCapacity']}/{b['MaxCapacity']}")
print(line)
with open(out, "a") as f:
    f.write(line + "\n")
PY
