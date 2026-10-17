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

## WIFI-1 result (2026-10-17) — driver loads, firmware patch never finishes [measured]
- wifi-0002 fixed the link: `kmutil` built the collection, `kextstat` shows `com.laobamac.SimpleMtkWlan` loaded
  No `SimpleMtkWlan` object stays on `PXSX`, no new interface, no network.
- Driver log (`log show --last boot`, `MtkLog`): probe matches `14c3:7961`, MSI, `chip id=0x7961 hwrev=0x10`,
  `WFSYS reset ok`, rings allocated (FWDL ring 16 entries), firmware blobs found (`mt7961_patch_mcu_1_2_hdr`
  92192 B, build `20231109190918a`; `mt7961_ram_code_1` 797300 B). The patch semaphore answers (`status=0x2`: download
  needed, semaphore granted), the 92032-byte patch region goes out as 4096-byte FW_SCATTER chunks (11 FWDL TX-done
  interrupts logged), then `command 7 timeout` (PATCH_FINISH_REQ), `patch start failed error=35`, `command 10
  timeout` (semaphore release), `attach to interface fail`, `start: return false at line 434`.
- So the interrupt path works (the semaphore reply arrives within 1 ms); either the firmware never answers
  PATCH_FINISH or its answer is lost. The upstream code sleeps 3 s on a `tsleep` wakeup with no handshake.
- Also logged: `kernelmanagerd … tried to insert an invalid codeful kernel extension in the restricted lookup
  table` for this kext; the kext loaded anyway [measured], effect unknown.

## WIFI-2 prep — dump the MCU and DMA state at the timeout
`wifi-0003`: on an MCU timeout the driver logs `intr_calls`, interrupt status/enable, `GLO_CFG`, `MT_CONN_ON_MISC`
(firmware state) and CPU/DMA indices of the TX MCU, TX FWDL and RX MCU rings. Reading: RX MCU DMA index moved but no
wakeup → lost wakeup; TX MCU DMA index did not move → the command never left; FWDL CPU ≠ DMA → the patch was not
fully fetched. Everything else as WIFI-1.

## WIFI-2 result (2026-10-17) — firmware up, interface en2, scanning [measured]
- This boot the whole firmware load worked: patch (PATCH_FINISH answered `status=0x0`), the 5 WM regions,
  `firmware start ok`, NIC capability, EEPROM. `start: OK`, `SimpleMtkWlan` attached, macOS lists a new Ethernet port
  **en2** with the card's MAC `c0:35:32:…`. No network was configured (Lukas skipped the prompt), so it only scans:
  beacons on 2.4 GHz channels 1–8 and 5 GHz 44/108, ~22 BSSs per scan, a scan every ~5.4 s.
- The first command after `enable` (MAC enable, `0x46ed`) timed out; the dump: `rxmcu cpu=2 dma=4 prod=2 cons=3`,
  `int_sta=0x08400000` pending, `intr_calls=209`. The device had written the reply into the RX MCU ring and raised
  the interrupt, but the handler did not run during the 3 s wait. The retry worked.
- Reading [inferred]: `enable`/`start` run inside the driver workloop gate, and the interrupt handler is on the same
  workloop, so a reply that comes in while the gate is held waits for the timeout. That is also the likely cause of
  WIFI-1's `command 7 timeout` (same 3 s sleep, a reply that sometimes arrives before the sleep and sometimes after).
  OverlordDev hit the same thing in `AirportMtkWlan` v1.1 ("MCU responses are polled; they were only processed after
  the timeout").

## WIFI-3 prep — MCU waits poll the interrupt handler, and join the network
`wifi-0004`: `mwx_mcu_wait()` replaces the single 3 s `tsleep`: every 2 ms it checks the reply slot, calls the
interrupt handler itself, and sleeps 2 ms; `mwx_intr()` is now a wrapper with an atomic busy flag, so the real
interrupt and the poller never run the handler at once. Same idea as OverlordDev's `AIRPORT_WCL poll intr`, written
for the Ethernet build. Install with the home network this time (WiFiConfig).

## WIFI-3 result (2026-10-17) — **connected**, then RX/TX stopped under load [measured]
- Join works: scan picks `Nardino` (5 GHz ch 108, RSSI 31), open auth, assoc (`aid=21`), WPA2 4-way handshake with
  CCMP pairwise + group keys (`port valid`), link up, **DHCP 192.168.1.11** on en2. The MAC-enable timeout of WIFI-2
  is gone (no MCU timeout this boot).
- ~3 min of light traffic (Lukas browsing): 2–20 frames/s each way, no errors.
- Lukas ran `networkQuality`: the AP set up RX BA on TID 2 and 1 (`HB rx ba wtbl … rv=0`, `rx ba sta … rv=0`), the
  driver moved 140–400 frames/s for 4 s, then at `52930` everything stopped: from then on the 1 s heartbeat shows
  `rx=0 (bcn 0)` and `tx_enq=0`, rings idle (`txq prod=14 cons=14`), no MCU timeout, no error line. `networkQuality`
  timed out; later `ping -b en2` to the gateway: 100 % loss, ARP `incomplete`. `netstat -I en2`: 779 in (212 errors),
  `Obytes 185304`.
- Reading [inferred]: the driver is alive (watchdog runs every second) but receives nothing at all, not even beacons,
  so either the device's interrupt stopped coming (MSI lost while the handler had `INT_ENA` cleared) or its DMA
  stopped. Our VM fork saw a similar stop under load from TX descriptors with more than 4 segments (`dma-short-map`);
  this fork already bounces those (`dmaseg overflow … -> bounce` seen twice, fine).

## WIFI-4 prep — lost-interrupt rescue and silent-RX dump
`wifi-0005`: once a second in `mwx_watchdog` (RUN state) read `HOST_INT_STA`; if anything is pending, log it (first 32
times) and run the guarded interrupt handler; after 3 s with no frame at all, log `INT_STA/ENA`, `GLO_CFG` and the RX
data and RX MCU ring indices. If the link survives `networkQuality` with `HB rescue` lines, the cause was lost
interrupts; if it still dies, the dump tells whether the RX DMA stopped (`GLO_CFG`) or the ring is full.
