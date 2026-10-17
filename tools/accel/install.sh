#!/bin/bash
# Instala o NVAccel compilado por tools/accel/build.sh em /Library/Extensions e refaz a coleção auxiliar de kexts
# (como tools/intelfb/install.sh). Na primeira vez guarda o original do nullmoth em ~/NVAccel.kext.original.
#   sudo bash tools/accel/install.sh            instala o nosso
#   sudo bash tools/accel/install.sh restore    volta o original do nullmoth
# Atenção: ligar/desligar o driver no app 1401 pode copiar o NVAccel do nullmoth de volta.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
HOMEU=$(eval echo "~${SUDO_USER:-root}")
SRC=${SRC:-$HOMEU/nmx-build/accel/out/NVAccel.kext}; ORIG=$HOMEU/NVAccel.kext.original
EXT=/Library/Extensions; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
KB=/System/Library/KernelCollections/BootKernelExtensions.kc; KS=/System/Library/KernelCollections/SystemKernelExtensions.kc
K=/System/Library/Kernels/kernel; KARG=(--allow-missing-kdk); [ -f "$K" ] && KARG+=(--kernel "$K")
T=$(mktemp -d)

[ -d "$ORIG" ] || { ditto "$EXT/NVAccel.kext" "$ORIG" && echo "original guardado em $ORIG"; } || { echo "não consegui guardar o original"; exit 1; }
if [ "${1:-}" = restore ]; then FROM=$ORIG; else FROM=$SRC; fi
[ -f "$FROM/Contents/MacOS/NVAccel" ] || { echo "falta $FROM (bash tools/accel/build.sh)"; exit 1; }
[ -f "$HOMEU/AuxiliaryKernelExtensions.kc.antes-accel" ] || cp -p "$KC" "$HOMEU/AuxiliaryKernelExtensions.kc.antes-accel"
rm -rf "$EXT/NVAccel.kext" && ditto "$FROM" "$EXT/NVAccel.kext" || { echo "cópia falhou; rode de novo com restore"; exit 1; }
chown -R root:wheel "$EXT/NVAccel.kext" && chmod -R 755 "$EXT/NVAccel.kext"
echo "NVAccel: $(shasum -a 256 "$EXT/NVAccel.kext/Contents/MacOS/NVAccel" | cut -c1-8)"

NEWKC="$KC.nmx-accel-new"; rm -f "$NEWKC"
echo "refazendo a coleção de kexts (1-2 min)..."
kmutil create -n aux --volume-root / "${KARG[@]}" -B $KB -S $KS --repository "$EXT" -A "$NEWKC" -z >"$T/kmutil.log" 2>&1 \
  || { tail -20 "$T/kmutil.log"; echo "kmutil falhou; a coleção não mudou (o kext em $EXT mudou: rode com restore)"; exit 1; }
INS=$(kmutil inspect -a x86_64 -A "$NEWKC" 2>/dev/null) || { echo "não consegui ler a coleção nova"; rm -f "$NEWKC"; exit 1; }
for k in NVRM NVRMFB NVAccel NMIntelFB; do
  printf '%s\n' "$INS" | grep -qw "com.nullmoth.$k" || { echo "com.nullmoth.$k sumiu da coleção nova; nada mudou"; rm -f "$NEWKC"; exit 1; }
done
mv -f "$NEWKC" "$KC" && rm -rf "$T" || { echo "não consegui trocar a coleção"; exit 1; }
echo "pronto. Reinicie."
