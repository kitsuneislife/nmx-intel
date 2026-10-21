# Upgrading nullmoth's NVIDIA driver

> **Summary.** Decided 2026-10-18 after UPG-1: we do not optimise nullmoth's driver ourselves; we follow its releases
> and re-apply our two changes on top: the RTX-25 NVRM byte patch and the NVAccel accel series (bridge stage 4).
> NMIntelFB is ours and only needs a rebuild when `kexts/NMIntelFB` or the headers it shares change. This page is the
> runbook; UPG-1 (2.1.0 → 2.3.6) in [../tests/rtx-8-accelerated-desktop.md](../tests/rtx-8-accelerated-desktop.md)
> is the worked example; UPG-2 (2.3.6 → 2.5.0, NVIDIA 610 → 615) the one with an OGKM change.

## What we carry on top of a release

| Piece | Ours | How it moves to a new release |
| --- | --- | --- |
| NVRM | copy-engine wait sleeps (`tools/nvrm/build.sh`) | find the new offsets (below), add a hash case to the script |
| NVAccel | `source-fixes/accel/v<ver>/accel-0001..0003` | `git am -3` on the new tag, resolve, rebuild |
| NMIntelFB | `source-fixes/intelfb/*` | rebuild with `REV=v<ver>`; same hash = nothing to install |
| NVRMFB, NVRMAGDC, Metal (GPUBundles) | nothing | the release's |

## 1. Read the release (in the clone)

```
cd ~/nmx-build/nvidia-macos-driver && git fetch --tags origin
git show origin/main:CHANGELOG.md                       # what changed
git diff --stat v<old> v<new> -- kexts/NVRM kexts/NMIntelFB kexts/NVRMFB kexts/NVRMAGDC
```
Look for: new boot or install behaviour (guards, fallback jobs), ABI headers (`nvrm_surfshare_abi.h`,
`nvrm_vram_abi.h`), a new OGKM tag in `kexts/NVRM/patches/README.md` (then `~/ogkm610` and the NMIntelFB KAPI
headers change too), and anything that touches the EFI or boot-args in `install.sh`. The OGKM tag is also named in
the release notes ("Built on NVIDIA's …") and in `package/install.sh`; `kexts/NVRM/patches/README.md` can lag.

**When the OGKM tag changes** (UPG-2): clone the new tree (`git clone --depth 1 --branch <tag> …open-gpu-kernel-modules
~/ogkm<NNN>`), build the plain NVAccel against old and new trees and NMIntelFB with `OGKM_TAG=<old>` and `<new>`
KAPI headers: identical binaries prove the RM/KAPI members we use did not move. If NMIntelFB differs, read the
`NvKmsKapiFunctionsTable` diff before installing: NMIntelFB calls that table by offset through the `nvkms-kapi` nub
property, so a moved member is a wrong call, not a build error.

## 2. Download and verify

```
D=~/nmx-build/pkg-<new>; mkdir -p $D && cd $D
gh release download v<new> -R nullmoth/nvidia-macos-driver -p 'nullmoth-nvidia-<new>.tar.gz' -p SHA256SUMS.txt
shasum -a 256 nullmoth-nvidia-<new>.tar.gz              # must match SHA256SUMS.txt
mkdir x && tar -xzf nullmoth-nvidia-<new>.tar.gz -C x
(cd x/pkgroot && shasum -a 256 -c SHA256SUMS --quiet)   # inner files
```
Read `x/pkgroot/install.sh` before running it.

## 3. NVRM patch

`nvrm_pageoff.c` is public: check the wait loop is unchanged (`git grep -n spins v<new> -- kexts/NVRM/nvrm_pageoff.c`).
In the binary, find the second `osDelayUs` call in `_nvrm_ce_copy_to_pages` (the contiguous-run wait):
```
otool -tV -p _nvrm_ce_copy_to_pages <pkg NVRM> | grep -n -B4 -A2 osDelayUs
nm <pkg NVRM> | grep -E ' _(os_delay|osDelayUs)$'
```
Three patches: the spin limit → /100, `movl $10,%edi` → `$1`, `callq _osDelayUs` → `callq _os_delay`
(rel32 = `os_delay` − (call address + 5), little endian). File offset = vm address in this kext (`__text` addr ==
offset). Add a `case` with the full SHA-256 to `tools/nvrm/build.sh`, build with `SRCK=…/pkgroot/Library/Extensions/NVRM.kext`,
and check `otool` shows `callq _os_delay`.

## 4. NVAccel series

```
git -C ~/nmx-build/nvidia-macos-driver worktree add -b nmx-accel-<v> ~/nmx-build/accel/src-<v> v<new>
cd ~/nmx-build/accel/src-<v> && git am -3 ~/Documents/Projetos/nmx-intel/source-fixes/accel/v<old>/*.patch
```
Then: build the plain tag first (`SRC=<plain worktree> OUT=<scratch> bash tools/accel/build.sh`) and compare with the
release's NVAccel (`nm -j` and `strings` identical, section sizes equal but `__text`) to prove the recipe; build ours,
check every sysctl `tools/intelfb/auto.sh` uses exists (`nm … _sysctl__debug_<name>`), export with
`git format-patch -3 -o source-fixes/accel/v<new>`, point `tools/accel/build.sh`'s default `SRC` at the new worktree.

## 5. Install (Lukas, numbered steps)

1. `bash tools/checkpoint.sh save antes-<new>` (kexts + aux KC + knobs).
2. Move the old originals: `mkdir ~/nmx-<old>` then `sudo mv ~/NVRM.kext.original ~/NVAccel.kext.original ~/nmx-<old>/`
   (our install scripts keep nullmoth's original only if none is there).
3. `sudo CHECK=1 bash ~/nmx-build/pkg-<new>/x/pkgroot/install.sh` → `CHECK PASS`.
4. `sudo bash …/install.sh > ~/install-<new>.log 2>&1`, then `grep -E "backup|STOP|Done|note" ~/install-<new>.log`;
   note the `/Library/NullMoth/backup-…` path.
5. `sudo bash tools/nvrm/install.sh`, then `sudo bash tools/accel/install.sh` (hashes printed).
6. Reboot. Do not toggle the AMD/Intel driver in the 1401 app (it copies nullmoth's NVAccel back).
7. Check: `nvram 7C436110-AB2A-4BBB-A880-FE41995C9F82:nullmoth-nv-starts` must be "not found"; then the bridge
   counters (`sysctl debug.nvaccel_iop_ok debug.nvaccel_iop_fail debug.nmintelfb_ram`) and `auto.sh`'s lines in
   `/usr/bin/log show --last boot --predicate 'process == "logger"'`.

Undo: `sudo bash tools/upgrade/rollback.sh /Library/NullMoth/backup-…`, reboot. No desktop: OpenCore → Space →
"Start once without NVIDIA driver", then the rollback.

## 6. Record

Test row (`UPG-N`) in [../tests/index.md](../tests/index.md), entry in the current phase file, hashes in
[patches.md](patches.md), [../status.md](../status.md). Commit and push.
