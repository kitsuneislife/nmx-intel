# External research (what exists, what does not)

> **Summary.** Nobody has published accelerated macOS graphics on an Intel Xe panel. nullmoth's own release notes
> say the built-in screen of Intel-panel laptops is not accelerated. Apple-driver projects (NootedGreen, WhateverXe)
> target Tiger Lake drivers and are not usable here. Checked 2026-10-16. **Update 2026-10-29:** WhateverXe 0.6.1
> accepts our `A7A8` on Sequoia 15.8.x with an experimental internal-panel (eDP) path, untested on hardware; Julio's
> Tahoe stack spreads to more Iris Xe laptops, but nobody has `A7A8` working. See the 10-29 section below.

| Project | What it does | Verdict for us |
| --- | --- | --- |
| nullmoth `nvidia-macos-driver` | NVIDIA Metal driver; NMXGPU (AMD/Intel test driver), NMXAccel, NMIntelFB (unshipped) | base of this work; Intel panel "not accelerated" (release notes); issues #119, #131, #163, #219 open |
| nullmoth 2.0.3 / 2.0.4 / 2.1.0 | app, installer, NVIDIA fixes; 2.1.0 adds PCI logs to NMXGPU | nothing for `gpu-port/` we need |
| nullmoth #196 | WindowServer waits for GPU completion per composite (NVIDIA, 144 Hz caps ~100 fps) | relevant if the RTX path composites |
| WhateverGreen | patches Apple Intel drivers (≤ Ice Lake); knows ADL/RPL IDs only | no framebuffer for Xe |
| NootedBlue | Apple drivers for unsupported iGPUs ≤ Gen11 | no |
| NootedGreen (sgiammori, forks) | Apple **Tiger Lake** drivers on RPL-P (macOS 14.7.1) | WIP: fragmented image, WindowServer hang ~200 ms after activation; different path |
| JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe (2026-10-21) | NootedGreen fork + patched TGL Metal driver on RPL-P `A7A0`, Tahoe 26.7.1 | Metal desktop works; GPU hang after ~1 h, shutdown panic. Note added 10-21, supersedes the row above for RPL-P. Basis of [hybrid-route.md](hybrid-route.md) |
| WhateverXe (b00t0x) | Lilu plugin + OCLP fork root patch, Apple TGL drivers | Big Sur 20G1443, TGL/ADL-N, external displays only; RPL/internal on roadmap |
| Graphify (Graphify-Labs) | knowledge graph / wiki of a corpus for agents | inspired this docs layout; run `/graphify docs --wiki` when installed |

Sources: <https://github.com/nullmoth/nvidia-macos-driver/releases>,
<https://github.com/nullmoth/nvidia-macos-driver/issues/119>, <https://github.com/nullmoth/nvidia-macos-driver/issues>,
<https://github.com/Graphify-Labs/graphify>.

## 2026-10-29 sweep (GitHub repos, issues, releases)

- **WhateverXe 0.6.1 + WhateverXe Graphics 0.3.2 (b00t0x, both 2026-10-27)** [measured, read from the releases and
  `docs/device-selection.md`]: a Lilu plugin derived from WhateverGreen plus a signed graphics package (Apple's TGL
  stack, `AppleIntelTGLCompat` provider) installed in `/Library` with the AuxKC rebuilt; no System or EFI changes by
  the package. One binary covers Big Sur to Tahoe, **Sequoia 15.8.x included**. 0.6.0 accepts ADL-H/P/U and
  **RPL-H/P/U (`A7A0`, `A7A1`, `A7A8`–`A7AD`)**; 0.6.1 adds an **experimental eDP path**: one panel described by the
  VBT on Combo A/B, PPS0, PCH PWM0 brightness, own modesetting; "no ADL-P/N eDP hardware result is claimed". PSR,
  DSC, PPS1, AUX/EC brightness and startup without a GOP are out of scope. Hardware-tested: TGL-U 48/80 EU, ADL-N,
  ADL-H `46A6` 96 EU (external outputs), ADL-S. Graphics 0.2.0 fixed rendering errors on "smaller integrated GPUs"
  and 0.3.2 fixed OpenGL for "six-bank" URB layouts; our `A7A8` 48 EU has 6 L3 banks (reported in Julio #17), so
  this may be the class of bug behind our HYB-12 missing triangles/text [inferred]. Needs SIP `0x803`, its AMFIPass
  Mod, and **must not load together with WhateverGreen**, even with mixed GPUs. Known: App Store video can freeze the
  GPU on Sequoia; DP reconnect freezes.
- **JulioNectar Tahoe stack** (171 stars, 23 forks, daily commits) [measured]: confirmed on Iris Xe 80/96 EU
  (XPS 13 Plus, Latitude 7430, X1 Carbon G11 `dssoftx`, Lenovo Yoga `willyyypatootieee`, ADL-P `46A6` in #16).
  Fixed since 10-21: shutdown stall/panic, a 96 KB-per-command-buffer leak (#12), an RCS hang (#2); H.264/HEVC
  decode with `-ngreengva`. Still Tahoe 26.7.1 only. **`A7A8` fails for everyone**: #8 (48 EU, HDMI mini PC) and a
  46A0 eDP board panic in `AppleIntelPort::probePortState()+0x207` (pure virtual); #13 (64 EU) page fault in
  `IGAccelTask::withOptions`; #17 (an Acer Nitro V15 ANV15-51, i5-13420H, using a NootedGreen fork with our HYB
  changes) probes the accelerator but pipe A never scans (VBL timeout). Julio has no `A7A8` machine.
- **nullmoth**: no Intel Metal work; #163 (i915 not attaching on ADL-P `46A6`, Sequoia) open.
- Verdict: WhateverXe is the first route that matches our OS (Sequoia), our device ID and an internal panel, and it
  ships its own eDP modesetting instead of relying on the GOP's pipe. It would replace NootedGreen in
  [hybrid-route.md](hybrid-route.md), with nullmoth headless for the RTX as planned there [inferred, untested].

Sources: <https://github.com/b00t0x/WhateverXe/releases>, <https://github.com/b00t0x/WhateverXe-Graphics/releases>,
<https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe/issues>.

## 2026-10-30 check (fetched the git remotes)

- WhateverXe still 0.6.1 and WhateverXe Graphics 0.3.2 (both 2026-10-28 merges): nothing new for the hybrid.
- SimpleMtkWlan (flxxxxddd): nothing after v1.5.0; our PR #1 still open, no comments.
- nullmoth **2.6.5** (2026-10-30): user-space only (Metal plugin and shader translator: WebGL shadows, WindowServer
  per-frame work, Photo Booth, ANGLE in Vivaldi/Opera/Arc, game fixes); `kexts/`, `gpu-port/` and `package/`
  unchanged since 2.6.4 [measured, `git diff --stat v2.6.4 origin/main`]. On the hybrid it only matters for apps
  listed in `ondemand.sh` (Safari now). The install replaces `/Library/GPUBundles/nvmtl` (so `nvrm610.conf`) and may
  rewrite `nvmtl-allow.txt`: run `ondemand.sh on` and `noboost` again after it. Its "my settings" block keeps only
  `NVMTL_`/`NVK_`/`NVRM_` keys, and NVK reads the boost knob as a bare `BOOST=` line, so the block cannot carry it.
