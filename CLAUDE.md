# Contexto para o Claude (sessões futuras)

Leia isto inteiro antes de mexer em qualquer coisa. Depois leia `README.md`, `LOG.md` (o fim é o mais
novo) e `patches/PATCHES.md`.

## Quem e como

- O usuário é o Lukas. Escreve em português e quer respostas **curtas e simples**: o que fazer, um comando
  por vez, o que esperar.
- Ele **não consegue digitar `|`** no teclado do Mac. Quando for ele que digita, nada de pipe: grave num
  arquivo e depois use `grep`/`tail`/`sed -n` no arquivo. Se você mesmo roda os comandos, tanto faz.
- Nunca mande o e-mail dele para lugar nenhum.
- Commits: mensagem clara, em inglês ou português, sem identificador de modelo. Terminar com:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- Não abrir PR sem ele pedir.
- Antes de qualquer coisa que reinicie o Mac, mexa no EFI ou em `/Library/Extensions`: explicar e
  confirmar com ele.

## A máquina

- Acer Nitro V15 ANV15-51, i5-13420H (Raptor Lake-H, 4P+4E).
- iGPU Intel `8086:a7a8` (Raptor Lake-P, Xe-LP, display version 13.00 stepping E0). **O painel interno
  está ligado nela**, e não há MUX. A stolen memory da Intel tem 64 MiB em `0x3e800000`. O framebuffer do
  GOP fica na aperture em `0x4000000000`.
- dGPU RTX 3050 6 GB Laptop `10de:25ac`, com o driver do nullmoth (app 1401, driver 2.0.2). **Funciona.**
- macOS Sequoia 15.8.1, bare metal, dual boot com o Windows.
- OpenCore está na ESP do Windows (`disk0s1`). Para montar: `sudo diskutil mount disk0s1`. A config é gerada
  por `tools/make_config.py` no repo `kitsuneislife/Acer-Nitro-V15-ANV15-51-Hackintosh`.
- Os boot-args estão com `-v` (verbose) para os testes. O backup da config sem `-v` está em
  `~/config-antes-v.plist`.

## Os três repositórios

| Repo | Para quê |
| --- | --- |
| `kitsuneislife/nmx-intel` (este) | Aceleração da Intel pelo NMXGPU: patches, ferramentas, diário de testes |
| `kitsuneislife/Acer-Nitro-V15-ANV15-51-Hackintosh` | EFI público: SSDTs, `make_config.py`, `build.sh` |
| `kitsuneislife/hackintosh` | Área de trabalho privada: `CONTEXT.md` (pesquisa e decisões), guias de instalação, handoffs |

Até 2026-10-15 o trabalho estava no branch `ccr-918d231a-luzxg0` dos dois outros repos (ainda não mesclado no
`main`). Este repo usa o `main`.

## O que é o NMXGPU

- É o porte do amdgpu, i915 e xe (do drm-kmod e do Linux 6.14) para o xnu, pelo LinuxKPI do FreeBSD ("xkpi").
- Fonte: `https://github.com/nullmoth/nvidia-macos-driver`, pasta `gpu-port/xkpi`. A versão analisada é a
  2.0.2, commit `d96eaca`. Licença PolyForm Noncommercial: uso pessoal e de pesquisa, sem redistribuir binários.
- Liga com `nmxintel=1` nos boot-args. O app 1401 põe e tira isso.
- O app guarda o kext em `/Library/NullMoth/kexts/15/NMXGPU.kext`. Quando o driver de teste "AMD / Intel" é
  ligado no app, ele copia essa cópia para `/Library/Extensions`. Não confere hash, e o kext não tem
  assinatura. É por isso que os patches binários funcionam.
- Arquivos do nullmoth que importam:
  - `override/src/linux_pci.c`: `linux_pci_find`, `linux_pci_probe` (bug 1).
  - `bsdcompat/src/nmx_bus.c`: lista de dispositivos, `pci_find_class_from` (bug 2).
  - `xnu/nmx_kext.cpp`: `attachNow` e a trava de segurança.
  - `xnu/nmx_fb.cpp`: o `NMXGPUFB`, o IOFramebuffer.
  - `override/src/nmx_fb_bridge.c`: a ponte de tela (bloqueio atual).
- Os scripts de build (`cc.sh`, `all-i915.sh`, `kext/build.sh`) têm caminhos fixos em
  `/Volumes/MiniData/build/gpu-src/{xkpi,kpi}`. As entradas são `freebsd-src` (LinuxKPI), `drm-kmod` e
  `linux-6.14`, com Xcode/CLT (`xcrun clang -mkernel`).

## Segurança e como voltar

- Se o attach nunca retorna (boot travado), o NMXGPU percebe no boot seguinte e desiste da placa. Para tentar
  de novo: no app, desligar e ligar o driver de teste.
- No seletor do OpenCore: **Espaço**, depois "Start once without NVIDIA driver" (`-nvoff`). Isso desliga também
  o NMXGPU naquele boot.
- `sudo bash patches/apply.sh restore` volta o binário original. O backup fica em `~/NMXGPU.original`.
- Pelo Recovery: apagar `/Library/Extensions/NMXGPU.kext`.
- **Com os patches 1 a 5, todo boot com o driver de teste da Intel ligado dá tela preta**, com o Mac vivo, e
  o NMXGPU não desiste sozinho porque o attach retorna. Para usar o Mac normalmente: driver de teste da Intel
  **desligado** no app. O NVIDIA não é afetado.

## Onde paramos (2026-10-15, depois do teste 5)

**Mais novo (teste 9):** o NMXGPU é compilado no Mac (`build/`), com `source-fixes/0001..0010`. Os testes 6, 7, 8 e
9 congelam **depois** de o framebuffer ser publicado, na fase do WindowServer. O teste 5, sem framebuffer, ficava
vivo. No teste 9 a marca `nullmoth-gpu-attaching` não estava na NVRAM, ou seja, o attach retornou. O 0010 grava cada
etapa em `nullmoth-gpu-trail` na NVRAM, para saber onde para. Já está compilado sem debug (`06f83e7a…`), mas **ainda
não foi instalado**: é o teste 10 (ver o fim do `LOG.md`). Depois de congelar, boote com `-nvoff` e rode
`nvram nullmoth-gpu-trail`.
- Com o debug ligado, o macOS descarta mensagens do kext, então use `build-all.sh … nodebug kext` quando as linhas
  `NullMoth display:` importarem.
- O log de um boot que congelou ainda pode ser lido pelo horário. Os vídeos ficam no Google Drive dele
  (`VIDEO_BOOT_HACKINTOSH_N.mp4`). No zsh, use `/usr/bin/log`.
- Já conferido (2026-10-16): WhateverGreen, NootedBlue e NootedGreen (ver o LOG). Nenhum tem algo que dê para
  usar direto.
O resto desta seção é o estado do teste 5, com os patches binários.



O binário instalado no Mac é o `apply.sh debug` (patches 1 a 5), SHA-256 `c55a4432…`.

- O i915 inicializa inteiro: `NullMoth GPU: driving 8086:a7a8`. Lê o VBT da OpRegion, faz o primeiro modeset
  com eDP-1 em 1920x1080, e o NMXAccel começa a atender clientes Metal.
- **Bloqueio:** `override/src/nmx_fb_bridge.c`.
  - Ela chama `drm_client_framebuffer_create` + `drm_client_buffer_vmap`. Os objetos GEM do i915 não têm
    `.vmap`, então dá `-EOPNOTSUPP` (102): `NullMoth display: the scan-out buffer would not map (102)`.
  - Além disso, ela exige memória **fisicamente contínua**, com `nmx_xnu_kva_to_phys`, porque publica o
    endereço físico como "VRAM" do IOFramebuffer. Isso foi pensado para a VRAM das AMD.
  - Sem framebuffer, o i915 desliga o pipe (DC6): tela preta com o Mac vivo.
- Isso não se resolve com patch de bytes. **Precisa de código novo e de compilar o NMXGPU.**

### Próximo passo imediato

Ver se o i915 herdou o framebuffer do GOP. Rodar no log do teste 5 (`~/n6.txt` no Mac):
```
sed -n '3440,$p' ~/n6.txt > ~/b5.txt
grep -n -m 60 -e initial -e BIOS -e stolen -e inherit -e "pipe A" -e "plane 1A" -e takeover ~/b5.txt
```
Se `~/n6.txt` não existir mais, refazer o boot de teste e gravar o log:
`log show --last boot --info --debug --predicate 'sender == "NMXGPU"' > ~/n6.txt`

### Plano para a ponte de tela

Para o i915, há dois caminhos. Em ambos, o buffer fica na stolen memory, que é contínua:
1. **Reaproveitar o framebuffer do GOP.** O i915 herda o fb da BIOS em `intel_initial_plane_config` /
   `intel_find_initial_plane_obj`, como um objeto da stolen. A ponte publicaria esse endereço físico em vez de
   criar um buffer novo. É o mais simples, se o log mostrar que o fb foi herdado.
2. **Criar o buffer de scan-out na stolen** (`i915_gem_object_create_stolen`), fixar no GGTT e usar o endereço
   físico da stolen (`0x3e800000 + offset`), ou o endereço pela aperture.

Nos dois casos, o acesso da CPU pode ser pela aperture do GGTT (BAR2, write-combining) em vez de `vmap`.

### Para compilar o NMXGPU no Mac

**Já funciona** (2026-10-15): o build sem mudanças bate com a release. Ver o fim do `LOG.md`.
1. `bash build/setup.sh` monta a árvore em `~/nmx-build` (nullmoth, drm-kmod, freebsd-src e linux-6.14 nas
   revisões certas, com `$NMX_SRC` no lugar de `/Volumes/MiniData/build/gpu-src`).
2. `bash build/build-all.sh` compila tudo (~6 min). Para refazer só uma parte: `build-all.sh i915 kext`. Os
   nomes das etapas são `amd rt i915 xe kext`. A saída fica em `~/nmx-build/out/NMXGPU.kext`, e o log é o do
   próprio comando.
3. As mudanças nossas no fonte vão no branch `nmx-intel-build` do clone `~/nmx-build/nvidia-macos-driver` e
   são guardadas aqui como patch.
4. Instalar como os patches: substituir o binário em `/Library/NullMoth/kexts/15/NMXGPU.kext/Contents/MacOS/`,
   depois desligar e ligar o driver no app. Guardar o original antes.

## Como trabalhar

- Cada teste vira uma entrada no fim de `LOG.md`: o que mudou, o resultado com as linhas do log que importam,
  a causa e o próximo passo. Atualizar a tabela "Estado atual" do `README.md` e o `patches/PATCHES.md` quando
  um patch muda. Commit e push depois de cada teste.
- Para uma versão nova do nullmoth, rodar `python3 -I tools/find-offsets.py <binário>` antes de aplicar
  qualquer patch. Se der `NOT FOUND`, reler a função.
- Antes de começar, conferir o que mudou upstream: releases e commits em `nullmoth/nvidia-macos-driver`
  (`gpu-port/`) e as issues #163 e #219 (Intel que não anexa). Se o upstream corrigir algo, registrar no LOG e
  descartar o patch nosso equivalente.

## Pendências fora da Intel

- Remover o `-v` quando os testes acabarem: restaurar `~/config-antes-v.plist` na ESP.
- Wi-Fi MT7921 (`14c3:7961`): ver a seção 14 do `CONTEXT.md` no repo `hackintosh` (AirportMtkWlan do mnnobre).
- Bateria, sleep, benchmark (Geekbench) da RTX.
