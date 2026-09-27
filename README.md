# Poolside

**LP positions in the Mac notch.** A native macOS app that reads your wallet's liquidity positions from the Revert API: pooled assets, unclaimed fees and lifetime P&L at a glance. SwiftUI + AppKit, zero dependencies, macOS 14+ Apple silicon.

![Poolside: LP positions, fees and P&L in the Mac notch](docs/poolside-screenshot.png)

[Watch the 11s demo](docs/poolside-demo.mp4): expand, open a position, switch benchmarks, close.

## Download

Grab the build from [Releases](https://github.com/0xaaiden/poolside/releases). It's ad-hoc signed (not notarized), so on first launch: right-click → **Open**, or `xattr -d com.apple.quarantine Poolside.app`.

## Features

- Lives in the notch: collapsed strip shows wallet + P&L; hover expands, click or `Esc` closes, never stealing keyboard focus.
- Per-position detail: price range with current-price marker, balances, ROI, fee APR, impermanent loss and gas spent.
- Amber "near bound" warning when a position is close to falling out of range.
- Open and closed positions; USD, HOLD, ETH and per-token P&L benchmarks.
- Custom wallet labels, multi-wallet switching, privacy mask (the `eye` button hides every amount).
- Polite polling (60s, 15s on Pro) with stale-data markers and preserved data on failure.

## Privacy

Read-only. The public wallet address goes only to `api.revert.finance`; token icons come from Revert's proxy. No keys, signing, transactions or analytics. Preferences stay in UserDefaults.

## Build

```sh
bash build.sh      # writes Poolside.app into the parent folder
bash validate.sh   # model-layer checks (decoding, totals, ranges, motion math)
```

Or open `Package.swift` in Xcode / `swift build`. If Command Line Tools picks an SDK newer than the compiler, `sdk.sh` (sourced by both scripts) probes for a working one; set `POOLSIDE_SDK` to skip probing.

## Free and Pro

| | Free | Pro |
|---|---|---|
| P&L benchmarks | USD, HOLD | + ETH, per-token |
| Refresh | 60 s | 15 s |
| Wallets | 1 | 5 |
| Range alerts | no | ✓ |
| Closed positions | no | ✓ |
| Launch at login | no | ✓ |

Pro keys are verified fully offline (`POOLSIDE-<payload>-<ed25519-sig>`), no server or account. Issue them on the dev machine with `license.sh` (`keys`, `issue`, `verify`); the private key in `.license/` is gitignored and never ships.

## Repo map

```
Sources/Poolside/   app: models, Revert client, panel, views, licensing
Validation/         checks exercised by validate.sh
Tools/              license issuer, scripted demo recording (record-demo.sh)
docs/               API & product analysis, engineering notes, demo media
```

Engineering details (panel motion, hover gate, icon pipeline, large-wallet tuning): [docs/engineering.md](docs/engineering.md). Revert data contract and product analysis: [docs/API-and-product-analysis.md](docs/API-and-product-analysis.md).

## Status

Prototype: verified against Uniswap v4 and a live v3 position; other protocols decode leniently and skip unreadable rows. No chart history, fiat conversion or transactions yet. See [VALIDATION.md](VALIDATION.md) for what has and hasn't been QA'd.
