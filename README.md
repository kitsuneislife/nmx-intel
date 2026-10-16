# nmx-intel

Experimento para levar a tela da Intel (`8086:a7a8`, Raptor Lake-P, Xe-LP) do Acer Nitro V15 ANV15-51 ao macOS
pelo **NMXGPU**, o porte do i915 do Linux feito pelo nullmoth. O painel interno é ligado na Intel e não há MUX.

Base: nullmoth `nvidia-macos-driver` 2.0.2, macOS Sequoia 15.8.1, app 1401. A RTX 3050 funciona com o driver
original e não é afetada por nada daqui.

## Estado

| | |
| --- | --- |
| i915 dirige o painel (1920x1080, 144 Hz) pelo nosso IOFramebuffer | ✅ |
| Desktop estável, sem glitches (com `tools/mirror`) | ✅ |
| ANV (Vulkan da Intel) enxerga a GPU | ✅ |
| Desktop acelerado (WindowServer pela GPU) | ❌ compõe por software |

O passo a passo de cada teste está em [docs/LOG.md](docs/LOG.md).

## Estrutura

```
build/          monta a árvore em ~/nmx-build, aplica as correções, compila e instala o NMXGPU
source-fixes/   correções no fonte: 00NN-*.patch (nullmoth e drm-kmod), intelfb/, libdrm/
tools/
  mirror/       espelha a tela fantasma do firmware (LaunchAgent)
  libdrm/       compila e instala o libdrm corrigido
  probe/        diagnóstico em todo boot (/Users/Shared/nmx-probe.txt)
  vram/         lê a memória da tela e lista as telas do WindowServer
  intelfb/      NMIntelFB do nullmoth (caminho RTX, parado)
  binpatch/     patches binários antigos (testes 1 a 5) e restauração do original
docs/           LOG.md (diário) e binary-patches.md
```

## Compilar e instalar

```
bash build/setup.sh                # uma vez: fontes em ~/nmx-build
bash build/apply-fixes.sh          # aplica source-fixes/ (pula o que já está aplicado)
bash build/build-all.sh rt kext    # ~/nmx-build/out/NMXGPU.kext
sudo bash build/install.sh         # troca o binário que o app 1401 usa
```

Depois: no app 1401, desligar e ligar o driver de teste **AMD / Intel**; `sudo bash tools/libdrm/install.sh`;
`sudo bash tools/mirror/install.sh` (uma vez); reiniciar.

Depois do boot: `nvram nullmoth-gpu-trail` e `nvram nullmoth-gpu-beat` mostram até onde o driver chegou.

## Segurança

- O NMXGPU só roda com `nmxintel=1`, que o app põe e tira.
- Um attach que nunca volta faz o NMXGPU desistir da placa no boot seguinte. Desligar e ligar no app libera.
- OpenCore: **Espaço** → **Start once without NVIDIA driver** (`-nvoff`) desliga também o NMXGPU.
- `sudo bash tools/binpatch/apply.sh restore` volta ao binário original da release.
- Pelo Recovery: apagar `/Library/Extensions/NMXGPU.kext`.

## Licença

O código do nullmoth é PolyForm Noncommercial 1.0.0 (uso pessoal e de pesquisa). Este repositório não
redistribui binários, só scripts e diffs.
