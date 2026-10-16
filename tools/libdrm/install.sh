#!/bin/bash
# sudo bash tools/libdrm/install.sh          põe o libdrm corrigido em /Library/GPUBundles/nvmtl (guarda o do nullmoth)
# sudo bash tools/libdrm/install.sh restore  volta o do nullmoth
# O app 1401 recopia os arquivos do nvmtl quando o driver de teste é ligado: rode isto DEPOIS de ligar o driver.
set -e
[ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
D=/Library/GPUBundles/nvmtl/libdrm.2.dylib
UH=$(eval echo "~${SUDO_USER:-$(id -un)}")
BK="$UH/libdrm.2.dylib.nullmoth"
NEW="$UH/nmx-build/libdrm/build-nmx/libdrm.2.dylib"
if [ "${1:-}" = restore ]; then cp "$BK" "$D"; echo "voltou: $(shasum -a 256 "$D" | cut -c1-8)"; exit 0; fi
[ -f "$NEW" ] || { echo "não achei $NEW (rode bash tools/libdrm/build.sh)"; exit 1; }
if ! cmp -s "$D" "$NEW"; then
  [ -f "$BK" ] || cp "$D" "$BK"
  cp "$NEW" "$D"
fi
echo "agora: $(shasum -a 256 "$D" | cut -c1-8) (backup do original: $BK)"
