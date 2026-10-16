# Contexto para o Claude

Leia isto, depois o `README.md` e o fim de `docs/LOG.md` (o mais novo fica no fim).

## Quem e como

- O usuário é o Lukas. Escreve em português e quer respostas **curtas e simples**: o que fazer, um comando
  por vez, o que esperar.
- Ele **não consegue digitar `|`**. Quando for ele que digita, nada de pipe: grave num arquivo e use
  `grep`/`tail`/`sed -n` no arquivo.
- Nunca mande o e-mail dele para lugar nenhum.
- Commits: mensagem clara, sem identificador de modelo, terminando com
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Commit e push depois de cada teste.
- Não abrir PR sem ele pedir.
- Antes de qualquer coisa que reinicie o Mac, mexa no EFI ou em `/Library/Extensions`: explicar e confirmar.

## A máquina

- Acer Nitro V15 ANV15-51, i5-13420H. macOS Sequoia 15.8.1, bare metal, dual boot com o Windows.
- iGPU Intel `8086:a7a8` (Raptor Lake-P, display 13.00 E0). **O painel interno está nela**, sem MUX. Stolen de
  64 MiB em `0x3e800000`; fb do GOP na aperture em `0x4000000000`.
- dGPU RTX 3050 Laptop `10de:25ac` com o driver do nullmoth (app 1401). Funciona.
- OpenCore na ESP do Windows (`sudo diskutil mount disk0s1`); config gerada por `tools/make_config.py` no repo
  `kitsuneislife/Acer-Nitro-V15-ANV15-51-Hackintosh`. Boot-args com `-v` para os testes; backup sem `-v` em
  `~/config-antes-v.plist`.
- Outros repos: `kitsuneislife/Acer-Nitro-V15-ANV15-51-Hackintosh` (EFI público) e `kitsuneislife/hackintosh`
  (privado: `CONTEXT.md`, guias).

## NMXGPU

- Porte do amdgpu/i915/xe (drm-kmod, Linux 6.14) para o xnu pelo LinuxKPI do FreeBSD. Fonte:
  `nullmoth/nvidia-macos-driver`, `gpu-port/xkpi`, versão 2.0.2 (`d96eaca`). PolyForm Noncommercial: sem
  redistribuir binários.
- Liga com `nmxintel=1` (o app 1401 põe e tira). O app guarda o kext em `/Library/NullMoth/kexts/15/NMXGPU.kext`
  e o copia para `/Library/Extensions` ao ligar o driver de teste "AMD / Intel", sem conferir hash.
- Árvore de build em `~/nmx-build` (`build/setup.sh`). As nossas mudanças ficam no branch `nmx-intel-build` do
  clone `~/nmx-build/nvidia-macos-driver` (e `nmx-intel` no drm-kmod), com tag `fix-00NN`, e são guardadas aqui
  em `source-fixes/` (`git format-patch -1`) e listadas em `build/apply-fixes.sh`.
- Arquivos que importam: `xnu/nmx_kext.cpp` (attach, trilha, batimento, chaves), `xnu/nmx_fb.cpp` (`NMXGPUFB`),
  `override/src/nmx_fb_bridge.c` e `override/i915/nmx_i915_fb.c` (ponte de tela), `override/src/linux_rcu.c`.
- Acelerador: `kexts/NVRM/accel/nvrm-accel.cpp` com `NMX_ACCEL` = NMXAccel. Nesse modo o `fFB` nunca é
  preenchido, e o Metal do AMD/Intel é só para apps: o WindowServer não é acelerado.

## Diagnóstico

- NVRAM: `nullmoth-gpu-trail` (etapas), `nullmoth-gpu-beat` (batimento), `nullmoth-gpu-io` (pedidos e energia).
- Chaves (`sudo nvram <chave>=N`, `-d` apaga): `nullmoth-gpu-fb` (1 = nosso fb, 2 = só o painel),
  `nullmoth-gpu-accel`, `nullmoth-gpu-fbdep`, `nullmoth-gpu-ndrv`, `nullmoth-gpu-vbl`, `nullmoth-gpu-shadow`.
- Panics salvos: `/Library/Logs/DiagnosticReports/Kernel-*.panic`. Log do WindowServer: `/usr/bin/log show`.
- `tools/vram`: `dump.c`/`watch.c` leem a VRAM como o WindowServer; `displays.c` lista as telas do CoreGraphics.
- Vídeos no Google Drive dele (`VIDEO_BOOT_HACKINTOSH_N.mp4`, `HACKINTOSH_GLITCHES_N.mp4`).

## Segurança e como voltar

- Attach que nunca volta: o NMXGPU desiste da placa no boot seguinte; desligar e ligar no app libera.
- OpenCore: Espaço → "Start once without NVIDIA driver" (`-nvoff`, desliga também o NMXGPU).
- `sudo bash tools/binpatch/apply.sh restore` volta ao binário original (backup em `~/NMXGPU.original`).
- Pelo Recovery: apagar `/Library/Extensions/NMXGPU.kext`.

## Onde paramos (2026-10-16, teste 32)

- Desktop pelo i915 no `NMXGPUFB`, 1920x1080 a 144 Hz, estável. Patches até `0032`, binário `9823079e…`.
- Os glitches vinham da tela do firmware (`.Display_boot`), que o WindowServer mantém como segunda tela mesmo
  depois de removida do IOKit. `tools/mirror` (LaunchAgent) a espelha na nossa, e os glitches somem.
- Sem aceleração: o WindowServer compõe por software (~225 % de CPU).
- Faltam, para acelerar: um acelerador que o WindowServer use (NMXAccel ligado ao `NMXGPUFB`), a ponte de
  memória/GPU VA do NMXAccel para o i915, e o Metal via ANV de ponta a ponta. Alternativa: a RTX compor o desktop
  e copiar para o painel (NMIntelFB, `tools/intelfb`, parado; os panics `CR2 0x170` dele eram o mesmo NULL de
  controlador corrigido em 0026).

## Pendências fora da Intel

- Remover o `-v` no fim dos testes (restaurar `~/config-antes-v.plist` na ESP).
- Wi-Fi MT7921 (`14c3:7961`): seção 14 do `CONTEXT.md` no repo `hackintosh`.
- Bateria, sleep, benchmark da RTX.
