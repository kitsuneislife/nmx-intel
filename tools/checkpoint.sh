#!/bin/bash
# checkpoint.sh: guarda e restaura o estado que funciona antes de cada teste: os kexts do nullmoth/nosso em
# /Library/Extensions (NV*, NM*), a coleção auxiliar de kexts e os knobs nullmoth-* do NVRAM. Cada checkpoint tem uma
# lista SHA-256 e é conferido na hora de salvar e antes de restaurar.
#   bash tools/checkpoint.sh save [nome]       salva (sem sudo) em ~/nmx-checkpoints/<data>-<nome>
#   bash tools/checkpoint.sh list              lista os checkpoints
#   sudo bash tools/checkpoint.sh restore <dir> volta kexts + coleção (reinicie depois)
set -uo pipefail
HOMEU=$(eval echo "~${SUDO_USER:-$(id -un)}")
ROOT=$HOMEU/nmx-checkpoints
EXT=/Library/Extensions; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
kexts() { ls -d "$EXT"/NV*.kext "$EXT"/NM*.kext 2>/dev/null; }

case "${1:-}" in
save)
    D=$ROOT/$(date +%Y%m%d-%H%M%S)${2:+-$2}
    mkdir -p "$D/Extensions" || exit 1
    for k in $(kexts); do ditto "$k" "$D/Extensions/$(basename "$k")" || { echo "cópia de $k falhou"; exit 1; }; done
    cp "$KC" "$D/AuxiliaryKernelExtensions.kc" || { echo "cópia da coleção falhou"; exit 1; }
    # only the knobs (trail/beat/io are per-boot evidence, not state)
    nvram -p 2>/dev/null | grep -E '^nullmoth-' | grep -v -E '^nullmoth-(gpu|intelfb)-(trail|beat|io)' > "$D/nvram.txt"
    nvram boot-args > "$D/boot-args.txt" 2>/dev/null
    ( cd "$D" && find Extensions AuxiliaryKernelExtensions.kc -type f -print0 | xargs -0 shasum -a 256 > SHA256 ) || exit 1
    ( cd "$D" && shasum -a 256 -c -q SHA256 ) || { echo "conferência falhou: checkpoint ruim em $D"; exit 1; }
    echo "checkpoint ok: $D"
    for k in $(kexts); do b=$(basename "$k" .kext); echo "  $b $(shasum -a 256 "$k/Contents/MacOS/$b" | cut -c1-8)"; done
    ;;
list)
    ls -1d "$ROOT"/*/ 2>/dev/null || echo "nenhum checkpoint"
    ;;
restore)
    [ "$(id -u)" = 0 ] || { echo "rode com sudo"; exit 1; }
    D=${2:-}; [ -f "$D/SHA256" ] || { echo "uso: sudo bash tools/checkpoint.sh restore ~/nmx-checkpoints/<dir>"; exit 1; }
    ( cd "$D" && shasum -a 256 -c -q SHA256 ) || { echo "checkpoint corrompido; nada mudou"; exit 1; }
    A=/private/var/tmp/nmx-replaced-$(date +%Y%m%d-%H%M%S); mkdir -p "$A"
    for k in $(kexts); do mv "$k" "$A/" || { echo "não consegui tirar $k"; exit 1; }; done
    for k in "$D"/Extensions/*.kext; do
        ditto "$k" "$EXT/$(basename "$k")" && chown -R root:wheel "$EXT/$(basename "$k")" && chmod -R 755 "$EXT/$(basename "$k")" \
            || { echo "cópia de $k falhou; os kexts tirados estão em $A"; exit 1; }
    done
    cp "$D/AuxiliaryKernelExtensions.kc" "$KC.nmx-restore" && chown root:wheel "$KC.nmx-restore" && chmod 744 "$KC.nmx-restore" && mv -f "$KC.nmx-restore" "$KC" \
        || { echo "não consegui trocar a coleção"; exit 1; }
    echo "restaurado de $D (os kexts tirados estão em $A). Knobs do NVRAM salvos em $D/nvram.txt. Reinicie."
    ;;
*) echo "uso: checkpoint.sh save [nome] | list | restore <dir>"; exit 1 ;;
esac
