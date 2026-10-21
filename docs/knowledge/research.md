# External research (what exists, what does not)

> **Summary.** Nobody has published accelerated macOS graphics on an Intel Xe panel. nullmoth's own release notes
> say the built-in screen of Intel-panel laptops is not accelerated. Apple-driver projects (NootedGreen, WhateverXe)
> target Tiger Lake drivers and are not usable here. Checked 2026-10-16.

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
