# nmx-intel: aceleração da Intel Iris Xe (Raptor Lake-P) no macOS

Experimento para fazer o driver de teste AMD/Intel do nullmoth (**NMXGPU**, o porte do i915/xe do Linux
para o macOS) funcionar na iGPU do Acer Nitro V15 ANV15-51 (`8086:a7a8`, Raptor Lake-P, Xe-LP,
display version 13.00 stepping E0). O painel interno é ligado na Intel (não há MUX), então só a
Intel acelerada dá tela acelerada.

Base: nullmoth `nvidia-macos-driver` **2.0.2**, macOS Sequoia **15.8.1**, app 1401.
O NVIDIA (RTX 3050) já funciona com o driver original e não é afetado por nada daqui.

## Estado atual

| Etapa | Estado |
| --- | --- |
| i915 aceita a placa (`a7a8`) | ✅ patch 1 |
| i915 detecta a plataforma e carrega o firmware DMC (`adlp_dmc.bin` v2.20) | ✅ |
| Controle de energia do painel (PPS) lido no lugar certo | ✅ patch 2 |
| Boot não trava mais (o i915 falha e devolve a placa) | ✅ |
| VBT lida, conectores criados (eDP em DDI A, HDMI em DDI B, DP em TC1/TC2) | ✅ |
| `-102` do gerenciador de túnel DP (bug de build: o stub sempre devolve EOPNOTSUPP) | ✅ patch 4 |
| Timeout do PPS no eDP | ✅ explicado: era a limpeza depois do `-102` (espera o painel desligar no unload) |
| `-102` no primeiro modeset (`intel_dp_tunnel_atomic_check_link`, mesma falha de build) | ✅ patch 5 |
| **i915 inicializa por completo: `NullMoth GPU: driving 8086:a7a8`** | ✅ |
| NMXAccel atende clientes Metal (user clients, GPU tasks) | ✅ começou |
| fb do GOP herdado pelo i915 | ❌ não: o pipe A já está desligado quando o i915 assume. Fica o buffer na stolen |
| **Compilar o NMXGPU no Mac** (`build/`) | ✅ o build sem mudanças bate com a release |
| Ponte de tela: `the scan-out buffer would not map (102)` (GEM do i915 sem `.vmap`, buffer não contínuo) | ✅ teste 6: o i915 mostra o nosso buffer no painel |
| Buffer novo na stolen caiu por cima do fb do GOP, onde o console ainda escreve (imagem deslocada, Mac congelou sem log) | 🔧 `0006`: tomar o fb do GOP |
| Teste 7: a tomada falha porque o error capture já está em GGTT 0, e o resto da faixa do console fica sem dono (tela preta, congelou) | 🔧 `0007` + `0008`: segurar a faixa no `init_ggtt` |
| Teste 8: endereço do fb de boot com flag no bit 0 (tomada não aconteceu); congela ~9 s depois que o WindowServer usa o framebuffer | 🔧 `0009`: máscara e GPU acordada enquanto o fb existe |
| Teste 9: ainda congela depois de publicar o fb (a marca de boot foi apagada), sem log | 🔧 `0010`: trilha das etapas na NVRAM (`nvram nullmoth-gpu-trail`) |
| Teste 10: modeset da ponte OK (`lit`); congela entre `lit` e `published` (registro do cliente DRM ou start do IOFramebuffer); a tomada do fb do GOP ainda falha | 🔧 `0011`: trilha mais fina, compilado, falta testar (teste 11) |
| Patches 1 a 5 viram correções no fonte (`source-fixes/0001..0003`) | 🔧 compilado, falta testar |
| Tela preta com o Mac vivo (sem framebuffer, o i915 desliga o pipe, DC6) | ❌ consequência da ponte |
| Tela acelerada / Metal na Intel | ❌ ainda não |

Contexto completo para retomar o trabalho (máquina, segurança, onde paramos, plano): [CLAUDE.md](CLAUDE.md).

Detalhes, hipóteses e o passo a passo de cada teste estão em [LOG.md](LOG.md). O que cada patch muda
está em [patches/PATCHES.md](patches/PATCHES.md).

## Como aplicar (no Mac)

Clone este repositório no Mac (`git clone https://github.com/kitsuneislife/nmx-intel`) e rode os comandos de dentro dele.

Os patches mudam só a cópia do NMXGPU que o app 1401 guarda em
`/Library/NullMoth/kexts/15/NMXGPU.kext`. Quando o driver de teste da Intel é ligado no app, o app copia
essa versão para `/Library/Extensions`. Antes de tocar em qualquer coisa, o script confere os bytes que vai
trocar e faz backup do original em `~/NMXGPU.original`.

```
sudo bash patches/apply.sh          # correções: patches 1, 2, 4 e 5
sudo bash patches/apply.sh debug    # correções + patch 3 (mensagens de debug do i915, DRIVER+KMS)
sudo bash patches/apply.sh restore  # volta ao original
```

Depois, no app 1401: desligue e ligue de novo o driver de teste da Intel, e reinicie.

Para ler o resultado:

```
log show --last boot --info --debug --predicate 'sender == "NMXGPU"' > ~/nmx.txt
tail -n 60 ~/nmx.txt
```

## Segurança e como voltar

- O i915 só roda com `nmxintel=1` nos boot-args, que o app põe e tira.
- Se o boot travar enquanto o driver configura a placa, o NMXGPU percebe no boot seguinte e não tenta mais
  (`the last attach of 8086:a7a8 never returned`). Desligar e ligar no app libera uma nova tentativa.
- No seletor do OpenCore: **Espaço**, depois **"Start once without NVIDIA driver"** (`-nvoff`), que também
  desliga o NMXGPU naquele boot.
- O EFI do pendrive não tem nada disso.
- Pelo Recovery: apagar `/Library/Extensions/NMXGPU.kext`.

## Para uma versão nova do nullmoth

Os offsets mudam a cada build. O `tools/find-offsets.py` acha os cinco pontos de patch num binário NMXGPU
qualquer e imprime os bytes atuais e os novos. Se ele disser `NOT FOUND`, o código mudou e é preciso reler a
função antes de aplicar qualquer coisa.

```
python3 -I tools/find-offsets.py /Library/NullMoth/kexts/15/NMXGPU.kext/Contents/MacOS/NMXGPU
```

## Correções no código-fonte

Os patches binários servem para testar rápido. As correções equivalentes no código, para um build próprio
ou para mandar ao nullmoth, ficam em [source-fixes/](source-fixes/):

- `0001-linux_pci-match-only-the-probing-driver.patch`: equivale ao patch 1, mas sem desligar o xe.
- `0002-i915-intel_pch-guess-the-pch-when-none-is-visible.patch`: equivale ao patch 2. O certo mesmo seria
  o NMXGPU mostrar a ponte ISA (`00:1f.0`) ao LinuxKPI.
- `0003-i915-dp_tunnel-no-manager-is-not-an-error.patch`: equivale aos patches 4 e 5. A alternativa no build é
  desligar `CONFIG_DRM_I915_DP_TUNNEL` ou compilar os helpers `CONFIG_DRM_DISPLAY_DP_TUNNEL` junto.

## Licença

O código do nullmoth (`gpu-port/`, `kexts/`) é PolyForm Noncommercial 1.0.0: uso pessoal e de pesquisa
permitido. Este repositório não redistribui binários do nullmoth, só a descrição dos bytes trocados e
diffs pequenos.
