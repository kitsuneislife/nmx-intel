# Docs index — start here

The knowledge base is split so a session reads **only what the task needs** (graph-style: small articles with a
summary block on top, linked to each other). The original Portuguese diary is preserved verbatim in
`archive/LOG-pt.md` for integrity — do not read it routinely.

## Reading order by task

| Task | Read |
| --- | --- |
| Start of any session | [status.md](status.md) (short), then this index |
| Analysing a new test result | [knowledge/diagnostics.md](knowledge/diagnostics.md), [knowledge/pitfalls.md](knowledge/pitfalls.md) |
| Writing or changing a fix | [knowledge/architecture.md](knowledge/architecture.md), [knowledge/patches.md](knowledge/patches.md) |
| "Did we already try X?" | [tests/index.md](tests/index.md) → the one phase file |
| Recovering the original binary / legacy patches | [knowledge/binary-patches.md](knowledge/binary-patches.md) |
| Other projects, upstream state | [knowledge/research.md](knowledge/research.md) |
| Making the RTX → Intel bridge cheaper | [knowledge/bridge-optimization.md](knowledge/bridge-optimization.md) |
| Panel brightness (nullmoth switch vs our Intel panel) | [knowledge/brightness.md](knowledge/brightness.md) |
| Moving to a new nullmoth release | [knowledge/nullmoth-upgrade.md](knowledge/nullmoth-upgrade.md) |
| Wi-Fi (MT7921): build, install, knobs, undo | [knowledge/wifi.md](knowledge/wifi.md) |
| Hybrid route (Iris Xe composites, RTX renders chosen apps) | [knowledge/hybrid-route.md](knowledge/hybrid-route.md) |

## Map

```
status.md                         current state, open problems, next step            (always current)
tests/index.md                    one row per test → phase file
tests/00-05-binary-patches.md     tests 0–5: i915 takes the GPU (byte patches)
tests/06-14-display-bridge.md     own build, display bridge, GOP takeover, NVRAM trail
tests/15-24-drm-userspace.md      fb=2: FBC/PSR, DRM opens, libdrm, RCU, watchdog → stable desktop
tests/rtx-1-7-nmintelfb.md        RTX composites, Intel panel shows (parked)
tests/25-32-framebuffer.md        NMXGPUFB on the desktop, controller fix, ghost display, mirror
tests/rtx-8-accelerated-desktop.md RTX path resumed: own controller for NMIntelFB → accelerated desktop (current)
tests/wifi-1-mt7921.md            Wi-Fi MT7921: SimpleMtkWlan (WIFI-1..4), AirportMtkWlan native menu (WIFI-5..8)
tests/sleep-1-hibernate.md        sleep: hibernation instead of S3 so the GOP relights the panel (SLEEP-1)
knowledge/architecture.md         components and the path of a frame
knowledge/pitfalls.md             symptom → cause → fix, by area           (highest-value file)
knowledge/diagnostics.md          trail/beat/io tokens, knobs, tools, recovery
knowledge/patches.md              every source fix: repo, kind, test, purpose
knowledge/binary-patches.md       legacy byte patches 1–5
knowledge/research.md             external projects and upstream
knowledge/bridge-optimization.md  per-frame cost of the bridge and the staged plan (CASO shape)
knowledge/nullmoth-upgrade.md     runbook: new nullmoth release + our NVRM/NVAccel patches on top
knowledge/wifi.md                 runbook: MT7921 native Wi-Fi driver, our patches, knobs, recovery
knowledge/brightness.md           why nullmoth's brightness switch does not reach the Intel panel; BL-1/BL-2 plan
knowledge/hybrid-route.md         proposal: Apple TGL driver on the Iris Xe + nullmoth headless, per-app routing (H0-H4)
archive/LOG-pt.md                 original diary (Portuguese, verbatim)
```

## Conventions

- **Evidence tags** (as Graphify tags edges EXTRACTED/INFERRED/AMBIGUOUS): **[measured]** seen in a log, panic, trail
  or source; **[inferred]** reasoned and consistent with data; **[unverified]** a hypothesis not yet tested. Never
  promote a claim without new evidence.
- Every file starts with a `> **Summary.**` block; read the summary before deciding to read the rest.
- Binaries are named by the first 8 hex digits of their SHA-256 (`NMXGPU 9823079e…`).
- Dates are 2026; times are the Mac's local time (UTC−3).

## Graphify

Installed by `tools/agent/install-skills.sh` (CLI via uv). Build the graph from this folder:
`/graphify docs --wiki` (the archive duplicates the rest; exclude or ignore its nodes). Query instead of reading:
`/graphify query "why did NMXGPUFB freeze after fb-started?"`.
