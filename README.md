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
| Teste 10: modeset da ponte OK (`lit`); congela entre `lit` e `published` (registro do cliente DRM ou start do IOFramebuffer); a tomada do fb do GOP ainda falha | ✅ testado no teste 11 |
| Teste 11: **o attach termina** (`published`, marca apagada); congela depois, antes do macOS usar o nosso fb. Tomada do GOP: `tk-obj` (stolen ocupada) | ✅ testado no teste 12 |
| Teste 12: sem batimento, então congela < 2 s depois do registro do IOFramebuffer. O `IONDRVFramebuffer` do firmware continua na Intel | ✅ testado no teste 13 |
| Teste 13: congela dentro de `NMXGPUFB::start`, logo depois do modeset; a tomada falha com `-ENOSPC` porque o i915 pôs objetos dele nas páginas da stolen do fb do GOP, onde o macOS ainda desenha | ✅ testado no teste 14 |
| Teste 14: **a tomada do fb do GOP funciona** (`took`): o painel mostra o console do macOS pelo i915. Ainda congela depois do attach | ✅ testado no teste 15 |
| Teste 15 (`fb=2`, sem o nosso IOFramebuffer): **o Mac não congela** (viveu 91 s, WindowServer subiu). O congelamento vem do `NMXGPUFB`. O painel fica parado no quadro do modeset (FBC/PSR) | ✅ testado no teste 16 |
| Teste 16: **o painel atualiza** (console ao vivo pelo i915) e o Mac fica vivo. O WindowServer sobe, mas não mostra o desktop; o ANV acha 0 GPUs | ✅ testado no teste 17 |
| Teste 17 (probe): os nós `/dev/dri` existem, mas toda abertura falha com ENODEV. Bug do port: a `struct file` não tem vnode, e o `drm_stub_open` não acha o minor | ✅ testado no teste 18 |
| Teste 18: **desktop no painel, com o i915 controlando a tela** (`fb=2`). A abertura do DRM agora funciona, mas o port lê o ENXIO do `finit` como erro | ✅ testado no teste 19 |
| Teste 19: desktop de novo; **o i915 responde ao espaço do usuário** (`drmGetVersion` = i915 1.6.0). O libdrm não acha a GPU (nós clone) e o `GET_PCIINFO` dá ENODEV | ✅ testado no teste 20 |
| Teste 20: **o libdrm acha a GPU** (`GET_PCIINFO` responde) e o Mac trava logo depois, quando os processos do macOS carregam o ANV | 🔧 `0020`: cada pedido na NVRAM (teste 21) |
| Teste 21: o ANV conversa com o i915 (centenas de pedidos). O travamento é o RCU do port: `synchronize_rcu` no `close` gira sem interrupções (panic TLB flush timeout) | 🔧 `0021`: RCU com leitores que podem dormir (teste 22) |
| Teste 22: com 0021, trava aos ~4 min sem panic e sem RCU esperando; o desktop não aparece porque o NMXAccel da Intel recusa as superfícies do WindowServer | 🔧 `0022`/`0023`: batimento de 1 s, interrupções e eventos de energia da GPU (teste 23) |
| Teste 23: a GPU estava parada; o WindowServer fica em loop no NMXAccel (sem framebuffer nosso) e o watchdog do macOS derruba o Mac ~225 s depois | 🔧 `0024`: sem NMXAccel na Intel enquanto não houver o nosso IOFramebuffer (teste 24) |
| Teste 24: **desktop pelo i915, sem travar**; o ANV (Vulkan da Intel) enxerga `Intel(R) Graphics (RPL-P)`, Vulkan 1.4 | ✅ Próximo: o `NMXGPUFB` (fb=1) para ter o Metal da Intel |
| Caminho RTX: o NMIntelFB do nullmoth (fora do pacote) põe o painel da Intel como cabeça 4 do NVAccel, e a RTX compõe o desktop | 🔧 `tools/intelfb` (build, install, enable); teste RTX-1 |
| RTX-1: o boot trava quando o NMIntelFB entra, sem log | 🔧 intelfb-0002: trilha na NVRAM e trava de boot (RTX-2) |
| RTX-2: o NMIntelFB acha o painel (pipe A, 1920x1080) e trava no registro de energia | 🔧 intelfb-0003: dependent ID antes do start, como o NVRMFB (RTX-3) |
| RTX-3: o NMIntelFB sobe inteiro; tela preta e trava depois | 🔧 intelfb-0004/0005: trilha de cada chamada e trava de boot de 2 min (RTX-4) |
| RTX-4: o macOS abre a tela inteira (modo, gamma, VRAM) e trava depois de ligar o VBL | 🔧 intelfb-0006: batimento com a última chamada (RTX-5) |
| RTX-5: o VBL travou o grupo de `thread_call` do kernel (`vbl=2`) | 🔧 intelfb-0007: VBL em thread própria e só depois de ligado (RTX-6) |
| RTX-6/6b: tela preta ~20 s depois (no grupo do NVRM) ou trava no registro de energia (fora dele) | 🔧 intelfb-0008: esperar 45 s antes de assumir o painel (RTX-7) |
| RTX-7: mesmo esperando a NVIDIA, trava igual; caminho RTX parado | 🔧 `0025`: o VBL do `NMXGPUFB` em thread própria (o mesmo erro do NMIntelFB); teste 25 com `fb=1` |
| Teste 25: trava logo depois de `fb-started`. O IOFramebuffer não tinha controlador até o `open` (NULL no `setPowerState` e no `extGetAttribute`, os panics do NMIntelFB) | 🔧 `0026`: `IOFBDependentID` próprio antes do `start`; NMXAccel desligado por padrão (teste 26) |
| **Teste 26: desktop pelo nosso framebuffer (144 Hz), sem travar**; muito glitch, com duas telas (a nossa e a do firmware) | 🔧 `0027`: VBL ligado desde o registro; a tela do firmware sai (teste 27) |
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
