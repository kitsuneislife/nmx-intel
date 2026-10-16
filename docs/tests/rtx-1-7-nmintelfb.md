# Tests RTX-1 – RTX-7: the RTX composites, the Intel panel shows it (NMIntelFB) — parked

> **Summary.** nullmoth's unshipped `kexts/NMIntelFB` publishes the Intel panel as head 4 of NVAccel so WindowServer
> composites on the RTX (Metal 3) and NVAccel copies frames to the panel. Here it froze two ways: in
> `registerPowerDriver` without a dependent ID, and after `IOFramebuffer::open` with NVRM's dependent ID. Parked after
> RTX-7. **Later root cause (test 25):** IOGraphics needs an `IOFBController`; the saved panics
> (`IOFramebuffer::extGetAttribute + 0x111`, `CR2 0x170`) read `controller->fFbs[0]`, NULL when index 0 of NVRM's
> group is not open. Worth retrying with that knowledge — see [../knowledge/pitfalls.md](../knowledge/pitfalls.md).

Requires the Intel test driver **off** (no `nmxintel=1`). Tools: `tools/intelfb/{build,install,enable}.sh`
(`install.sh` rebuilds the aux kernel collection with `kmutil create`, checks NVRM/NVRMFB/NVAccel stay in it, backs up
to `~/AuxiliaryKernelExtensions.kc.antes-intelfb`). Runtime switch: `debug.nvaccel_igpu=1`, `debug.nvaccelfb=3`,
restart WindowServer (a reboot undoes it).

## NMIntelFB (v2.1.0)
IOFramebuffer for Intel display versions 12–20: reads the plane the firmware lit (linear XRGB8888), publishes it via
the aperture, measures refresh from the frame counter; `IOFBDependentID` of NVRM + `IOFBDependentIndex` 4.
intelfb-0001: off with `-nvoff` (emergency exit) or `nmxintel=1`. Build `3b86a1e1…`.

## RTX-1
Boot froze right after `KextLog: Loading Aux KC … Collection UUID matches`. No log. `-nvoff` boot fine
(`NMIntelFB: off: -nvoff`).
- intelfb-0002: trail `nvram nullmoth-intelfb-trail`; boot guard `nullmoth-intelfb-attaching`; knobs
  `nullmoth-intelfb=0`, `nullmoth-intelfb-dep=0`. `9dbd6128…`.

## RTX-2 — hangs in `registerPowerDriver`
Trail `start mmio mode-A-1920x1080-s0 fb-started surf dep vbl`. Mode read works (pipe A, surface at GGTT 0).
NVRMFB sets the dependent ID **before** `super::start`; NMIntelFB did it after.
- intelfb-0003: dependent ID before `IOFramebuffer::start`; PM trail `pm sp1/sp0 sp-done power`; knob
  `nullmoth-intelfb-pm=0`; `install.sh` clears guard and trail. `261eca1c…`.

## RTX-3 — `start` completes, black screen + freeze later
Trail `… dep fb-started vbl pm power sp1 ok sp-done`.
- intelfb-0004: first call of each method/attribute in the trail (900 chars). intelfb-0005: guard armed until 2 min
  alive (`alive`). `65901097…`.

## RTX-4 — full `IOFramebuffer::open`, freeze after `setInterruptState`
```
ga:gnps con ec ri:'vbl ' ga:vclt ri:'dci ' ri:dpir ri:hdci ga:crsr gc:lddc gc:cena gc:pcnt gc:flgs gc:hddc gc:asns
gc:enab gc:thrm vbl1 ga:mrdf cdm dmc dms info cf tim pix ga:wsrv sa:sHDC sa:hdcp setdm gc:parm gc:rgsc gc:ggsc
gc:bgsc gc:vblm apr vram sc:rgsc sc:ggsc sc:bgsc sc:vblm sc:flus ga:vrsv is
```
- intelfb-0006: beat `nvram nullmoth-intelfb-beat` (`ms vbl calls last`). `bf5091eb…`.

## RTX-5 — the VBL blocks the kernel's HIGH thread_call group
Beat `ms=21450 vbl=2 calls=18 last=ga:mrdf`.
- [measured] VBL and beat were `thread_call_allocate` → kernel HIGH group, **one thread**. The second VBL callback
  blocked inside IOFramebuffer (it came before `open` enabled VBL); every HIGH thread_call stalled → gradual freeze.
- intelfb-0007: VBL and beat on own kernel threads; VBL only after `setInterruptState`; `stop()` waits. `2119d10f…`.

## RTX-6 — black screen; NVRAM stops recording
Beat `ms=18383 vbl=0 calls=1`; trail to `ok sp-done ga:gnps`, yet the screen went black (only `open` does that) →
NVRAM writes stop landing ~18–21 s after `start`.

## RTX-6b — `nullmoth-intelfb-dep=0`
Trail `… fb-started vbl pm` (no `power`): plain framebuffer hangs in `registerPowerDriver` again.
No nullmoth issue reports NMIntelFB on a real laptop; Intel-panel laptops (#76, #119, #135) stay on the firmware fb.
- intelfb-0008: `nullmoth-intelfb-delay=<s>` wait before taking the panel. `e2c417e7…`.

## RTX-7 — `delay=45`: same freeze after the NVIDIA stack is up
Trail `start wait go mmio … dep fb-started ga:gnps vbl pm power sp1 sp-done ok`; log reached disk to ~24 s. Not a
race with NVIDIA. **Decision (with Lukas): park the RTX path, return to Intel.** The same HIGH-group VBL existed in
`NMXGPUFB` → 0025.
