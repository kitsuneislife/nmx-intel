# Binary patches on NMXGPU 2.0.2 (legacy, tests 1–5)

> **Summary.** Five byte patches on the release `NMXGPU` made i915 drive the GPU before we could build from source.
> Superseded by `source-fixes/0001–0003`; kept because `tools/binpatch/apply.sh restore` is the way back to the
> original binary. `tools/binpatch/find-offsets.py <binary>` locates the sites in another release (`NOT FOUND` → the
> code changed; reread the function before patching).

Binary `NMXGPU.kext/Contents/MacOS/NMXGPU` (same for macOS 15 and 26). Unsigned (no `LC_CODE_SIGNATURE`); the 1401
app does not hash-check its cached copy.

| State | SHA-256 |
| --- | --- |
| original 2.0.2 | `33aa04a8681223e56228223491c8205ec3023289a49187d8668c0458eda61c77` |
| + 1 | `10538014be72189593351a5d009a5ee39c4114f7e59523a6443137583bc5fa08` |
| + 1, 2 | `11c2f5bb66308ac2565b735e71d3d93a2b02dd6361ce468f73f0fa75d2f91555` |
| + 1, 2, 3 | `8fda0afbff7a4460be7a083ad674f1423eeec31f805e61c41425483f4f0a8be2` |
| + 1, 2, 4 | `bb0fc550557417196b2dad371da0464a343e8c731056b7d88c98d5c65cb28428` |
| + 1, 2, 3, 4 | `1378bc322a97e176f807fa7c8d9aa0349fa3b55e50e0818acedef4d1023a8b4e` |
| + 1, 2, 4, 5 (`apply.sh`) | `3a87955819b05bd56b3c3a079a4b044afc9e2cc7979c9e491bb4bcc50f06a8e1` |
| + 1–5 (`apply.sh debug`) | `c55a443294ea5810092c0be3712ed13e31ed75da2a30b99966b94fc9479fb759` |

## Patch 1 — xe no longer takes i915's GPUs
- Offset `13212864` (`0xc99cc0`), 4 bytes `86 80 00 00` → `00 00 00 00`: first entry of `xe_pci_driver.id_table`
  (starts at `8086:9a60`) gets vendor 0, emptying xe's table.
- Why: `linux_pci_find()` returns the **first** driver whose table has the ID; xe registers after i915 but
  `list_add` puts it at the head; xe's table (127 IDs) includes `a7a8`/`46a6`. In i915's `linux_pci_probe()`,
  `device_get_driver(dev) != &pdrv->bsddriver` → `ENXIO`. xe registers on `pci`, not `vgapci`, so it is never offered
  the GPU either → `no driver took 8086:a7a8`.
- Side effect: xe takes nothing (Lunar Lake, Battlemage, Panther Lake). Proper fix: `source-fixes/0001`.

## Patch 2 — assume the Alder/Raptor Lake-P PCH
- Offset `8378636` (`0x7fd90c`), 21 bytes at the start of the "No PCH found." branch of the global
  `intel_detect_pch` (`T _intel_detect_pch`, not xe's display copy):
```
before: 48 8b 73 08 48 8d 0d ...          movq 0x8(%rbx),%rsi ... jmp __drm_dev_dbg   ("No PCH found.")
after:  c7 83 f0 25 00 00 08 00 00 00     movl $0x8, 0x25f0(%rbx)       pch_type = PCH_ADP
        66 c7 83 f4 25 00 00 80 51        movw $0x5180, 0x25f4(%rbx)    pch_id = 0x5180 (ADP-P)
        eb de                             jmp <function epilogue>
```
- Why: LinuxKPI `pci_get_class(PCI_CLASS_BRIDGE_ISA << 8)` only searches devices NMXGPU knows (its own GPU), so no
  PCH, `HAS_PCH_SPLIT` false, `intel_pps_setup()` uses `PPS_BASE 0x61200` instead of `PCH_PPS_BASE 0xc7200`, reads
  zeros → `PPS state mismatch` loop and a frozen boot.
- Values: `PCH_ADP = 8` and `0x5180` checked against `intel_pch_type()` in the binary; `0x25f0`/`0x25f4` from the
  function's other stores.

## Patch 3 (diagnostic) — DRM debug DRIVER + KMS
- Offset `4387952` (`0x42f470`), 6 bytes in `__drm_dev_dbg`: `85 15 52 55 93 00` (`testl %edx, __drm_debug(%rip)`)
  → `f7 c2 06 00 00 00` (`testl $0x6, %edx`). `__drm_debug` is in BSS and `drm.debug` cannot be passed on macOS.

## Patch 4 — no DP tunnel manager is not an error
- Offset `7847302` (`0x77bd86`), 5 bytes in `intel_dp_tunnel_mgr_init`: `b8 9a ff ff ff` (`movl $-102,%eax`) →
  `31 c0 90 90 90` (`xorl %eax,%eax` + NOPs).
- Why: i915 built with `CONFIG_DRM_I915_DP_TUNNEL`, DRM without `CONFIG_DRM_DISPLAY_DP_TUNNEL`; the stub
  `drm_dp_tunnel_mgr_create()` returns `ERR_PTR(-EOPNOTSUPP)` and the compiler reduced the function to "count
  connectors, return -102". Called right after `intel_setup_outputs()` → every Intel failed with -102.
- No side effect: `drm_dp_tunnel_detect()` is a stub too and `intel_dp_detect()` ignores its error; only DP tunnelling
  (TB/USB4 bandwidth allocation) is lost.

## Patch 5 — the DP tunnel bandwidth check passes
- Offset `7846980` (`0x77bc44`), 5 bytes in `intel_dp_tunnel_atomic_check_link`: `b8 9a ff ff ff` → `31 c0 90 90 90`.
- Same build defect (`drm_dp_tunnel_atomic_check_stream_bws()` stub); runs on every `atomic_check` → `Initial
  modeset failed, -102`. Without a tunnel there is no tunnel bandwidth to check; 0 is correct.
