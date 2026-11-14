# Same-band FIFO queueing stalls Iris Xe jobs

> **Summary.** The 10-15 ms p90 Iris Xe submit wait is almost certainly a scheduling problem: equal-priority Metal work
> queues behind a busy client on the one render engine. Clock, RC6, CPU and vblank are each ruled out or close to it.
> No public report matches the symptom. The cheapest discriminating test needs no rebuild: elevate the probe's PID with
> Apple's `debug.intel.schedPriElevatePID` sysctl. Ranked test plan at the end.

**Bottom line.** The evidence points at **scheduling, not power**. Apple's host scheduler (`GraphicsSchedulerSelect=5`,
"Host Preemptive") does preempt, but by **priority band**, so a tiny job from a normal app waits in FIFO order behind
whatever a same-band client (Claude's renderer and GPU process, and WindowServer compositing their frames) has already
queued on the render engine. On top of that, WhateverXe turns off 3D object-level preemption, so a long draw cannot be
interrupted mid-object. The other suspects fail against the measurements. The GPU frequency request is already pinned at
RP0 (1400 MHz) by WhateverXe's host RPS hook. The probe's wait is the same with 0, 8 or 16 ms idle gaps, so it is not a
wake-up cost. Twelve CPU burners make it *better* (p99 ~8 ms). 144 Hz leaves the max at ~19 ms, so it is not a vblank
wait. Nobody in the WhateverXe tracker, the forums or the Linux world has reported this exact symptom. The closest
mechanism in Linux is i915's execlists rule that "equal priority never preempts", which is why i915 adds a 1 ms
timeslice. Apple's driver has no timeslice key that we could find. The plan below therefore starts with zero-rebuild
probes: elevate one PID, read the frozen-looking clock sampler under load, and run a per-PID queue trace. Only then does
it move to Development-dict and preemption-granularity knobs in our WhateverXe fork. A kext-side timeslicer comes last,
as the expensive option.

## What we measured: queueing appears only when a busy client is on screen

The probe is `tools/hybrid/xe-lattest.m`, which submits 300 tiny compute jobs to the Iris Xe. On a clean desktop (only
Terminal open), `kernel->gpu` start latency is **p50 0.01-0.06 ms, p99 0.12-0.24 ms, max 0.5-1.0 ms** [measured]. With
the Claude desktop app on screen it jumps to **p90 10.6-15.8 ms, max 17-22 ms**, while GPU execution of each job stays
around **0.005 ms** [measured] ([wex-1](../docs/tests/wex-1.md)). The driver's own submit path is therefore fast; the
time goes to waiting in front of the engine [inferred].

Three measured controls narrow the cause. First, with **12 `yes` CPU burners** the busy run *improves* to p99 7.4-8.4 ms
and max 9 ms [measured], so CPU starvation of the submit or interrupt path is not the cause. The likely reason is that
the starved Electron renderer draws less, so less GPU work is queued [inferred]. Second, at **144 Hz** the busy run gives
p90 8.5-15 ms and max 17.8-19.6 ms, the same as at 60 Hz [measured]. That rejects the "job waits for a vblank/flip"
hypothesis, because the max does not follow the frame time [inferred]. Third, moving Claude's GPU process
(`Claude Helper --type=gpu-process`) to the RTX left the metric unchanged: **p90 10.5-15.8 ms** [measured]
([wex-1](../docs/tests/wex-1.md)). The GPU process still held 4 Intel user clients, because Chromium opens every Metal
device [measured]. In any case, WindowServer still composites that window on the Iris Xe, since the panel hangs off the
iGPU, and frames rendered on the RTX must still be copied and composited there [inferred]. Lukas reported that the
desktop *felt* better with Claude on the RTX. That is plausible if the renderer's own Intel draws went away while the
composite load stayed, but the probe cannot see it, so the gain is [unverified].

## Frequency and RC6 are already pinned and do not explain 10 ms

Waitboost or forcing RP0 is the usual hackintosh fix for "slow iGPU", but here the request is already at the maximum.
WhateverXe 0.8.2 hooks `AppleIntelFramebufferController::pmNotify`, an "Unsupported" stub in the TGL donor, and on
event 1 answers `max(requested, boost)` clamped to [RPn, RP0], encoded as `(f*3)<<23` for RPNSWREQ. The hook is installed
only with `-disablegfxfirmware` and can be disabled with `-wex-no-host-rps`
([WhateverXe kern_xe.cpp](https://github.com/b00t0x/WhateverXe/blob/main/WhateverXe/kern_xe.cpp)). On this machine
`N97HostRPSReady = Yes`, and the `N97GTPowerSample` property shows Apple requesting **RP0 = 28 (1400 MHz)**, with the last
encoded request `0x2A000000` and about **390 answered calls per second** [measured, local `ioreg`]. WhateverGreen's older
`igfxrpsc` patch, which always returns RP0 and removes an RCS-only gate in `submitExecList`, exists only for SKL-CML, and
its only claimed benefit is "improves IGPU performance", with no numbers
([WhateverGreen kern_igfx_pm.cpp](https://github.com/acidanthera/WhateverGreen/blob/master/WhateverGreen/kern_igfx_pm.cpp);
[WhateverGreen README](https://github.com/acidanthera/WhateverGreen/blob/master/README.md)).

Two loose ends remain. The granted clock (CAGF from `GEN12_RPSTAT1` 0x1381B4 bits [19:11]) read **1100 MHz**, below the
1400 MHz request, and the FMA throughput test (~711 GFLOPS on 48 EUs) agrees at ~0.93 GHz [measured/inferred]
([i915 intel_gt_regs.h](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_gt_regs.h)). That
suggests a package power or current limit, which costs throughput (~20-30 %), not 10 ms of queueing [inferred]. More
oddly, RPSTAT1, GT_PERF_STATUS and the RC6 residency counter were **identical across 9 samples over 30 s** [measured].
Either the GT never enters RC6 on this setup (i915 says RPSTAT1 reads 0 in RC6, so a constant non-zero value fits
permanent RC0), or the mirrors are latched and untrustworthy [unverified]. If the GT never leaves RC0, RC6 exit cannot add
delay. Even if it does, i915's numbers bound the cost at tens to low hundreds of µs: ~32 µs RC idle hysteresis and ~77 µs
power-gating hysteresis, as set in `gen11_rc6_enable` ([i915 intel_rc6.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rc6.c))
[inferred]. Linux RPS ramping costs a few ms at worst, not 10-20 ms
([i915 intel_rps.c](https://github.com/torvalds/linux/blob/v6.14/drivers/gpu/drm/i915/gt/intel_rps.c)) [inferred]. This
corrects a line in `wex-1.md` ("WhateverXe publishes no clock telemetry"): it does, but the sampler is capped at **512
reads per boot**, so it has to be read during a busy run, not polled continuously
([WhateverXe kern_xe.cpp](https://github.com/b00t0x/WhateverXe/blob/HEAD/WhateverXe/kern_xe.cpp)).

The one frequency-side precedent worth noting is WhateverXe #57: on ADL-P under CPU load, "PCODE holds the GT at 100 MHz
with PL1 as the limit reason" ([Issue #57](https://github.com/b00t0x/WhateverXe/issues/57)). Our CPU-burner run got
faster, not slower, so PL1 clamping is not the current problem [inferred], but it is cheap to rule out with a sample.

## Apple's host scheduler preempts by priority band, not by time

The Apple TGL accelerator on this machine runs `GraphicsSchedulerSelect=5`, with `EnablePreemption=1`,
`PreemptionDelayIntervalUS=160`, `PreemptionTimerIntervalUS=2000`, `SchedThrottleCapMS=100`, `MetalCoalesce=1` and
`CsbProcModeSelect=0` in the live `Development` dict [measured,
[local Info.plist](file:///Library/Extensions/AppleIntelTGLGraphics.kext/Contents/Info.plist)]. WhateverGreen documents 5
as "Host Preemptive (as of 10.15)", the mode WEG selects when GuC is off
([WhateverGreen kern_igfx.cpp](https://github.com/acidanthera/WhateverGreen/blob/master/WhateverGreen/kern_igfx.cpp)), and
WhateverXe forces `GraphicsSchedulerSelect=5` and `MultiForceWakeSelect=1` itself before the parent starts
([WhateverXe kern_xe.cpp](https://github.com/b00t0x/WhateverXe/blob/main/WhateverXe/kern_xe.cpp)). The binary also
carries `-disablegfxpreemption`, "Constraining preemption delay interval in the range [%u,%u] us", "Scheduler Tail
Coalescing Enabled" and a `DisableTailCoalescing` key [measured,
[local binary](file:///Library/Extensions/AppleIntelTGLGraphics.kext/Contents/MacOS/AppleIntelTGLGraphics)].
"Host scheduler means no preemption" is therefore wrong for Apple's driver. A 160 µs delay and a 2 ms timer are far below
the stalls we see, so a missing preemption feature alone does not explain them [inferred].

What decides *who* preempts whom is a band system exposed through live sysctls: `debug.intel.schedPriCredits{High,
NormalHigh,Normal,Low} = -1`, `schedPriPreemption = 1`, `schedPriElevatePID = -1`, `schedEnableThrottleOverride = 0`, and
`schedThrottle*PriByVal = -1`. The binary also contains a "Priority change requested, but is not entitled!" path that
names WindowServer [measured, local sysctl and binary]. Four credit-weighted bands with priority preemption match the
i915 model closely, and there the rule is explicit: `need_preempt()` refuses to preempt "at the same priority level: the
task that is running should remain running to preserve FIFO ordering"
([i915 intel_execlists_submission.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/intel_execlists_submission.c)).
Execlist hardware has no notion of priority or time. It runs ELSP[0] to completion unless the driver writes a new pair
and the running context reaches an arbitration point. i915 bounds equal-priority waits only with a **1 ms timeslice
timer** (`DRM_I915_TIMESLICE_DURATION=1`, "Minimalistic timeslicing", 2019)
([i915 Kconfig.profile](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/Kconfig.profile);
[commit 8ee36e0](https://lab.nexedi.com/kirr/linux/-/commit/8ee36e048c98d4015804a23f884be2576f778a93)). No `timeslice`
or `quantum` string exists in the TGL binary [measured]. The best-fitting model is therefore that xe-lattest and Claude
sit in the same Normal band, so the probe waits FIFO behind every command buffer the busy client has already queued, and
one or two frame-sized batches add up to 10-20 ms [inferred]. On a real Mac, GuC firmware would apply its own execution
quantum next to the hardware. xe/GuC expose `timeslice_duration_us` for exactly this
([intel-xe sysfs patch](https://lists.freedesktop.org/archives/intel-xe/2023-July/008805.html)) [inferred].

WhateverXe adds a second factor. On TGL it clears 3D **object-level preemption** in `CS_DEBUG_MODE1` (0x20EC) and
`CS_CHICKEN1` (0x2580) as a "TGL B0 object-preemption topology corruption" workaround (r135), and clears
`FF_SLICE_CS_CHICKEN1` (0x20E0) bit 14 so contexts cannot re-enable it (r144). The registry flags
`TGLObjectPreemptionDisabledReady` / `TGLObjectPreemptionGlobalReady` report this
([WhateverXe kern_xe.cpp](https://github.com/b00t0x/WhateverXe/blob/main/WhateverXe/kern_xe.cpp)). Linux leaves 3D
object-level preemption *enabled* on Gen11/Gen12 and only limits GPGPU to thread-group level
(`WaDisableGPGPUMidThreadPreemption:gen12`)
([i915 intel_workarounds.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/intel_workarounds.c)).
Even when Apple's scheduler does decide to preempt, a long WindowServer or Chromium draw therefore runs to the end of the
draw [inferred]. Whether the B0 erratum applies to a Raptor Lake-P stepping is unverified; that risk sets the rank of the
test that touches it.

GuC is not a way out. Apple's TGL GuC loader needs an ME-checked hash ("Graphics Firmware Load failed boot hash check!")
[measured, local binary]. WhateverXe still requires `-disablegfxfirmware`. Removing it on TGL gives "GuC load STATUS
0x830000EC" and breaks Metal ([WhateverXe #48](https://github.com/b00t0x/WhateverXe/issues/48)). Even on Coffee Lake,
Apple GuC worked "on very few laptops" and was valued for power, not latency
([acidanthera/bugtracker#748](https://github.com/acidanthera/bugtracker/issues/748)).

## Nobody has reported this, but adjacent bugs point at Chromium and IGScheduler5

All 124 WhateverXe issues (opened 2026-11-02..13) were scanned. Every "laggy UI" report was a machine without
acceleration (#14, #67, #122), and the reports of a smooth desktop (#64, #69, #115) never measured submit latency or ran
an Electron app ([#115](https://github.com/b00t0x/WhateverXe/issues/115);
[#64](https://github.com/b00t0x/WhateverXe/issues/64)). Several issues are adjacent. #44 and #40 show
`IGAccelEventMachine::eventTimeout` → `IGScheduler5::checkForProgress` stalls under load on Xe
([#44](https://github.com/b00t0x/WhateverXe/issues/44)). #47 is a 72 KB-per-command-buffer leak that kills Claude
Desktop's `CrGpuMain` every 20-39 min ([#47](https://github.com/b00t0x/WhateverXe/issues/47)). #72 describes a 2D/3D
blit-path race tied to Chromium/Graphite index buffers ([#72](https://github.com/b00t0x/WhateverXe/issues/72)). #109 is a
fork (`SaqibAlMalik/WhateverXe` `tgl-stability`) with `-wex-tgl-no-posh` that reports WindowServer growing ~200 MB/min
([#109](https://github.com/b00t0x/WhateverXe/issues/109)). The forums offer nothing measured: Dortania lists Xe iGPUs as
unsupported, and the few "not smooth" Tiger Lake threads have no content
([Dortania GPU Buyers Guide](https://dortania.github.io/GPU-Buyers-Guide/modern-gpus/intel-gpu.html)). WhateverXe already
ships an `-wex-adln-qtrace` hook on `IGAccelCommandQueue::processCommandBuffer` plus `getOwningTaskPid`
([WhateverXe kern_xe.cpp](https://github.com/b00t0x/WhateverXe/blob/main/WhateverXe/kern_xe.cpp)). Because RPL-P runs
through the AlderLakeN entry here, that trace is the fastest way to see *which* PID's buffers sit in front of the probe
[inferred].

## Conclusion

The question has shifted from "why is the Iris Xe slow" to "why does Apple's host scheduler let one same-band client
monopolise the render engine". That reframing makes most community folklore (force RP0, disable RC6, try GuC) low-value
here, and makes a single sysctl the highest-information experiment. If elevating the probe's PID collapses its wait
below 1 ms, the band/credit model is confirmed, and the fix space becomes priority policy, such as raising WindowServer
and focused apps or tuning credits, rather than hardware. If it does not, the object-preemption workaround and the
missing timeslice are next. Writing a kext timeslicer would then mean re-implementing i915's execlists policy inside a
binary-patched Apple scheduler, a large and risky job worth starting only after the cheap knobs have failed.

A practical note for every row below: run `xe-lattest` three times busy (Claude visible, same window) and once clean, and
compare p50/p90/max to the baselines (busy p90 10.6-15.8 ms, max ~20 ms; clean p50 0.01-0.06 ms). Sysctl writes are
runtime-only and vanish on reboot. Boot-arg knobs need a reboot but no rebuild. Every new fork knob defaults to *off*.

## Ranked test plan

| Rank | Test id | Single change | How to undo | Confirms / refutes |
|---|---|---|---|---|
| 1 | LAT-1 | Read-only: dump `sysctl debug.intel` and `ioreg` `N97GTPowerSample` (3-4 reads, within the 512 cap) **during** a busy `xe-lattest` run, and once clean. | Nothing to undo. | CAGF and RC6 counter that change between reads mean the sampler is live. If CAGF stays ~1100 MHz busy and clean, frequency is excluded for good. CAGF near 100 MHz or a PL1-type limit while busy reopens the power hypothesis (#57). |
| 2 | LAT-2 | `sudo sysctl debug.intel.schedPriElevatePID=<xe-lattest pid>` (start the probe paused, set the PID, then run). Lukas OK first: runtime driver write. | `sudo sysctl debug.intel.schedPriElevatePID=-1`, or reboot. | Busy p90 under 1-2 ms **confirms** same-band FIFO queueing. No change refutes band priority as the lever, or shows the sysctl is read-only/ignored (check with a read-back). |
| 3 | LAT-3 | Boot-arg `-wex-adln-qtrace` (existing WhateverXe knob) for one busy run, to log per-PID command buffers. | Remove the boot-arg and reboot. | Shows who fills the queue (WindowServer vs Claude GPU process vs Renderer) and buffer counts per frame. Confirms the queueing model if the probe's buffers land behind bursts from one PID. No trace output means the hook does not install on RPL-P (record as a pitfall). |
| 4 | LAT-4 | Boot-arg `-disablegfxpreemption` (Apple's own knob). | Remove the boot-arg and reboot. | Worse latency means preemption is active and helping, so tuning it (LAT-5/6) is worthwhile. Unchanged means preemption never fires for our case, so skip to LAT-7/8. |
| 5 | LAT-5 | New fork knob `wexdev=Key:value` that writes one `Development` key before parent start (same path as `GraphicsSchedulerSelect`). First key: `PreemptionDelayIntervalUS` at its lower clamp. | Remove `wexdev` and reboot; default build unchanged. | A lower p90 confirms the delay matters. Unchanged refutes it. The boot log line "Constraining preemption delay ..." shows the clamp. |
| 6 | LAT-6 | Same `wexdev` knob, one key per run: `SchedThrottleCapMS` lower (100 to e.g. 10), then `DisableTailCoalescing=1`, then `MetalCoalesce=0`. | Remove `wexdev` and reboot. | Any single key that cuts the busy max below ~10 ms names the mechanism. All unchanged leaves only granularity and timeslicing. |
| 7 | LAT-7 | Read-only fork diagnostic `-wex-preemptdiag`: sample `CS_CHICKEN1` 0x2580, `CS_DEBUG_MODE1` 0x20EC, `FF_SLICE_CS_CHICKEN1` 0x20E0 and RCS `EXECLIST_STATUS` (0x2234/0x2238) while busy. | Remove the boot-arg and reboot. | Shows the real preemption granularity per context and whether ELSP[1] is populated (a waiting second context). It decides whether LAT-8 can help. |
| 8 | LAT-8 | Fork knob `-wex-objpreempt` that skips WhateverXe's r135/r144 object-preemption disable (risk: B0 corruption/hang; RPL-P stepping unverified). | Remove the boot-arg and reboot. Recovery: OpenCore Space → `-nvoff` entry, or the normal boot config. | A lower max (long draws now preemptible) confirms granularity as a cause. Corruption or hangs refute its safety on RPL-P; record as a pitfall and drop it. |
| 9 | LAT-9 | Boot-arg `-wex-no-host-rps` (existing knob). | Remove the boot-arg and reboot. | Expected unchanged (request already RP0). Worse confirms the RPS hook helps throughput. Equal closes the frequency branch. |
| 10 | LAT-10 | Fork knob `-wex-rc6off`: `GEN6_RC_CONTROL=0`, `GEN9_PG_ENABLE=0` under forcewake at accelerator start. | Remove the boot-arg and reboot. | Expected unchanged (RC6 counter frozen, exit cost well under 1 ms). A drop would refute the RC0 reading of LAT-1. |
| 11 | LAT-11 | Fork knob `wextslice=<ms>`: kext timer that, when ELSP[0] has run longer than N ms with work waiting, asks Apple's scheduler to resubmit (i915-style timeslice). Build only if LAT-2..8 point here. | Remove `wextslice` and reboot; the timer is not installed by default. | Busy p90 near N ms + switch cost confirms the missing timeslice. Unchanged, or CSB errors / `checkForProgress` stalls (#44), mean it does not work. |
