# Wi-Fi MT7921: the native driver

> **Summary.** Since WIFI-8 (2026-10-18) the internal MediaTek MT7921 (`14c3:7961`) works as a normal Mac Wi-Fi card:
> native Wi-Fi menu, Keychain joins, 5 GHz VHT80, 37 down / 37 up on Lukas's line (the same as his phone). The driver is
> flxxxxddd's **AirportMtkWlan** (SimpleMtkWlan fork v1.5.0, IO80211 Sequoia ABI) built from source with our six
> patches, installed in `/Library/Extensions` (auxiliary kernel collection), not in the EFI. History and measurements:
> [../tests/wifi-1-mt7921.md](../tests/wifi-1-mt7921.md).

## What is installed

| Piece | Where | Notes |
| --- | --- | --- |
| `AirportMtkWlan.kext` `dd967442` (WIFI-9; was `a7bfaa40`) | `/Library/Extensions` | bundle `com.flxxxxddd.AirportMtkWlan` 1.5.0; MediaTek firmware inside (not versioned) |
| Source | `~/nmx-build/wifi5/src`, branch `nmx-wifi5` | flxxxxddd/SimpleMtkWlan `9a9c2ea` (v1.5.0) + `source-fixes/wifi/flx-v1.5.0/*` |
| MacKernelSDK | `~/nmx-build/wifi/mks` `3f75008` | the fork's submodule commit |
| EFI requirement | `DisableIoMapper=true` (already in our config) | the driver does its own DMA without VT-d |

No OpenCore kext entry, no boot-arg, no SSDT. The Bluetooth half of the card (`SimpleMtkBtFw`, `SimpleMtkBtPatcher`)
is separate and lives in the EFI.

## Our patches (`source-fixes/wifi/flx-v1.5.0/`)

| Patch | Test | Why |
| --- | --- | --- |
| wifi5-0001 | WIFI-5 | `-nvoff` or `-mtkwlanoff` keeps the driver off the card (OpenCore "Start once without NVIDIA driver" is the safe boot) |
| wifi5-0002 | WIFI-5 | queue drain without `thread_call_cancel_wait` (private KPI: kmutil refused the kext) |
| wifi5-0003 | WIFI-6 | NVRAM knob `nullmoth-wifi-band` (`5` = 5 GHz only, `2` = upstream) |
| wifi5-0004 | WIFI-7 | default "prefer 5 GHz": 5 GHz scanned first, a 2.4 GHz twin of a 5 GHz SSID hidden, 2.4-only networks kept |
| wifi5-0005 | WIFI-8 | data frames through firmware rate adaptation; was fixed 1/6 Mbit/s with block ack off (the upload cap) |
| wifi5-0006 | WIFI-9 | lock around TX ring cleanup: a boot panic (`m_free: freeing an already freed mbuf`) came from the interrupt and the firmware download freeing the same mbuf |

## Build, install, undo

```
bash tools/wifi/build-airport.sh                   # prints "AirportMtkWlan <sha8> (…)"; host tests in the fork: tests/
sudo bash tools/wifi/install.sh airport            # checkpoint of the aux KC first time; prints the hash; reboot
sudo bash tools/wifi/install.sh restore            # removes any Wi-Fi driver; reboot
```
The build fails on purpose if the safe-boot string is missing or a symbol would bind to a private KPI. The install
keeps the pre-Wi-Fi aux KC at `~/AuxiliaryKernelExtensions.kc.antes-wifi`.

No desktop or a boot hang after a Wi-Fi install: OpenCore → Space → "Start once without NVIDIA driver" (`-nvoff`, also
keeps this driver off), then `install.sh restore`.

## Knobs and diagnostics

- `sudo nvram nullmoth-wifi-band=5` (5 GHz only) or `=2` (upstream); `sudo nvram -d nullmoth-wifi-band` = prefer 5 GHz.
  Takes effect at the next boot, no rebuild.
- Driver log (ioreg, persistent): `bash ~/nmx-build/wifi5/out/mtklog.sh > ~/mtk.txt`. Useful fields: `selbs=` (chosen
  BSS, channel, RSSI), `RUN peer … vht= chw=` (link), `rxrate` (RX modes and widths), `txwi_free`/`ring_free`/`full`
  (TX queue), `gap_timeout`/`frame_lost` (RX reorder holes).
- Speed from the terminal (single flow): `curl -A Mozilla/5.0` against `speed.cloudflare.com/__down?bytes=25000000`
  and a POST to `/__up` (without the User-Agent Cloudflare answers 1 byte).

## Upgrading the driver

When flxxxxddd tags a new release: bump `REV` in `tools/wifi/build-airport.sh`, `git am -3` our series on the new
tag in `~/nmx-build/wifi5/src`, drop patches upstream already has (check wifi5-0005's comparison and the
`taskq_quiesce` code), export the rest to `source-fixes/wifi/flx-<ver>/`, build (the symbol check must pass), run the
fork's host tests, install, record a `WIFI-N` test.

## Open

- University network: may be WPA2-Enterprise (802.1X) [unverified]; only WPA2-PSK is known to work with this driver.
- wifi5-0002 and wifi5-0005 offered upstream in one PR (2026-10-18, Lukas's OK): https://github.com/flxxxxddd/SimpleMtkWlan/pull/1
  (branch `upstream-tx-kpi` of kitsuneislife/SimpleMtkWlan, credit to luzility `110c92c`). If merged, drop both at the next rebase.
- Sleep is off on this machine (RTX-22), so Wi-Fi across sleep/wake is untested.
