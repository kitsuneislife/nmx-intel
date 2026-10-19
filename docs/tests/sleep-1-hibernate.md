# Sleep: hibernation instead of S3

> **Summary.** S3 sleep blanks the Intel display engine and nothing relights the panel (RTX-22). Nobody else drives
> this panel from macOS, so there is no community fix to copy [inferred, 2026-10-19 search]. SLEEP-1 tries the cheap
> way round: hibernate (`hibernatemode 25`), so the firmware's GOP lights the panel again on wake and NMIntelFB
> re-adopts it. The alternative is a full panel relight in NMIntelFB (i915's display resume). Tool:
> `tools/sleep/hibernate.sh`.

## Starting point (2026-10-19)
- [measured] `pmset -g`: `SleepDisabled 1`, `hibernatemode 3`, `standby 1`, `powernap 1`; `/var/vm/sleepimage` 1 GiB;
  FileVault off; 16 GiB RAM.
- [measured] OpenCore config (`make_config.py`) never sets `Misc/Boot/HibernateMode`, so it is the Sample's `None`:
  OpenCore does not pass the hibernation data to boot.efi and a hibernated image would be discarded.
- [measured] NMIntelFB already rewrites its RAM-scanout GGTT entries at power-on (`setPowerState`, intelfb-0017) and
  logs `power 1: trans … plane … pp … blc …` there (intelfb-0018).
- Search (2026-10-19): hackintosh threads cover hibernation (HibernateMode Auto, HibernationSkipsPicker,
  DevirtualiseMmio, drives not marked internal) and Linux threads cover Raptor Lake-P eDP after resume; none covers an
  unsupported Intel iGPU driving the panel under macOS.

## SLEEP-1 prep — hibernate (`hibernatemode 25`)
- `sudo bash tools/sleep/hibernate.sh on`: backs up the ESP's `config.plist` to `~/config-antes-hibernate.plist`, sets
  `Misc/Boot/HibernateMode=Auto` and `HibernationSkipsPicker=true`, checks the plist, then `pmset hibernatemode 25`,
  `standby 0`, `powernap 0`, `disablesleep 0`, `sleep 0` (no automatic sleep yet; only `pmset sleepnow`). One reboot
  for OpenCore to load the config. `off` restores the backup and the pmset state above. `log` writes `~/sleep.txt`.
- Everything else as daily use (RAM scanout with flips, AirportMtkWlan, nullmoth 2.3.6).
- Questions: does OpenCore/boot.efi resume the image (`pmset -g log` "Wake from Hibernate" vs a cold boot)? Does the
  panel show the desktop (NMIntelFB `power 1` with `trans c0000000 plane 94000008` from the GOP)? Do the RTX, Wi-Fi and
  brightness come back?
- Risk: if resume fails the Mac boots fresh and unsaved work is lost; nothing on disk changes beyond the sleep image.
