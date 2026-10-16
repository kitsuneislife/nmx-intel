# Diário de testes

Máquina: Acer Nitro V15 ANV15-51, i5-13420H, iGPU `8086:a7a8` (Raptor Lake-P, painel interno), RTX 3050 6 GB
Laptop `10de:25ac`. macOS 15.8.1, nullmoth 2.0.2, `nmxintel=1`.

As entradas mais novas ficam no fim.

---

## 2026-10-15: teste 0, driver original

Resultado:
```
(NMXGPU) NullMoth Intel: stolen memory 0x3e800000, 64 MiB
(NMXGPU) NullMoth xkpi: no FADT; ACPI power flags read as zero
(NMXGPU) <6>[drm] amdgpu kernel modesetting enabled.
(NMXGPU) NullMoth xkpi: ran 50 SYSINITs
(NMXGPU) NullMoth xkpi: vgapci0: no driver attached (0)
(NMXGPU) NullMoth GPU: no driver took 8086:a7a8
```
É o mesmo resultado de nullmoth#163 (Alder Lake-P `46a6`): nenhuma Intel funcionou até agora.

Análise do binário 2.0.2:
- `i915_pci_probe` e `i915kmsmodule` estão linkados.
- `a7a8` está na tabela do i915 (item 324 de 365) **e** na do xe (item 55 de 127).
- Os dois drivers se chamam `drmn`, e o `linux_pci_find()` escolhe o primeiro da lista, que é o xe.
- Conclusão: o i915 recusa a placa. → **patch 1**

## 2026-10-15: teste 1, patch 1

Resultado: o boot **travou**. No boot seguinte o NMXGPU desistiu da placa (`the last attach of 8086:a7a8
never returned`). O log do boot travado não foi gravado.

Com `-v` e um vídeo da tela:
```
drm0: [drm] Found alderlake_p/raptorlake_p (device ID a7a8) integrated display version 13.00 stepping E0
drm0: successfully loaded firmware image 'i915/adlp_dmc.bin'
drm0: [drm] Finished loading DMC firmware i915/adlp_dmc.bin (v2.20)
drm0: [drm] *ERROR* PPS state mismatch
drmn drmn0: [drm] [ENCODER:240:DDI A/PHY A] PPS 0 powered off while attempting AUX CH communication.
drmn drmn0: [drm] drm_WARN_ON(intel_dp->pps.vdd_wakeref)
drmn drmn0: [drm] *ERROR* PPS state mismatch          (repete para sempre)
```
O i915 subiu e conversa com o painel. Mas lê o controle de energia (PPS) como zero.

Causa:
- O NMXGPU só cria registro para a própria GPU, então `pci_get_class()` nunca acha a ponte ISA do PCH.
- Sem PCH, o i915 usa o PPS em `0x61200` em vez de `0xc7200`.

→ **patch 2**

## 2026-10-15: teste 2, patches 1 e 2

Resultado: o macOS **bootou**, com o i915 falhando de forma limpa e devolvendo a placa.
```
19:54:47.310 drmn0: [drm] Found alderlake_p/raptorlake_p (device ID a7a8) integrated display version 13.00 stepping E0
19:54:47.317 drmn0: successfully loaded firmware image 'i915/adlp_dmc.bin'
19:54:47.319 drmn0: [drm] Finished loading DMC firmware i915/adlp_dmc.bin (v2.20)
19:54:52.333 drmn0: [drm] *ERROR* [ENCODER:240:DDI A/PHY A] PPS 0 panel status timeout: PP_STATUS: 0x80000008 PP_CONTROL: 0x00000067
19:54:52.335 drmn0: [drm] *ERROR* Device initialization failed (-102)
19:54:52.335 NullMoth xkpi: drmn0: attach failed (102)
19:54:52.335 NullMoth xkpi: vgapci0: no driver attached (0)
19:54:52.338 NullMoth GPU: no driver took 8086:a7a8
```

O que melhorou:
- Os erros `PPS state mismatch` e `powered off while attempting AUX` sumiram.
- A leitura do PPS agora é real:
  - `PP_STATUS 0x80000008` quer dizer PP_ON e sequência ON_IDLE, ou seja, o painel está ligado e parado.
  - `PP_CONTROL 0x67` quer dizer POWER_TARGET_ON e BLC_ENABLE, sem FORCE_VDD.

O que ainda falha:
1. **`-102` é `EOPNOTSUPP` na numeração do xnu.**
   - Alguma função que o i915 chama ainda não foi implementada no porte.
   - Ela vem 2 ms depois do timeout do PPS, ou seja, ainda durante a configuração do display.
   - Não é o `intel_opregion_setup` (que devolve `-ENOTSUPP` sem ASLS), porque o i915 ignora o retorno dele.
   - O `sysctl.h` do porte também foi descartado.
   - Ainda não se sabe qual é. → **patch 3** para ligar o debug.
2. **Timeout do PPS de 5 s.**
   - O valor lido, `0x80000008`, é exatamente o que `wait_panel_on` espera (`IDLE_ON_MASK`/`VALUE`).
   - Então ou ele esperava o painel **desligar** (`IDLE_OFF`/`IDLE_CYCLE`) e a escrita no `PP_CONTROL`
     não pegou, ou a rotina de espera (`__intel_wait_for_register`) do porte não está funcionando.
   - O debug do patch 3 mostra a linha `mask: ... value: ...` antes da espera, e isso resolve a dúvida.

Observação: com o i915 falhando, a tela continua no framebuffer básico. Ainda não há aceleração na Intel.

## Próximo: teste 3, patches 1, 2 e 3 (debug)

Coletar `log show --last boot --info --debug --predicate 'sender == "NMXGPU"'` e procurar:
- a linha `PPS 0 mask: 0x... value: 0x...` que vem antes do timeout;
- a última etapa do i915 antes do `Device initialization failed (-102)`.

## 2026-10-15: teste 3, patches 1, 2 e 3 (debug)

Resultado: 563 linhas do NMXGPU no log. O i915 chega bem mais longe do que parecia:
- O VBT é lido, e o i915 usa os tempos dele para o painel:
  `vbt power_up 2000 ... power_cycle 5000`, `PP_ON 0x7d00001, PP_OFF 0x1f40001, PP_DIV 0x60`.
- Os conectores são criados: HDMI em `DDI B` (DDC pin 0x2), e DP em `TC1` (`tbt-alt, ready: yes`) e em
  `TC2`.

Logo depois do último conector:
```
intel_pps_vdd_off_sync_unlocked: [ENCODER:240:DDI A/PHY A] PPS 0 turning VDD off
intel_power_well_disable: disabling AUX_A
wait_panel_power_cycle: PPS 0 wait for panel power cycle (0 ms remaining)
wait_panel_status: PPS 0 mask: 0xb800000f value: 0x00000000 PP_STATUS: 0x80000008 PP_CONTROL: 0x00000067
*ERROR* PPS 0 panel status timeout ...            (5 s depois)
*ERROR* Device initialization failed (-102)
```

O que isso quer dizer:
- Essa sequência é o `intel_dp_encoder_flush_work()`, a limpeza **depois** de um erro.
  - Ela desliga o VDD e espera o painel ficar `OFF_IDLE` (`IDLE_CYCLE`, mask `0xb800000f`, value `0`).
  - Só que o painel está ligado pelo GOP, então a espera estoura. É inofensivo.
- O erro real é o passo seguinte ao `intel_setup_outputs()`, o `intel_dp_tunnel_mgr_init()`.
  - No binário 2.0.2, essa função **sempre** devolve `-102` (`movl $0xffffff9a, %eax`).
  - O i915 foi compilado com o túnel DP, mas o DRM não (o stub `drm_dp_tunnel_mgr_create` devolve
    `ERR_PTR(-EOPNOTSUPP)`).
  - Ou seja, nenhuma Intel passaria daqui com esse build.

→ **patch 4**

## Próximo: teste 4, patches 1, 2, 3 e 4

O i915 passa da configuração do display. O que vem depois, ainda não testado:
- a leitura do estado que o GOP deixou na tela (`intel_modeset_setup_hw_state`);
- a parte de GEM/GT, com o firmware GuC/HuC (`adlp_guc_70.bin`, `tgl_huc.bin`);
- e o registro do framebuffer, quando o i915 assume a tela.

Risco: tela preta ou travamento quando o i915 assumir o painel. Como voltar: o NMXGPU desiste sozinho no boot
seguinte, ou `-nvoff` no seletor do OpenCore.

## 2026-10-15: teste 4, patches 1, 2, 3 e 4

Resultado: num boot, **tela preta**, e o Mac teve que ser reiniciado. No boot seguinte, ele subiu normal. Os
dois boots ficaram gravados no log, e em ambos o i915 foi bem mais longe:
- `Found valid VBT in ACPI OpRegion (RVDA)`: o VBT vem da OpRegion. O `no FADT` não atrapalha isso.
- Modo do painel no VBT legado: `1024x768`. O modo real é lido do EDID depois: `[CONNECTOR:241:eDP-1] Found mode 1920x1080`.
- `intel_fbc_init: Sanitized enable_fbc value: 1`.
- `atomic driver check for <private> failed: -102` e depois `Initial modeset failed, -102`.
- Só no boot da tela preta: `*ERROR* DC state mismatch (0x0 -> 0x2)`.
- `drm_mode_addfb2` cria o `nmxfb`: o i915 **criou o framebuffer** dele.

Causa do `-102`:
- É `intel_dp_tunnel_atomic_check_link()`, que no binário é só `return -102`. É a mesma falha de build do
  patch 4 (o stub `drm_dp_tunnel_atomic_check_stream_bws`).
- Ela roda em todo `atomic_check`, então nenhum modeset passaria.

→ **patch 5**

Tela preta, ainda sem explicação:
- `DC state mismatch (0x0 -> 0x2)` quer dizer que o DMC achou o display em DC5 quando o i915 esperava DC
  desligado.
- Com o primeiro modeset falhando, o i915 pode ter desligado o pipe que o GOP deixou ligado, ou deixado o
  DMC entrar em DC5. Qualquer um dos dois apaga o painel.
- Observar no teste 5.

## Próximo: teste 5, patches 1 a 5

Ver se o primeiro modeset passa e se o i915 assume a tela. Anotar se o Mac responde durante uma tela preta
(luz do Caps Lock, teclas de volume).

## 2026-10-15: teste 5, patches 1 a 5

Resultado: **tela preta, com o Mac vivo** (a luz do Caps Lock acendia e apagava). O log foi gravado:
```
(sem "atomic driver check ... failed" e sem "Initial modeset failed": o primeiro modeset passou)
drm_client_modeset_probe: [CRTC:82:pipe A] desired mode 1920x1080 set (0,0)
drm_mode_addfb2: [FB:242]
NullMoth display: the scan-out buffer would not map (102)
drm_client_release: nmxfb
NullMoth display: no framebuffer (102)
NullMoth GPU: driving 8086:a7a8                      <- o i915 assumiu a placa por completo
... 2,4 s depois: PPS 0 turning VDD off, disabling AUX_A, disabling DC_off, Enabling DC6, disabling always-on
```
- O **NMXAccel** começou a atender clientes, com `newUserClient` do tipo 5/6 e `createUserGPUTask init=1`.
- **Marco:** é a primeira vez que o i915 roda inteiro nesta máquina.

O que falha agora é a ponte de tela (`override/src/nmx_fb_bridge.c`):
- Ela usa `drm_client_framebuffer_create` + `drm_client_buffer_vmap`. Os objetos GEM do i915 não implementam
  `.vmap` (o i915 tem o fbdev próprio, `intel_fbdev`), então `drm_gem_vmap()` devolve `-EOPNOTSUPP` (102).
- Mesmo mapeado, a ponte exige um buffer **fisicamente contínuo**, porque publica o endereço físico como VRAM
  do IOFramebuffer. Isso foi pensado para a VRAM das AMD. Um objeto shmem do i915 não é contínuo.
- Sem framebuffer publicado, nada segura o pipe A, e o i915 desliga o display (DC6). Daí a tela preta.

Saídas possíveis, as duas exigindo código novo e build do NMXGPU:
1. Reaproveitar o framebuffer do GOP, que o i915 herda em `intel_initial_plane_config`. Ele fica na stolen
   memory (`0x3e800000`, 64 MiB) e é contínuo.
2. Criar o buffer de scan-out na stolen memory (`i915_gem_object_create_stolen`).

Falta saber se o i915 herdou o fb do GOP (procurar `initial plane`/`BIOS fb` no log do boot).

## 2026-10-15: análise do teste 5, o fb do GOP não foi herdado

No log do teste 5 (`~/n6.txt`, linhas a partir de 3440), a leitura do estado do hardware pelo i915 mostra
tudo desligado:
```
[drm] Got Intel graphics stolen memory base 0x3e800000, size 0x4000000
[CRTC:82:pipe A] hw state readout: disabled
[PLANE:32:plane 1A] hw state readout: disabled, pipe A
BIOS left unused DDI_IO_A power well enabled, disabling it
```
- Não aparece `initial plane`, `BIOS fb` nem `takeover`. Quando o i915 assume, o pipe A já está desligado,
  então não sobra framebuffer do GOP para herdar.
- **O caminho 1 está descartado.** Fica o caminho 2: criar o buffer de scan-out na stolen memory
  (`i915_gem_object_create_stolen`), fixar no GGTT e publicar o endereço físico (`0x3e800000 + offset`).
- A stolen foi detectada certa (64 MiB), então há espaço: 1920x1080x4 dá uns 8 MiB.

## Próximo: build do NMXGPU

Montar a árvore de fontes, compilar sem mudanças e comparar com o binário da release 2.0.2. Só depois
escrever a ponte nova para o i915.

## 2026-10-15: primeiro build do NMXGPU no Mac, sem mudanças

Árvore montada em `~/nmx-build` por `build/setup.sh`, e build por `build/build-all.sh`. Revisões:
- nullmoth 2.0.2 (`d96eaca`, ainda o `main` do upstream), branch local `nmx-intel-build` com
  `build/nmx-src-paths.patch`: troca `/Volumes/MiniData/build/gpu-src` por `$NMX_SRC` e `/opt/homebrew/bin/python3`
  por `python3` (o 3.9 das CLT serve).
- drm-kmod `master` `c16de0f9fa` (2026-10-08, o último commit antes de o xkpi aparecer no nullmoth).
- freebsd-src `bbfd52d`. O nullmoth não diz a revisão. Os forks em `override/src` batem com qualquer commit
  entre `d7e7397` (10-05) e `bbfd52d` (10-10). O `9d82546` (10-11) já muda o `linux_pci.c`.
- Linux `v6.14`, só `drivers/gpu/drm/xe` e `include/uapi`.
- Apple clang 17.0.0 (clang-1700.0.13.5), das Command Line Tools, SDK 15.5.

O que faltava e não está no repo do nullmoth:
- `fbroot/`: links para `freebsd-src/sys/compat` e `sys/contrib` (o ACPICA é necessário).
- `amd.flags`: gerado por `gen_flags.py`.
- `xe_drm.h`: o xe inclui `<uapi/drm/xe_drm.h>`, que o drm-kmod não tem. Pus um link para o do Linux 6.14 em
  `drm-kmod/include/uapi/drm/`.
- O `rt.sh` compila também `xnu/nmx_npu_kext.cpp`, e isso duplica o `kmod_info` no link. O `build-all.sh`
  tira esse objeto, como o `kext-npu/build.sh` faz.

Resultado: **compila e linka sem erro**. amd 900/900, runtime 76/76, i915 274/274, xe 193/193.
`NMXGPU 16b0a4d6`, 15.236.184 B.

Comparação com o binário da release (`~/NMXGPU.original`, 15.368.736 B):

| | release | nosso |
| --- | --- | --- |
| `__text` | 10.526.990 | 10.523.694 (−0,03%) |
| `__DATA,__data` | 199.928 | 199.944 |
| `nmx_sysinit`, `__bss`, `__common`, `__got` | iguais | iguais |
| símbolos com nome | 28.296 | 28.296 |

Só 11 símbolos de cada lado diferem. São funções e tabelas `static` que um compilador embutiu e o outro não, por
exemplo `subplatform_rpl_ids`, que está no fonte mas o nosso clang dobrou para dentro do código. A diferença vem do
compilador: o nullmoth compila cruzado num Apple Silicon. **O build bate com a release.**

## Próximo: aplicar as correções no fonte e escrever a ponte para o i915

1. Aplicar `source-fixes/0001..0003` (os equivalentes dos patches 1 a 3) e corrigir o stub do dp_tunnel
   (patches 4 e 5) no fonte.
2. Ponte de tela: para o i915, criar o buffer na stolen memory e publicar o endereço físico.
3. Antes de instalar: guardar o binário original e explicar o teste para o Lukas.

## 2026-10-15: correções no fonte e ponte de tela nova para o i915 (compilado, não instalado)

Tudo em `source-fixes/`. Para aplicar numa árvore nova: `build/setup.sh` e depois `build/apply-fixes.sh`.
- `0001` (nullmoth): o `linux_pci_find` só olha a tabela do driver que está fazendo o probe. Substitui o patch 1
  **sem** desligar o xe.
- `0002` (drm-kmod): sem PCH visível, usa o mesmo chute de uma VM. Raptor Lake-P é subtipo de Alder Lake-P, então
  o chute dá `0x7A80`, que é `PCH_ADP`, o mesmo tipo do patch 2. O `pch_id` muda de `0x5180` para `0x7A80`, mas o
  i915 só usa o tipo.
- `0003` (drm-kmod): sem gerenciador de túnel DP não é erro, e sem túnel não há banda para conferir. Substitui
  os patches 4 e 5. No `.o`, `intel_dp_tunnel_mgr_init` agora termina em `xorl %eax,%eax`.
- `0004` (nullmoth): **a ponte de tela para o i915.**

### A ponte nova (`override/i915/nmx_i915_fb.c`)

Faz o mesmo que o fbdev do próprio i915 (`intel_fbdev.c` e `intel_fbdev_fb.c`):
1. `i915_gem_object_create_stolen` (1920x1080x4 ≈ 8 MiB, bem menos que a metade dos 64 MiB). Se não couber,
   usa shmem.
2. `intel_framebuffer_create`, XRGB8888 linear, pitch alinhado a 64. Linear não usa DPT no display 13.
3. `intel_fb_pin_to_ggtt`, que fixa primeiro na parte mapeável do GGTT, e depois confere
   `i915_vma_is_map_and_fenceable`.
4. `i915_vma_pin_iomap` para a CPU (write-combining, pela aperture), e o buffer é zerado.
5. O endereço publicado para o macOS é `ggtt->gmadr.start + i915_ggtt_offset(vma)`, isto é, a aperture (BAR2),
   **não** o físico da stolen (`0x3e800000`). É o que o Linux publica como `smem_start`. Pela aperture o buffer é
   uma faixa contínua, e a CPU não acessa a stolen direto. O `nmx_fb.cpp` só usa esse endereço num
   `IODeviceMemory`, como faz com a VRAM (BAR) das AMD.

O `nmx_fb_bridge.c` só desvia quando `drm->driver->name` é `"i915"`. O caminho das AMD não mudou.

Mensagens novas no log:
- `NullMoth display: i915 buffer in stolen, GGTT 0x…, aperture 0x…` quando funciona.
- Na falha: `i915 has no memory…`, `i915 refused the framebuffer…`, `could not pin the buffer in the GGTT…`,
  `landed outside the GGTT aperture` ou `would not map through the aperture…`.

Build: amd 900, runtime 76, i915 275/275 (o arquivo novo a mais), xe 193.
`NMXGPU cf8b2a2c4ed20df426f1f2eaceb7bea92f3c5251ba3b20c489a1172dce4d79af`, 15.236.328 B, em `~/nmx-build/out`.
Os únicos avisos nos arquivos novos são de conversão de sinal, como o resto do port.

**Não instalado.**

## Próximo: teste 6, o NMXGPU compilado

- Este binário **não** tem o patch 3 (debug do DRM). Antes do teste, decidir entre ligar `__drm_debug` no
  fonte (mais log) ou testar assim.
- Instalar: guardar o binário atual, trocar o binário em `/Library/NullMoth/kexts/15/NMXGPU.kext/Contents/MacOS/`,
  desligar e ligar o driver de teste no app, e reiniciar. Confirmar com o Lukas antes.
- Procurar no log: `i915 buffer in stolen`, `NullMoth display: 1920x1080, pitch 7680, phys 0x40…`, e se a tela
  acende.

## 2026-10-15: build de diagnóstico para o teste 6

- `source-fixes/0005` (drm-kmod, `drm_print.c`): com `-DNMX_DRM_DEBUG`, o `__drm_debug` começa em
  `BIT(DRM_UT_DRIVER) | BIT(DRM_UT_KMS)` = `0x6`, o mesmo efeito do patch 3. Sem a flag, nada muda.
  - Cuidado: no 6.14 os `DRM_UT_*` são **números de bit**, não máscaras. A primeira tentativa,
    `DRM_UT_DRIVER | DRM_UT_KMS`, deu `3` (CORE + DRIVER). Conferido no `__data` do binário: agora é `6`.
- `build/build-all.sh debug kext` recompila só o `drm_print.c` com a flag e linka.
- Binário do teste 6: `NMXGPU df90b1b5e3a938b614f02115157e90d7264f504434af7d6ac05e7784758fa083`, 15.236.328 B.
  Tem 0001 a 0005.
- `build/install.sh` copia o binário para `/Library/NullMoth/kexts/15/…`. Antes, confere o backup do original.
  Para voltar: `sudo bash patches/apply.sh restore`.

## 2026-10-15: teste 6, NMXGPU compilado (0001 a 0005, debug do DRM)

Instalado com `build/install.sh` (binário `df90b1b5…`). O `kextstat` do boot seguinte mostra o NMXGPU com
`0xc1bffa` bytes, que é o tamanho do nosso build (o da release é maior). Ou seja, o binário certo foi carregado.

Resultado (duas fotos, sem log):
- Durante o boot, o console do `-v` mostra as mensagens de debug do i915, até
  `[CONNECTOR:241:eDP-1] Detected Intel HDR backlight interface version 170` e `DRRS type: none`. Logo, o debug
  do DRM pelo fonte (0005) funciona.
- Depois disso, **o painel continua aceso pela Intel**, mas com uma imagem "glitchada": o texto antigo do
  console aparece só numa faixa da direita, cortado na borda, e a metade esquerda fica preta. As últimas linhas
  visíveis são do i915 (`intel_dp_aux_supports_hdr`, `intel_panel_init: [CONNEC…`).
- **Nenhum log desse boot foi gravado.** O `log show` não tem nenhuma linha (nem do kernel) entre o desligamento
  das 21:30 e o boot das 21:35 (que foi com `-nvoff`). É o que acontece quando o Mac congela antes de o `logd`
  gravar no disco.
  - Atenção: o `~/n7.txt` que o Lukas gravou pegou o boot com `-nvoff` (o "last boot"), por isso veio vazio.
  - No zsh, chamar como `/usr/bin/log`.

### Causa provável da imagem

- No Gen8+ o i915 usa `ggtt->vm.clear_range = nop_clear_range` (`intel_ggtt.c`). As entradas do GGTT que o GOP
  programou continuam valendo, e a aperture em `0x4000000000` (GGTT 0) continua apontando para o início da stolen.
- O console do macOS continua escrevendo no endereço de boot (`0x4000000000`), ou seja, nas páginas da stolen
  do framebuffer do GOP.
- O nosso buffer novo (`i915_gem_object_create_stolen`) foi alocado **por cima** dessas páginas, com um
  deslocamento de meia linha mais algumas linhas. A tela mostra o nosso buffer, que é o texto do console
  deslocado: as linhas começam no meio da tela e o resto delas "volta" pela esquerda da linha seguinte, que é
  preta. Isso bate com as fotos.
- Então a varredura do i915 **funciona**: ele mostra o nosso buffer no painel, com o modo certo. O que está
  errado é onde o buffer foi parar.
- Risco extra: sem ninguém dono da faixa GGTT 0..8 MiB, o i915 pode pôr qualquer objeto da GPU ali (ring, GuC), e
  o console escreveria por cima. Isso pode ser a causa do congelamento, mas sem log não dá para provar.

### Correção: 0006, tomar o framebuffer do GOP

`source-fixes/0006` (nullmoth), no lugar de criar um buffer novo, faz o que o i915 faz com um plano que a BIOS
deixa ligado (`intel_plane_initial.c`):
1. `nmx_xnu_boot_fb` (novo, em `xnu/nmx_platform.cpp`): endereço e geometria do framebuffer de boot por
   `IOPlatformExpert::getConsoleInfo`.
2. Se ele está na aperture e tem o mesmo tamanho do modo (1920x1080), o offset no GGTT é
   `phys - gmadr.start` (aqui deve ser 0).
3. Lê as PTEs do GGTT nesse offset e confere que apontam para **uma faixa contínua da stolen**.
4. `i915_gem_object_create_region_at(stolen, offset, size, PREALLOC)`, WT, e `i915_vma_pin` com
   `PIN_OFFSET_FIXED` no mesmo offset do GGTT.
5. O framebuffer usa esse objeto com o pitch do GOP, sem zerar. O endereço publicado para o macOS volta a ser o
   próprio `0x4000000000`.
- Resultado esperado: o console, o WindowServer e o display engine usam o mesmo buffer. **O texto do `-v` continua
  legível na tela depois que o i915 assume**, então o console vira o log: se travar, a foto mostra onde.
- Se a tomada falhar, cai no buffer novo, mas só em shmem e com a faixa do GGTT do console reservada
  (`i915_gem_gtt_reserve`), para nenhum objeto da GPU ficar embaixo das escritas do console.
- Mensagens novas: `boot framebuffer WxH, pitch P, GGTT 0x…`, `took over the boot framebuffer: stolen 0x…,
  GGTT 0x…`, ou o motivo da falha (`not in the GGTT aperture`, `not one run of stolen memory`, `… is taken`).

Build: i915 275/275, debug `0x6` conferido. `NMXGPU da43cdbb3cf4cc0e1701f7c2990584c2075d5cd8a599d4d826815884a00b3109`,
15.240.648 B. **Não instalado.**

## Próximo: teste 7 (0001 a 0006, debug)

- Mesma instalação: `sudo bash build/install.sh`, depois desligar e ligar o driver no app, e reiniciar.
- **Fotografar a tela** depois que o i915 assumir (o console deve continuar legível), principalmente as linhas
  `NullMoth display: …`.
- Anotar se o Mac responde (luz do Caps Lock).
- Se o Mac estiver vivo, gravar o log **antes** de reiniciar:
  `/usr/bin/log show --last boot --info --debug --predicate 'sender == "NMXGPU"' > ~/n7.txt`

## 2026-10-16: nullmoth 2.0.3 (`20f1974`)

- **Nada mudou em `gpu-port/`** (o fonte do NMXGPU): `git diff d96eaca v2.0.3 -- gpu-port` vem vazio.
- As mudanças são no NVIDIA (sleep e wake, segurança, log), no plugin Metal e no app (o driver de teste também
  para Macs só AMD/Intel). As issues #163 e #219 continuam abertas e sem resposta.
- Nenhuma das nossas correções fica obsoleta. O teste 7 segue igual, e o build continua na base `d96eaca`.
- Se o app for atualizado, ele pode recolocar o NMXGPU da release em `/Library/NullMoth/kexts/15/`. Depois de
  atualizar, rodar `sudo bash build/install.sh` de novo. O backup `~/NMXGPU.original` é o da 2.0.2.

## 2026-10-15: teste 7, 0006 (tomar o fb do GOP)

Binário `da43cdbb…`. Resultado: **tela preta, sem o glitch**, sem chegar à área de trabalho, e a luz do Caps Lock
não respondia (Mac congelado). Vídeo no Drive: `VIDEO_BOOT_HACKINTOSH_4.mp4`.

Desta vez houve log (boots das 21:56 e 22:02):
- O i915 inicializa inteiro, como no teste 5. O primeiro modeset passa e aparece
  `Initialized i915 1.6.0 for drmn0 on minor 0`.
- O thread do attach (`0x78b`) para em `intel_didl_outputs: 4 outputs detected` / `disabling PW_B`, às 56,828.
  Nenhuma linha da ponte foi gravada (`drm_client_*`, `NullMoth display: …`). Depois, outro thread ainda faz o
  resume do display (DC9, power wells, PPS, CDCLK) e o `PPS 0 turning VDD off` às 59,35, e o log acaba.
- O log persistido é truncado quando o Mac congela, então a falta das linhas da ponte não prova onde parou.

### Causa da tela preta: o offset 0 do GGTT já era do i915

`init_ggtt` (`gt/intel_ggtt.c`) reserva **GGTT 0..8 KiB** para o error capture (`drm_mm_reserve_node` em 0) e
aponta essas páginas para a página de rascunho (`scratch_range`). Então:
1. O `i915_vma_pin(PIN_OFFSET_FIXED | 0)` da 0006 falha porque a faixa está ocupada (unevictable), e a ponte cai
   no buffer reserva em shmem. Ele é zerado e não está embaixo do console: tela preta, sem glitch.
2. Ninguém segura o resto da faixa do console (8 KiB a 8 MiB do GGTT). As PTEs ainda apontam para a stolen do GOP,
   mas o `drm_mm` acha que a faixa está livre. Qualquer objeto da GPU que o i915 põe ali (ring, contexto, GuC, o
   próprio fb) recebe as escritas do console do `-v`. **Isso pode explicar o congelamento**, aqui e no teste 6.
   Ainda é hipótese.

### Correção: 0007 (drm-kmod) + 0008 (nullmoth)

- **0007**: o `init_ggtt` chama `nmx_i915_reserve_boot_fb(ggtt)` **antes** do error capture, que então vai para
  outro lugar. Isso segura a faixa do GGTT do framebuffer de boot como `I915_COLOR_UNEVICTABLE` desde o início,
  antes de qualquer objeto da GPU. O `cleanup_init_ggtt` solta a faixa.
- **0008**: na ponte, a tomada solta a reserva e fixa o objeto da stolen exatamente ali (`PIN_OFFSET_FIXED`). Se
  falhar, a reserva volta. O buffer reserva (shmem) mantém a faixa segura.
- Mensagens novas: `holding GGTT 0x0+0x7e9000 for the boot framebuffer (1920x1080)` no `init_ggtt`, e depois
  `took over the boot framebuffer: …`.

Build: `NMXGPU 8e8a8f8e7cd7d4ef238c9d87db6d6ae069b916f18c0fda1f71028d15d08ab860`, 15.240.856 B, com 0001 a 0008 e debug.
**Não instalado.**

## Próximo: teste 8 (0001 a 0008, debug)

O mesmo procedimento do teste 7. Se a tomada funcionar, o texto do `-v` continua legível depois que o i915
assume, e a foto mostra as linhas `NullMoth display: …`.

## 2026-10-16: teste 8, 0007 + 0008 (segurar a faixa do console no GGTT)

Binário `8e8a8f8e…`. Resultado: tela preta. O Caps Lock funcionou por um tempo e depois parou. Sem vídeo.

O log mostra (boot das 22:18):
- `NullMoth display: the boot framebuffer 0x4000000001 is not in the GGTT aperture 0x4000000000-0x400fffffff`.
  **O `v_baseAddr` do console vem com flag no bit 0.** O endereço "não alinhado" foi recusado, então nem a
  reserva no `init_ggtt` nem a tomada aconteceram, e a ponte caiu de novo no buffer reserva (shmem, zerado).
- `NMXAccel: NMXGPU drives 8086:a7a8 - starting` às 25,226: o attach **retornou** e a ponte rodou. Mesmo assim,
  as linhas da ponte e `NullMoth GPU: driving` não estão no log. Com o debug do DRM ligado, o macOS descarta parte
  das mensagens do kext, então a falta de uma linha não prova nada.
- 22:18:55: o WindowServer sobe e acha o framebuffer em `GFX0`:
  - CoreDisplay: `Setting offline display 0x00000000 main`, depois
    `IOFBSetDisplayModeAndDepth: Setting mode 0x0 … Failed to obtain mode info from IOFBGetDisplayModeInformation()`.
  - NMXAccel: `serviceMatching(NVRMFramebuffer) returned NULL -- cannot watch for the framebuffer`,
    `initFramebufferResource(index 0): scanout gate CLOSED`, e o NVMTL diz `headless GPU: no device for WindowServer`.
- 22:19:03: o Mac estava **na tela de login** (`loginwindow`, `SecurityAgent`, LED do Caps Lock mudando). O kernel
  repete `IOAccelLegacySurface::set_shape_backing_length_ext … Bad frame buffer index`, mas isso também aparece no
  teste 5, que ficou vivo (683 vezes), e no boot normal. É ruído.
- O log acaba às 22:19:04.374, uns 9 s depois de o WindowServer começar a usar o framebuffer.

### Hipótese do congelamento (testes 6, 7 e 8)

O IOFramebuffer (`nmx_fb.cpp`) publica como VRAM o endereço **da aperture** (BAR2 + offset no GGTT), e o
WindowServer desenha ali com escritas da CPU. No Linux, o i915 não deixa ninguém tocar a aperture com a GPU em
runtime suspend: ele revoga os mapeamentos do GGTT antes de suspender. Aqui nada segura a GPU. O log mostra
power wells ligando e desligando a cada ~10 s, e a ponte só segurava um wakeref durante a criação do buffer. Uma
escrita na aperture com a GPU suspensa pode travar a máquina sem log.
- O teste 5 (sem framebuffer) ficou vivo, e os testes 6, 7 e 8 (com framebuffer) congelaram.
- O README do nullmoth diz que esse caminho de tela "has not been loaded on hardware". Somos os primeiros a rodá-lo.

### Correção: 0009 (nullmoth)

- `nmx_xnu_boot_fb`: o endereço é `(v_baseAddr & ~0xfff) + v_offset`.
- `nmx_i915_fb_create` **mantém o wakeref de runtime PM** enquanto o framebuffer existe e só solta em
  `nmx_i915_fb_destroy`. A mensagem agora termina em `GPU kept awake while it is shown`.
- Build **sem** o debug do DRM (`build-all.sh … nodebug kext`), para as mensagens `NullMoth display: …` não
  serem descartadas.
- Binário: `NMXGPU 775e893affde58277c320dc6933e9525eee61f7b1214264bf40009cc98d34e99`, 15.240.856 B, com 0001 a 0004 e
  0006 a 0009 (o 0005 está aplicado, mas sem efeito sem a flag). **Não instalado.**

### Pesquisa: outros projetos para Intel Xe no macOS

- **WhateverGreen**: só faz patch dos drivers Intel da Apple, que vão até Ice Lake. Ele reconhece Alder/Raptor
  Lake (1.6.9), mas não há framebuffer da Apple para Xe. O Dortania lista os iGPUs de Alder/Raptor Lake como
  não suportados.
- **NootedBlue** (KennNek): drivers da Apple para iGPUs sem suporte, só até Gen9.5/Gen11. Não serve.
- **NootedGreen** (sgiammori e forks): carrega os drivers de **Tiger Lake** da Apple
  (`AppleIntelTGLGraphicsFramebuffer`) fingindo ser TGL. É desenvolvido justamente em Raptor Lake-P, no macOS 14.7.1.
  Ainda é trabalho em andamento:
  - a imagem sai fragmentada (DBUF zerado) e às vezes fica preta ou duplicada;
  - ele trava o WindowServer uns 200 ms depois de o WindowServer ficar ativo;
  - há "reset storms" no acelerador.
  - Caminho diferente do nosso (drivers da Apple em vez do i915). Não dá para combinar, mas confirma que a parte
    difícil é a ligação entre o display e o WindowServer. Vale acompanhar.

## Próximo: teste 9 (0009, sem debug)

O mesmo procedimento. Agora o log deve guardar as linhas `NullMoth display: …`, com `holding GGTT 0x0+0x7e9000`,
`took over the boot framebuffer` e `GPU kept awake`.

## 2026-10-16: teste 9, 0009 (bit de flag e GPU acordada), sem debug

Binário `775e893a…`. Resultado: **tela preta e Mac congelado**.
- **Nenhuma linha de log** desse boot. Entre o fim do boot anterior (00:11) e o boot com `-nvoff` (00:13:42) não há
  nada, como no teste 6. O kext foi instalado às 00:10:50 (`kernelmanagerd`).
- **A marca `nullmoth-gpu-attaching` não está na NVRAM.** O NMXGPU grava essa marca antes do attach e só apaga
  depois de publicar o framebuffer. O boot com `-nvoff` não mexe nela. Então, no teste 9, **o attach retornou e o
  framebuffer foi publicado**, e o congelamento veio depois, na fase do WindowServer, como no teste 8.
- Logo, segurar a GPU acordada (0009) não bastou. A hipótese do runtime PM fica fraca, mas o wakeref fica, porque é
  o certo para escritas na aperture.
- Tela preta: se a tomada tivesse funcionado e o pipe estivesse aceso, o texto do console estaria visível. Ou a
  tomada falhou de novo, ou alguém desligou o pipe depois. No teste 8, o CoreDisplay marcou o display como
  "offline" e falhou ao pedir o modo, e isso pode virar um `kIOPowerAttribute` 0, que apaga as saídas pela ponte.

### 0010: trilha de diagnóstico na NVRAM

Como o log se perde quando o Mac congela, cada etapa é acrescentada à variável `nullmoth-gpu-trail` da NVRAM, com
`sync` na hora. O limite é 40 escritas por boot. A trilha também aparece no log como `NullMoth trail: …`.
- Etapas: `attach`, `hold`/`hold-fail` (`init_ggtt`), `attached`, `publish`, `probe`, `i915-fb`, `take-pin`,
  `took`/`fallback`, `fb-pin`, `iomap`, `commit`, `lit`/`commit-fail`, `published`/`no-fb`.
- Eventos do IOFramebuffer (uma vez cada): `fb-vram` (alguém pediu a VRAM), `fb-setmode`, `ws-on`/`ws-off`
  (WindowServer), e `fb-pwr-on`/`fb-pwr-off` (toda vez).
- Para ler depois de um congelamento, no boot seguinte com `-nvoff` (que não mexe na trilha):
  `nvram nullmoth-gpu-trail`.

Build sem debug: `NMXGPU 06f83e7afefaf995673bbdce6d0a3a61b07ee52eaef845c9c89e97055baaf1f9`, 15.241.120 B. **Não instalado.**

## Próximo: teste 10 (0010)

O mesmo procedimento. Depois do congelamento, bootar com `-nvoff` e ler `nvram nullmoth-gpu-trail`.
