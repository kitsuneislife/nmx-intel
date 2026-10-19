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

## SLEEP-1 result (10-19) — fails: macOS never hibernated, it did plain S3
Lukas: after "hibernating" the panel did not come back (not black, just off). Evidence (`pmset -g log`, kernel log):
- [measured] 08:37:46 `Entering Sleep state due to 'Software Sleep'`; sleep factors `0x2308c6` include
  `HibernateForced`, yet the kernel logged `PMRD: sleep params v2, type 7, flags 0x0` and `PMRD: hibernateMode 0x0`.
- [measured] 08:38:10 `Wake from Normal Sleep [CDNVA] : due to PWRB XDCI CNVW/User` (hibmode=25 in HibernateStats, but
  no image was written: `IOHibernateState` 0). NMIntelFB at wake: `power 1: trans 00000000 plane 00000000 …
  pp 00000000/00000000 blc 00000000/…`, the RTX-22 picture. 08:40:46 `SMC shutdown cause: 5` (Lukas powered off).
- [measured] NVRM took 5668 ms to sleep (slow, but it did sleep).
- [inferred] On x86 the sleep type comes from the platform sleep-policy handler (X86PlatformPlugin, `SLPT` table in
  the board plist). For MacBookPro16,1 (`Mac-E1008331FDC96864`) none of the 10 entries has type 4 (hibernate) and the
  default is 7 (deep idle = S3), so `hibernatemode 25` alone is ignored. OpenCore's `HibernateMode=Auto` was fine but
  never used.

## SLEEP-2 prep — force hibernation with HibernationFixup (`hbfx-ahbm=1`)
- One variable: add acidanthera's **HibernationFixup 1.5.4** (Lilu plugin, release zip SHA-256 `89f50c51`, checked
  against GitHub's asset digest) with boot-arg `hbfx-ahbm=1` (EnableAutoHibernation: "hibernate instead of regular
  sleep"). It also stores the image key in NVRAM for boot.efi and skips IOPCIFamily `restoreMachineState` at resume
  (its fix for black screens after hibernate).
- `sudo bash tools/sleep/hibernate.sh on` (re-runnable): keeps the SLEEP-1 settings, copies the kext into
  `EFI/OC/Kexts`, appends its `Kernel/Add` entry (after Lilu), appends ` hbfx-ahbm=1` to `boot-args`, checks the plist.
  `off` restores `~/config-antes-hibernate.plist` (taken before SLEEP-1) and removes the kext.
- Expect: `PMRD: sleep params … type 4` or `hibernateMode 0x19`, the machine powers off fully, the OpenCore picker is
  skipped, `Wake from Hibernate`. Then the SLEEP-1 questions: panel (NMIntelFB `power 1` with the GOP's
  `trans c0000000`), RTX, Wi-Fi, brightness.
- Risk: resume failure = fresh boot, unsaved work lost. If the boot hangs: OpenCore picker → boot normally, then `off`.

## SLEEP-2 result (10-19) — fails: still S3; sleep work parked
Lukas: the machine did not come back ("travou no boot"); he asked to park sleep/wake and go back to the safe backup.
- [measured] Boot at 08:52 with the SLEEP-2 config: `kextstat` (next boot, same config) lists
  `as.lvs1974.HibernationFixup (1.5.4)` after Lilu 1.7.2, and `boot-args` ends in `hbfx-ahbm=1`.
- [measured] 09:07:38 `Entering Sleep state due to 'Software Sleep'`; kernel `PMRD: sleep params v2, type 7, flags
  0x0 … poweroff 0` (four times) and `PMRD: hibernateMode 0x0`; 09:08:10 `Wake from Normal Sleep [CDNVA] : due to PWRB
  XDCI CNVW/User`. Same as SLEEP-1: plain S3, no image written.
- [measured] NMIntelFB at wake: `power 1: trans 00000000 plane 00000000 surf 00000000 pp 00000000/00000000 blc
  00000000/…` (RTX-22 again, panel off). Before sleep it was `power 0: trans c0000000 plane 94000008 … pp 80000008`.
- [measured] NVRM slow to sleep again (8056 ms). 09:14:18 `SMC shutdown cause: 5`, next boot 09:14:21 came up normally
  (HibernationFixup still loaded); no panic report.
- [inferred] `hbfx-ahbm=1` did not change the sleep type on this setup: the policy result (`type 7`) is what the
  kernel used. Why HibernationFixup did not override it is open [unverified]; candidates: it only acts on its own
  standby/auto-power-off path (it needs `standby`/`autopoweroff` and a timer), or the X86PlatformPlugin policy runs
  after its hook. Reading HibernationFixup's `kern_hbfx.cpp` is the first step if this is resumed.

### Decision (10-19): sleep/wake parked
Back to the state before SLEEP-1: `sudo bash tools/sleep/hibernate.sh off` restores `~/config-antes-hibernate.plist`
(ESP config from 08:32, before any sleep change), removes `HibernationFixup.kext` from the ESP and sets
`hibernatemode 3`, `standby 1`, `powernap 1`, `sleep 0`, `disablesleep 1`. If resumed later, the two routes left:
(a) a real panel relight in NMIntelFB on `power 1` (i915's eDP resume: PPS power-on, transcoder/pipe/plane, backlight
PWM), which works whatever the sleep type; (b) understanding why the platform policy ignores hibernation.

## After `off` (10-19): two black boots — nullmoth's boot guard tripped
Lukas ran `hibernate.sh off` and the next two boots failed; he got in with the picker's "without NVIDIA" entry.
- [measured] `off` worked: HibernationFixup not loaded, `hibernatemode 3`, `SleepDisabled 1`, `boot-args` without
  `hbfx-ahbm=1`. Installed kexts unchanged (NVRM `8c8873d5`, NVAccel `8166045f`, NMIntelFB `36afddf1`).
- [measured] boot guard trail in the kernel log: every boot from 08:13 to 08:52 logged `start 1` and then
  `boot guard cleared` at NVKMS enumeration; 09:14 logged `start 2 without a display so far` and no `cleared`;
  09:20, 09:26 and 09:28 logged `NVRMFB: driver off`. NVRAM now `nullmoth-nv-starts %02`.
- [measured] Failed boots: `NMIntelFB: claim: Intel-panel NVRMDisplay nub not published: no NVRMDisplay 0 after 120 s`;
  WindowServer aborted in `CGXMappedDisplayStart` (`IOServiceOpen failed(0xe00002c7), index(0)`, "0 of 1 framebuffers
  were successfully opened") and restarted in a loop (reports 09:21, 09:27).
- [inferred] The 08:52 clear did not reach the firmware's NVRAM: the 09:14 boot read 1, not 0. That boot (HibernationFixup
  loaded, after the forced power-off at the black wake) then never logged an NVKMS enumeration, so 2 stayed. Why the
  clear was lost is [unverified]: candidates are the S3 wake/forced power-off before the NVRAM sync, or
  HibernationFixup's NVRAM handling.
- [inferred] When the guard turns NVRM off, NMIntelFB still claims the panel (it only checks `-nvoff` and its own
  guard), so WindowServer finds a framebuffer it cannot open and loops on a black screen instead of using the
  firmware framebuffer. Follow-up: NMIntelFB should also stand down when `nullmoth-nv-starts` ≥ 2.
- Fix: `sudo nvram -d nullmoth-nv-starts`, then a normal boot.
