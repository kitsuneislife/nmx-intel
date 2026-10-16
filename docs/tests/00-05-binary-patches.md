# Tests 0–5: getting i915 to take the GPU (binary patches)

> **Summary.** The stock NMXGPU never drove `8086:a7a8`. Five byte patches on the release binary got i915 all the
> way through init (`NullMoth GPU: driving 8086:a7a8`, test 5). The display bridge then failed (`vmap` → -102) and
> the panel went dark (DC6). The GOP framebuffer was **not** inherited: pipe A was already off when i915 took over.
> Patch details: [../knowledge/binary-patches.md](../knowledge/binary-patches.md). Source equivalents:
> `source-fixes/0001–0003`.

Machine: Acer Nitro V15 ANV15-51, i5-13420H, iGPU `8086:a7a8` (panel), RTX 3050 `10de:25ac`. macOS 15.8.1,
nullmoth 2.0.2, `nmxintel=1`.

## Test 0 — stock driver (2026-10-15)

```
NullMoth Intel: stolen memory 0x3e800000, 64 MiB
NullMoth xkpi: no FADT; ACPI power flags read as zero
NullMoth xkpi: vgapci0: no driver attached (0)
NullMoth GPU: no driver took 8086:a7a8
```
Same as nullmoth#163 (ADL-P `46a6`): no Intel had ever worked.
- [measured] `a7a8` is in both the i915 table (entry 324/365) and the xe table (55/127). Both drivers are named
  `drmn`; `linux_pci_find()` returns the first match, which is xe → i915's probe returns ENXIO. → **patch 1**.

## Test 1 — patch 1

Boot froze; next boot NMXGPU parked the GPU (`the last attach of 8086:a7a8 never returned`). From a `-v` video:
```
drm0: [drm] Found alderlake_p/raptorlake_p (device ID a7a8) integrated display version 13.00 stepping E0
drm0: [drm] Finished loading DMC firmware i915/adlp_dmc.bin (v2.20)
drm0: [drm] *ERROR* PPS state mismatch                       (loops forever)
[ENCODER:240:DDI A/PHY A] PPS 0 powered off while attempting AUX CH communication.
```
- [measured] Cause: NMXGPU only registers its own GPU, so `pci_get_class()` never finds the PCH ISA bridge; without
  a PCH, i915 uses PPS at `0x61200` instead of `0xc7200` and reads zeros. → **patch 2**.

## Test 2 — patches 1+2

macOS booted; i915 failed cleanly and released the GPU.
```
*ERROR* [ENCODER:240:DDI A/PHY A] PPS 0 panel status timeout: PP_STATUS: 0x80000008 PP_CONTROL: 0x00000067
*ERROR* Device initialization failed (-102)
```
- PPS reads are real now (`PP_STATUS 0x80000008` = on/idle; `PP_CONTROL 0x67` = target on + backlight).
- `-102` is `EOPNOTSUPP` in xnu numbering: some unimplemented call during display setup. → **patch 3** (DRM debug).

## Test 3 — patches 1–3 (debug)

563 NMXGPU lines. VBT read from the OpRegion (`power_up 2000 … power_cycle 5000`); connectors created (HDMI on
DDI B, DP on TC1/TC2).
- [measured] The PPS timeout is `intel_dp_encoder_flush_work()` — cleanup **after** an error, waiting for the panel
  to turn off while the GOP keeps it on. Harmless.
- [measured] The real error: `intel_dp_tunnel_mgr_init()` always returns -102 in the 2.0.2 binary
  (`movl $0xffffff9a,%eax`): i915 built with DP tunnelling, DRM helpers without (`drm_dp_tunnel_mgr_create` stub
  returns `-EOPNOTSUPP`). No Intel could pass this with that build. → **patch 4**.

## Test 4 — patches 1–4

One boot black screen (reboot needed), the next normal. i915 went much further: VBT from ACPI OpRegion, eDP mode
`1920x1080` from EDID, `nmxfb` created, but `atomic driver check … failed: -102` / `Initial modeset failed, -102`.
- [measured] `intel_dp_tunnel_atomic_check_link()` is also `return -102` (same build defect), run on every
  `atomic_check`. → **patch 5**.
- Black-screen boot only: `DC state mismatch (0x0 -> 0x2)` (DMC found the display in DC5).

## Test 5 — patches 1–5 (installed binary `c55a4432…`)

**Black screen, Mac alive** (Caps Lock LED worked). First full i915 run on this machine:
```
[CRTC:82:pipe A] desired mode 1920x1080 set (0,0)
NullMoth display: the scan-out buffer would not map (102)
NullMoth display: no framebuffer (102)
NullMoth GPU: driving 8086:a7a8
… 2.4 s later: PPS 0 turning VDD off, … Enabling DC6
```
- NMXAccel started serving Metal clients (`newUserClient` types 5/6).
- [measured] Bridge failure (`override/src/nmx_fb_bridge.c`): `drm_client_buffer_vmap` → i915 GEM objects have no
  `.vmap` → -102. The bridge also wants **physically contiguous** memory (designed for AMD VRAM). With no
  framebuffer, nothing holds pipe A and i915 enters DC6 → black.

### Analysis — the GOP framebuffer was not inherited

```
[CRTC:82:pipe A] hw state readout: disabled
[PLANE:32:plane 1A] hw state readout: disabled, pipe A
BIOS left unused DDI_IO_A power well enabled, disabling it
```
No `initial plane`/`BIOS fb`. Option "inherit the GOP fb" ruled out at this point; next: a scan-out buffer in stolen
memory, built from source (→ [06-14-display-bridge.md](06-14-display-bridge.md)).
