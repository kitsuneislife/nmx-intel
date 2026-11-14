# GPU frequency and power-state management (RPS, waitboost, RC6) on Gen12 Xe-LP without GuC SLPC, and how macOS / WhateverXe does it

Scope: Raptor Lake-P Iris Xe (8086:a7a8, 48 EU), macOS Sequoia, Apple's TGL accelerator via WhateverXe 0.8.2, `-disablegfxfirmware` (no GuC, so no SLPC and no GuC RC).
Linux references are pinned to v6.14, the base of the nullmoth drm-kmod port.

## Q1. Linux i915 host RPS and RC6 on Gen12: registers, fields and sequences

### Takeaway
With GuC off, i915 controls Gen11/Gen12 frequency through one software request register, `GEN6_RPNSWREQ` (0xA008). It writes the target ratio to bits [31:23] in 16.67 MHz units. When busy-stats are available, a 1 to 20 ms software busyness timer decides when to step up or down. On top of that, waitboost jumps straight to `boost_freq` (RP0 by default) whenever a client blocks on a request. RC6 is entered by hardware using thresholds the host programs. The actual frequency is read from `GEN12_RPSTAT1` (0x1381B4) CAGF bits [19:11]; on Gen12 that register reads 0 while the GT is in RC6.

### Cited findings

**Frequency request (RPNSWREQ)**
- `GEN6_RPNSWREQ` = MMIO 0xA008. `GEN9_FREQUENCY(x) = x << 23` is used for every GRAPHICS_VER >= 9, so it covers Gen11 and Gen12. Bit 31 is `GEN6_TURBO_DISABLE`, and bit 13 is `GEN12_MEDIA_FREQ_RATIO`. `gen6_rps_set()` writes only `GEN9_FREQUENCY(val)` on Gen9+. — [intel_gt_regs.h v6.14](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_gt_regs.h); [intel_rps.c v6.14](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)
- Units: on Gen9+, `intel_gpu_freq(val) = val * 50 / 3` (GT_FREQUENCY_MULTIPLIER 50, GEN9_FREQ_SCALER 3), so the request value is in 16.67 MHz steps. For example, 1400 MHz is val 84, written as 0x2A000000. — [intel_rps.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)
- The requested frequency can be read back from RPNSWREQ >> 23 (`intel_rps_get_req`, `GEN9_SW_REQ_UNSLICE_RATIO_SHIFT` 23). — [intel_rps.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)

**Hardware limits (RP0, RP1, RPn)**
- `GEN6_RP_STATE_CAP` = MCHBAR mirror 0x140000 + 0x5998 = MMIO **0x145998**. Fields are RP0 [7:0], RP1 [15:8] and RPn [23:16]. `GEN6_RP_STATE_LIMITS` = 0x145994. `GEN6_GT_PERF_STATUS` = 0x145948. `GEN10_FREQ_INFO_REC` = 0x145EF0. — [intel_mchbar_regs.h v6.14](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/intel_mchbar_regs.h)
- On GRAPHICS_VER >= 11, RP_STATE_CAP values are in **50 MHz units**, and i915 multiplies them by 3 to get 16.67 MHz hardware units. On Gen10+, RP1 does not come from RP_STATE_CAP[15:8]; it comes from the RPE field of `GEN10_FREQ_INFO_REC`. The efficient frequency (RPe) is then refined from pcode `HSW_PCODE_DYNAMIC_DUTY_CYCLE_CONTROL` ((ddcc >> 8) & 0xff × 3). The MTL-style `MTL_RP_STATE_CAP` applies only to IP 12.70 and later, so not to TGL, ADL or RPL. — [intel_rps.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)
- Initial policy in `intel_rps_init()`:
  - `max_freq_softlimit = RP0` and `min_freq_softlimit = RPn`.
  - Up threshold is 95 % and down threshold is 85 %.
  - `boost_freq = max_freq` (RP0) and `idle_freq = min_freq`.
  - `cur_freq = efficient_freq` ("start in the middle").
  - Overclocking via `GEN6_READ_OC_PARAMS` is only for Gen6, IVB and HSW.
  — [intel_rps.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)

**Up/down evaluation (RP_CONTROL, thresholds, EI)**
- `GEN6_RP_CONTROL` = 0xA024. Bit 7 is `RP_ENABLE`. Bits [10:9] are the media mode (`HW_NORMAL_MODE` = 2 << 9). Bit 8 is `MEDIA_IS_GFX`. `UP_BUSY_AVG` = 2 << 3 and `DOWN_IDLE_AVG` = 2 << 0. `MEDIA_TURBO` (bit 11) is set only for ver <= 9. — [intel_gt_regs.h](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_gt_regs.h); [intel_rps.c rps_set_power](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)
- Related registers:

  | Register | Offset |
  |---|---|
  | `GEN6_RP_DOWN_TIMEOUT` | 0xA010 |
  | `GEN6_RP_INTERRUPT_LIMITS` | 0xA014 |
  | `GEN6_RP_UP_THRESHOLD` | 0xA02C |
  | `GEN6_RP_DOWN_THRESHOLD` | 0xA030 |
  | `GEN6_RP_CUR_UP_EI` / `CUR_UP` / `PREV_UP` | 0xA050 / 0xA054 / 0xA058 |
  | `GEN6_RP_CUR_DOWN_EI` / `CUR_DOWN` / `PREV_DOWN` | 0xA05C / 0xA060 / 0xA064 |
  | `GEN6_RP_UP_EI` | 0xA068 |
  | `GEN6_RP_DOWN_EI` | 0xA06C |
  | `GEN6_RP_IDLE_HYSTERSIS` | 0xA070 |
  | `GEN6_PMINTRMSK` | 0xA168 |

  — [intel_gt_regs.h](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_gt_regs.h)
- EI presets in `rps_set_power`, in nominal 1.28 µs units:

  | Mode | ei_up | ei_down |
  |---|---|---|
  | LOW_POWER | 16000 | 32000 |
  | BETWEEN | 13000 | 32000 |
  | HIGH_POWER | 10000 | 32000 |

  So the up-evaluation interval is about 10 to 16 ms and the down interval about 32 ms. The threshold registers are written as `ei * threshold% * 10` ns, converted with `intel_gt_ns_to_pm_interval`. `intel_rps_mark_interactive()` (set by display flips) forces HIGH_POWER. — [intel_rps.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)
- `GEN6_RP_INTERRUPT_LIMITS` on Gen9+ is `max_softlimit << 23`, plus `min_softlimit << 14` only when already at the minimum. A comment explains why: just after RC6 exit there is a tiny window where the hardware runs at the minimum clock before selecting the requested frequency. — [intel_rps.c rps_limits](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)
- `gen9_rps_enable()` (used for ver >= 9, including Gen11 and Gen12) writes `GEN6_RP_IDLE_HYSTERSIS = 0xA`, sets `pm_events` to UP/DOWN_THRESHOLD, and resets to `min_freq`. `GEN6_RC_VIDEO_FREQ` is written only on ver 9. — [intel_rps.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)
- On current i915, if every engine supports busy-stats, RPS uses a **software timer** (`rps_timer`) instead of the hardware EI interrupts. The interval starts at 1 ms, doubles up to `BUSY_MAX_EI` = 20 ms, and resets to 1 ms on every adjustment. Hardware interrupts are the fallback only for Gen6 to Gen11. — [intel_rps.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)
- How `rps_work` steps the frequency:
  - Each up event multiplies the step by 2: +1, +2, +4 bins of 16.67 MHz.
  - Each down event steps down the same way.
  - A DOWN_TIMEOUT drops to RPe, then to min.
  - On park (GT idle), the frequency is set to `idle_freq` (RPn) under media forcewake, so pcode commits the voltage drop. `cur_freq` for the next unpark is lowered by an adjustment, but never below RPe.
  - On unpark, `cur_freq` (clamped to softlimits) is restored immediately.
  — [intel_rps.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)

**Waitboost**
- `intel_rps_boost(rq)` runs when a client waits on an unsignalled request. It is skipped for contexts flagged `CONTEXT_LOW_LATENCY`. It counts one waiter per request via `I915_FENCE_FLAG_BOOST`. If `cur_freq < boost_freq`, it queues `rps_work`, which sets `new_freq = boost_freq` and allows up to `max_freq` (above the softlimit) while waiters exist. — [intel_rps.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)

**Actual frequency (CAGF)**
- `GEN12_RPSTAT1` = **0x1381B4**: `GEN12_CAGF_MASK` = bits [19:11] and `GEN12_VOLTAGE_MASK` = bits [10:0]. The i915 comment says that on Gen12+ this register needs no forcewake and "will return 0 freq when GT is in RC6". The older `GEN6_RPSTAT1` (0xA01C) with `GEN9_CAGF_MASK` [31:23] is for Gen9 to Gen11. — [intel_gt_regs.h](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_gt_regs.h); [intel_rps.c __read_cagf](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)

**RC6 (gen11_rc6_enable, used for Gen11 and Gen12)**
- The host-controlled RC6 setup, used when GuC RC is not in use:

  | Register | Value | Meaning |
  |---|---|---|
  | `GEN6_RC6_WAKE_RATE_LIMIT` (0xA09C) | 54 << 16 \| 85 | |
  | `GEN10_MEDIA_WAKE_RATE_LIMIT` (0xA0A0) | 150 | |
  | `GEN6_RC_EVALUATION_INTERVAL` (0xA0A8) | 125000 | |
  | `GEN6_RC_IDLE_HYSTERSIS` (0xA0AC) | 25 | 25 × 1.28 µs ≈ 32 µs |
  | `RING_MAX_IDLE(engine)` | 10 | |
  | `GUC_MAX_IDLE_COUNT` | 0xA | |
  | `GEN6_RC_SLEEP` (0xA0B0) | 0 | |
  | `GEN6_RC6_THRESHOLD` (0xA0B8) | 50000 | |
  | `GEN9_MEDIA_PG_IDLE_HYSTERESIS` (0xA0C4) | 60 | |
  | `GEN9_RENDER_PG_IDLE_HYSTERESIS` (0xA0C8) | 60 | |
  | `GEN9_PG_ENABLE` (0xA210) | render \| media \| media-sampler PG, plus VDBOX HCP/MFX PG on Gen12 | |

  Then `GEN6_RC_CONTROL` (0xA090) = `HW_ENABLE` (bit 31) | `RC6_ENABLE` (bit 18) | `EI_MODE(1)` (bit 27). — [intel_rc6.c v6.14](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rc6.c); [intel_gt_regs.h](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_gt_regs.h)
- The i915 comment on the 60-unit (~77 µs) power-gating hysteresis says it was chosen instead of Bspec's 25. If the hysteresis is shorter than the CPU interrupt-service plus ELSP-resubmit latency (under 10 µs on Icelake), "the hardware will automatically gate the power well and we will then incur the wake up cost on top of the service latency". — [intel_rc6.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rc6.c)
- RC6 disable sequence: under forcewake, write `GEN9_PG_ENABLE = 0`, `GEN6_RC_CONTROL = 0`, `GEN6_RC_STATE = 0`. On park in manual mode, write `RC_CONTROL = RC6_ENABLE` (hardware timers off) and `RC_STATE` target (4 << 16). — [intel_rc6.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rc6.c)
- RC6 residency counter: `GEN6_GT_GFX_RC6` = 0x138108. Current RC state: `GEN6_GT_CORE_STATUS` = 0x138060, with RCn in bits [2:0] (0 = RC0, 3 = RC6). — [intel_gt_regs.h](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_gt_regs.h)
- Tuning precedent: Intel's i915 patches exposing the RPS up/down thresholds in sysfs were reported (by a Google engineer) to give up to about 10 to 15 % better gaming performance. — [Phoronix](https://phoronix.com/news/Intel-RPS-Threshold-Linux-Tune)

### Inferences
- With Linux defaults, the worst-case ramp from RPe to RP0 under the software timer takes several 1 to 20 ms evaluations: 1+2+4+8+16 bins ≈ 31 bins ≈ 520 MHz in 5 steps. A small job that arrives just after park would therefore run at RPe or lower for a few ms unless it is waitboosted. This is a plausible source of a few ms, not 10 to 20 ms, of extra latency per job. [inferred]
- Bounded estimate of RC6 exit cost [inferred]: one RC6 entry needs about 32 µs of idle (RC idle hysteresis), and power gating about 77 µs. An RC6 exit is a forcewake-style wake, and WhateverGreen uses 50 ms only as the ack timeout, not the typical cost. On this basis RC6 exit should cost tens to low hundreds of µs, not 10 ms. No Gen12 number for RC6 exit latency was found.

### Gaps
- Typical RC6 exit latency on Gen12 is not documented in the sources read; Bspec 52698 and the PRM Vol 2c were not opened.
- The exact semantics of the two halves of `RC6_WAKE_RATE_LIMIT` (54 and 85) were not found.

## Q2. How Apple's macOS Intel driver manages GPU frequency, and what WhateverGreen and WhateverXe patch

### Takeaway
In Apple's Intel drivers, the framebuffer side handles the frequency request through `pmNotifyWrapper` / `AppleIntelFramebufferController::pmNotify`, which returns an RPNSWREQ-encoded value. In the TGL framebuffer that WhateverXe uses on non-TGL hardware, `pmNotify` is an "Unsupported" stub. With GuC off, WhateverXe therefore answers it itself: it requests max(requested, boost), clamped to [RPn, RP0]. This hook is active on this machine and requests 1400 MHz (RP0) about 390 times per second. WhateverGreen's `igfxrpsc` (always request RP0 at exec-list submit) exists only for SKL (as KBL), KBL, CFL and CML.

### Cited findings

**WhateverGreen `igfxrpsc` (older generations only)**
- `igfxrpsc=1` (or the `rps-control` property on IGPU) enables "RPS control patch (improves IGPU performance)". — [WhateverGreen README](https://github.com/acidanthera/WhateverGreen/blob/master/README.md)
- How the patch works:
  - It routes `__ZL15pmNotifyWrapperjjPyPj` in the framebuffer kext. The wrapper calls the original and then always returns `*freq = (3 << 23) * RP0`, with RP0 read from `GEN6_RP_STATE_CAP` (0x145998) & 0xFF.
  - It also NOPs a `cmp byte [rcx],0; jnz` in `IGHardwareCommandStreamer5::submitExecList`, which normally does RPS control only for RCS streamers, so that every streamer triggers it.
  - The source comment says power management stays sane "due to force wake clears".
  — [kern_igfx_pm.cpp](https://github.com/acidanthera/WhateverGreen/blob/master/WhateverGreen/kern_igfx_pm.cpp)
- `modRPSControlPatch.available` is set only for Skylake (when forced to the KBL kexts), Kaby Lake, Coffee Lake and Comet Lake. Ice Lake and later are not listed. — [kern_igfx.cpp](https://github.com/acidanthera/WhateverGreen/blob/master/WhateverGreen/kern_igfx.cpp)

**WhateverXe host RPS (TGL and ADL-N paths)**
- WhateverXe "r285": "the exact donor pmNotify is an Unsupported stub. Fulfill only the non-GuC frequency query".
  - `tglHostPMNotify` hooks `__ZN31AppleIntelFramebufferController8pmNotifyEjjPyPj`. It first checks that the stub bytes match, a stub returning 0xE00002C7.
  - On `event == 1` it reads RP_STATE_CAP at BAR+0x145998 and takes `f = max(controller+0xEC8 (requested), controller+0xECC (boost))`, both in 50 MHz units.
  - It clamps f to [RPn = caps>>16 & 0xFF, RP0 = caps & 0xFF] and refuses if RP0 > 85.
  - It returns `(f*3) << 23`, the RPNSWREQ encoding.
  - It is installed only with `-disablegfxfirmware` and can be turned off with `-wex-no-host-rps`.
  — [WhateverXe kern_xe.cpp](https://github.com/b00t0x/WhateverXe/blob/HEAD/WhateverXe/kern_xe.cpp)
- On the AlderLakeN entry, which RPL-P goes through here, the same hook is installed as "N97HostRPS", with registry flags `N97HostRPSRequested` and `N97HostRPSReady`. — [WhateverXe kern_xe.cpp](https://github.com/b00t0x/WhateverXe/blob/HEAD/WhateverXe/kern_xe.cpp)
- WhateverXe publishes `N97GTPowerSample` (schema 1285) on the framebuffer. Its slots are:

  | Slot | Content |
  |---|---|
  | q[3] | `GEN12_RPSTAT1` 0x1381B4 |
  | q[4] | RC6 counter 0x138108 |
  | q[5] | 0x145960 |
  | q[6] | GT_PERF_STATUS 0x145948 |
  | q[7] / q[8] | Apple requested / boost |
  | q[12] / q[13] | callback calls / answers |
  | q[14] | last encoded request |
  | q[15] | RP_STATE_CAP |

  The comment says these "GT mirrors require no forcewake". The sampler is capped at **512 reads per boot**. — [WhateverXe kern_xe.cpp](https://github.com/b00t0x/WhateverXe/blob/HEAD/WhateverXe/kern_xe.cpp)

**Measured on this machine** (2026-11-13, about 380 s after boot, WhateverXe 0.8.2, boot-args include `-disablegfxfirmware`) [measured]
- `N97HostRPSRequested = Yes` and `N97HostRPSReady = Yes`. — local `ioreg -l` read
- `N97GTPowerSample` decoded over 9 reads in about 30 s on the desktop:
  - RP_STATE_CAP = 0x0002061C: RP0 = 28 (1400 MHz), field[15:8] = 6, RPn = 2 (100 MHz).
  - Apple requested = boost = 28 (1400 MHz).
  - Last encoded request = 0x2A000000 (84 × 16.67 = 1400 MHz).
  - Calls = answers: about 390 per second (188611 to 192458 over about 10 s).
  - RPSTAT1 = 0x04221095: CAGF = 66 (1100 MHz), voltage field 0x095.
  - RC6 counter = 27422158 (≈ 35.1 s at 1.28 µs per tick).
  - RPSTAT1, GT_PERF_STATUS and the RC6 counter were **identical in every sample**.
  — local `ioreg -l` read

**AGPM (AppleGraphicsPowerManagement)**
- The AGPM Info.plist needs a per-Mac-model, per-GPU entry. `IGPU` is the integrated-GPU key and `GFX0` the discrete one. Entries have a `control-id` (16 for IGPU in the MBP5,1 example) and `Heuristic` dictionaries (ID, IdleInterval, threshold arrays). These sources cover old Macs and NVIDIA GPUs, not Gen11 or Gen12. — [osxlatitude AGPM tuning](https://osxlatitude.com/topic/7807-nvidia-gpu-performance-tuning-with-agpm/); [osxlatitude E6400 AGPM](https://osxlatitude.com/forums/topic/8336-dell-latitude-e6400-agpm-editing-yosemite/)

### Inferences
- Apple's own policy, AGPM or the accelerator writing controller+0xEC8 and +0xECC, already asks for RP0 continuously here, and WhateverXe forwards that request. **A low requested clock is therefore not the cause** of the 10 to 15 ms p90. Waitboost-style tuning or an `igfxrpsc`-style patch would change nothing, because the request is already pinned at maximum. [inferred from measured values]
- CAGF (1100 MHz) is below the request (1400 MHz). The FMA estimate agrees: 48 EU × 16 FP32 FLOP per clock = 768 FLOP/clk, and 711 GFLOPS / 768 ≈ 0.93 GHz. Pcode is therefore granting less than RP0. Likely limits are package power (PL1/PL2 shared with the CPU cores) or thermal/current limits, or a `GEN6_RP_STATE_LIMITS` (0x145994) cap. This would cost about 20 to 30 % throughput, not 10 ms queueing. [inferred]
- Two explanations fit the identical RPSTAT1 and RC6-counter values across 30 s on an active desktop [unverified]:
  - (a) The GT never left RC0, so RC6 is not being entered at all and RC6 exit latency cannot add delay.
  - (b) The mirror reads are stale or latched, so they are not trustworthy as a live gauge.

  One fact favours (a): i915 says RPSTAT1 reads 0 in RC6, and a non-zero, constant value with a frozen RC6 counter is consistent with permanent RC0. The ~35 s of accumulated RC6 would then come from early boot, before the accelerator started.
- If (a) holds, neither frequency ramp nor RC6 exit explains the 10 to 20 ms wait. The remaining explanation is scheduling: small jobs queue behind long batches from the visible app on the same engine. This matches the earlier project finding "slowness is gpu queueing behind other apps". [inferred]

### Gaps
- Not checked: which AGPM IGPU entry, if any, applies to the SMBIOS model in use, and whether Apple's TGL accelerator (`IGAccelerator` / `IntelAccelerator`) has its own frequency heuristics ("BusyEnhancement" and similar) for TGL. No public documentation of the TGL AGPM keys was found.
- The meaning of controller offsets 0xEC8, 0xECC and 0xB68, and of the `event` values other than 1, comes only from WhateverXe code comments, not from Apple documentation.
- No source covers how `pmNotify` is triggered (per submit or timer); the measured rate of about 390 per second suggests per-submission or tick-driven calls.

## Q3. Tools to read the current GPU frequency on macOS

### Takeaway
On this hackintosh, the practical gauge is WhateverXe's `N97GTPowerSample` IORegistry property: CAGF = (RPSTAT1 >> 11) & 0x1FF, × 50/3 MHz. It is capped at 512 reads per boot. Intel Power Gadget is discontinued, and nothing found shows `powermetrics` reporting Intel iGPU frequency.

### Cited findings
- Intel Power Gadget is discontinued with no further updates; Intel recommends uninstalling it in favour of Intel PCM. On Mac it showed the graphics-core frequency. — [Intel Power Gadget page](https://intel.com/content/www/us/en/developer/articles/tool/power-gadget.html); [Intel community thread](https://community.intel.com/t5/Software-Archive/Intel-Power-Gadget-for-Mac/m-p/1147813)
- `powermetrics --samplers gpu_power` is documented for Apple Silicon. No source confirmed Intel iGPU frequency output. — [agputop](https://github.com/hbasria/agputop)
- WhateverXe's `N97GTPowerSample` / `TGLPowerSample` serializers read RPSTAT1, the RC6 counter and RP_STATE_CAP with no forcewake, up to 512 reads per boot. — [WhateverXe kern_xe.cpp](https://github.com/b00t0x/WhateverXe/blob/HEAD/WhateverXe/kern_xe.cpp)

### Inferences
- The 512-read cap means a long-running poller will stop returning data. A kext-side sampler, for example one tied to submit and complete in the latency test, would be better for correlating CAGF and RC state with each slow job. It should read 0x1381B4, 0x138060 and 0x138108, which need no forcewake on Gen12 according to the i915 comment. [inferred]

### Gaps
- Not tested: whether Intel PCM runs on this macOS, and whether `powermetrics` on an Intel hackintosh prints iGPU frequency.

## Q4. Evidence that RPS control improved UI smoothness on hackintosh

### Takeaway
The only evidence found is WhateverGreen's own one-line claim, "improves IGPU performance", for Skylake to Comet Lake. No benchmarks, and nothing for Ice Lake, Tiger Lake or Raptor Lake.

### Cited findings
- WhateverGreen README: `igfxrpsc=1` "improves IGPU performance", with no numbers. — [WhateverGreen README](https://github.com/acidanthera/WhateverGreen/blob/master/README.md)
- Linux analogue: tuning the RPS thresholds gave up to about 10 to 15 % in games. — [Phoronix](https://phoronix.com/news/Intel-RPS-Threshold-Linux-Tune)

### Inferences
- On this machine the request is already pinned at RP0 by WhateverXe's host RPS. A further frequency-forcing experiment (one variable) would only test the pcode-granted clock, not the request. The levers available to a kext are:
  - `GEN6_RC_CONTROL = 0` (disable RC6) and `GEN9_PG_ENABLE = 0` (disable power gating). Both should be write-and-restore knobs taken under forcewake.
  - Comparing `-wex-no-host-rps` A/B against latency p90, to confirm whether the frequency request matters at all.

  [inferred]

### Gaps
- No hackintosh forum benchmarks of `igfxrpsc` or of any TGL/ADL RPS patch were found.
- An early Linux TGL bug discussion said RPS was disabled on TGL to reduce lockups. Only search snippets were seen, so the specific freedesktop issue was not verified.
