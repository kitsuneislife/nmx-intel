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
