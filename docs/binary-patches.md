# Patches binários do NMXGPU (nullmoth 2.0.2)

Binário: `NMXGPU.kext/Contents/MacOS/NMXGPU`, que é o mesmo para o macOS 15 e o 26.

| Estado | SHA-256 |
| --- | --- |
| original 2.0.2 | `33aa04a8681223e56228223491c8205ec3023289a49187d8668c0458eda61c77` |
| + patch 1 | `10538014be72189593351a5d009a5ee39c4114f7e59523a6443137583bc5fa08` |
| + patches 1, 2 | `11c2f5bb66308ac2565b735e71d3d93a2b02dd6361ce468f73f0fa75d2f91555` |
| + patches 1, 2, 3 | `8fda0afbff7a4460be7a083ad674f1423eeec31f805e61c41425483f4f0a8be2` |
| + patches 1, 2, 4 | `bb0fc550557417196b2dad371da0464a343e8c731056b7d88c98d5c65cb28428` |
| + patches 1, 2, 3, 4 | `1378bc322a97e176f807fa7c8d9aa0349fa3b55e50e0818acedef4d1023a8b4e` |
| + patches 1, 2, 4, 5 (`apply.sh`) | `3a87955819b05bd56b3c3a079a4b044afc9e2cc7979c9e491bb4bcc50f06a8e1` |
| + patches 1, 2, 3, 4, 5 (`apply.sh debug`) | `c55a443294ea5810092c0be3712ed13e31ed75da2a30b99966b94fc9479fb759` |

O kext não tem assinatura de código (sem `LC_CODE_SIGNATURE`), então mudar bytes não quebra assinatura
nenhuma. O app 1401 não confere o hash dessa cópia quando liga o driver de teste.

## Patch 1: o xe não pega mais as GPUs do i915

- **Offset** `13212864` (`0xc99cc0`), 4 bytes: `86 80 00 00` → `00 00 00 00`.
- **Onde:** é o primeiro item da tabela de IDs PCI do xe (`xe_pci_driver.id_table`, que começa em `8086:9a60`).
- **O que faz:** o primeiro item passa a ter vendor `0`, então a tabela do xe fica vazia.
- **Por que:**
  - O `linux_pci_find()` do LinuxKPI devolve o **primeiro** driver cuja tabela tem o ID.
  - O xe se registra depois do i915 e, como o `list_add` põe na cabeça da lista, fica na frente.
  - A tabela do xe tem 127 IDs, incluindo `a7a8` e `46a6`. A do i915 tem 365.
  - Então, no `linux_pci_probe()` do i915, `device_get_driver(dev) != &pdrv->bsddriver` e ele devolve `ENXIO`.
  - O xe se registra na classe `pci`, não em `vgapci`, então nunca é oferecido à placa de vídeo.
  - Resultado: `vgapci0: no driver attached (0)`, `no driver took 8086:a7a8`.
- **Efeito colateral:** o xe não pega mais nada (Lunar Lake, Battlemage, Panther Lake). Nesta máquina isso não
  importa. A correção certa, sem esse efeito, é a [source-fixes/0001](../source-fixes/0001-linux_pci-match-only-the-probing-driver.patch).

## Patch 2: assumir o PCH do Alder/Raptor Lake-P

- **Offset** `8378636` (`0x7fd90c`), 21 bytes, no início do ramo "No PCH found." de `intel_detect_pch`
  (a cópia global do i915, `T _intel_detect_pch`, e não a do display do xe).

```
antes:  48 8b 73 08 48 8d 0d ...          movq 0x8(%rbx),%rsi ... jmp __drm_dev_dbg   ("No PCH found.")
depois: c7 83 f0 25 00 00 08 00 00 00     movl $0x8, 0x25f0(%rbx)       pch_type = PCH_ADP
        66 c7 83 f4 25 00 00 80 51        movw $0x5180, 0x25f4(%rbx)    pch_id = 0x5180 (ADP-P)
        eb de                             jmp <epílogo da função>
```

- **Por que:**
  - O `pci_get_class(PCI_CLASS_BRIDGE_ISA << 8)` do LinuxKPI só procura entre os dispositivos que o
    NMXGPU conhece, e ele só conhece a própria GPU.
  - Então o PCH nunca é achado, `HAS_PCH_SPLIT` fica falso e `intel_pps_setup()` usa `PPS_BASE` `0x61200`
    em vez de `PCH_PPS_BASE` `0xc7200`.
  - Ali os registradores são lidos como zero. Daí os erros `PPS 0 powered off while attempting AUX CH
    communication`, `drm_WARN_ON(intel_dp->pps.vdd_wakeref)` e `PPS state mismatch` em loop, e o boot
    travava.
- **Valores:** `PCH_ADP = 8` e `0x5180` foram conferidos no `intel_pch_type()` do próprio binário
  (`0x5180`/`0x5480` → 8). Os offsets `0x25f0`/`0x25f4` (`pch_type`/`pch_id`) vêm das outras escritas da
  mesma função.

## Patch 3 (diagnóstico): ligar o debug do DRM (DRIVER + KMS)

- **Offset** `4387952` (`0x42f470`), 6 bytes, em `__drm_dev_dbg`:
  - antes: `85 15 52 55 93 00` (`testl %edx, __drm_debug(%rip)`)
  - depois: `f7 c2 06 00 00 00` (`testl $0x6, %edx`)
- **O que faz:** as mensagens `drm_dbg()` (categoria DRIVER, `0x2`) e `drm_dbg_kms()` (KMS, `0x4`) passam a
  sair sempre.
- **Por que assim:** `__drm_debug` está no BSS (zero e sem bytes no arquivo), e no macOS não há como passar
  `drm.debug` no boot.
- Não tem efeito nenhum além de log. Pode tirar quando não precisar mais.

## Patch 4: não ter gerenciador de túnel DP não é erro

- **Offset** `7847302` (`0x77bd86`), 5 bytes, em `intel_dp_tunnel_mgr_init`:
  - antes: `b8 9a ff ff ff` (`movl $-102, %eax`)
  - depois: `31 c0 90 90 90` (`xorl %eax, %eax`, seguido de NOPs)
- **Por que:**
  - O i915 foi compilado com `CONFIG_DRM_I915_DP_TUNNEL`, mas os helpers do DRM não (falta
    `CONFIG_DRM_DISPLAY_DP_TUNNEL`).
  - O `drm_dp_tunnel_mgr_create()` vira um stub `ERR_PTR(-EOPNOTSUPP)`, e o compilador reduziu a função
    inteira a "conta os conectores e devolve -102".
  - Como `intel_display_driver_probe_nogem()` chama isso logo depois de `intel_setup_outputs()`, o probe do
    display falhava **sempre**, em qualquer Intel: `Device initialization failed (-102)`.
- **Sem efeito colateral:** com o gerenciador nulo, `drm_dp_tunnel_detect()` também é stub (`-EOPNOTSUPP`), e o
  `intel_dp_detect()` ignora esse erro. Só não há túnel DP (DisplayPort via Thunderbolt/USB4 com alocação de
  banda).

## Patch 5: a checagem de banda dos túneis DP passa

- **Offset** `7846980` (`0x77bc44`), 5 bytes, em `intel_dp_tunnel_atomic_check_link`:
  `b8 9a ff ff ff` → `31 c0 90 90 90`.
- **Por que:**
  - É a mesma falha de build do patch 4. `drm_dp_tunnel_atomic_check_stream_bws()` também é stub
    (`-EOPNOTSUPP`), e a função foi reduzida a `return -102`.
  - Ela roda em todo `atomic_check`, então o primeiro modeset do i915 falhava:
    `atomic driver check ... failed: -102`, seguido de `Initial modeset failed, -102`.
- **Efeito:** sem túnel não há banda de túnel para conferir, e `0` é a resposta certa. As outras funções de
  túnel só devolvem `-102` quando já existe um túnel (`intel_dp->tunnel`), o que não acontece sem gerenciador.
