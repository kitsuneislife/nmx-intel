# Panel brightness

> **Summary.** nullmoth's brightness work (v2.0.3+, app switch "Built-in screen brightness") only drives a panel wired
> to the NVIDIA GPU (MUX laptops): RM reads the backlight through the NBCI `_DSM` and NVRMFB publishes it to macOS.
> Our panel is on the Intel iGPU with no MUX, so the switch cannot help and should stay **off**. Brightness here has to
> come from NMIntelFB: the Intel PCH PWM registers (already mapped through BAR0) plus the same macOS plumbing NVRMFB
> uses. Written 2026-10-17; nothing built yet.

## What nullmoth shipped [measured, source]

- `8a870ec` NVRM answers the NBCI `_DSM` (sub-functions 0, 0x10, 0x14) and `_DOD` on the dGPU's ACPI node, so RM finds
  the panel's backlight table and NVKMS calls `nvkms_register_backlight()`.
- `25b9fed` NVRM keeps that backlight and exposes it as `callPlatformFunction("NVRMBacklight")` (percent get/set via
  `nvKmsGetBacklight`/`nvKmsSetBacklight`).
- `60dc7c8` NVRMFB (+129 lines): for the internal panel, publishes `NVRMBacklightHandler` (an
  `IODisplayParameterHandler` named "backlight") below the framebuffer before `IOFramebuffer::start`, offers
  `brightness`/`linear-brightness` (0–100, floor 5 %), applies changes from a thread call (IODisplay holds the
  framebuffer lock in `doIntegerSet`), and answers `getAppleSense()` with `kGenericLCD`. IOGraphics then makes an
  `AppleBacklightDisplay`, which owns the brightness keys and the System Settings slider.
- `21775ea` the app switch only adds or removes boot-arg `nvrmacpibl=1` (gates the `_DSM` call). The app text: for a
  laptop whose built-in screen is wired to the NVIDIA GPU; off by default because the firmware call stopped some PCs
  at GPU start. `12a273c` (2.3.2) only adds logging.

## Why it does not apply here

- [measured] Our panel is driven by the iGPU (`8086:a7a8`, eDP-1); there is no MUX, so NVKMS has no internal panel
  and no backlight to register. `nvrmacpibl=1` would run the `_DSM` for nothing and carries the documented
  start-up stall risk. Current boot-args have no `nvrmacpibl` (off).
- [measured 2026-10-17] `ioreg`: the panel's display is a plain `AppleDisplay` (no `AppleBacklightDisplay`, no
  `brightness` parameter; `IODisplayParameters` only has gamma/scale entries). NMIntelFB already reports
  `kIOConnectionBuiltIn`; what is missing is the "backlight" handler and `getAppleSense`.

## What the panel uses [inferred]

- i915 on this machine (LOG-pt, test 6) printed `Detected Intel HDR backlight interface version 170`, so the VBT
  backlight type is `INTEL_BACKLIGHT_DISPLAY_DDI` (that probe runs only then, `intel_dp_aux_backlight.c`). i915 uses
  the Intel AUX (nits) interface only when the panel EDID carries HDR static metadata; a 1080p SDR panel normally
  does not, so it falls back to PWM. The log was cut before i915's choice was printed: **[unverified]**.
- PWM on Raptor Lake-P (PCH ≥ CNP) is `cnp_pwm_funcs`: `BXT_BLC_PWM_CTL1` 0xC8250 (bit 31 enable, bit 29
  polarity), `BXT_BLC_PWM_FREQ1` 0xC8254 (period), `BXT_BLC_PWM_DUTY1` 0xC8258 (duty); controller 2 at 0xC8350/54/58
  (`intel_backlight_regs.h`). Brightness = duty / period. The GOP leaves them programmed, so no setup is needed,
  only duty writes.

## Plan (two small tests, NMIntelFB only)

1. **BL-1, read-only.** A `debug.nmintelfb_backlight` sysctl that prints CTL/FREQ/DUTY of both controllers. Confirms
   which controller is live and that duty changes nothing else. Zero risk.
2. **BL-2, control.** Port NVRMFB's handler (`60dc7c8`) into NMIntelFB: level → `DUTY = FREQ * level / 100` (floor
   5 %, respecting polarity), `getAppleSense` → `kGenericLCD`, behind a knob (`nvram nullmoth-intelfb-backlight=0`
   turns it off). Expected: brightness keys (VoodooPS2 already sends them) and the slider work.
   If BL-1 shows PWM disabled or duty ignored, the panel is on the AUX interface and BL-2 needs DPCD writes (0x354)
   instead: a larger job, since NMIntelFB has no AUX channel yet.

## BL-1 answered (RTX-22, 2026-10-17) [measured]
`debug.nmintelfb_regs`: `blc 80000000/00004b00/00004b00 blc2 0/0/0`. PWM controller 1 drives the panel, enabled,
period 19200, duty 19200 (100 %); controller 2 unused. BL-2 writes `BXT_BLC_PWM_DUTY1` (0xC8258) = period × level.

## BL-2 built (2026-10-17)
`intelfb-0020`, NMIntelFB `36afddf1`: the plan above, as written (knob `nullmoth-intelfb-backlight`, trail `bl`).
