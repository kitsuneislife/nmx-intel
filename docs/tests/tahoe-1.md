# TAHOE-1: in-place upgrade from Sequoia 15.8.1 to Tahoe 26.7.x

> **Summary.** The third step of the upgrade plan: macOS Tahoe 26.7.3 (25G342) with the same hybrid stack (nullmoth
> 2.9 + no-wsreset, WhateverXe 0.8.2 + Graphics 0.4.3). Two blockers found before any download: only ~22 GB free on
> the 215 GB container, and the four CPU-topology kernel patches stop at Darwin 24. `tools/tahoe/tahoe.sh` checks,
> extracts the Tahoe kernel, verifies and copies the patches, and prepares the plain boot for the installer.

## TAHOE-0 (2026-11-12): readiness, offline

[measured] `tahoe.sh check` on 15.8.1: SMBIOS MacBookPro16,1 (Tahoe supports it), OpenCore `DBG-108-2026-09-27`
(1.0.8), Wi-Fi Tahoe build present, Graphics 0.4.3 pkg present (it carries `Tahoe.pkg`). Missing: free space (22 GB;
installer 17957880 KiB ≈ 18.4 GB plus ~30 GB for the upgrade itself), the installer, the patch check against the
Tahoe kernel, and a Time Machine backup (`tmutil latestbackup` empty, no local snapshots).

[measured] `softwareupdate --list-full-installers`: 26.7.3 (25G342) newest, 26.7.2, 26.7.1; 15.8.1 still offered
(rollback = reinstall 15.8.1 + restore from Time Machine).

### Blocker: the PCCI topology patches are Darwin 24 only

[measured] config-gpu-only.plist / config.plist / config-wex.plist carry four `PCCI topo:` Kernel>Patch entries
(hackintosh repo tests J–L, commit 1654887) with MinKernel 24.0.0 / MaxKernel 24.99.99. Without them the i5-13420H
kernel divides by zero in `smp_init()` or panics in `x86_validate_topology`. On Darwin 25 OpenCore skips all four, so
Tahoe would not boot [inferred from the J–L panics].

`tools/tahoe/kpatch.py` reads the kernel inside a BootKernelExtensions.kc (fileset entry `com.apple.kernel`, its
symtab and `__TEXT`), counts each Find from its Base symbol on and checks the first Count hits fall inside that
function; for "cores per package" it finds which OpenCore 1.0.8 variant the kernel has (V2 masked, then V1_5) and
writes the 0x40 form of that variant. `add` writes Darwin 25 copies only if all four match.

[measured] Self-test on the running Sequoia BootKC: MSR35h 2 hits inside `_cpuid_set_info`; fallback 4 hits, first 2
inside; `_x86_validate_topology` at 0xffffff80005230d0; cores per package V1 0 / V1_5 1 / V2 0 → V1_5 (what the
config already uses); exit 0.

### Wi-Fi Tahoe build

[measured] `AIRPORT_OS=tahoe bash tools/wifi/build-airport.sh`: all six wifi5 patches apply, `AirportMtkWlan
3b22cfa5` in `~/nmx-build/wifi5/out-tahoe/` (Sequoia build unchanged `dd967442`). The kmutil KPI link check is
skipped off-Tahoe; rerun the build on Tahoe before `install.sh airport` (which picks out-tahoe on macOS 26).

### Plan

1. Free ~30 GB (Lukas chooses), Time Machine backup to an external disk, `bash tools/checkpoint.sh save pre-tahoe`.
2. `softwareupdate --fetch-full-installer --full-installer-version 26.7.3`.
3. `bash tools/tahoe/tahoe.sh kc` → `sudo bash tools/tahoe/tahoe.sh patch` (backups in `~/config-antes-tahoe/`).
4. `sudo bash tools/tahoe/tahoe.sh prepare`: wex-install.sh remove, wifi restore, `efi.sh plain` (GPU-only config
   with `-nvoff -v`, kept through the installer's reboots). One reboot into Sequoia to prove the plain config boots.
5. Run the installer. After Tahoe boots: rebuild/install Wi-Fi (`AIRPORT_OS=tahoe`), nullmoth 2.9 for 26 in the
   1401 app + `ondemand.sh on/add`, `wex-install.sh`, `efi.sh wexrtx` once, then `wexrtx-keep`.

Risks [unverified]: no AppleHDA on Tahoe (AppleALC useless; nullmoth's NMHDA is the substitute), RealtekRTL8111 3.0.4
and VoodooI2C 2.9.1 on Tahoe, the RTX-only route patches (not ported anyway). `sudo tahoe.sh undo` restores the daily
Sequoia setup if the installer was not started.

## TAHOE-0 update (2026-11-12): space freed, no backup disk → separate-volume route

[measured] After moving radar/kitnet to GitHub and clearing build caches: 92 GB free, container disk1 has 99.8 GB
unallocated, FileVault off. Lukas has no external disk, so no Time Machine backup is possible.

Decision: **TAHOE-1a** installs Tahoe on a new APFS volume `Tahoe` in disk1 (`sudo tahoe.sh volume`) instead of
upgrading in place. Sequoia stays untouched and remains the rollback (pick it in the OpenCore picker; `efi.sh
wexrtx-keep` restores its daily config). Same OpenCore configs for both: the Darwin 25 PCCI copies only apply to
Tahoe. Once the stack works on the Tahoe volume, the in-place upgrade (`prepare`) or a migration can follow, and the
test volume is deleted. The plan's steps 2–3 are unchanged; step 4 becomes `volume`, and the installer is pointed at
the disk `Tahoe`.

## TAHOE-1a step 1 (2026-11-12): installer and kernel check

[measured] Checkpoint `20261112-204952-pre-tahoe` (NMIntelFB `241aff3d`, NVAccel `b298771e`, NVRM `c1d62ff7`,
NVRMAGDC `97623c55`, NVRMFB `4890671d`). Installer 26.7.3 (25G342) downloaded (48 min). `tahoe.sh kc`:
BootKernelExtensions.kc `9bb053cf` from `AssetData/boot/System/Library/KernelCollections/`; all four patches match:
- MSR 35h: 2 hits, both inside `_cpuid_set_info` [0x1d3d00,0x1d5770).
- fallback 8/12: 8 hits (Sequoia had 4), the first 2 inside `_cpuid_set_info`; OpenCore patches only those 2.
- `_x86_validate_topology` at 0xffffff80004c0c10.
- cores per package: V1 0, V1_5 1 (0xffffff80004bdce5), V2 0 → V1_5, the same variant as Sequoia.

[measured] Dry run of `kpatch.py add` on copies of config-gpu-only / config / config-wex: four `(Tahoe)` entries
each (MinKernel 25.0.0, MaxKernel 25.99.99, Identifier kernel, Enabled), `plutil -lint` OK. Next: `sudo tahoe.sh
patch` (ESP), `sudo tahoe.sh volume`, one plain boot of Sequoia, then the installer onto `Tahoe`.

## TAHOE-1a step 2 (2026-11-12): Tahoe installed on its own volume

[measured, Lukas] `tahoe.sh patch` + `volume`, plain boot, installer onto `Tahoe`: the install finished and Tahoe
reached Setup Assistant on the plain config (`-nvoff -v`, Darwin 25 PCCI copies). So the CPU patches work on Tahoe
[measured: no smp_init divide-by-zero, it boots]. Volumes now: `Tahoe` 12.6 GB + `Tahoe - Data` 3.5 GB; container
has 60.7 GB unallocated, Sequoia's data volume holds 119 GB, so Migration Assistant cannot copy it all.

Decision: on Tahoe, no migration. One local account named `lukas` (first account → UID 501, same as Sequoia, so the
Sequoia data volume `/Volumes/macOS - Data` stays readable). `tahoe.sh link` symlinks `~/nmx-build` and the repo to
it. The drivers are installed from inside Tahoe, one per boot: Wi-Fi (`install.sh airport`, out-tahoe) → WhateverXe
Graphics (`wex-install.sh`, needs the Command Line Tools for python3) + `efi.sh wex` → nullmoth 2.9 for 26 (1401 app,
`no-wsreset`, `ondemand.sh`) + `efi.sh wexrtx`. Keeping everything from Sequoia = once Tahoe works, upgrade Sequoia in
place (`prepare`) and delete the test volume.
