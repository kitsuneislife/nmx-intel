# Linux i915/xe execlists scheduling on Gen11/Gen12 (Xe-LP): priority, preemption, timeslicing, head-of-line blocking

Primary source: the i915 tree vendored in the local drm-kmod clone (Linux 6.14,
`~/nmx-build/gpu-src/kpi/drm-kmod/drivers/gpu/drm/i915/`). Line numbers below refer to that copy. The same files
upstream are at `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/`
(abbreviated "[i915 gt]" below; line numbers may shift slightly across versions).

## 1. Execlists on Gen11/Gen12: ports, ELSQ, CSB, and when the hardware switches contexts

### Takeaway
On Gen11+ the driver writes up to two context descriptors (ELSP[0], ELSP[1]) into the Execlist Submit Queue at
`RING_EXECLIST_SQ_CONTENTS` (base+0x510) and triggers them with `EL_CTRL_LOAD` in `RING_EXECLIST_CONTROL`
(base+0x550). The hardware runs ELSP[0] to completion and then ELSP[1]; it only switches away early when the driver
submits a new ELSP pair (a preemption request) **and** the running context reaches an arbitration point
(`MI_ARB_CHECK`, or any point while `MI_ARB_ON_OFF` arbitration is enabled). Without a driver-side policy that
submits a new pair (priority preemption or a timeslice timer), a small job queued behind another context waits for
that context's whole submitted ring tail to drain: that is the head-of-line blocking.

### Cited Findings
- Register map (Gen11+): `RING_ELSP(base)` = base+0x230 (pre-Gen11 submit port); `RING_EXECLIST_STATUS_LO/HI` =
  base+0x234/0x238; `RING_CONTEXT_STATUS_PTR` = base+0x3a0; `RING_EXECLIST_SQ_CONTENTS` = base+0x510;
  `RING_EXECLIST_CONTROL` = base+0x550 with `EL_CTRL_LOAD` = bit 0; `RING_MI_MODE` = base+0x9c —
  [i915 gt/intel_engine_regs.h lines 73, 178-180, 209, 232-235](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/intel_engine_regs.h)
- When the platform has ELSQ (`HAS_LOGICAL_RING_ELSQ`, Gen11+), `submit_reg` points at `RING_EXECLIST_SQ_CONTENTS`
  and `ctrl_reg` at `RING_EXECLIST_CONTROL`; otherwise at `RING_ELSP`. The CSB lives in the HW status page
  (`I915_HWS_CSB_BUF0_INDEX`), with `GEN11_CSB_ENTRIES` on Gen11+ (`GEN8_CSB_ENTRIES` before) —
  [i915 gt/intel_execlists_submission.c ~3554-3577](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/intel_execlists_submission.c)
- Submission sequence `execlists_submit_ports()`: write each port's descriptor in reverse order (`for (n = num_ports;
  n--; ) write_desc(...)`), writing 0 for an empty port, then `writel(EL_CTRL_LOAD, ctrl_reg)`. Comment: "the submit
  queue is not cleared after being submitted to the HW so we need to make sure we always clean it up ... we always
  write the same number of elsq entries" — same file, lines 901-935.
- Design comment (file header): requests are sent "in pairs" to ELSP; the queue is otherwise "processed during a
  context switch interrupt"; resubmitting the currently running context with a new tail makes the GPU "not do
  preemption, but just sampl[e] the new tail pointer" (lite restore) — same file, lines ~75-110.
- Gen12 CSB format: `GEN12_CSB_SW_CTX_ID_MASK GENMASK(25,15)`, valid if not `GEN12_IDLE_CTX_ID`; status bits
  `GEN8_CTX_STATUS_PREEMPTED (1<<1)`, `GEN8_CTX_STATUS_IDLE_ACTIVE`; a "promotion" (pending → active) is
  `csb & (IDLE_ACTIVE | PREEMPTED)` on Gen8-11 and parsed via `__gen12_csb_parse(ctx_to_valid, ctx_away_valid, ...)`
  on Gen12 — same file, lines 145-165, 1729-1745.
- Interrupts: `GT_CONTEXT_SWITCH_INTERRUPT` schedules the tasklet (CSB processing → dequeue);
  `GT_WAIT_SEMAPHORE_INTERRUPT` reads `RING_EXECLIST_STATUS_HI` into `execlists.yield` and kills the timeslice timer
  so a context spinning on a semaphore yields at once; `GT_RENDER_USER_INTERRUPT` signals breadcrumbs — same file,
  `execlists_irq_handler()` ~2486-2525.
- The tasklet only dequeues new work when nothing is pending acknowledgement (`if (!pending[0]) {
  execlists_dequeue_irq(); start_timeslice(); }`), i.e. one ELSP write is in flight at a time and the next decision
  happens on the CSB ack interrupt — same file, `execlists_submission_tasklet()` ~2425-2483.
- Preemption is enabled for Gen > 8 (`can_preempt()` returns `GRAPHICS_VER > 8`); engines then get
  `I915_ENGINE_HAS_PREEMPTION`, and `I915_ENGINE_HAS_TIMESLICES` if `CONFIG_DRM_I915_TIMESLICE_DURATION` != 0;
  `I915_ENGINE_HAS_SEMAPHORES` unless running as a vGPU — same file, lines 3313-3316, 3466-3474.

### Inferences
- Execlists hardware has no notion of priority or timeslice. Everything that bounds latency on i915-with-execlists is
  software: deciding to write a new ELSP pair, plus making sure the running context has arbitration points enabled.
  If Apple's driver (running its own execlists path because GuC is off) only resubmits on context-complete, a tiny
  Metal compute job queued behind an Electron/WindowServer context will wait for that context's queued work to finish
  (one or more ~frame-sized batches → 10-20 ms matches 1 frame at 60 Hz). [inferred]
- A practical equivalent in a patching kext needs: (a) a timer that, when ELSP[0] has been running > N ms and other
  work is queued, writes a new ELSP pair putting the other context in port 0; (b) arbitration enabled in the victim's
  ring (MI_ARB_ON_OFF|ENABLE around the batch) so the switch can happen mid-ring/mid-batch. [inferred]

### Gaps
- Exact Gen12 PRM text for ELSQ/CSB event semantics was not fetched (Intel PRM vol. "Command Stream Programming" for
  TGL); the summary above is from i915 code and comments only.

## 2. How i915 decides to preempt: priority, PI, display/wait boosts

### Takeaway
i915 keeps a priority-sorted queue (rbtree of priolists). On every dequeue it calls `need_preempt()`: if the best
queued priority is strictly higher than the effective priority of the running request (with a floor of NORMAL-1),
it pauses the ring, unwinds incomplete requests, and submits a new ELSP pair → hardware preemption. Equal priority
never preempts (FIFO); only timeslicing helps equal-priority clients. The only automatic "interactive" boosts are
`I915_PRIORITY_DISPLAY` for work a pending page-flip waits on, and RPS frequency boosts for waiters (not a priority).

### Cited Findings
- Priority levels: `I915_PRIORITY_MIN = I915_CONTEXT_MIN_USER_PRIORITY - 1`, `NORMAL = I915_CONTEXT_DEFAULT_PRIORITY`
  (0), `MAX = I915_CONTEXT_MAX_USER_PRIORITY + 1` (1024), then `I915_PRIORITY_HEARTBEAT`, then
  `I915_PRIORITY_DISPLAY` ("Interactive workload, scheduled for immediate pageflipping");
  `I915_PRIORITY_UNPREEMPTABLE INT_MAX` for perf-query requests; `I915_PRIORITY_BARRIER = UNPREEMPTABLE - 1` —
  [i915_priolist_types.h](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/i915_priolist_types.h);
  uapi `I915_CONTEXT_PARAM_PRIORITY 0x6`, `I915_CONTEXT_MAX_USER_PRIORITY 1023`, `I915_CONTEXT_DEFAULT_PRIORITY 0` —
  [include/uapi/drm/i915_drm.h ~2008-2010](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/drm/i915_drm.h)
- `need_preempt()`: returns false without semaphores; `last_prio = max(effective_prio(rq), I915_PRIORITY_NORMAL - 1)`;
  no preemption if `queue_priority_hint <= last_prio`; comment: "we wish to prevent triggering preemption at the same
  priority level: the task that is running should remain running to preserve FIFO ordering"; then compares against
  the request in ELSP[1] and against `max(virtual_prio, queue_prio)` —
  [intel_execlists_submission.c 297-351](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/intel_execlists_submission.c)
- Preemption sequence in `execlists_dequeue()`: `ring_set_paused(engine, 1)` (writes `I915_GEM_HWS_PREEMPT` in the
  status page, then `wmb()`), `__unwind_incomplete_requests()`, rebuild ELSP, `set_preempt_timeout()`,
  `execlists_submit_ports()`; the pause flag is cleared (`ring_set_paused(engine, 0)`) when the CSB shows the new
  ELSP was promoted — same file, ~1315-1340, ~1600-1606, ~1921.
- `kick_execlists()` (called on priority bump via the scheduler): sets `queue_priority_hint = prio` and kicks the
  tasklet only if `prio >= max(I915_PRIORITY_NORMAL, rq_prio(inflight))` — "we do not allow low priority tasks to
  preempt other low priority tasks" — same file, ~3318-3364.
- Display boost: `intel_atomic_plane.c` builds `struct i915_sched_attr attr = { .priority = I915_PRIORITY_DISPLAY }`
  and calls `i915_gem_fence_wait_priority(new_plane_state->uapi.fence, &attr)` on the fences a flip waits for, plus
  `intel_display_rps_boost_after_vblank()` —
  [display/intel_atomic_plane.c ~1093-1145](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/display/intel_atomic_plane.c)
- Wait boost is frequency, not priority: in `i915_request_wait_timeout()`, "This client is about to stall waiting for
  the GPU ... RPS autotuning may take tens of milliseconds to respond"; `if (flags & I915_WAIT_PRIORITY &&
  !i915_request_started(rq)) intel_rps_boost(rq);` —
  [i915_request.c ~2060-2072](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/i915_request.c)
- Historic "NEWCLIENT" boost (Chris Wilson, 2018): the first request of a new flow got a small priority bump, idea
  borrowed from FQ_CODEL because such flows are "likely to correspond with short, interactive tasks" —
  [intel-gfx v2 thread](https://lists.freedesktop.org/archives/intel-gfx/2018-August/173037.html),
  [commit b16c765122f9](https://github.molgen.mpg.de/mariux64/linux/commit/b16c765122f987056e1dc9ef6c214571bb5bd694.patch);
  later restricted to "strictly fresh clients" by "drm/i915: Trim NEWCLIENT boosting" —
  [commit 1413b2bc0717](https://github.molgen.mpg.de/mariux64/linux/commit/1413b2bc0717036a5a653eef20cc3ae4cc66501a.patch).
  Reviewer Tvrtko Ursulin worried one spinning client could win most races — same thread. The boost no longer exists in
  the 6.14 tree (no `NEWCLIENT` symbol in `i915_request.c`/`i915_scheduler.c` of the local clone) [measured by grep].

### Inferences
- A kext cannot reuse i915's per-request priority without Apple's driver exposing one; the cheapest equivalents are
  (a) treat any newly queued context that is not the running one as "deserving a slice" (timeslicing, section 3), or
  (b) mark small/interactive clients (e.g. a process allow-list or small command buffers) as higher priority and
  preempt immediately. [inferred]

### Gaps
- I found no patch titled "Bump priority for display"; the mechanism is `I915_PRIORITY_DISPLAY` via
  `i915_gem_fence_wait_priority()`. Its introducing commit was not identified.
- No published before/after latency numbers for the NEWCLIENT boost were found.

## 3. Timeslicing and preempt timeout (CONFIG_DRM_I915_TIMESLICE_DURATION / PREEMPT_TIMEOUT)

### Takeaway
Timeslicing (Chris Wilson, "Minimalistic timeslicing", 2019, v5.4) arms a timer (default 1 ms) whenever ELSP[0] is
running and something else is waiting (ELSP[1] occupied, queue non-empty, or a virtual engine waiting). On expiry the
tasklet demotes the running context behind equal-priority work and resubmits ELSP, which preempts at the next
arbitration point. If the victim does not reach an arbitration point within the preempt timeout (default 640 ms;
7500 ms for compute), the engine is reset. With timeslicing, worst-case wait for an equal-priority small job is
≈ 1 ms + time to next arbitration point + context save/restore, not the length of the other client's queue.

### Cited Findings
- Defaults in the build config: `DRM_I915_TIMESLICE_DURATION=1` (ms), `DRM_I915_PREEMPT_TIMEOUT=640` (ms),
  `DRM_I915_PREEMPT_TIMEOUT_COMPUTE=7500`, `DRM_I915_HEARTBEAT_INTERVAL=2500`, `DRM_I915_STOP_TIMEOUT=100` —
  local `drm-kmod/kconfig.mk` lines 21-25 (mirrors upstream `drivers/gpu/drm/i915/Kconfig.profile`,
  [kernel.org](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/Kconfig.profile)).
  Values are per-engine and tunable in sysfs (`engine->props.timeslice_duration_ms`, `preempt_timeout_ms`).
- `needs_timeslice()`: false if no timeslices, request complete, or `pending[0]` (waiting for ACK); true if ELSP[1]
  occupied ("timeslice required for second inflight context"), queue not empty, or virtual queue not empty —
  [intel_execlists_submission.c 1147-1180](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/intel_execlists_submission.c)
- `timeslice_expired()`: never for a started `nopreempt` request; otherwise `timer_expired(&el->timer) ||
  timeslice_yield(el, rq)`. `timeslice_yield` = the running ccid equals the ccid reported by the last semaphore-wait
  interrupt ("Once bitten, forever smitten!") — same file, 1128-1194.
- On expiry: `cancel_timer`, `ring_set_paused(engine, 1)`, `defer_active(engine)` (moves the active context behind
  same-priority waiters), recompute ELSP; if the same context is chosen again it gets a lite-restore and a fresh slice —
  same file, 1341-1375.
- `start_timeslice()` arms `set_timer_ms(&el->timer, timeslice(engine))` only if `needs_timeslice()`; avoids
  prolonging an active slice — same file, 1201-1225. The timer callback only schedules the tasklet
  (`execlists_timeslice → execlists_kick`) — same file, ~2537.
- Preempt timeout: `set_preempt_timeout()` arms `execlists.preempt` with `preempt_timeout_ms` (or
  `INTEL_CONTEXT_BANNED_PREEMPT_TIMEOUT_MS = 1` for banned contexts) when a new ELSP is written; in the tasklet, if
  it expired and `pending[0]` is still set on the same `preempt_target`, `error_interrupt |= ERROR_PREEMPT` →
  `execlists_reset(engine, "preemption time out")` — same file, 1232-1256, 2410-2475.
- History: "drm/i915/execlists: Minimalistic timeslicing" (commit 8ee36e048c98, June 2019) uses a timer to demote
  the executing context in favour of the next queued context of equal priority; follow-ups "Trim immediate timeslice
  expiry" (2229adc81380, Oct 2019), "Don't merely skip submission if maybe timeslicing" (253a774bb08b), "Enable
  timeslice on partial virtual engine dequeue" (eafc2aa20fba, Mar 2020, stable v5.4+), and "drm/i915/gt: Remove
  timeslice suppression" (Jan 2021) — [nexedi mirror 8ee36e0](https://lab.nexedi.com/kirr/linux/-/commit/8ee36e048c98d4015804a23f884be2576f778a93),
  [2229adc](https://git.disroot.org/kpriv/linux-hardened/commit/2229adc81380),
  [253a774](https://gitlab.collabora.com/martyn/linux/-/commit/253a774bb08b549488047c3fb4afc0faf6f194ae),
  [eafc2aa](https://linux.googlesource.com/linux/kernel/git/bpf/bpf/+/eafc2aa20fba319b6e791a1b0c45a91511eccb6b%5E%21/),
  [intel-gfx 2021-01](https://lists.freedesktop.org/archives/intel-gfx/2021-January/257206.html)
  (commit details from search-result summaries; the commit page itself returned HTTP 429).

### Inferences
- Observed p90 10-15 ms / max ~20 ms with no timeslicing is consistent with "small job waits for the whole queued
  frame of the other client". i915's design would bound it near 1 ms + switch cost. [inferred]
- Minimal kext policy mirroring i915: on submit of a context ≠ running one, and on a 1 ms timer while ELSP[0] has
  been running and others wait, write a new ELSQ pair {waiter, previous} + `EL_CTRL_LOAD`; keep a watchdog
  (preempt timeout) that does *not* reset but just logs, at least initially. [inferred]

### Gaps
- No published before/after latency figures for timeslicing were retrieved (the commit message could not be fetched;
  Phoronix coverage not checked).

## 4. Arbitration points, preemption granularity on Gen12, and what blocks preemption

### Takeaway
Preemption only takes effect at arbitration points. i915 brackets every user batch with `MI_ARB_ON_OFF | ENABLE`
… `MI_ARB_ON_OFF | DISABLE`, puts `MI_ARB_CHECK` in the init breadcrumb and the tail, and ends each request with a
semaphore busy-wait on `HWS_PREEMPT` so a paused ring can be preempted cleanly. Inside a batch, granularity is set by
`CS_CHICKEN1` (0x2580, per-context, masked): on Gen11/Gen12 i915 forces GPGPU preemption to **thread-group** level
(mid-thread disabled by workaround) and leaves 3D object-level enabled; `FF_SLICE_CS_CHICKEN1` (0x20e0) bit 14 makes
these settings per-context so userspace can change them. Thus a compute walker can be preempted only between thread
groups, and anything with arbitration disabled (or a `nopreempt` request) cannot be preempted at all until it ends.

### Cited Findings
- Batch emission (Gen8-12, non-XeHP): `MI_ARB_ON_OFF | MI_ARB_ENABLE; MI_BATCH_BUFFER_START_GEN8 ...;
  MI_ARB_ON_OFF | MI_ARB_DISABLE; MI_NOOP`. `nopreempt` requests use `gen8_emit_bb_start_noarb` (arb disabled around
  the batch, "WaDisableCtxRestoreArbitration") —
  [gt/gen8_engine_cs.c ~540-600](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/gen8_engine_cs.c).
  Opcodes: `MI_ARB_ON_OFF = MI_INSTR(0x08,0)`, `MI_ARB_ENABLE (1<<0)`, `MI_ARB_DISABLE (0<<0)`,
  `MI_ARB_CHECK = MI_INSTR(0x05,0)`; on Gen12 `MI_ARB_CHECK | 1<<8 | state` toggles the pre-parser —
  [gt/intel_gpu_commands.h 59-61, 384](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/intel_gpu_commands.h), gen8_engine_cs.c 163-166.
- Init breadcrumb ends with `MI_NOOP; MI_ARB_CHECK` ("Check if we have been preempted before we even get started");
  wa tail `MI_ARB_CHECK; MI_NOOP` ("Ensure there's always at least one preemption point per-request") —
  gen8_engine_cs.c ~452-470, ~613-620.
- Fini breadcrumb: `MI_USER_INTERRUPT; MI_ARB_ON_OFF | MI_ARB_ENABLE;` then (execlists only, not GuC)
  `emit_preempt_busywait`: `MI_ARB_CHECK` ("trigger IDLE->ACTIVE first"), `MI_SEMAPHORE_WAIT(_TOKEN on Gen12) |
  MI_SEMAPHORE_GLOBAL_GTT | MI_SEMAPHORE_POLL | MI_SEMAPHORE_SAD_EQ_SDD`, data 0, address
  `I915_GEM_HWS_PREEMPT_ADDR` — gen8_engine_cs.c ~626-650, ~727-740. `ring_set_paused()` comment: "If the dword is
  true, the ring is paused as the semaphore will busywait until the dword is false" — intel_execlists_submission.c 238-249.
- `emit_pdps` disables arbitration around the PDP LRIs ("Beware ye of the dragons, this sequence is magic!") —
  intel_execlists_submission.c ~2715-2760.
- `GEN8_CS_CHICKEN1` = 0x2580: `GEN9_PREEMPT_3D_OBJECT_LEVEL (1<<0)`, `GEN9_PREEMPT_GPGPU_LEVEL(hi,lo) =
  (hi<<2)|(lo<<1)`; MID_THREAD = (0,0), THREAD_GROUP = (0,1), COMMAND = (1,0), mask (1,1).
  `GEN7_FF_SLICE_CS_CHICKEN1` = 0x20e0 with `GEN9_FFSC_PERCTX_PREEMPT_CTRL (1<<14)`. `GEN9_CSFE_CHICKEN1_RCS` 0x20d4
  `GEN9_PREEMPT_GPGPU_SYNC_SWITCH_DISABLE (1<<2)`. `GEN9_CTX_PREEMPT_REG` 0x2248. `GEN9_ENABLE_GPGPU_PREEMPTION`
  = bit 2 of `GEN9_HALF_SLICE_CHICKEN7` (MCR 0xe194). `VF_PREEMPTION` 0x83a4 `PREEMPTION_VERTEX_COUNT` [15:0] —
  [gt/intel_gt_regs.h 163-172, 244, 287-293, 528-531, 1115-1119](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/intel_gt_regs.h)
- Gen12 context workaround: "WaDisableGPGPUMidThreadPreemption:gen12" → `wa_masked_field_set(GEN8_CS_CHICKEN1,
  GEN9_PREEMPT_GPGPU_LEVEL_MASK, GEN9_PREEMPT_GPGPU_THREAD_GROUP_LEVEL)`; same for ICL
  ("WaDisableGPGPUMidThreadPreemption:icl", plus `GEN11_SAMPLER_ENABLE_HEADLESS_MSG` "allow headerless messages for
  preemptible GPGPU context"). Gen9 instead defaults to COMMAND level and disables 3D object level
  (`WaDisable3DMidCmdPreemption`) —
  [gt/intel_workarounds.c ~509-525, ~655-662, ~708-712](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/intel_workarounds.c)
- Engine workaround (all Gen9+): `wa_masked_en(GEN7_FF_SLICE_CS_CHICKEN1, GEN9_FFSC_PERCTX_PREEMPT_CTRL)`. Long
  comment: Option 1 (HW default) = global control via kernel-only `CS_DEBUG_MODE1` (0x20EC); Option 2 = per-context
  via `CS_CHICKEN1` (0x2580), "saved/restored on context switch and is writable by userspace (e.g., via
  MI_LOAD_REGISTER_IMMEDIATE ...)". Linux always uses Option 2. `GEN8_CS_CHICKEN1` and `GEN9_CTX_PREEMPT_REG` are
  whitelisted for userspace ("WaEnablePreemptionGranularityControlByUMD") — intel_workarounds.c ~2375-2432, ~1876-1881.
- `RING_MI_MODE`: Gen12 render clears `TGL_NESTED_BB_EN`; `ASYNC_FLIP_PERF_DISABLE` on older parts —
  intel_workarounds.c 354, 858.

### Inferences
- Because `CS_CHICKEN1` is context-saved and UMD-writable, Apple's Metal UMD/driver decides granularity for each
  context. If Apple programs COMMAND-level for compute (or disables arbitration inside its batches), a long Electron
  compute/blit batch is non-preemptible until it ends, and only timeslicing *between* batches helps. Reading
  `CS_CHICKEN1` (0x2580) and `CS_DEBUG_MODE1` (0x20EC) while each context runs would tell which option Apple uses.
  [inferred, not verified on this machine]
- If Apple's ring commands lack `MI_ARB_ON_OFF|ENABLE` around batches, writing a new ELSP pair will only take effect
  at the end of the ring tail already submitted; a kext would need to inject arb-enable or keep ring tails short.
  [inferred]

### Gaps
- No primary Intel PRM excerpt was retrieved for the exact preemption-granularity behaviour on Xe-LP (thread-group vs
  mid-thread for compute; object-level for 3D) or for `CS_DEBUG_MODE1` bit layout.
- Measured context-switch/preemption latency on Gen12 (save/restore cost) was not found.

## 5. Linux xe and GuC submission: how they differ

### Takeaway
With GuC submission the firmware owns ELSP and runs the timeslice ("execution quantum") and preemption timeout per
context, reacting in microseconds without a host interrupt → tasklet → MMIO round trip. xe always uses GuC for
production; its knobs are `timeslice_duration_us` and `preempt_timeout_us` (default 640 000 µs). i915-with-GuC also
drops the HWS_PREEMPT busy-wait from the breadcrumb.

### Cited Findings
- xe `Kconfig.profile`: `DRM_XE_PREEMPT_TIMEOUT` default 640000 µs ("driver waits for the running context to yield at
  an arbitration point when a higher-priority context becomes runnable ... If it doesn't yield before the timer
  expires, the hardware is reset"); `DRM_XE_TIMESLICE_MIN/MAX` 1 µs / 10 000 000 µs; job timeout default 5000 ms
  hardcoded — [xe Kconfig.profile](https://git.zx2c4.com/linux-rng/plain/drivers/gpu/drm/xe/Kconfig.profile)
- xe exposes per-engine-class sysfs `timeslice_duration_us`, `preempt_timeout_us`, `job_timeout_ms` with min/max caps —
  [intel-xe "Add min/max cap for engine scheduler properties"](https://lists.freedesktop.org/archives/intel-xe/2023-July/008805.html),
  [intel-xe "Add sysfs for preempt reset timeout"](https://lists.freedesktop.org/archives/intel-xe/2023-July/008401.html)
- GuC caps preempt timeout at `GUC_POLICY_MAX_PREEMPT_TIMEOUT_US (100*1000*1000UL)` —
  [gt/uc/intel_guc_fwif.h 337](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/uc/intel_guc_fwif.h)
- i915's GuC path maps priorities into GuC bands (`else if (prio < I915_PRIORITY_DISPLAY)` in
  `intel_guc_submission.c` ~3660) and skips `emit_preempt_busywait` when `intel_uc_uses_guc_submission()` —
  gen8_engine_cs.c ~646-650; [intel_guc_submission.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/gpu/drm/i915/gt/uc/intel_guc_submission.c)

### Inferences
- GuC's lower latency comes from (1) the scheduler running next to the hardware, so a 1 ms quantum expiry or a
  higher-priority doorbell triggers ELSP immediately; (2) many contexts registered at once with no host-side ELSP
  pairing; (3) no CPU interrupt/tasklet latency in the decision path. With GuC disabled, Apple's driver loses all of
  that and must implement it itself; if its execlists fallback lacks timeslicing, the observed 10-20 ms
  head-of-line blocking follows. [inferred]
- Re-enabling GuC submission (if WhateverXe/firmware allow it) is the "free" fix; otherwise a kext timeslice timer
  is the i915-equivalent. [inferred]

### Gaps
- Default value of xe `timeslice_duration_us` per engine class was not confirmed from source (search snippets mention
  1 ms in an early commit with a FIXME). xe also has an execlist backend (`xe_execlist.c`) reportedly for bring-up
  only, without timeslicing; not verified in this session.
- No measured GuC-vs-execlists latency comparison was found.
- Whether Apple's TGL driver normally uses GuC submission on real Macs/other hackintoshes, and what its own
  execlists fallback does on preemption, is not covered by Linux sources.
