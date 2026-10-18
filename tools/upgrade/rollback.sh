#!/bin/bash
# rollback.sh: puts back the NVIDIA driver that nullmoth's install.sh backed up before an upgrade (its "4. back up what is
# there now -> /Library/NullMoth/backup-…" step). nullmoth's uninstall.sh only removes the driver, and its fallback job
# (lastgood.sh) only restores when the boot guard tripped; this does the same restore on demand. Our kexts outside the
# package (NMIntelFB) are not touched.
#   sudo bash tools/upgrade/rollback.sh /Library/NullMoth/backup-YYYYMMDD-HHMMSS.xxxxxx      then reboot
set -uo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
BK=${1:-}
case "$BK" in /Library/NullMoth/backup-*) ;; *) echo "uso: sudo bash $0 /Library/NullMoth/backup-…"; exit 1;; esac
[ -d "$BK/NVRM.kext" ] && [ -d "$BK/nvmtl" ] && [ -f "$BK/AuxiliaryKernelExtensions.kc" ] || { echo "$BK não tem um backup completo"; exit 1; }
EXT=/Library/Extensions; GB=/Library/GPUBundles; FW=/Users/Shared/nvfw; NM=/Library/NullMoth
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc; V=7C436110-AB2A-4BBB-A880-FE41995C9F82
fail=0
for k in NVRM NVAccel NVRMFB NVRMAGDC; do rm -rf "$EXT/$k.kext"; [ ! -e "$BK/$k.kext" ] || ditto "$BK/$k.kext" "$EXT/$k.kext" || fail=1; done
for b in NVMTLDriver.bundle NVIDIAShared.bundle nvmtl nvmtl-allow.txt; do rm -rf "$GB/$b"; [ ! -e "$BK/$b" ] || ditto "$BK/$b" "$GB/$b" || fail=1; done
rm -rf "$NM/kexts" "$FW"
[ ! -d "$BK/kexts" ] || ditto "$BK/kexts" "$NM/kexts" || fail=1
[ ! -d "$BK/nvfw" ] || ditto "$BK/nvfw" "$FW" || fail=1
cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC" || fail=1
for f in os-major driver-version; do if [ -f "$BK/$f" ]; then cp -p "$BK/$f" "$NM/$f" || fail=1; else rm -f "$NM/$f"; fi; done
launchctl bootout system/com.nullmoth.lastgood 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.nullmoth.lastgood.plist "$NM/lastgood.sh"
nvram -d $V:nullmoth-nv-starts 2>/dev/null || true
[ "$fail" = 0 ] || { echo "alguma cópia falhou; rode de novo antes de reiniciar"; exit 1; }
for k in NVRM NVAccel NMIntelFB; do echo "  $k $(shasum -a 256 "$EXT/$k.kext/Contents/MacOS/$k" | cut -c1-8)"; done
echo "pronto. Reinicie."
