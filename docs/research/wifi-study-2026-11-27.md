# Wi-Fi study 2026-11-27: slow download after the line upgrade

> **Summary.** Lukas's line is now ~400 Mbit/s (phone), cable gives ~80 and Wi-Fi ~4. The Mac sits on the 2.4 GHz
> side of `Nardino` in legacy OFDM and never sees the 5 GHz side; the cable is a 100 Mbit/s link. Upstream has a
> two-line DMA cache fix (~40 → ~150–200 Mbit/s on MT7921/MT7922) that our v1.5.0 build lacks. Plan: band knob first,
> then the cache fix as its own test, then consider a rebase on e5u v1.6.0.

## What the machine shows [measured, 2026-11-27, uptime ~2.5 h]

- `kextstat`: `com.flxxxxddd.AirportMtkWlan (1.5.0)` loaded; Wi-Fi is `en2` (default route), network service still
  named "Ethernet 2" (leftover from the SimpleMtkWlan era; cosmetic).
- Driver log (`MtkDebugLog` in ioreg): `ieee80211_node_choose_bss 2ghz ssid=Nardino … rssi=45`, `poll state=4 chan=7`.
- Every `rxrate` window: `mode[cck=… ofdm=N ht=0 vht=0]`, `bw[20=N]`, `nss[1=N]`. No HT at all, so the PHY cap is
  54 Mbit/s and ~4 Mbit/s in practice. CoreWLAN: channel 7, RSSI −54, TX rate 6.0.
- CoreWLAN scan: four neighbour networks, all 2.4 GHz; **no 5 GHz BSS at all**. Earlier (WIFI-6..8) the same SSID
  joined on 5 GHz channel 108, VHT80. Prefer-5 GHz (wifi5-0004) scans 5 GHz first, so the 5 GHz BSS was not heard.
- `system_profiler`: country code 0, locale unknown.
- `en0` (cable): `media: 100baseTX <full-duplex>` → ~94 Mbit/s ceiling. A cable or port problem, not a driver one.

## Hypotheses for the missing 5 GHz [inferred]

1. The router changed with the plan upgrade (new 5 GHz channel, width, Wi-Fi 6 mode or WPA3) [unverified: need the
   phone's channel/frequency]. WPA3-only is unsupported by every fork; an HE-only 5 GHz would still beacon.
2. Passive/DFS channels not heard with country code 0 (Linux users of MT7921/7922 fix hidden 5/6 GHz by setting the
   regdomain) [unverified for this driver].
3. The 2.4 GHz link has no HT (ht=0) — maybe the AP serves 2.4 GHz as legacy, or our association misses HT [unverified].

## Upstream since our base (flxxxxddd v1.5.0, 2026-10-18) [measured via GitHub API]

| Source | What | Relevance |
| --- | --- | --- |
| flxxxxddd/SimpleMtkWlan | no commits since v1.5.0; PR #1 (ours) and PR #2 open | base is idle |
| PR #2 (tinywifi) `fix(dma): cache packet bounce buffers` | bounce buffers were `kIOMapInhibitCache`; now cached. MT7922: 26 → 197 Mbit/s | **high**: 2-line change in `compat.cpp` |
| OverlordDev v1.2 (2026-11-11, Tahoe only) | same cache fix on MT7921: ~40 → ~148 down / 150–200 up | confirms the fix on our chip |
| e5u v1.6.0 (2026-10-30) | v1.5.0 + our two PR patches + DMA cache + HE (802.11ax, `-mtkhe`) + roam lock + RX batching; "Sequoia not tested on hardware with this HAL" | candidate new base later |
| Wado729 (2026-11-21) | MT7927 work: roaming, AP signal averaging | other chip; ideas only |
| laobamac #9, mnnobre #1–3 | Tahoe RX ring / other chips | not ours |

Without the cache fix, even a good 5 GHz link should top out near the old ~40 Mbit/s [inferred from OverlordDev and
PR #2 numbers]. That is why the line upgrade exposes it now: the old line was 37 Mbit/s.

## Recommended order (one variable per test)

1. **WIFI-11 (knob, no rebuild):** `nullmoth-wifi-band=5`. Success = joins Nardino on 5 GHz (`chan=` > 14, `vht=`).
   If nothing appears, read the router's 5 GHz channel/width/security from the phone before any code change.
2. **WIFI-12 (rebuild):** cherry-pick e5u `dc88cdf` (DMA cache) onto our v1.5.0 series as wifi5-0008. Success =
   download well above ~40 Mbit/s on 5 GHz.
3. Later, optional: rebase onto e5u v1.6.0 (drops our 0002/0005, adds HE). Larger HAL diff, untested on Sequoia
   hardware: a planned phase, not a quickfix.
4. Cable: try another Cat5e/Cat6 cable or router port; `ifconfig en0` should show `1000baseT`.

## Sources

- flxxxxddd PR #2: https://github.com/flxxxxddd/SimpleMtkWlan/pull/2
- e5u v1.6.0: https://github.com/e5u/SimpleMtkWlan/releases/tag/v1.6.0 (commit `dc88cdf`)
- OverlordDev v1.2: https://github.com/OverlordDev/SimpleMtkWlan/releases/tag/v1.2
- laobamac #9: https://github.com/laobamac/SimpleMtkWlan/issues/9
- Regdomain hiding 5/6 GHz on MT7922 (Linux): https://lists.infradead.org/pipermail/linux-mediatek/2022-December/053706.html
- 5 GHz vanishing on MT7921 (Linux): https://universal-blue.discourse.group/t/some-5g-wifi-is-not-showing/3783
