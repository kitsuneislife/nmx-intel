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

**Teste 32 — desktop sem glitches:** a causa era a tela do firmware, que o WindowServer manteve (2 telas no CoreGraphics, a do firmware em 1920,0) escrevendo nas páginas do painel. Espelhada (`tools/mirror`, LaunchAgent `com.nmxintel.mirror`), os glitches somem. Sem aceleração (WindowServer ~225 % de CPU).
**Teste 31:** glitches iguais sem VBL. A VRAM é a aperture sem cache: ler 8 MB leva ~3,2 s, WindowServer a ~260 % de CPU (`tools/vram/{dump,watch}.c`). 0032 = sombra em RAM + thread que copia as linhas mudadas (chave `nullmoth-gpu-shadow`) (teste 32, `9823079e…`).
**Teste 30:** a tela do firmware sai (`ndrv-gone`), uma tela só, sem travar; glitches iguais. 0031 = sem VBL por padrão (`nullmoth-gpu-vbl=1` liga o de timer) (teste 31, `c1445517…`).
**Teste 29:** `ndrv-c2-1 … ndrv-term` aos 45 s, panic em `AppleUpstreamUserClientDriver::fbNotificationOccurred` (notificação `kIOFBNotifyTerminated`). 0030 = `s->IOService::terminate()` (teste 30, `52305765…`).
**Teste 28:** travou no `terminate` do IONDRV ainda fechado (sem controlador = NULL no `IOFramebuffer::terminate`). 0029 = thread que espera o `IODisplayConnect` dele (aberto) e só então dá `terminate` (teste 29, `a954ffc0…`).
**Teste 27:** VBL ok; `ndrv-none` (a tela do firmware ficou, duas telas nas mesmas páginas = os glitches). 0028 = achar pelos filhos do GFX0 (teste 28, `d002eae8…`).
**Resultado do teste 26: DESKTOP PELO `NMXGPUFB` (144 Hz), sem travar.** Glitches: duas telas online (a nossa + o
`IONDRVFramebuffer` `.Display_boot`) e o VBL nunca ligado. 0027 = VBL ligado desde o registro + `terminate` do IONDRV do mesmo PCI (chave `nullmoth-gpu-ndrv`) (teste 27, `3fc8feaf…`).
**Mais novo (teste 26, `838aa8d3…`):** o teste 25 parou logo depois de `fb-started`. Causa (IOGraphics da Apple): sem
`IOFBDependentID`, o `IOFBController` só nasce no `open()`, e o `setPowerState`/`extGetAttribute` caem no NULL (os panics
`CR2 0x170` do NMIntelFB são isso). 0026 = dependent ID próprio antes do `start` + NMXAccel com padrão 0 (com `NMX_ACCEL`
o `fFB` nunca é preenchido; o Metal do AMD/Intel do nullmoth é só para apps, o WindowServer desenha sem aceleração).
**Mais novo (teste 25, `483a5ae5…`):** caminho RTX parado (RTX-7 travou igual mesmo esperando 45 s). De volta ao
Metal da Intel. O `NMXGPUFB` tinha o mesmo VBL em `thread_call` HIGH que travou o NMIntelFB; 0025 = VBL em thread
própria só depois do `setInterruptState`. Teste 25 com `fb=1` e o NMIntelFB removido (`tools/intelfb/install.sh remove`).
**Caminho RTX (parado):** o NMIntelFB do nullmoth (`kexts/NMIntelFB`, fora do pacote) publica o painel da Intel
como cabeça 4 do NVAccel; com `debug.nvaccel_igpu=1` + `debug.nvaccelfb=3` + reiniciar o WindowServer, a RTX compõe o
desktop e copia cada quadro para o painel. `tools/intelfb/{build,install,enable}.sh`. Precisa do driver de teste da
Intel **desligado**. O NMIntelFB não sobe com `-nvoff` (patch nosso). RTX-1 travou o boot sem log; intelfb-0002 =
trilha `nvram nullmoth-intelfb-trail`, trava de boot (`nullmoth-intelfb-attaching`) e chaves `nullmoth-intelfb{,-dep}` (RTX-2, `9dbd6128…`).
RTX-2: acha o painel (pipe A 1920x1080, surf 0) e trava no `registerPowerDriver`; intelfb-0003 = dependent ID antes do
`IOFramebuffer::start` (como o NVRMFB), trilha `pm/sp1/sp-done/power`, chave `nullmoth-intelfb-pm=0` (RTX-3, `261eca1c…`).
RTX-3: o `start` termina (`… power sp1 ok sp-done`), tela preta e trava depois, sem log. intelfb-0004 = primeira
chamada de cada método na trilha; 0005 = trava de boot até 2 min vivo (`alive`) (RTX-4, `65901097…`).
RTX-4: o `IOFramebuffer::open` vai inteiro; último método novo `is` (`setInterruptState`), tela preta e trava.
intelfb-0006 = batimento `nvram nullmoth-intelfb-beat` (ms, vbl, calls, last) (RTX-5, `bf5091eb…`).
RTX-5: `vbl=2`, o batimento parou aos 21 s: o VBL (thread_call HIGH, uma thread) travou dentro do IOFramebuffer e
parou o grupo inteiro. intelfb-0007 = VBL e batimento em threads próprias, VBL só depois do `setInterruptState` (RTX-6, `2119d10f…`).
RTX-6: tela preta; a NVRAM para de registrar ~18–21 s depois do `start`. RTX-6b (`dep=0`): trava no
`registerPowerDriver` (como o RTX-2). intelfb-0008 = `nullmoth-intelfb-delay=<s>` antes de assumir o painel (RTX-7, `e2c417e7…`).
**Teste 24:** **desktop pelo i915 e sem travar** (passou de 330 s), e o ANV enxerga `Intel(R) Graphics
(RPL-P)`, Vulkan 1.4. Sem Metal da Intel ainda (NMXAccel desligado por 0024). Próximo: o `NMXGPUFB` (fb=1) sem
congelar. WhateverXe (b00t0x) conferido: só Big Sur e TGL/ADL-N por enquanto.
**Teste 23:** a GPU estava parada (`iot` 140 s antes, `irq` baixo). O travamento é o watchdog do macOS: a
thread principal do WindowServer fica em loop no NMXAccel (`RM refused 8294400`, sem framebuffer nosso com `fb=2`). 0024 =
não pôr `nmxgpu-claimed` sem o nosso IOFramebuffer (chave `nullmoth-gpu-accel`) (teste 24, `7fd87526…`).
**Teste 22:** com 0021, trava aos ~4 min, sem panic e sem RCU esperando, longe dos pedidos do ANV. O
desktop não aparece porque o NMXAccel da Intel recusa toda superfície do WindowServer (`RM refused 8294400`). 0022/0023 =
batimento de 1 s com `irq=`/`iot=` e `Gu`/`Gp`/`Rs`/`Rr`/`D…` no registro (teste 23, `2f1e7630…`).
**Teste 21:** o ANV faz centenas de pedidos ao i915. O travamento é o RCU do port: o `sched_pin` desliga as
interrupções por CPU, um leitor que dorme muda de CPU, e o `synchronize_rcu` do `close` gira para sempre (panic do teste 20).
0021 = `override/src/linux_rcu.c` com contadores globais (teste 22, `9a361f0e…`). A v2.1.0 do nullmoth só traz logs.
**Teste 20:** com o libdrm corrigido, o ANV acha a GPU (`GET_PCIINFO` ok) e o Mac trava ~0,5 s depois.
0020 grava cada pedido em `nvram nullmoth-gpu-io` (teste 21, `5b738a60…`). Instalar o libdrm **depois** de ligar o driver no app.
**Teste 19:** desktop pelo i915 e o DRM abre (`i915 1.6.0`). Faltavam: o libdrm reconhecer os nós clone
(`source-fixes/libdrm-0001`, `tools/libdrm/{build,install}.sh`) e o `GET_PCIINFO` (0019). Teste 20 (`8f2b4b6f…`).
**Teste 18:** **desktop no painel pelo i915** (`fb=2`, a tela do macOS é o IONDRV sobre o fb do GOP). A
abertura do DRM devolve ENXIO (convenção do `finit`), que o port lia como erro; 0018 corrige (teste 19, `7a16c6ad…`).
**Teste 17:** o probe mostrou que toda abertura de `/dev/dri/*` falhava com ENODEV (bug do port: sem
`f_vnode`, o `iminor` dá -1). 0017 corrige; teste 18 com o build completo `47133df7…`.
**Teste 16:** com 0016 e `fb=2`, o painel atualiza (console ao vivo pelo i915) e o Mac fica vivo. O
WindowServer sobe, mas o desktop não aparece; o ANV (Metal da Intel) acha 0 GPUs e ninguém abre o nó DRM.
`tools/probe` grava o diagnóstico em `/Users/Shared/nmx-probe.txt` no boot (teste 17).
**Teste 15:** com `nullmoth-gpu-fb=2` (sem o nosso IOFramebuffer) o Mac **não congela**; o congelamento
vem do `NMXGPUFB`. O painel fica parado no quadro do modeset (FBC/PSR); 0016 desliga os dois (teste 16).
**Teste 14:** a tomada funciona (`shold took`): o i915 mostra o console do macOS no painel. Ainda congela
depois do attach. 0015 = chaves na NVRAM (`sudo nvram nullmoth-gpu-fb=2` etc.); teste 15 com `fb=2`.
**Teste 13:** a tomada falha com `-ENOSPC` em stolen 0+0x7e9000: o i915 aloca objetos dele nas páginas do
fb do GOP, que o macOS (console e IONDRVFramebuffer) ainda desenha pela aperture. 0014 reserva essas páginas (teste 14).
**Teste 12:** congela < 2 s depois do registro do nosso IOFramebuffer; o `IONDRVFramebuffer` do firmware
continua na Intel (dois fbs "console" na mesma GPU). 0013 = teste 13, com chaves `nmxcon=0`/`nmxfb=2`/`nmxfb=0` (ver LOG).
**Teste 11:** o NMXGPU é compilado no Mac (`build/`), com `source-fixes/0001..0020`. A trilha na NVRAM
(`nvram nullmoth-gpu-trail`) mostrou que **o attach inteiro termina** (`published`, a marca de attach é apagada) e que o
Mac congela depois, antes do macOS usar o nosso framebuffer (sem `fb-vram`/`fb-setmode`). A tomada do fb do GOP cai em
`tk-obj` (a faixa da stolen já tem dono). Próximo: teste 12, com batimento e trilha depois do attach (ver o fim do `LOG.md`).
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
