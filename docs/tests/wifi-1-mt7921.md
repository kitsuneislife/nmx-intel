# Wi-Fi MT7921 on bare metal (WIFI-1 …)

> **Summary.** The internal Wi-Fi card (MediaTek MT7921, `14c3:7961`, Lite-On subsystem `11ad:3802`) has no macOS
> driver. Research and the VM work are in `CONTEXT.md` sections 12–14 of the private `hackintosh` repo and our fork
> `kitsuneislife/SimpleMtkWlan` (VM fixes, 2026-10-11/13). WIFI-1 tries OverlordDev's Sequoia build of SimpleMtkWlan
> (the only fork measured on our exact chip and macOS), built from source, as a plain Ethernet-type interface.

## Research (2026-10-17)

- [measured] Before WIFI-1: the card is at `RP07/PXSX@0` (`pci14c3,7961`), no driver attached; no SSDT hides it
  (vendor-id reads `14c3`). The system Wi-Fi panel shows "Wi-Fi desativado" with no hardware behind it.
- [unverified, upstream claims] `OverlordDev/SimpleMtkWlan` (GPL-2.0, `5b791c9`, 2026-10-15): macOS 15.8.1 x86_64,
  **MT7921 `14c3:7961`** on one laptop, ~300/226 Mbit/s at VHT80 2SS. Fixes for Sequoia: exact-size firmware chunks
  (the `patch send failed error=12` we also hit in the VM), HT/VHT BSS PHY mode, TX A-MPDU originator, BSS RLM TLV.
  Release `v1.1-native-wifi` adds `AirportMtkWlan` (system Wi-Fi menu, WPA2, DHCP) on the same chip.
- Other forks: `mnnobre/AirportMtkWlan` (RZ608 `14c3:0608`, desktop, ~290/155 Mbit/s, native menu, `7961`
  untested), `pengubow` (MT7922), `flxxxxddd` v1.2.0 (RZ608), `luzility` (HE). laobamac upstream idle since 06-27.
  The SimpleMtkWlan#3 report on `7961` (connect freezes/panics) is answered only with forks tested on other IDs.
- Not supported by any of them: AirDrop/AWDL, WPA3-only/PMF-required networks, 6 GHz, 160 MHz, roaming on beacon
  loss. Sleep/wake untested everywhere (sleep is off here anyway, RTX-22).
- Decision (Lukas, 10-17): Ethernet-type version first (fewer moving parts), native menu later.

## WIFI-1 prep — SimpleMtkWlan stageB (Ethernet type)

- Source review: the fork's diff over laobamac (`SimpleMtkWlan/`, `mtk80211/`, `include/`, +2.4k lines) is driver
  code only; `sequoia_build/*.py` only edit the copied sources. No network, file or process calls in kernel code.
- `wifi-0001`: `probe` returns NULL on `-nvoff` (OpenCore "Start once without NVIDIA driver") or `-mtkwlanoff`, so
  the usual safe boot also leaves the card alone.
- `tools/wifi/build.sh`: fork `5b791c9` + MacKernelSDK `3f75008`, our patches, the fork's own clang-only
  `sequoia_build/build.sh` (-O0, deployment target 10.9, checks every external symbol against this kernel with
  `kmutil libraries`: 587/587). The hash changes per build (`git am` timestamps); the one installed is recorded at
  install time.
- `tools/wifi/install.sh`: `/Library/Extensions/SimpleMtkWlan.kext` (diag build by default: driver log in the
  `MtkLog` ioreg property) and the auxiliary kext collection, keeping the nullmoth kexts. It asks for one network;
  SSID and password go into the personality's `WiFiConfig` (joined at start), the Info.plist becomes root-only (600)
  and the kext is re-signed ad hoc. `restore` removes the driver. EFI untouched.
- Expected: a new `en*` Ethernet-type interface, DHCP address from the router, traffic. Read with
  `ioreg -w0 -r -c SimpleMtkWlan` and `ioreg -w0 -rn PXSX -l` (`MtkLog`, `MtkHB`).

### WIFI-1 first install attempt (2026-10-17) — kmutil refused the kext [measured]
`sudo bash tools/wifi/install.sh`: `Failed to bind '_thread_call_cancel_wait' … could not find a kext which exports this
symbol`; the collection was left unchanged. The symbol is private KPI (`kmutil libraries` puts it in
`com.apple.kpi.private`), which kmutil does not let a third-party kext link; OpenCore injection (how the fork was
tested) links against the kernel directly and never noticed. The fork's own check passed because it compares
against every kernel export. Declaring `com.apple.kpi.private` does not help: kmutil then drops the kext ("No
extension"). Fix `wifi-0002`: the only caller (ring-log stop) now uses public `thread_call_cancel`, waits for a
running publish to finish, and cancels again. `kmutil libraries` now needs only the public KPIs
(IONetworkingFamily, IOPCIFamily, kpi.bsd/iokit/libkern/mach). A full collection build needs root, so linking is
[inferred] until the next install.
