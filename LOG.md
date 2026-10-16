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

## 2026-10-16: teste 10, trilha na NVRAM (0010)

Binário `06f83e7a…`. Resultado: tela preta e Mac congelado, de novo sem nenhuma linha de log.

**A trilha funcionou** (`nvram nullmoth-gpu-trail` no boot seguinte, com `-nvoff`):
```
attach hold attached publish probe i915-fb fallback fb-pin iomap commit lit
```
E `nullmoth-gpu-attaching = 1` continua gravada.
- `hold`: o `init_ggtt` segurou a faixa do console no GGTT (0009 corrigiu o endereço).
- `fallback`: **a tomada do fb do GOP falhou mesmo assim**. O motivo só foi para o log, que se perdeu.
- `commit lit`: **o modeset da ponte deu certo.** O i915 acendeu o painel com o nosso buffer (shmem, zerado,
  por isso a tela preta).
- **O congelamento é entre `lit` e `published`.** Nesse trecho rodam:
  - `drm_client_register`, que chama `bridge_hotplug` na hora (outro probe e commit);
  - `nmx_fb_publish`: `initWith`, `attach`, `IOFramebuffer::start` (com `isConsoleDevice() = true`, o console do
    kernel pode passar para este framebuffer), `registerPowerDriver` e `registerService`.
  - `fb-vram` não aparece, então ninguém pediu a VRAM antes do congelamento.
- Isso também explica o teste 9 de outro jeito: ali a marca tinha sido apagada. Logo, a ordem ou o momento do
  congelamento variam, e o teste 9 deve ter passado desse trecho e congelado depois.

### 0011: trilha mais fina

- Entre `lit` e `published`: `client-reg`, `hotplug` (uma vez), `registered`, `fb-new`, `fb-start`,
  `fb-started` (depois de `IOFramebuffer::start`), `fb-pm` (depois de `registerPowerDriver`) e `fb-reg`.
- Motivo da falha da tomada: `tk-noboot`, `tk-geom`, `tk-nomem`, `tk-pte`, `tk-run`, `tk-obj` (a faixa da
  stolen já é de alguém), `tk-vma`, `tk-range` e `tk-pin`.

Build sem debug: `NMXGPU 157d5e784b03a2ca8932f606631341cc2254da100552d92e51538625b59d97d1`, 15.241.160 B. **Não instalado.**

## Próximo: teste 11 (0011)

O mesmo procedimento. Desligar e ligar o driver no app apaga a marca `nullmoth-gpu-attaching`, que ficou gravada.
Sem isso, o NMXGPU desiste da placa. Depois do congelamento, bootar com `-nvoff` e ler `nvram nullmoth-gpu-trail`.

## 2026-10-16: teste 11, trilha mais fina (0011)

Binário `157d5e78…`. Resultado: tela preta e Mac congelado. Nenhuma linha de log do boot que congelou (o log
pula de 00:33:01, o desligamento do boot anterior, para 00:35:08, o boot com `-nvoff`).

Trilha:
```
attach hold attached publish probe i915-fb tk-obj fallback fb-pin iomap commit lit client-reg hotplug registered
fb-new fb-start fb-started fb-pm fb-reg published
```
E `nullmoth-gpu-attaching` **foi apagada**.
- **O attach inteiro termina.** O registro do cliente DRM (com o hotplug), `IOFramebuffer::start`,
  `registerPowerDriver` e `registerService` passam. O teste 10 congelou nesse trecho, e este passou: o momento
  do congelamento varia, então não é um passo fixo do attach. É algo que roda depois, ou em paralelo.
- Depois de `published`, nada: nem `fb-vram`, nem `fb-setmode`, nem `ws-on`. **O macOS ainda não tinha usado o
  nosso framebuffer** quando congelou.
- `tk-obj`: a tomada do fb do GOP falha porque a faixa da stolen já tem dono. Suspeita: o objeto que o
  `intel_plane_initial` criou para o fb da BIOS. O pin dele falha na nossa faixa segurada, mas a liberação do
  objeto é adiada (worker/RCU), então a faixa ainda está ocupada quando a ponte tenta.

Suspeitos para o congelamento, depois do attach e antes do WindowServer:
- o NMXAccel atendendo Metal no i915 (`NMXAccel: ... 8086:a7a8 ... claiming` aparece nos boots);
- workers do i915 (hotplug, power wells, DC states), com o buffer aceso;
- o console do kernel (`-v`) ainda escrevendo pela aperture em `0x4000000000`.

## Próximo: teste 12

Trilha depois de `published`: um batimento numa variável separada (para saber quanto tempo o Mac vive depois do
attach) e passos no NMXAccel e nos workers do i915. E, para a tomada, esvaziar os objetos liberados
(`i915_gem_drain_freed_objects`) antes de criar o objeto na stolen.

### 0012: batimento depois do attach e a tomada com os objetos liberados reaproveitados

- `nullmoth-gpu-beat` na NVRAM, a cada 2 s por 5 min depois de `published`:
  `t=<s> open=<aberturas do nó DRM> ioctl=<ioctls> in=<ioctls em andamento> cmd=<último ioctl>`. O último
  valor gravado mostra quanto tempo o Mac viveu depois do attach e se o Metal (Mesa/ANV pelo NMXAccel) estava
  dentro do i915 na hora (`in=1`).
- `take_boot_fb` chama `i915_gem_drain_freed_objects` antes de `i915_gem_object_create_region_at`. O
  `initial_plane_vma` cria o mesmo objeto na stolen e o solta quando o pin esbarra na nossa faixa segurada, mas a
  liberação é adiada.

Build sem debug: `NMXGPU 821d791cbe95f6ac754870eaee4b6124f440910e4991eafede018e68d0f1253a`, 15.245.696 B.

## Próximo: teste 12 (0012)

O mesmo procedimento. Depois do congelamento, bootar com `-nvoff` e ler `nvram nullmoth-gpu-trail` e
`nvram nullmoth-gpu-beat`.

## 2026-10-16: teste 12, batimento (0012)

Binário `821d791c…` (conferido em `/Library/Extensions`). Tela preta, Mac congelado, caps lock morto. Nenhum log do
boot (o boot anterior vai até 08:29:52, o com `-nvoff` começa 08:32:27).

- Trilha igual à do teste 11: `… tk-obj fallback … fb-reg published`.
- **`nullmoth-gpu-beat` não existe.** Ele é apagado no começo do attach e o primeiro valor vinha 2 s depois de
  `published`. Logo, **o Mac congela menos de 2 s depois de o IOFramebuffer ser registrado.**
- `tk-obj` continua, mesmo com o drain: não é objeto liberado à espera. O número do erro e a faixa só iam para o log.

### Pesquisa (2026-10-16)

- nullmoth 2.0.3 e 2.0.4 (02:21 UTC): só app e instalador. Nada em `gpu-port/` desde 2026-10-13.
- Issues #119/#131/#219: o `NVRMFBClaim` agora só pega NVIDIA (2.0.0), então o **`IONDRVFramebuffer`
  (`.Display_boot`) fica na Intel (GFX0)**. Confirmado aqui no ioreg. É a tela do firmware do macOS. O NMXGPU não
  mexe nele. No nosso boot ficam dois IOFramebuffers na mesma GPU, os dois "console": o do firmware (aperture
  `0x4000000000`) e o nosso. Suspeito forte para o congelamento logo depois do registro.
- #219 (Tiger Lake, sem MUX): o NMXGPU nem anexa. Sem resposta do autor.
- NootedGreen (fork willyyypatootieee): só docs/CI e uma checagem de BAR0 nula até 2026-10-10. sgiammori parado desde
  maio. Nada novo para nós.

### 0013: trilha de cada chamada do IOFramebuffer, batimento mais cedo, chaves de bisseção

- A primeira chamada de cada método do `NMXGPUFB` entra na trilha: `fb-con`, `fb-ap`, `fb-cur`, `fb-boot`,
  `fb-tim`, `fb-irq`, `fb-ps0/1`, `fb-gac`, `fb-sac`, `fb-ga`, `fb-sa`, `fb-pix`, `fb-gam`, `fb-inf`, `fb-vbl`,
  `fb-modes`, `fb-fmt`, `fb-en`, `fb-cf`, `fb-clut`. Trilha com 480 caracteres e 80 passos.
- `tk-obj<erro>@<offset>+<tamanho>`.
- O batimento começa no início do attach, a cada 0,5 s no primeiro minuto: `ms=… pub=… open=… ioctl=… in=… cmd=…`.
- Boot-args para os próximos testes, sem recompilar:
  - `nmxcon=0`: o nosso fb não é o console;
  - `nmxfb=2`: acende o painel, mas não publica o IOFramebuffer;
  - `nmxfb=0`: sem ponte de tela.

Build sem debug: `NMXGPU 6ebb48545fc99fa5359119bd993d9f3d6e4423dd0a5ffbb2be45fd05d54ac53e`, 15.245.864 B.

## Próximo: teste 13 (0013)

O mesmo procedimento, sem boot-args novos. Ler `nvram nullmoth-gpu-trail` e `nvram nullmoth-gpu-beat`.

## 2026-10-16: teste 13, trilha por método do fb (0013)

Binário `6ebb4854…`. Tela preta, Mac congelado. Trilha:
```
attach hold attached publish probe i915-fb tk-obj-28@0+7e9000 fallback fb-pin iomap commit lit client-reg hotplug
registered fb-new fb-start fb-started
```
`nullmoth-gpu-attaching = 1` (desta vez o attach não terminou). `nullmoth-gpu-beat` de novo não existe.

- **Para dentro de `NMXGPUFB::start`**, entre `IOFramebuffer::start` e `registerPowerDriver`. Nenhum método do fb foi
  chamado (nem `fb-con`). O ponto muda a cada teste (10: antes de `client-reg`; 11 e 12: depois de `published`;
  13: aqui), sempre logo depois de `lit`. Então é algo assíncrono que começa com o modeset, não uma chamada nossa.
- **`tk-obj-28@0+7e9000`: `-ENOSPC` na stolen.** O fb do GOP ocupa a stolen a partir do offset 0 (8 MB), e quando a
  ponte tenta pegar essas páginas, **o i915 já pôs objetos dele ali**. O alocador da stolen é first-fit a partir de
  4 KB, e o i915 cria na stolen, por exemplo, a página de scratch do GT. Enquanto isso, o console do kernel e o
  `IONDRVFramebuffer` do macOS continuam desenhando nessas mesmas páginas pela aperture (a faixa do GGTT que seguramos
  ainda aponta para elas). **O macOS escreve pixels por cima de objetos da GPU.** É o suspeito número 1 do congelamento.
- O batimento não aparece nem com 0,5 s, mesmo com o attach levando segundos. A gravação dele numa variável separada
  não está chegando à NVRAM (motivo ainda desconhecido).

### 0014: segurar as páginas da stolen do fb do GOP

- No `init_ggtt`, além da faixa do GGTT, a ponte reserva no alocador da stolen as páginas que o GGTT do console aponta
  (`shold`; `shold-fail` + donos `st<início>+<tamanho>` se alguém já estiver lá; `shold-none` se não achar). O i915
  passa a alocar os objetos dele fora do fb do GOP.
- A tomada solta essa reserva logo antes de criar o objeto nas mesmas páginas. Se falhar, a trilha lista os donos e a
  reserva volta.
- O batimento agora também vai no fim da própria trilha: ` @<ms desde o início do attach>`.

Build sem debug: `NMXGPU 959844160a2b2645211daa8398766c9e24d3a5e23a14a70f307cf0872f46dd45`, 15.250.256 B.

## Próximo: teste 14 (0014)

O mesmo procedimento. Se a tomada der certo (`took` na trilha), o painel deve mostrar o mesmo conteúdo do console do
macOS, porque o nosso fb passa a ser o próprio fb do GOP.

## 2026-10-16: teste 14, as páginas da stolen seguras (0014) — **a tomada funcionou**

Binário `95984416…`. Trilha:
```
attach hold shold attached publish probe i915-fb take-pin took fb-pin iomap commit lit client-reg hotplug registered
fb-new fb-start fb-started fb-pm fb-reg published
```
- **`shold` e `took`: a ponte pegou o próprio fb do GOP.** O i915 acende o painel com ele, e **a tela mostra o console
  do macOS** (foto do Lukas: texto do boot, `AppleKeyStore`, `apfs_keybag_init`…). Antes era tela preta.
- O attach termina (`published`, marca apagada). O Mac congela depois, no meio das mensagens do boot.
- O batimento nunca aparece, nem o `@ms` no fim da trilha. Então a thread do batimento nunca passou da primeira
  gravação, apesar de o attach durar segundos. Na 0015 ela grava `beat` na trilha logo ao começar, e o `@ms` vai
  antes da variável separada.

### 0015: chaves de teste na NVRAM

`nmx_xnu_knob`: o boot-arg, senão a variável da NVRAM, senão o padrão. Assim o Lukas liga uma chave com um comando
só, sem mexer nos boot-args:
- `sudo nvram nullmoth-gpu-fb=2`: acende o painel com o fb do GOP, mas **não publica** o nosso IOFramebuffer (o
  macOS fica no `IONDRVFramebuffer`, que agora aparece no painel porque é a mesma memória);
- `nullmoth-gpu-fb=0`: sem ponte; `nullmoth-gpu-con=0`: o nosso fb não é console;
- apagar: `sudo nvram -d nullmoth-gpu-fb`.

Build sem debug: `NMXGPU ff044b86b58ef59b4028edd50d015795952e20ec417ded095049cae6a05bf331`, 15.250.296 B.

## Próximo: teste 15 (0015, com `nullmoth-gpu-fb=2`)

Se o Mac chegar ao desktop, quem trava é o nosso IOFramebuffer. Se congelar igual, é o i915 (ou o NMXAccel/Metal).

## 2026-10-16: teste 15, sem o nosso IOFramebuffer (`nullmoth-gpu-fb=2`) — **o Mac não congela**

Binário `ff044b86…`. Trilha e batimento:
```
attach beat hold shold attached publish-nofb probe i915-fb take-pin took fb-pin iomap commit lit client-reg hotplug
registered fb-skip no-fb @91637
nullmoth-gpu-beat: ms=91658 pub=91278 open=0 ioctl=0 in=0 cmd=0x0
```
- **O Mac viveu 91 s depois do attach** (o attach todo leva ~0,4 s) e **ficou log do boot**: o WindowServer subiu às
  09:12:51, o loginwindow também. O log acaba às 09:13:30 com `PMRD: sleep reason Software Sleep`, provavelmente o
  toque no botão de ligar para desligar.
- Então **o congelamento dos testes 10-14 vem do nosso IOFramebuffer** (`NMXGPUFB`). Sem ele, o i915 com o fb do GOP
  roda normal.
- **Tela parada:** a última linha visível na foto (`ALUC:clientDied … pid 229`) é das 09:12:11.9, logo antes do
  attach (09:12:13). Depois do modeset da ponte, o painel ficou no quadro daquele instante, e nem o console nem o
  WindowServer aparecem. Causa provável: **FBC e/ou PSR**. O macOS escreve no buffer pela aperture, com a CPU, e o
  rastreio de frontbuffer do i915 não vê isso. Com FBC, o plano mostra a cópia comprimida. Com PSR, o painel mostra
  a cópia dele.
- `open=0 ioctl=0`: nada abriu o nó DRM, então o Metal (NMXAccel + ANV) não chegou a usar a GPU.
- O WindowServer abriu o `IONDRVFramebuffer` de GFX0 ("Creating FB 1 of 1", "Failed to obtain mode info").

### 0016 (drm-kmod): sem FBC e sem PSR no xnu

`intel_display_params.h`: `enable_fbc` e `enable_psr` passam a ter o padrão 0 com `NMXKPI`.

Build sem debug: `NMXGPU 8ce69ba8d0d879b21b5622c49b4741cad5efbd2818dd293a98d4d5a5deba58dc`, 15.250.296 B.

## Próximo: teste 16 (0016, ainda com `nullmoth-gpu-fb=2`)

Esperado: o painel continua atualizando depois do attach (texto do console e, depois, o desktop do macOS sem
aceleração, pelo `IONDRVFramebuffer`, só que agora com o i915 no controle da tela). Depois disso, voltar ao nosso
IOFramebuffer (`fb=1`) para achar o congelamento.

## 2026-10-16: teste 16, sem FBC e PSR (0016, `fb=2`) — **o painel atualiza e o Mac fica vivo**

Binário `8ce69ba8…`. Trilha igual à do teste 15 com `@141014`. Batimento: `ms=141042 pub=140735 open=0 ioctl=0`.
- **O Mac viveu 141 s** e o caps lock funcionava. Ficou log do boot.
- **O painel continuou atualizando depois do modeset.** O console aparece até 09:41:18 (`NVRM-xnu: boot hold
  RELEASED`, `AppleActuatorDeviceUserClient::start Entered`), 36 s depois de `lit` (09:40:42). O 0016 resolveu a tela
  parada: era FBC/PSR.
- O console para quando o WindowServer sobe (09:41:18), e o desktop não aparece.
  - O WindowServer abre o `IONDRVFramebuffer` de GFX0, como num boot normal.
  - O NVMTL diz `GPU vendor 8086 (Intel, ANV)` / `headless GPU: no device for WindowServer`, porque o NMXAccel está na
    Intel e não há um IOFramebuffer do NMXGPU.
  - SecurityAgent, Installer Progress, loginwindow e CursorUIViewService abrem o ANV (`libvulkan_intel.dylib`), e
    `vkEnumeratePhysicalDevices` dá **0 dispositivos**.
  - Nenhum processo chegou a abrir o nó DRM (`open=0`). O ANV/libdrm não acha a GPU antes mesmo de abrir o nó.

### `tools/probe`: diagnóstico no boot

Um LaunchDaemon (`com.kitsune.nmxprobe`) roda aos 45 s e aos 120 s e grava em `/Users/Shared/nmx-probe.txt`:
- `/dev/dri`;
- o `drmGetDevices2` do libdrm do nullmoth;
- a abertura de `renderD128`/`card0` com `drmGetVersion`;
- uma instância Vulkan direto no ANV, com a contagem de dispositivos;
- IOAccelerator, IOFramebuffer e o WindowServer.

Instalar: `sudo bash tools/probe/install.sh`. Tirar: `... install.sh remove`.

## Próximo: teste 17 (mesmo binário, `fb=2`, com o probe)

Descobrir por que o ANV não vê a Intel. Em paralelo, o congelamento com o nosso IOFramebuffer (`fb=1`) continua aberto.

## 2026-10-16: teste 17, o probe no boot (`fb=2`)

Mesmo binário `8ce69ba8…`. O Mac viveu 117 s (o batimento termina em `@116933`), então só a rodada dos 45 s do probe
foi gravada (`/Users/Shared/nmx-probe.prev.txt`):
```
/dev/dri/renderD128 mode 666 dev 22,268
/dev/dri/card0 mode 600 dev 22,269
drmGetDevices2: 0 device(s)
open /dev/dri/renderD128: Operation not supported by device
open /dev/dri/card0: Operation not supported by device
ANV: vkEnumeratePhysicalDevices -> 0, 0 device(s)
```
Depois do probe, o batimento mostrou `open=2 ioctl=0`: as duas aberturas chegaram ao NMXGPU e falharam lá dentro.

**Causa (bug do nullmoth, `override/src/nmx_linux_cdev.c`):**
- `nmx_cdev_open` monta a `struct file` sem `f_vnode`.
- O `linux_dev_fdopen` do LinuxKPI passa `file->f_vnode` como inode para o `open` do Linux.
- O `drm_stub_open` acha o minor com `iminor(inode)`, que dá `-1` sem vnode. `drm_minor_acquire` devolve `-ENODEV`.
- Ou seja: **nenhuma abertura de nó DRM funciona** no port, então o libdrm não lista a GPU e o ANV acha 0 dispositivos.
  Não há issue sobre isso no upstream.

### 0017: um vnode por nó

- `struct cdev` ganha `nmx_vnode`, criado na primeira abertura (`v_rdev` = o nó, `VCHR`), e `fp->f_vnode` aponta para ele.
- A estrutura muda, então o build é completo (`amd rt i915 xe nodebug kext`).

Build sem debug, completo: `NMXGPU 47133df7d3da0853135d4d6194ed42e76701c0304312be1eca6b0d2f74a6c155`, 15.250.288 B.

## Próximo: teste 18 (0017, `fb=2`, probe instalado)

Esperado no probe: `open … driver i915`, `drmGetDevices2: 1 device(s)` e o ANV com 1 dispositivo (Raptor Lake).

## 2026-10-16: teste 18, um vnode por nó (0017) — **desktop no painel pelo i915**

Binário `47133df7…`, com `fb=2`. **O Mac chegou ao desktop** e o Lukas está usando essa sessão. O i915 controla o
painel, mostrando o fb do GOP, e o macOS desenha nele pelo `IONDRVFramebuffer`. O `system_profiler` mostra a Intel
`0xa7a8` com "Metal: Supported" (NMXAccel), 1920x1080, Main Display, Online.

Probe aos 45 s:
```
open /dev/dri/renderD128: Device not configured
open /dev/dri/card0: Device not configured
drmGetDevices2: 0 device(s); ANV: 0 device(s)
```
- O erro mudou de ENODEV para **ENXIO**. Com o vnode, o `drm_stub_open` agora funciona.
- O `linux_dev_fdopen` termina, como no FreeBSD, com `finit(...)` + `return (ENXIO)`: é o jeito de dizer "instalei
  as minhas fileops" (o `devfs_open` do FreeBSD trata isso como sucesso).
- O `nmx_cdev_open` do port trata isso como erro: a abertura que deu certo volta como "Device not configured", e o
  `drm_file` fica perdido.

### 0018: ENXIO depois do finit é sucesso

`nmx_cdev_open`: com `d_fdopen` e `fp->f_ops` instaladas, ENXIO vira 0. Build `rt kext`:
`NMXGPU 7a16c6adb2a0eb0a76b8ab2cec17d91fbc7cafe62c20e7a1b63448044e479abd`, 15.250.288 B.

## Próximo: teste 19 (0018, `fb=2`, probe)

Esperado: `open … driver i915`, `drmGetDevices2: 1`, ANV com 1 dispositivo. Os apps passam a ter o Metal da Intel. O
WindowServer continua sem ele (`headless GPU`), porque o nosso IOFramebuffer está desligado.

## 2026-10-16: teste 19, ENXIO como sucesso (0018) — desktop de novo; o DRM abre, mas o libdrm não acha a GPU

Binário `7a16c6ad…`, com `fb=2`. Desktop no painel pelo i915, de novo. Batimento `open=2 ioctl=4`: as aberturas
agora funcionam.

Probe aos 45 s, mais testes ao vivo nesta sessão:
```
open /dev/dri/renderD128: driver i915 1.6.0          <- primeira conversa com o i915 vinda do espaço do usuário
drmGetDevices2: 0 device(s); ANV: 0 device(s)
```
Dois bugs a mais no caminho:
1. **libdrm (userland):** os nós do NMXGPU são clones do devfs, e cada consulta ganha um minor novo
   (`renderD128` = 30,256, depois 30,356, depois 30,388). O libdrm do nullmoth para Darwin reconhece o nó e o tipo
   pelo `st_rdev`, e isso nunca bate.
   - Correção: `source-fixes/libdrm-0001-darwin-node-numbers-from-names.patch`. Dentro do libdrm, `stat`/`fstat` de
     `/dev/dri/cardN` e `renderDN` devolvem `makedev(226, N)`, com o nome de um fd vindo de `F_GETPATH`.
   - Testado ao vivo: o `drmGetNodeTypeFromFd` passa de -1 para 2 (render).
   - `tools/libdrm/build.sh`: clona b97cbde, aplica o patch do nullmoth e o nosso, e compila com meson num venv.
   - `tools/libdrm/install.sh`: instala com backup (`~/libdrm.2.dylib.nullmoth`).
   - O NVK não usa o libdrm, então a RTX não é afetada.
2. **`DRM_IOCTL_GET_PCIINFO` (kernel):** responde ENODEV. `dev_is_pci()` olha o `bsddev` do filho DRM, e o
   `is_pci_device()` do port só é verdadeiro para o registro da função PCI.
   - Correção: **0019**, que sobe pelos pais até o registro PCI.
   - Build `rt kext`: `NMXGPU 8f2b4b6f702220b14d546f627ae8d257a8ed7384317adaf4ace5c51a72b62c52`.
   - libdrm `719cb625…`.

## Próximo: teste 20 (0019 + libdrm corrigido, `fb=2`)

Ordem: instalar o kext, desligar/ligar o driver no app (ele recopia o nvmtl), instalar o libdrm e reiniciar. Esperado:
o ANV com 1 dispositivo no probe.

## 2026-10-16: teste 20, 0019 + libdrm corrigido — **o ANV chega à GPU, e o Mac trava**

Kext `8f2b4b6f…`, libdrm `719cb625…`, `fb=2`. Tela preta e Mac travado. Trilha `… fb-skip no-fb @38735`, batimento
`ms=38755 pub=38413 open=2 ioctl=1 in=0 cmd=0x40106415`.
- `0x40106415` = `DRM_IOCTL_GET_PCIINFO` (`_IOR('d', 0x15, 16)`). Ele retornou. **O libdrm achou a GPU e começou a
  conversar com ela.** Nos testes anteriores, ninguém passava do `open`.
- O Mac congelou até 0,5 s depois disso (o batimento é de 0,5 em 0,5 s), aos ~38,7 s do attach, quando os processos
  do macOS (WindowServer, loginwindow…) carregam o ANV. O probe (45 s) não chegou a rodar.
- A rodada não diz qual pedido trava.

### 0020: registro de cada pedido na NVRAM

- `nullmoth-gpu-io`: cada `open` (`o<pid>`), `close` (`c`) e ioctl (`d<nr>` na entrada; `+` ou `-<errno>` na saída) é
  gravado na hora, e uma entrada sem saída é o pedido em andamento. Guarda os 470 caracteres mais novos e para
  depois de 400 tokens.
- `build/build-all.sh` agora para quando um arquivo não compila. Os scripts do nullmoth só imprimem `FAIL`/`failed: N`
  e seguem, e um build saiu sem o `nmx_devfs.o` sem avisar (pego antes de instalar).

Build `rt kext`: `NMXGPU 5b738a6066b4840ad50f25490707eeebbae88a076f0e1ace26c7ad00cd2f19d3`, 15.250.680 B.

## Próximo: teste 21 (0020, mesmo libdrm, `fb=2`)

Depois do congelamento: `nvram nullmoth-gpu-io`.

## 2026-10-16: teste 21, 0020 — **a causa do travamento: o RCU do port**

Kext `5b738a60…`, libdrm `719cb625…`, `fb=2`. Parou na tela de texto (NVRM/IOConsoleUsers/AppleKeyStore), sem desktop.
Batimento `ms=208167 open=56 ioctl=314 in=0 cmd=0xc0186474`: travou aos ~208 s do attach, **fora** de um ioctl.
- `nullmoth-gpu-io` atingiu o limite de 400 tokens antes do fim, mas mostra o ANV inteiro conversando com o i915:
  `GETPARAM`, `QUERY`, `GEM_CONTEXT_{GET,SET}PARAM`, `GET_CAP`, `SYNCOBJ_{CREATE,WAIT,DESTROY}`, `GEM_CREATE`,
  `GEM_CLOSE`, `REG_READ`, `GET_APERTURE`, `GET_TILING`, quase tudo `+`. Falham `GEM_USERPTR` (-22),
  `PRIME_HANDLE_TO_FD` (-102) e alguns `GETPARAM` (-19/-102). 56 aberturas em processos diferentes.
- **O panic do teste 20** (`Kernel-2026-10-16-104230.panic`) mostra o travamento:
  `NMIPI for unresponsive processor: TLB flush timeout`, no SecurityAgent fechando o nó DRM:
  `nmx_close → nmx_cdev_close → linux_file_close → linux_synchronize_rcu`, com o RIP em
  `ck_epoch_synchronize_wait` e as interrupções desligadas (RFLAGS 0x93).

**Causa.** O RCU do LinuxKPI fixa o leitor na CPU (`sched_pin`) e usa o registro de época daquela CPU. No xnu o port
faz `sched_pin` desligando as interrupções, com a contagem por CPU. Um leitor que dorme (todo leitor SRCU pode, e o DRM
usa SRCU; os spinlocks do port também podem bloquear) volta em outra CPU. Aí a seção termina no registro errado, a
primeira CPU fica com as interrupções desligadas para quem rodar nela, e `synchronize_rcu` (a cada `close`) espera para
sempre girando sem interrupções. As outras CPUs não conseguem o TLB shootdown, e o Mac congela.

### 0021: leitores RCU que podem dormir

- `override/src/linux_rcu.c` (substitui o do FreeBSD): o leitor só soma 1 num de dois contadores globais por tipo, sem
  fixar a CPU nem mexer nas interrupções. `synchronize_rcu` espera o contador antigo zerar, troca o índice e espera o
  outro (o período de graça clássico do SRCU), dormindo (`mi_switch`/`pause`) em vez de girar.
- O batimento ganhou `rcu=` (quantos `synchronize_rcu` estão esperando agora).
- `nullmoth-gpu-io` continua seguindo os pedidos depois de 400 tokens; o batimento grava o final quando muda. Assim o
  fim antes de um travamento aparece.
- Upstream: a v2.1.0 do nullmoth (2026-10-16) só acrescenta logs de registro/probe de PCI no NMXGPU. Nada sobre RCU,
  framebuffer ou i915.

Build `rt kext`: `NMXGPU 9a361f0ebdcd581ed88720192eefc4516d228bb27f1648b22ba7b3328ac75b74`, 15.250.856 B.

## Próximo: teste 22 (0021, mesmo libdrm, `fb=2`)

Esperado: sem o congelamento no `close`. Depois: `nvram nullmoth-gpu-beat`, `nvram nullmoth-gpu-io` e o probe.

## 2026-10-16: teste 22, 0021 — **outro travamento, sem panic e longe do `close`**

Kext `9a361f0e…`, libdrm `719cb625…`, `fb=2`. Ficou na tela de texto (sem desktop) e travou.
- Batimento `ms=263427 open=66 ioctl=377 in=0 cmd=0xc0186474 rcu=0`: travou aos ~263 s do attach (teste 21: ~208 s),
  sem ioctl em andamento e **sem `synchronize_rcu` esperando**. Não houve panic desta vez.
- O fim de `nullmoth-gpu-io` é uma sessão inteira do ANV (`… d46 + d74 + c`), mas os clientes Metal só aparecem no
  log até 11:08:30, e o travamento foi às ~11:11:50. O fim do registro pode ter sido minutos antes do travamento.
- O log do macOS termina 34 s antes do travamento (o buffer não foi gravado).
- O WindowServer tenta usar o NMXAccel da Intel e toda superfície falha (`NVTask::allocate: RM refused 8294400 bytes`,
  ~1.100 por minuto): o NMXAccel não tem `nvAccelRmHandles` para a Intel ("no framebuffer has published yet"). Nos
  testes 18 e 19 (desktop) isso deu 2 linhas; nos 15–17 e 21–22 (sem desktop), milhares. É por isso que o desktop não
  aparece; não parece ser a causa do travamento (nos testes 15–17 o Mac ficou vivo com a mesma enxurrada).
- Visto na tela e no log: `MobileSoftwareUpdate`/`Installer Progress` ativos (o macOS parece preparar uma atualização).

### 0022 / 0023: diagnóstico mais fino

- 0022 (nullmoth): batimento a cada 1 s até 10 min (0,5 s no 1º minuto), com `irq=` (interrupções da GPU até agora,
  para ver uma tempestade) e `iot=` (ms do token mais novo do registro). A trilha só é regravada a cada 10 s depois do
  1º minuto.
- 0023 (drm-kmod): eventos de energia da GPU no registro `nullmoth-gpu-io`: `Gu`/`Gp` (GT acorda/estaciona), `Rs`/`Rr`
  (runtime suspend/resume) e `D<estado>` (estado DC do display).

Build `rt i915 kext`: `NMXGPU 2f1e76300c88d4b1e6d673076eb53b3fabdc811d02fe273800f331d4a53baadc`, 15.250.936 B.

## Próximo: teste 23 (0022 + 0023, mesmo libdrm, `fb=2`)

Depois do travamento: `nvram nullmoth-gpu-beat` e `nvram nullmoth-gpu-io`. Comparar `iot` com `ms` (a GPU estava sendo
usada na hora?), `irq` (subiu de repente?) e os últimos `Gu`/`Gp`/`D…`.

## 2026-10-16: teste 23, 0022 + 0023 — **a causa: o WindowServer preso e o watchdog do macOS**

Kext `2f1e7630…`, libdrm `719cb625…`, `fb=2`. Travou de novo sem desktop, com a tela de texto parada (não ficou preta).
Batimento `ms=267714 open=46 ioctl=251 in=0 rcu=0 irq=109 iot=127647`:
- O último pedido à GPU foi aos 127,6 s, e o travamento aos 267,7 s: **a GPU estava parada havia 140 s**.
- `irq=109`: nenhuma tempestade de interrupções. Nenhum `Gu`/`Gp`/`D…` no fim do registro: a GPU não acordou nem
  mudou de estado de energia nesse tempo.
- O travamento vem sempre ~225 s depois de o WindowServer se inscrever no watchdog
  (`enrolling watchdog endpoints in monitoring`): teste 22 às 11:08:05 → ~11:11:50; teste 23 às 13:56:57 → ~14:00:43.
- A thread principal do WindowServer (`[891:d9b]`) passa esse tempo todo num loop: `NVTask::allocate: RM refused 8294400
  bytes` / `IOAccelLegacySurface::surface_flush: failed to prepare buffers`, ~19 por segundo (3.296 no boot). O
  NMXAccel recusa porque `nvAccelRmHandles: no framebuffer has published yet`: com `fb=2` o nosso IOFramebuffer
  não existe, mas o IONDRVFramebuffer do firmware fica na Intel e o IOAccel o junta ao NMXAccel do mesmo PCI.
- O WindowServer não responde ao watchdog, e o `watchdogd` derruba o kernel. O panic não chega a ser salvo (não há
  relatório), e a máquina fica parada.

### 0024: sem NMXAccel na Intel quando não há o nosso IOFramebuffer

- `nmx_kext.cpp`: o `nmxgpu-claimed` (que deixa o NMXAccel subir) só é posto quando o nosso IOFramebuffer é publicado
  (`fb=1`). Com `fb=0`/`fb=2`, a trilha ganha `noaccel` e o WindowServer desenha como nos testes 18 e 19. O DRM
  (`/dev/dri`) continua, e o probe ainda testa o ANV. Chave: `nmxaccel=1`/`nullmoth-gpu-accel=1` força o NMXAccel,
  `nmxaccel=0` nunca.
- Fica sem o Metal da Intel por enquanto. Ele volta quando o `NMXGPUFB` (fb=1) parar de congelar.

Build `rt kext`: `NMXGPU 7fd87526d8ef26cc9db34ae4ebb0f81e489792fb67f761423ebf6716a6a9826f`, 15.250.936 B.

## Próximo: teste 24 (0024, mesmo libdrm, `fb=2`)

Esperado: desktop e sem travar depois de 5 min. Conferir `nvram nullmoth-gpu-trail` (`noaccel`) e o probe (o ANV deve
achar 1 GPU).

## 2026-10-16: teste 24, 0024 — **desktop, sem travar, e o Vulkan da Intel enxerga a GPU**

Kext `7fd87526…`, libdrm `719cb625…`, `fb=2`. **Chegou ao desktop** pelo i915 e passou dos 330 s (batimento
`ms=333134`), bem depois do ponto em que os testes 21–23 travavam. Trilha com `noaccel`; nenhuma linha
`RM refused` neste boot.

Probe (120 s):
```
drmGetDevices2: 1 device(s)
  device 0: bustype 0, nodes mask 0x5, pci 8086:a7a8
open /dev/dri/renderD128: driver i915 1.6.0
ANV: vkEnumeratePhysicalDevices -> 0, 1 device(s)
  0: Intel(R) Graphics (RPL-P), 8086:a7a8, api 1.4
```
O Vulkan da Intel (ANV) cria a instância e enxerga a GPU pelo i915. O Metal da Intel ainda não, porque o NMXAccel
fica desligado enquanto não houver o nosso IOFramebuffer (0024).

**Confirmado:** o travamento dos testes 21–23 era o watchdog do macOS sobre o WindowServer preso no NMXAccel.

### WhateverXe (b00t0x, 2026-10-09)

Plugin do Lilu derivado do WhateverGreen que adapta os drivers **da Apple** (Tiger Lake) para alguns Xe-LP, com o
root patch de um fork do OCLP. Hoje: só **Big Sur 20G1443**, Tiger Lake (`9A40/9A49/9A78`) e Alder Lake-N
(`46D0–46D4`), só telas externas. Raptor Lake, tela interna e Monterey a Tahoe estão no roadmap. **Não serve para
nós agora** (Sequoia, `a7a8`, painel interno). É outro caminho (driver da Apple em vez do i915); vale acompanhar.

## Próximo

Fazer o `NMXGPUFB` (fb=1) funcionar sem congelar (testes 10–14). Com ele, o NMXAccel volta a ter framebuffer e o
WindowServer ganha o Metal da Intel.

## 2026-10-16: caminho novo — **a RTX desenha o desktop no painel da Intel (NMIntelFB)**

O Lukas quer acelerar o desktop do dia a dia. O Metal da Intel pelo i915 ainda está longe (falta o `NMXGPUFB`), mas
o nullmoth já tem um caminho feito para notebooks com o painel na Intel e sem MUX, como este:
- `kexts/NMIntelFB` (desde 2026-10-10, **não vem no pacote**): um IOFramebuffer para o painel interno das Intel
  com display version 12–20 (inclui Raptor Lake). Ele não programa nada no display: lê o plano que o firmware acendeu
  (linear XRGB8888), publica essa superfície pela aperture (BAR2 + offset no GGTT) e mede o refresh pelo contador
  de quadros. Se algo não bate, `start()` desiste e o IONDRVFramebuffer fica com a tela, como hoje.
- Ele se publica como **cabeça 4 do NVAccel** (`IOFBDependentID` do NVRM, `IOFBDependentIndex` 4): o WindowServer
  compõe essa tela **na RTX (Metal 3)**, e o caminho de cópia do NVAccel escreve cada quadro na superfície da Intel.
- O NVAccel instalado já tem isso (`debug.nvaccel_igpu`, contador `debug.nvaccel_iop_ok_h4`). Fica desligado por
  padrão e é ligado em tempo de execução: `debug.nvaccel_igpu=1`, `debug.nvaccelfb=3` e reiniciar o WindowServer.
  Um reboot desfaz.

### Ferramentas (`tools/intelfb/`)

- `build.sh`: compila o NMIntelFB da tag `v2.1.0` do clone do nullmoth, com os nossos patches. Saída em
  `~/nmx-build/intelfb/out/NMIntelFB.kext` (`3b86a1e1…`, 63.456 B). O binário não é versionado (licença).
- `source-fixes/intelfb-0001-off-with-nvoff-or-nmxintel.patch`: o NMIntelFB não sobe com `-nvoff` ("Start once
  without NVIDIA driver" vira a saída de emergência) nem com `nmxintel=1` (aí o i915 cuida da tela).
- `install.sh` [`remove`]: copia para `/Library/Extensions` e refaz a coleção auxiliar com `kmutil create`, como o
  instalador do nullmoth. Confere que NVRM, NVRMFB e NVAccel continuam nela. Backup em
  `~/AuxiliaryKernelExtensions.kc.antes-intelfb`.
- `enable.sh` [`status`]: liga a cópia da RTX para o painel neste boot e mostra o estado.

## Próximo: teste RTX-1

1. App 1401: desligar o driver de teste AMD / Intel (sem `nmxintel=1`).
2. `sudo bash tools/intelfb/install.sh`, reiniciar. Esperado: desktop pelo NMIntelFB (ainda sem aceleração).
3. `sudo bash tools/intelfb/enable.sh` e `sudo killall WindowServer`. Esperado: o desktop composto na RTX.

## 2026-10-16: teste RTX-1 — **o boot trava logo depois da coleção auxiliar carregar**

NMIntelFB `3b86a1e1…`, driver de teste da Intel desligado. O boot parou na tela de texto logo depois de
`KextLog: Loading Aux KC … Collection UUID matches` / `Generation from SMC report as 2`, que é quando o NMIntelFB
entra. Nenhum log salvo (o boot morreu antes de gravar). O boot com "Start once without NVIDIA driver" funcionou:
`NMIntelFB: off: -nvoff` (o patch intelfb-0001 é a saída de emergência).

Sem log, a causa não dá para ver. Suspeitas: o `IOFramebuffer::start` com o `IOFBDependentID` do NVRM sem nenhum
NVRMFB publicado (a RTX não tem tela), ou a leitura dos registradores do display.

### intelfb-0002: trilha na NVRAM, trava de boot e chaves

- `nvram nullmoth-intelfb-trail`: `start mmio mode-<pipe>-<w>x<h>-s<surf> fb-started surf dep vbl power ok`, gravada
  e sincronizada a cada passo.
- Trava de boot: `nullmoth-intelfb-attaching` fica gravada enquanto o `start()` roda. Se o boot seguinte a encontra, o
  NMIntelFB fica de fora e a tela fica com o firmware. Para tentar de novo: `sudo nvram -d nullmoth-intelfb-attaching`.
- Chaves: `sudo nvram nullmoth-intelfb=0` (desliga), `sudo nvram nullmoth-intelfb-dep=0` (framebuffer simples,
  sem virar cabeça 4 do NVAccel).

Build: `NMIntelFB 9dbd6128…`, 64.416 B.

## Próximo: teste RTX-2 (intelfb-0002)

Se travar: boot com "Start once without NVIDIA driver", e `nvram nullmoth-intelfb-trail`.

## 2026-10-16: teste RTX-2 (intelfb-0002) — **o NMIntelFB acha o painel e trava no `registerPowerDriver`**

Trilha: `start mmio mode-A-1920x1080-s0 fb-started surf dep vbl`. A trava de boot ficou gravada
(`nullmoth-intelfb-attaching 1`).
- A leitura do modo do firmware funciona: pipe A, 1920x1080, superfície no offset 0 do GGTT (o fb do GOP).
- O `IOFramebuffer::start` volta, a superfície mapeia e o timer de VBL arma. O travamento é dentro de
  `registerPowerDriver(this, kPowerStates, 2)`.
- Diferença para o NVRMFB, que funciona: ele põe `IOFBDependentID`/`IOFBDependentIndex` **antes** do `super::start`
  (o IOFramebuffer monta o controlador pelo dependent ID no start). O NMIntelFB põe **depois**.

### intelfb-0003

- `IOFBDependentID`/`Index` antes do `IOFramebuffer::start`, como o NVRMFB.
- Trilha em volta do PM: `pm` → `sp1`/`sp0` → `sp-done` (no `setPowerState`) → `power`.
- Chave `sudo nvram nullmoth-intelfb-pm=0`: pula o `registerPowerDriver`.
- `install.sh` agora limpa a trava de boot e a trilha (um build novo ganha outra tentativa).

Build: `NMIntelFB 261eca1c…`.

## Próximo: teste RTX-3

## 2026-10-16: teste RTX-3 (intelfb-0003) — **o `start` termina; o travamento (tela preta) vem depois**

Trilha: `start mmio mode-A-1920x1080-s0 surf dep fb-started vbl pm power sp1 ok sp-done`. Com o dependent ID antes do
`IOFramebuffer::start`, o `registerPowerDriver` passou e o `start()` voltou (`ok`); a trava de boot foi apagada. O
travamento veio depois, com a tela preta, quando o macOS passa a usar o framebuffer novo. Nenhum log do boot chegou
ao disco.

### intelfb-0004 / 0005

- 0004: a primeira chamada de cada método do IOFramebuffer entra na trilha (`ec`, `apr`, `info`, `pix`, `setdm`,
  `tim`, `vbl1`, `scan`…), e a primeira de cada atributo (`sa:`/`ga:`/`sc:`/`gc:`/`ri:` + o código). A trilha cabe
  900 caracteres. A última chamada antes do travamento fica na NVRAM.
- 0005: a trava de boot fica armada até o Mac viver 2 min com o framebuffer (`alive` na trilha). Um travamento antes
  disso deixa o painel para o firmware no boot seguinte.

Build: `NMIntelFB 65901097…`, 70.272 B.

## Próximo: teste RTX-4

## 2026-10-16: teste RTX-4 (intelfb-0004/0005) — **o macOS abre a tela inteira e trava depois do `setInterruptState`**

Tela preta e travamento de novo. A trava de boot ficou armada (`attaching 1`), então o boot seguinte deixou o painel
para o firmware. Trilha, depois do `ok sp-done`:
```
ga:gnps con ec ri:'vbl ' ga:vclt ri:'dci ' ri:dpir ri:hdci ga:crsr gc:lddc gc:cena gc:pcnt gc:flgs gc:hddc gc:asns
gc:enab gc:thrm vbl1 ga:mrdf cdm dmc dms info cf tim pix ga:wsrv sa:sHDC sa:hdcp setdm gc:parm gc:rgsc gc:ggsc
gc:bgsc gc:vblm apr vram sc:rgsc sc:ggsc sc:bgsc sc:vblm sc:flus ga:vrsv is
```
- É o `IOFramebuffer::open` inteiro: interrupções (VBL, connect), conexão, modo, timing, pixel, `setDisplayMode`,
  gamma, abertura e VRAM. O último método novo é `is` (`setInterruptState`, que liga o VBL).
- O VBL roda (`vbl1`). A tela fica preta (o `open` limpa o framebuffer, então as escritas pela aperture chegam) e
  nada mais é desenhado.
- A trilha só guarda a **primeira** chamada de cada método; o que veio depois do `is` não aparece.

### intelfb-0006: batimento

`nvram nullmoth-intelfb-beat` a cada 1 s por 3 min depois do `start`: `ms=… vbl=… calls=… last=…` (a última chamada
de qualquer método, inclusive repetida). Se o batimento parar, o Mac travou; se o `vbl` parar de subir antes, o
travamento é no VBL; o `last` diz a chamada em andamento.

Build: `NMIntelFB bf5091eb…`, 70.800 B.

## Próximo: teste RTX-5

## 2026-10-16: teste RTX-5 (intelfb-0006) — **o VBL trava o grupo de `thread_call` do kernel**

Tela preta e travamento. Batimento: `ms=21450 vbl=2 calls=18 last=ga:mrdf`. A trilha continuou depois disso até o
`is` (igual ao RTX-4).
- O timer de VBL rodou **só 2 vezes**, e o batimento parou aos 21 s, mas o `open` seguiu chamando o framebuffer.
- Os dois eram `thread_call_allocate`, que cai no grupo HIGH do kernel, que tem **uma thread só**. A segunda chamada
  do VBL do IOFramebuffer ficou presa (ela vinha antes do `open` ligar o VBL com `setInterruptState`). Tudo o que usa
  `thread_call` HIGH no kernel ficou parado atrás dela, e o Mac congelou aos poucos. A tela preta é o `open`
  limpando o framebuffer.
- O NVRMFB tem o mesmo padrão; aqui ele trava porque o VBL é chamado durante o `open` do IOFramebuffer.

### intelfb-0007

- O VBL roda numa thread do kernel só dele e só chama o IOFramebuffer quando o VBL está ligado
  (`setInterruptState` com o `ref` do VBL; trilha `vbl-on`/`vbl-off`).
- O batimento também virou thread própria, e aos 2 min marca `alive` e desarma a trava de boot.
- `stop()` acorda a thread do VBL e espera ela sair.

Build: `NMIntelFB 2119d10f…`, 70.816 B.

## Próximo: teste RTX-6

## 2026-10-16: teste RTX-6 (intelfb-0007) — **tela preta; a NVRAM para de registrar antes do fim**

Batimento `ms=18383 vbl=0 calls=1 last=ga:gnps`; trilha até `… ok sp-done ga:gnps`. Mesmo assim a tela ficou preta,
e isso só acontece no `open` do IOFramebuffer, que vem depois. Então as gravações na NVRAM deixam de chegar ao
disco ~18–21 s depois do `start` (no RTX-5 o batimento também parou aos 21 s), e o travamento de verdade vem depois.
A trilha e o batimento não mostram mais nada útil a partir daí.

## Próximo: teste RTX-6b (A/B sem build): `nullmoth-intelfb-dep=0`

Framebuffer simples, sem entrar no grupo de telas do NVRM (`IOFBDependentID`). Se chegar ao desktop, o travamento vem
do grupo do NVRM (sem nenhum NVRMFB publicado); se travar igual, vem do próprio framebuffer.

## 2026-10-16: teste RTX-6b (`nullmoth-intelfb-dep=0`) — **o framebuffer simples trava no `registerPowerDriver`**

Trilha: `start mmio mode-A-1920x1080-s0 surf fb-started vbl pm` (sem `power`). A tela parou no texto do boot (não
ficou preta). É o mesmo travamento do RTX-2, quando o dependent ID entrava depois do `start`: fora do grupo de telas do
NVRM, o `registerPowerDriver` não volta. Dentro do grupo, ele passa, e o travamento vem ~18–21 s depois.

Nas issues do nullmoth, ninguém relata o NMIntelFB num notebook de verdade (ele está fora do pacote). As issues de
notebook com o painel na Intel (#76, #119, #135) ficam no framebuffer do firmware, sem aceleração.

### intelfb-0008: espera antes de assumir o painel

`sudo nvram nullmoth-intelfb-delay=45`: o `start` espera 45 s (trilha `wait`/`go`) antes de assumir o painel. Nesse
tempo o log do boot chega ao disco, e o NVRM/NVAccel (auto-go aos ~20 s) já subiu. Se o travamento for uma corrida com
a pilha da NVIDIA no começo do boot, ele muda; se não, pelo menos o log mostra o que vem depois.

Build: `NMIntelFB e2c417e7…`, 70.832 B.

## Próximo: teste RTX-7 (`dep=1`, `delay=45`)

## 2026-10-16: teste RTX-7 (`delay=45`) — **o NMIntelFB sobe depois da NVIDIA e trava igual**; caminho RTX parado

Trilha: `start wait go mmio mode-A-1920x1080-s0 surf dep fb-started ga:gnps vbl pm power sp1 sp-done ok`. O log do
boot chegou ao disco até ~24 s (`NMIntelFB: waiting 45 s…`, o NVAccel subindo e vigiando o NMIntelFB, `auto-go`).
Depois da espera o `start` terminou, e de novo tela preta e travamento. Então não é corrida com a pilha da NVIDIA.

**Decisão (com o Lukas): parar o caminho RTX e voltar ao Metal da Intel.** O NMIntelFB fica nas ferramentas
(`tools/intelfb`, patches intelfb-0001..0008); ninguém o roda num notebook de verdade, e aqui ele trava de dois jeitos
(no registro de energia fora do grupo do NVRM, e depois do `open` dentro dele).

### O que a investigação do NMIntelFB ensinou para o i915

O `NMXGPUFB` (o IOFramebuffer do NMXGPU, `fb=1`) usa **o mesmo VBL** que travou o NMIntelFB no RTX-5: um
`thread_call_allocate` (grupo HIGH do kernel, uma thread) que chama o IOFramebuffer a 60 Hz desde o `start`, antes do
`open` ligar o VBL. Nos testes 10–14, o Mac congelava < 2 s depois de o `NMXGPUFB` registrar, o mesmo padrão.

### 0025: o VBL do `NMXGPUFB` numa thread própria, só depois de ligado

Igual ao intelfb-0007: thread do kernel própria, chama o IOFramebuffer só com o VBL ligado (`setInterruptState`,
trilha `fb-vbl-on`/`fb-vbl-off`), e o `stop` espera a thread sair.

Build `rt kext`: `NMXGPU 483a5ae5384102f3b134af4dcf2ddb3b095db105cde33d0e8add4a7176a83a66`, 15.250.792 B.

## Próximo: teste 25 (0025, `fb=1`, NMIntelFB removido)

Com `fb=1` o NMXAccel volta a subir (0024 só o desliga sem o nosso framebuffer). Esperado: o `NMXGPUFB` sem
congelar. Depois: `nvram nullmoth-gpu-trail`, `nvram nullmoth-gpu-beat` e o probe.

## 2026-10-16: teste 25 (0025, `fb=1`) — **trava logo depois de `fb-started`; a causa é o controlador do IOFramebuffer**

Duas rodadas, as duas travaram (uma sem reinstalar o libdrm, o que não muda o kernel). Trilha:
```
attach beat hold shold attached publish probe i915-fb take-pin took fb-pin iomap commit lit client-reg hotplug registered
fb-new fb-start fb-started @543
```
Batimento `ms=564 … irq=107`; `nullmoth-gpu-attaching = 1`. Para dentro do `NMXGPUFB::start`, entre
`IOFramebuffer::start` e `registerPowerDriver`, menos de 1 s depois do começo do attach. É o mesmo ponto do teste 13.
Nenhum `fb-vbl-on`: o VBL (0025) não era a causa.

**A causa, lida no IOGraphics da Apple (`IOFramebuffer.cpp`):**
- `IOFramebuffer::start` já faz `PMinit`, `joinPMtree` e `registerService`. Ele só cria o `IOFBController` do
  framebuffer (`copyController(kDepIDCreate)`) se houver `IOFBDependentID`. Sem isso, o controlador só nasce no `open()`.
- Até lá, `__private->controller` é NULL, e quem passa por ele cai: `IOFramebuffer::setPowerState` (`FBGATEGUARD`,
  disparado pelo nosso `registerPowerDriver`) e o `extGetAttribute` do WindowServer.
- Os panics salvos das rodadas do NMIntelFB (14:55, 15:03 e 16:00, `uptime` 34–61 s) são exatamente isso: page fault
  em `CR2 0x170`, `IOFramebuffer::extGetAttribute + 0x111`, task WindowServer. No `kIOFBWSStartAttribute` ele lê
  `controller->fFbs[0]`, que é NULL quando o índice 0 do controlador não abriu (o NMIntelFB é o índice 4 do grupo do NVRM).
- Isso explica também o RTX-2/RTX-6b (NMIntelFB sem dependent ID: trava no `registerPowerDriver`) e por que o RTX-3
  passou do registro de energia (dependent ID antes do `start`, como o NVRMFB faz).
- Com o i915 carregado, o panic não chega a ser salvo; a máquina só para.

**O NMXAccel nunca liga o framebuffer dele no modo AMD/Intel.** Em `kexts/NVRM/accel/nvrm-accel.cpp`, com `NMX_ACCEL`
o `fbm` é `nullptr`, então o `fFB` nunca é preenchido e `nvAccelRmHandles` falha para toda superfície ("RM refused",
o loop do WindowServer dos testes 22/23). Além disso, pelo desenho do nullmoth (`gpu-port/README.md`, `plugin/nvmtl_vk.c`),
o Metal do AMD/Intel é **só para apps**: o WindowServer desenha no framebuffer sem aceleração.

### 0026: dependent ID próprio antes do `start`; NMXAccel desligado por padrão

- Antes do `IOFramebuffer::start`, o `NMXGPUFB` ganha `IOFBDependentID` = `'NMXI'<<32 | id do NMXGPU` e
  `IOFBDependentIndex` = 0 (trilha `fb-dep`). Chave `nullmoth-gpu-fbdep=0` desliga.
- `nullmoth-gpu-accel` passa a ter padrão 0 também com `fb=1` (trilha `noaccel`). Primeiro provar o framebuffer sozinho.

Build `rt kext`: `NMXGPU 838aa8d3b9438482ac7af9a612485a99a957f05b494b93ae8ac269be55519715`, 15.250.880 B.

## Próximo: teste 26 (0026, `fb=1`)

Mesmo procedimento do 25. Esperado: a trilha passar de `fb-started` para `fb-pm fb-reg published`, e o WindowServer
desenhar no nosso framebuffer (sem aceleração). Depois: `nvram nullmoth-gpu-trail`, `nvram nullmoth-gpu-beat` e o probe.

## 2026-10-16: teste 26 (0026) — **DESKTOP PELO NOSSO FRAMEBUFFER (`NMXGPUFB`), SEM TRAVAR**

Binário `838aa8d3…`. Trilha completa, marca de attach apagada:
```
… registered fb-new fb-dep fb-start fb-started fb-pm fb-reg fb-ps1 published fb-con fb-en fb-irq fb-ga fb-gac fb-cur
fb-modes fb-inf fb-cf fb-tim fb-pix fb-sa fb-setmode fb-ap fb-vram fb-sac fb-gam @199443
```
Batimento `ms=207585 open=30 ioctl=130 in=0 rcu=0`: vivo depois de 3,5 min, e o ANV conversando com o i915.
- **O WindowServer abriu o nosso framebuffer, fez `setDisplayMode` e desenha na nossa VRAM.** `system_profiler`: tela
  principal 1920x1080 a **144 Hz** no `NMXGPUFB` (`IOFBDependentID` `0x4E4D5849…`, índice 0).
- O Lukas: chegou no desktop, o mouse ficou rápido (antes lento), animações sem travar, mas com muito glitch: piscadas na
  tela de login, coisas que só aparecem quando o mouse passa por cima.
- **Duas telas no macOS:** a nossa (principal) e o `IONDRVFramebuffer` do firmware (`.Display_boot`) na mesma GPU,
  as duas "online". Suspeito número 1 dos glitches: o WindowServer compõe duas telas sobre o mesmo painel.
- Nenhum `fb-vbl-on`: o WindowServer registrou a interrupção (`fb-irq`), mas nunca ligou o VBL. Suspeito número 2
  (partes que só redesenham com o mouse).
- A causa do travamento era mesmo o controlador do IOFramebuffer (0026).

### 0027: VBL ligado desde o registro; a tela do firmware sai

- **VBL:** no IOGraphics, a interrupção de VBL começa ligada; o `IOFramebuffer` só chama `setInterruptState` para
  estrangular o VBL (`updateVBL`/`deferredVBLDisable`). Com 0025 ela começava desligada, então o WindowServer nunca teve
  VBL. Agora `registerForInterruptType` liga (`fVblOn = true`). Continua na thread própria da 0025 (trilha `fb-vbl`).
- **Tela duplicada:** depois do `registerService` do `NMXGPUFB`, o `IONDRVFramebuffer` do mesmo PCI recebe
  `terminate()` (trilha `ndrv-term`/`ndrv-none`). Chave `nullmoth-gpu-ndrv=0` mantém.

Build `rt kext`: `NMXGPU 3fc8feaf144b0420ab3b1bce13fad2ed313ef5601143b26da5c97a846c8d1576`, 15.250.960 B.

## Próximo: teste 27 (0027)

Mesmo procedimento. Esperado: uma tela só, `fb-vbl` e `ndrv-term` na trilha, menos glitches. Se a tela do firmware
saindo der problema: `sudo nvram nullmoth-gpu-ndrv=0`.

## 2026-10-16: teste 27 (0027) — VBL ok, mas a tela do firmware ficou (`ndrv-none`)

Binário `3fc8feaf…`. Trilha: `… fb-reg fb-ps1 ndrv-none published … fb-tim fb-vbl … fb-vbl-off fb-gam fb-vbl-on @148749`.
- **O VBL agora corre** (`fb-vbl`; o IOFramebuffer estrangula e religa: `fb-vbl-off`/`fb-vbl-on`).
- **`ndrv-none`:** `getMatchingServices("IONDRVFramebuffer")` não achou o `.Display_boot`, mas ele continua em
  `GFX0@2/.Display_boot`, ao lado do `NMXGPU`. Log do WindowServer: `Creating FB 1 of 2` / `FB 2 of 2`,
  `IOFBSetDisplayModeAndDepth` nos dois (`NMXGPUFB` e `.Display_boot`). As duas telas desenham nas **mesmas páginas**
  (o fb do GOP que o i915 assumiu): é isso que pisca e só redesenha onde o mouse passa.
- O Lukas: os mesmos glitches do teste 26.

### 0028: achar a tela do firmware pelos filhos do GFX0

Percorre os filhos do PCI no plano de serviço e dá `terminate()` em todo IOFramebuffer que não seja o nosso. Trilha
`ndrv-c<filhos vistos>` e `ndrv-term`/`ndrv-none`.

Build `rt kext`: `NMXGPU d002eae8f18c119a2a7c7806d6b73dc87b7d2e3e7d721e20cfead5102d484ed5`, 15.251.040 B.

## Próximo: teste 28 (0028)

Mesmo procedimento. Esperado: `ndrv-term`, uma tela só no `system_profiler` e no log do WindowServer (`FB 1 of 1`).

## 2026-10-16: teste 28 (0028) — trava ao remover a tela do firmware

Binário `d002eae8…`. Trilha: `… fb-started fb-pm fb-ps1 fb-reg @548`, batimento `ms=567`, marca de attach ficou.
A tela piscou no meio do boot e travou. Sem `ndrv-c…`: parou no `terminate()` do `.Display_boot`.

**Causa:** `IOFramebuffer::terminate` (IOGraphics) faz `FBGATEGUARD(ctrlgated, this)`. O `IONDRVFramebuffer` do
firmware não tem `IOFBDependentID`, então antes de o WindowServer abri-lo ele não tem controlador: o mesmo NULL do
teste 25, agora do lado dele.

### 0029: tirar a tela do firmware só depois de aberta

O `nmx_fb_publish` só anota os IOFramebuffers do GFX0 que não são o nosso (trilha `ndrv-c<filhos>-<achados>`). Uma
thread própria (`ndrv-wait`) espera, até 10 min, o `IODisplayConnect` aparecer embaixo de cada um (criado no `open()`,
quando já há controlador), espera mais 2 s e dá `terminate()` (`ndrv-term`, `ndrv-gone`; `ndrv-timeout` se nunca abrir).
Para o WindowServer é como desconectar um monitor. Chave `nullmoth-gpu-ndrv=0` mantém a tela.

Build `rt kext`: `NMXGPU a954ffc00b707a97d52b44e44332f1b0c1457ae3749a441e402374caf6e52b94`, 15.251.200 B.

## Próximo: teste 29 (0029)

Mesmo procedimento. Esperado: desktop como no 27, e alguns segundos depois a segunda tela some (a tela pode piscar uma
vez). Trilha com `ndrv-term ndrv-gone`.
