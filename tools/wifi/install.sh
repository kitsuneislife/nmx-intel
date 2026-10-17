#!/bin/bash
# Instala o driver de Wi-Fi compilado por tools/wifi/build.sh em /Library/Extensions e refaz a coleção auxiliar de
# kexts (como tools/accel/install.sh). Por padrão instala a versão -diag (log no ioreg, chave MtkLog).
#   sudo bash tools/wifi/install.sh            instala (diag)
#   sudo bash tools/wifi/install.sh plain      instala a versão sem log
#   sudo bash tools/wifi/install.sh restore    tira o driver de Wi-Fi
# Boot seguro: OpenCore Space -> "Start once without NVIDIA driver" (-nvoff) também deixa a placa de Wi-Fi em paz.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
HOMEU=$(eval echo "~${SUDO_USER:-root}")
EXT=/Library/Extensions; DST=$EXT/SimpleMtkWlan.kext; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
KB=/System/Library/KernelCollections/BootKernelExtensions.kc; KS=/System/Library/KernelCollections/SystemKernelExtensions.kc
K=/System/Library/Kernels/kernel; KARG=(--allow-missing-kdk); [ -f "$K" ] && KARG+=(--kernel "$K")
T=$(mktemp -d)

case "${1:-}" in
  restore) FROM= ;;
  plain)   FROM=$HOMEU/nmx-build/wifi/out/SimpleMtkWlan.kext ;;
  "")      FROM=$HOMEU/nmx-build/wifi/out/SimpleMtkWlan-diag.kext ;;
  *) echo "uso: sudo bash tools/wifi/install.sh [plain|restore]"; exit 1 ;;
esac
[ -z "$FROM" ] || [ -f "$FROM/Contents/MacOS/SimpleMtkWlan" ] || { echo "falta $FROM (bash tools/wifi/build.sh)"; exit 1; }
[ -f "$HOMEU/AuxiliaryKernelExtensions.kc.antes-wifi" ] || cp -p "$KC" "$HOMEU/AuxiliaryKernelExtensions.kc.antes-wifi"
rm -rf "$DST"
if [ -n "$FROM" ]; then
  ditto "$FROM" "$DST" && chown -R root:wheel "$DST" && chmod -R 755 "$DST" || { echo "cópia falhou; rode com restore"; exit 1; }
  # The driver joins the networks in its personality's WiFiConfig at start (no Wi-Fi menu in this version).
  # The password lands in Info.plist, so that file is root-only.
  read -r -p "nome da rede Wi-Fi (Enter pula): " SSID
  if [ -n "$SSID" ]; then
    read -r -s -p "senha da rede: " PASS; echo
    SSID="$SSID" PASS="$PASS" /usr/bin/python3 -I - "$DST/Contents/Info.plist" <<'EOF' || { echo "não consegui gravar a rede; rode com restore"; exit 1; }
import os, plistlib, sys
p = sys.argv[1]
with open(p, "rb") as f:
    d = plistlib.load(f)
d["IOKitPersonalities"]["SimpleMtkWlan"]["WiFiConfig"] = {"home": {"ssid": os.environ["SSID"], "password": os.environ["PASS"]}}
with open(p, "wb") as f:
    plistlib.dump(d, f)
EOF
    codesign -f -s - "$DST" >/dev/null 2>&1 || { echo "codesign falhou; rode com restore"; exit 1; }
    chmod 600 "$DST/Contents/Info.plist"
    echo "rede gravada: $SSID"
  fi
  echo "SimpleMtkWlan: $(shasum -a 256 "$DST/Contents/MacOS/SimpleMtkWlan" | cut -c1-8)"
else
  echo "SimpleMtkWlan removido de $EXT"
fi

NEWKC="$KC.nmx-wifi-new"; rm -f "$NEWKC"
echo "refazendo a coleção de kexts (1-2 min)..."
kmutil create -n aux --volume-root / "${KARG[@]}" -B $KB -S $KS --repository "$EXT" -A "$NEWKC" -z >"$T/kmutil.log" 2>&1 \
  || { tail -20 "$T/kmutil.log"; echo "kmutil falhou; a coleção não mudou (rode com restore)"; exit 1; }
INS=$(kmutil inspect -a x86_64 -A "$NEWKC" 2>/dev/null) || { echo "não consegui ler a coleção nova"; rm -f "$NEWKC"; exit 1; }
for k in NVRM NVRMFB NVAccel NMIntelFB; do
  printf '%s\n' "$INS" | grep -qw "com.nullmoth.$k" || { echo "com.nullmoth.$k sumiu da coleção nova; nada mudou"; rm -f "$NEWKC"; exit 1; }
done
if [ -n "$FROM" ]; then
  printf '%s\n' "$INS" | grep -qw com.laobamac.SimpleMtkWlan || { echo "o Wi-Fi não entrou na coleção; nada mudou"; rm -f "$NEWKC"; exit 1; }
fi
mv -f "$NEWKC" "$KC" && rm -rf "$T" || { echo "não consegui trocar a coleção"; exit 1; }
echo "pronto. Reinicie."
