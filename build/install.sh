#!/bin/bash
# install.sh: põe o NMXGPU compilado (~/nmx-build/out) no lugar do binário que o app 1401 usa para o driver de teste.
#   sudo bash build/install.sh
# Depois: no app, desligar e ligar o driver de teste "AMD / Intel", e reiniciar.
# Para voltar ao original da release: sudo bash tools/binpatch/apply.sh restore (e desligar/ligar no app de novo).
set -u
BIN=${NMX_BIN:-/Library/NullMoth/kexts/15/NMXGPU.kext/Contents/MacOS/NMXGPU}
UH=$(eval echo "~${SUDO_USER:-$(id -un)}")
NEW=${NMX_NEW:-"$UH/nmx-build/out/NMXGPU.kext/Contents/MacOS/NMXGPU"}
BK="$UH/NMXGPU.original"
ORIG_SHA=33aa04a8681223e56228223491c8205ec3023289a49187d8668c0458eda61c77
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

[ "$(id -u)" = 0 ] || { echo "rode com sudo: sudo bash $0"; exit 1; }
[ -f "$BIN" ] || { echo "não achei $BIN (o app 1401 / nullmoth 2.0.2 está instalado?)"; exit 1; }
[ -f "$NEW" ] || { echo "não achei o binário compilado: $NEW"; exit 1; }

# o original da release, uma vez só (o apply.sh usa o mesmo backup)
if [ ! -f "$BK" ]; then
  if [ "$(sha "$BIN")" = "$ORIG_SHA" ]; then cp "$BIN" "$BK" && echo "backup do original: $BK"
  else echo "sem backup do original e o binário instalado não é o original: pare e confira"; exit 1; fi
fi
[ "$(sha "$BK")" = "$ORIG_SHA" ] || { echo "$BK não é o original 2.0.2: pare e confira"; exit 1; }

echo "antes:  $(sha "$BIN")"
cp "$NEW" "$BIN" || exit 1          # cp sobre o arquivo existente mantém dono e permissões
echo "agora:  $(sha "$BIN")"
echo "pronto. Agora: app 1401 -> driver de teste AMD / Intel desligado, depois ligado -> reiniciar"
