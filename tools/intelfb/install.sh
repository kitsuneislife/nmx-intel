#!/bin/bash
# Instala o NMIntelFB (tools/intelfb/build.sh) em /Library/Extensions e refaz a coleção auxiliar de kexts, do mesmo
# jeito que o instalador do nullmoth (package/install.sh). Backup da coleção em ~/AuxiliaryKernelExtensions.kc.antes-intelfb.
#   sudo bash tools/intelfb/install.sh          instala
#   sudo bash tools/intelfb/install.sh remove   tira o kext e refaz a coleção
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
SRC=${SRC:-$(eval echo "~${SUDO_USER:-root}")/nmx-build/intelfb/out/NMIntelFB.kext}
BKDIR=$(eval echo "~${SUDO_USER:-root}")
EXT=/Library/Extensions; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
KB=/System/Library/KernelCollections/BootKernelExtensions.kc; KS=/System/Library/KernelCollections/SystemKernelExtensions.kc
K=/System/Library/Kernels/kernel; KARG=(--allow-missing-kdk); [ -f "$K" ] && KARG+=(--kernel "$K")
T=$(mktemp -d)

if [ "${1:-}" = remove ]; then
  rm -rf "$EXT/NMIntelFB.kext" && echo "kext removido"
else
  [ -f "$SRC/Contents/MacOS/NMIntelFB" ] || { echo "falta o build: bash tools/intelfb/build.sh"; exit 1; }
  case " $(nvram boot-args 2>/dev/null | cut -f2-) " in
    *" nmxintel=1 "*) echo "AVISO: nmxintel=1 está nos boot-args. Desligue o driver de teste AMD / Intel no app 1401;"
                      echo "       com ele ligado o NMIntelFB fica de fora (o i915 cuida da tela).";;
  esac
  rm -rf "$EXT/NMIntelFB.kext" && ditto "$SRC" "$EXT/NMIntelFB.kext" || { echo "cópia falhou"; exit 1; }
  chown -R root:wheel "$EXT/NMIntelFB.kext" && chmod -R 755 "$EXT/NMIntelFB.kext"
  echo "kext: $(shasum -a 256 "$EXT/NMIntelFB.kext/Contents/MacOS/NMIntelFB" | cut -c1-8)"
fi

[ -f "$BKDIR/AuxiliaryKernelExtensions.kc.antes-intelfb" ] || cp -p "$KC" "$BKDIR/AuxiliaryKernelExtensions.kc.antes-intelfb"
NEWKC="$KC.nmx-intel-new"; rm -f "$NEWKC"
echo "refazendo a coleção de kexts (1-2 min)..."
kmutil create -n aux --volume-root / "${KARG[@]}" -B $KB -S $KS --repository "$EXT" -A "$NEWKC" -z >"$T/kmutil.log" 2>&1 \
  || { tail -20 "$T/kmutil.log"; echo "kmutil falhou; nada mudou na coleção"; exit 1; }
INS=$(kmutil inspect -a x86_64 -A "$NEWKC" 2>/dev/null) || { echo "não consegui ler a coleção nova"; exit 1; }
for k in NVRM NVRMFB NVAccel; do
  printf '%s\n' "$INS" | grep -qw "com.nullmoth.$k" || { echo "com.nullmoth.$k sumiu da coleção nova; nada mudou"; rm -f "$NEWKC"; exit 1; }
done
if [ "${1:-}" != remove ]; then
  printf '%s\n' "$INS" | grep -q "com.nullmoth.NMIntelFB" || { tail -20 "$T/kmutil.log"; echo "o kmutil recusou o NMIntelFB"; rm -f "$NEWKC"; exit 1; }
fi
mv -f "$NEWKC" "$KC" && rm -rf "$T" || { echo "não consegui trocar a coleção"; exit 1; }
# um build novo merece outra tentativa: limpa a trava de boot e a trilha do NMIntelFB (intelfb-0002)
nvram -d nullmoth-intelfb-attaching 2>/dev/null; nvram -d nullmoth-intelfb-trail 2>/dev/null
echo "pronto. Reinicie."
