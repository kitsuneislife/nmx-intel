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

## WIFI-4 result (2026-10-17) — **boot hang, configd watchdog panic** [measured]
- Normal boot (13:09): no graphical session; the screen stayed on the verbose text. Kernel panic at 13:14:
  `userspace watchdog timeout: no successful checkins from configd (1 induced crashes) in 180 seconds`; two
  `configd` hang reports (13:11, 13:16, "monitoring timed out for service"). Lukas recovered with OpenCore Space →
  "Start once without NVIDIA driver" (`-nvoff`): `wifi-0001` kept the driver off the card and the system came up.
- Driver log of the hung boot: firmware, scan, join (2.4 GHz ch 8 this time), 4-way handshake, keys, `LINK_STATE_IS_UP`,
  one TX data frame, then nothing more from the driver.
- Reading [inferred]: the only change from WIFI-3 is `wifi-0005`, which runs the interrupt handler from the watchdog
  workloop as soon as the link is up. The handler delivers frames to the network stack and issues MCU commands;
  from that thread it can deadlock with configd's ioctls on the interface (configd sets up en2 right after link up).
  `wifi-0005` is dropped. Not proven: the configd stackshot has no symbolicated frame in the driver.
- Also seen: a `shutdown_stall` report at 13:08 (the reboot out of WIFI-3), so the driver may not stop cleanly
  either.
- Safety: the driver is removed with `tools/wifi/install.sh restore` before the next normal boot.

## Research round 2 (2026-10-18) — native Wi-Fi menu
Searched GitHub (all 16 forks of laobamac/SimpleMtkWlan by last push, their issues and releases), the web, Reddit and
the forums (tonymacx86's MediaTek thread is ~315 days old, behind a bot check, older than every driver below).
- [unverified, upstream claims] **`flxxxxddd/SimpleMtkWlan` v1.5.0** (GPL-2.0, released 10-18, 50 commits over
  laobamac): the most complete hardware layer. Its fixes match our WIFI-1..4 symptoms: real MSI vector registered
  instead of INTx + hand-set MSI bit; multi-mbuf TX frames linearized (WFDMA froze on the first DHCP frame); DMA-stall
  watchdog with hard reset + firmware reload; chip recovery at attach (WFSYS reset → PCIe FLR); software CCMP for
  group frames; TX backpressure instead of drops; sleep/wake (firmware reloaded on wake). Ships
  **`AirportMtkWlan`** (laobamac's AirportItlwm WCL front end as adapted by pengubow): native Wi-Fi menu, Keychain,
  private address; tested on Tahoe 26.7.1 with RZ608 `14c3:0608`; the **Sequoia 15.2+ build is "not tested on
  hardware with this HAL yet"**; `14c3:7961` "expected to work", untested. Needs `DisableIoMapper` (ours is on,
  `make_config.py:167`), no OCLP wireless patches, one kext only (both flavours match the card).
- `OverlordDev` v1.1-native-wifi (10-15): native menu on Sequoia 15.8.1 on `14c3:7961` per its author, and one
  `7961` user in laobamac#3 says they use it. Its hardware layer is the stageB we ran in WIFI-1..4 (died under load,
  WIFI-3), without flxxxxddd's MSI/TX/stall fixes.
- `pengubow` (native menu on Sequoia, MT7922 RZ616 only), `mnnobre` (native, RZ608 desktop; its only issue is an
  empty "MT7921 … cannot use WiFi" report from 10-18), `luzility` (HE, idle since 10-14). laobamac upstream idle since 06-27.
- Nothing else exists for this chip: no other kext, no commercial driver, no Apple-side support.
- Candidate for WIFI-5: flxxxxddd `AirportMtkWlan` Sequoia, built from source with our `wifi-0001` (off on `-nvoff`
  / `-mtkwlanoff`), DEBUG configuration (the one its hardware tests ran with), log via `mtklog.sh`.

## WIFI-5 prep — AirportMtkWlan (native Wi-Fi menu), flxxxxddd v1.5.0
One variable against WIFI-3: a different driver (flxxxxddd's hardware layer + the AirportItlwm WCL front end), so the
card shows up as macOS's own Wi-Fi (menu bar, System Settings, Keychain), no client app, no `WiFiConfig` in the plist.
- Source: `flxxxxddd/SimpleMtkWlan` `9a9c2ea` (tag v1.5.0), MacKernelSDK `3f75008` (its submodule commit, the same
  we used for WIFI-1). Review: `build-macos.sh` only compiles and links (no network); no file, socket, process or
  NVRAM calls in the kernel sources (grep of `AirportMtkWlan`, `SimpleMtkWlan`, `mtk80211`, `include`). It does not
  use `thread_call_cancel_wait` (so `wifi-0002` is not needed).
- `wifi5-0001` (`source-fixes/wifi/flx-v1.5.0/`): `IOPCIEDeviceWrapper::probe` returns NULL on `-nvoff` (OpenCore
  "Start once without NVIDIA driver") or `-mtkwlanoff`, before touching the device. Same switch as `wifi-0001`.
- `tools/wifi/build-airport.sh`: Debug configuration (the one the fork's hardware tests used), `AIRPORT_OS=sequoia`
  (IO80211 ABI of 15.2+; the Tahoe build would panic here). Output `AirportMtkWlan.kext` (`fa59d016` this build; the
  hash moves with each build because the commit id is compiled in), personality `IOPCIPrimaryMatch` includes
  `0x796114c3`, `OSBundleRequired Network-Root`. The switch string is checked in the binary.
- `tools/wifi/install.sh airport`: installs into `/Library/Extensions`, removes `SimpleMtkWlan.kext` (both match the
  card), rebuilds the aux KC and swaps it only if `com.flxxxxddd.AirportMtkWlan` and the four nullmoth kexts are in
  it. The kext could not be test-linked without root (kmutil skips kexts not owned by root); the installer's KC
  build is that check.
- Prerequisites already true: `DisableIoMapper` on, no SSDT hiding the card, no OCLP wireless patch, no
  `IOSkywalkFamily` block. Sleep is off (`pmset`), so the fork's sleep/wake path is not exercised.
- Log: `bash ~/nmx-build/wifi5/out/mtklog.sh > ~/mtk.txt` (the persistent `MtkDebugLog` on the PCI device, no root).
  Success = the Wi-Fi menu lists networks, joins `Nardino` from the menu, `networkQuality` completes (WIFI-3 died
  here), and the next reboot is clean (WIFI-4 hung).
- **First install refused (10-18)** [measured]: `install.sh airport` → kmutil `Failed to bind '_thread_call_cancel_wait'
  … could not find a kext which exports this symbol`; the aux KC was not changed (the kext file stayed in
  `/Library/Extensions`, the next install replaces it). The call is in `mtk80211/openbsd/sys/_task.cpp`
  (`taskq_quiesce`), not in `compat.cpp` where `wifi-0002` fixed it for OverlordDev's tree; my prep grep missed it
  (zsh globbing broke `--include`). `kmutil libraries -p` showed it was the only symbol from `com.apple.kpi.private`.
- `wifi5-0002`: `taskq_quiesce` waits for an in-flight counter instead (task_add counts each invocation
  `thread_call_enter` schedules, `taskq_run` uncounts on return, a successful `thread_call_cancel` uncounts one;
  bounded 5 s). Matches xnu's `THREAD_CALL_ONCE` rules (entering a running call reschedules it once and returns FALSE;
  cancel returns TRUE when it clears that reschedule) [read, xnu `thread_call.c`]. `thread_call_isactive` was tried
  first: not exported to kexts either. The fork's host test stub now follows the same ONCE rules; all 11 host tests
  pass (`tests/run-all.sh`, needs a UTF-8 locale for `scan`).
- `build-airport.sh` now fails if any undefined symbol is not exported to kexts or comes from `com.apple.kpi.private`
  (`kmutil libraries -p`). Rebuilt: `AirportMtkWlan 3159e898`, 941 symbols from IO80211Family, IONetworkingFamily,
  IOSkywalkFamily, IOPCIFamily, corecapture and the bsd/iokit/libkern/mach KPIs, none private [measured].

## WIFI-5 result (2026-10-18) — **native Wi-Fi works**; download very slow [measured]
Installed `AirportMtkWlan 3159e898` (`install.sh airport`), rebooted twice (second boot 15:21, clean). Lukas joined
`Nardino` from the macOS Wi-Fi menu, first try.
- Loaded `com.flxxxxddd.AirportMtkWlan (1.5.0)`; `IO80211InterfaceRole = Infrastructure`; System Information: en2
  "Card Type: Wi-Fi (0x14C3, 0x3802)", "Firmware Version: itlwm: 1.5.0bc9b48b fw: MT7921", PHY a/b/g/n/ac; DHCP
  192.168.1.12, default route on en2. Private Wi-Fi address in use (`96:8f:cb:…`).
- Join (log, s since load): WCL join from the Keychain at 195 s, 4-way, `RUN peer ht=1 vht=0`, re-join at 205 s, then
  BA sessions (rx tid 0/1/2/4/7, tx tid 0/2/3). **2.4 GHz channel 8, HT20**, RSSI 41; the scans cover all 41 channels
  and see Nardino on 5 GHz ch 108 too, but macOS picked 2.4 GHz.
- `networkQuality`: **uplink 18.6 Mbit/s, downlink 0.24 Mbit/s**, responsiveness 1.4 s, idle latency 254 ms. Ping to
  the gateway afterwards: 20 × 0 % loss, 10–30 ms.
- During the test the driver log shows [measured]: RX rates MCS 5–8, 2 streams, 20 MHz (PHY ~100+ Mbit/s);
  `ba gap_timeout` 3 → 40 → 73 and `frame_lost` 5 → 92 → 257, `below` up to 246 (reorder holes closed by the 100 ms
  timeout, late frames dropped); `tx txwi_free=10 … full=62 oactive=1` at 275 s (TX descriptors almost exhausted,
  output paused; back to 396–509 free a minute later, `full=92` total); repeated `watchdog: main work loop busy, poll
  skipped`. Later the AP fell to MCS 1, 1 stream. `rx_swdec` ~1 % of `rx_hwdec` (decryption fine), `ierr=9`.
- Reading [inferred]: the radio link is fine (rates, decryption, uplink), the download collapses in the driver: RX
  reorder holes stall TCP for 100 ms each (the fork's README says the firmware does not deliver BAR frames), and the
  TX ring filling during the test delays TCP ACKs. 2.4 GHz HT20 on a busy channel makes both worse. Log kept in
  `~/nmx-build/wifi5/mtk-wifi5.txt` (not versioned: private addresses).

## WIFI-6 prep — 5 GHz only (one variable: the band)
Lukas, 10-18: Google's speed test gives ~5 Mbit/s down, upload never finishes; his phone in the same spot gets
29.9 / 20 Mbit/s. Measured from this Mac on WIFI-5 (single TCP flow, curl, 25 s each) [measured]:
- download 4.9 Mbit/s (`speed.cloudflare.com`, 15.2 MB) and 2.1 Mbit/s (`speedtest.tele2.net`); upload 0.9 Mbit/s
  (2.9 MB of 20 MB in 25 s).
- driver log over those transfers: **every RX frame at HT MCS 1, 1 stream, 20 MHz, STBC** (n=2827 in one 30 s
  interval; PHY ~13 Mbit/s); no new reorder holes (`gap_timeout` stayed 83, `frame_lost` 346); during the upload
  `txwi_free` fell to 95 of 509 (`full` 118 → 124). Right after the join the same AP sent MCS 5–8 on 2 streams.
- Reading [inferred]: in single-flow transfers the limit is the link rate the AP chose (MCS 1, the most robust rate)
  and a TX queue that drains slowly, both typical of a weak or crowded 2.4 GHz channel (ch 8, HT20). The phone is
  probably on 5 GHz [unverified]. The reorder holes of WIFI-5 belong to `networkQuality`'s many parallel flows.
- `wifi5-0003`: NVRAM knob `nullmoth-wifi-band=5` leaves the 2.4 GHz channels out of the channel table, so scans
  (they skip channels without flags, `MtkMwx.cpp` scan request), macOS's list and WCL joins (`WCL.cpp` refuses a
  scan with no usable channel) are 5 GHz only; Nardino then joins on ch 108. `sudo nvram -d nullmoth-wifi-band`
  + reboot undoes it, no rebuild, no EFI change. Build `AirportMtkWlan f3742061`, knob string present.
- Success = join on a 5 GHz channel (log `RUN peer … vht=1`, `rxrate` VHT/HT40-80), and single-flow down/up well
  above 4.9 / 0.9 Mbit/s.

## WIFI-6 result (2026-10-18) — 5 GHz: download ×8, upload still low [measured]
`AirportMtkWlan f3742061`, `nullmoth-wifi-band=5`. Joined Nardino on **ch 108, VHT80** (`RUN peer ht=1 vht=1 chw=3
… center_freq1=5530`, rssi 34). Google speed test (Lukas): **38.0 down / 5.1 up**, ping 7 ms (was ~5 / never
finished). Phone in the same spot: 29.9 / 20.
- Driver log: RX VHT 80 MHz, 2 streams, MCS 3–5 (SGI on most), almost no reorder holes (`gap_timeout` 2).
- Single-flow curl from this Mac: upload 5.3 Mbit/s (13.2 MB in 20 s); while it ran `full` (output paused for want
  of a TXWI or TX ring slot) went 173 → 262 and the watchdog logged `main work loop busy` 26 times.
- Side effect Lukas does not want: networks that are only on 2.4 GHz are gone from the list.
- Reading [inferred], for later: with 512 TXWIs and ~440 frames/s, a frame's TXWI comes back ~1 s after it was queued.
  TXWIs and TX ring slots are only reclaimed by the firmware's TX-free event (`mwx_mac_tx_free` → `mwx_tx_kick`);
  the TX-done interrupt cleans the ring but does not restart output. Upload is the next test, not this one.

## WIFI-7 prep — prefer 5 GHz without hiding 2.4 GHz-only networks
`wifi5-0004` makes "prefer 5 GHz" the default when `nullmoth-wifi-band` is unset (`5` = 5 GHz only as in WIFI-6,
`2` = upstream behaviour):
- the scan request lists the 5 GHz channels first, then 2.4 GHz, so a dual-band SSID's 5 GHz node is in the node tree
  before its 2.4 GHz beacon arrives;
- `publishWCLBeacon` does not pass a 2.4 GHz beacon to macOS when the same SSID is on 5 GHz within 15 RSSI points
  (net80211's own preference rule, `ieee80211_node.c:1394`), except the BSS we are joined to; SSIDs that exist
  only on 2.4 GHz are shown as before.
- Host tests: the fork's scan test now checks both orders (`2` and prefer), 128 combinations; all 11 suites pass.
  Build `AirportMtkWlan 6bb3765a`.
- [unverified] Lukas's university network may be WPA2-Enterprise (802.1X); this driver is only known to do WPA2-PSK.

## WIFI-7 result (2026-10-18) — prefer 5 GHz works, 2.4 GHz-only networks back [measured]
`AirportMtkWlan 6bb3765a`, knob deleted. Lukas: the other networks are back in the list; Nardino joined on ch 108
(`selbs=Nardino … chan=108 rssi=35`, `RUN peer … vht=1 chw=3`). Google: **36.8 down / 5.09 up**, ping 6 ms.
- 65 s single-flow upload from this Mac: 5.0 Mbit/s (40.6 MB). Mid-upload stats: **`txwi_free=21` then `8` of 509,
  `ring_free=255`** (the DMA ring empty), `full` 326 → 520, `oactive=1`; ~464 frames/s out (`opkts` +15303 in 33 s).
  So the TXWIs are held by the firmware until its TX-free event, and frames leave slowly.

## WIFI-8 prep — data frames through firmware rate adaptation (the upload cap)
Root cause found in source [read]: `mt7921_mac_write_txwi_80211` shifts the frame type to 0..3 for the TXD fields,
then tests `if (multicast || type != IEEE80211_FC0_TYPE_DATA)` against the unshifted constant 0x08 — always true.
Every frame, unicast data included, gets `MT_TXD2_FIX_RATE` + `MT_TXD3_BA_DISABLE` at `mt7921_mac_tx_rate_val()`:
`mt76_rates[0]` (CCK 1 Mbit/s) on 2.4 GHz, `mt76_rates[4]` (OFDM 6 Mbit/s) on 5 GHz. That matches every upload we
measured: 0.9 Mbit/s on 2.4 GHz (WIFI-6 prep), 5.0–5.3 on 5 GHz (WIFI-6/7). The same function compares correctly
a few lines above (`type == (IEEE80211_FC0_TYPE_DATA >> IEEE80211_FC0_TYPE_SHIFT)`). The control-frame header length
test had the same mistake.
- `wifi5-0005`: keep `fc_type` unshifted for the comparisons; EAPOL stays at the basic rate (mt76's USE_MINRATE).
  Identical in substance to luzility/SimpleMtkWlan `110c92c` ("upload stayed at ~4 Mbps … download 70-80"), which
  never reached flxxxxddd's tree. Other `type` comparisons in the file checked: unshifted or `NOTYET`.
- Build `AirportMtkWlan a7bfaa40`; host tests 11/11.
- Success = upload well above 5 Mbit/s with download unchanged (~37), `full` stops climbing during an upload.

## WIFI-8 result (2026-10-18) — upload at the line's ceiling [measured]
`AirportMtkWlan a7bfaa40` (`kextstat`: `com.flxxxxddd.AirportMtkWlan (1.5.0)`), knob unset. Nardino on ch 108, VHT80
(`selbs=Nardino … chan=108 rssi=35`, `RUN peer ht=1 vht=1 chw=3 … center_freq1=5530`).
- Google speed test (Lukas): **37.10 down / 36.91 up**, ping 6 ms (WIFI-7: 36.8 / 5.09). Lukas: the same ceiling as
  his phone; the phone's 20 up was the phone, so the line is the limit now.
- Single-flow curl from this Mac: upload **38.2 Mbit/s** (30 MB to `speed.cloudflare.com` in ~6 s; WIFI-7: 5.0),
  download **44.7 Mbit/s** (25 MB). `speedtest.tele2.net` (Sweden) stays ~2 Mbit/s, as on WIFI-5: distance, not us.
- Driver log after the tests: RX all VHT 80 MHz (`rxrate n=18016 … vht=18016 … 80=18016`), `gap_timeout=3`,
  `frame_lost=8`; mid-upload `txwi_free=3`, `ring_free=246`, idle `txwi_free=509`, `ring_free=255`. The TXWI pool
  still empties during an upload, but the frames now leave at the negotiated rate, so it no longer caps the speed
  [inferred]. `main work loop busy` 32 times in the log (also seen on WIFI-6), harmless so far.
- Log kept in `~/nmx-build/wifi5/mtk-wifi8.txt` (not versioned).
- Wi-Fi is done for daily use. Open: WPA2-Enterprise for the university network [unverified]; offering wifi5-0005
  and the in-flight counter (wifi5-0002) upstream to flxxxxddd needs Lukas's OK. Runbook:
  [../knowledge/wifi.md](../knowledge/wifi.md).

- Note (2026-10-18): wifi5-0002 and wifi5-0005 sent upstream in https://github.com/flxxxxddd/SimpleMtkWlan/pull/1
  (both build, the fork's `tests/run-all.sh` passes on that branch).

## WIFI-9 (prepared 2026-10-30): boot panic in the firmware download, TX cleanup lock

Evidence [measured]: `/Library/Logs/DiagnosticReports/Kernel-2026-10-30-183855.panic`, the boot before 18:38 (the
next boot came up normally on the hybrid):

```
panic(cpu 4 ...): m_free: freeing an already freed mbuf @uipc_mbuf.c:4509
  _m_freem
  AirportMtkWlan : mwx_dma_tx_cleanup(mwx_softc*, mwx_queue*) + 0x119
  AirportMtkWlan : mwx_mcu_send_firmware(...) + 0xa4
  AirportMtkWlan : mwx_load_firmware / mt7921_mcu_init / mwx_init_hardware / mwx_preinit / mwx_attach
  IOService::startCandidate ... _IOConfigThread::main
```

Cause [inferred from the source, `nmx-wifi5` `0727db5`]: `mwx_dma_tx_cleanup` reclaims a TX ring with no lock. Two
threads call it on the firmware-download ring `sc_txfwdlq`: the attach thread after each firmware chunk
(`mwx_mcu_send_firmware`) and the interrupt handler on the driver's work loop (`mwx_intr` → `mwx_dma_tx_done`, which
cleans all three TX rings). OpenBSD serialises them with `splnet()`, but here `splnet()` returns 1 and does nothing
(`mtk80211/openbsd/net80211/timeout.c:40`). Both threads can see the same `md_mbuf != NULL` and free it: a rare,
timing-dependent boot panic. Not a GPU or hybrid issue.

Fix wifi5-0006: an `IOLock` in the softc, allocated before the interrupt is established, held around the ring walk
in `mwx_dma_tx_cleanup` (released before `wakeup`). Every caller runs in thread context (attach, work loop, timeout),
so a mutex is legal. Build `AirportMtkWlan dd967442` (`7202ddd`): the KPI check passes (`_IOLockAlloc`,
`_IOLockLock`, `_IOLockUnlock` resolve), the fork's host tests pass (10/10). Not covered: `mwx_queue_reset` also
frees TX mbufs without the lock (only on reset/attach, with DMA disabled) [unverified risk, not seen].

Expected: no more `freeing an already freed mbuf` at boot; Wi-Fi unchanged. The panic was rare, so one clean boot
proves little; the check is "no recurrence" over the next days.
