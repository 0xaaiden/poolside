# Poolside

A native macOS notch prototype for read-only Revert position analytics. SwiftUI interface, AppKit panel, no third-party dependencies. Requires macOS 14+. The included app build targets Apple silicon.

## Run

Build with `bash build.sh`, then open **Poolside.app** in the parent folder. The app sits at the top of the display; its menu-bar icon provides Show, Wallet & appearance, and Quit.

1. Continue through onboarding, enter a public 0x wallet address, and select System, Light, or Dark.
2. Alternatively, choose **Explore the saved example** for an explicitly labeled offline snapshot of the supplied wallet.
3. Click a position for its range, balances, P&L, ROI, fee APR, and pool ID.
4. Press Escape while the panel has keyboard focus to collapse; hover the strip to expand. The header shows “esc to close.”

The wallet address is sent only to api.revert.finance when using live mode. Address and appearance preferences persist locally in UserDefaults. No keys, wallet signing, transactions, analytics, or runtime image requests are involved. Bundled identity icons include source attribution.

## Build and validate

```sh
bash build.sh
bash validate.sh
```

Open Package.swift in Xcode for development. `swift build` is also supported on a healthy Swift 6 toolchain. On the development machine, swift-package failed to launch because of a missing BuildServerProtocol symbol; build.sh uses swiftc directly and packages an ad-hoc-signed app. This is a local development build, not a notarized distribution.

The machine also selects an SDK newer than its compiler supports. Both scripts were successfully run with `POOLSIDE_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk` prefixed to the command. This selects a compatible installed SDK without changing system settings.

## Implemented

- Camera-aware top panel, menu-bar fallback controls, automatic display geometry updates.
- Three-step onboarding; System/Light/Dark preference; saved wallet; labeled offline example.
- Active positions endpoint with v4 and Ekubo flags, cursor pagination, duplicate suppression, pagination loop guard.
- Decimal arithmetic, string/number decoding, optional metrics rendered as unavailable.
- Pooled assets separate from unclaimed fees; lifetime USD and vs-HOLD P&L.
- Position detail, range indicator, source timestamp, stale marker, retry button, preserved in-memory data on failed refresh.
- 60-second polling; 180-second delay following errors; explicit empty and loading states.

## Prototype boundaries

API decoding is verified against the two supplied Uniswap v4 positions. Other protocols may have different identity/schema requirements. One tracked wallet, active positions only, one automatically selected screen. No chart history, persistent response cache, alerts, launch at login, custom shortcuts, fiat conversion, transaction actions, or closed-position browsing yet. Hover expands and remains open until collapsed intentionally. The compact panel animates its size over 300 ms; navigation, benchmark selection, number updates, range markers and hover feedback have restrained transitions. Motion is disabled when macOS Reduce Motion is enabled. Large text/accessibility and physical-notch/full-screen behavior need testing across real hardware configurations.

The [API/product analysis](docs/API-and-product-analysis.md) separates observed fields, inferred semantics, and production work still required.

## Compact redesign

The expanded overview is 400 × 352 points on a 32-point menu bar (width adapts to the camera gap). Details expand vertically to 462 points. Borderless rows, a monochrome surface, muted gain/loss accents and a tick-based range graphic with wider price context replace the original large cards. Both camera-side controls are independent accessible buttons. Hover expansion has a 180 ms delay. Dismissal is guarded by the physical cursor position in a fixed screen-space header region, so resize-generated hover events cannot reopen it. The pointer must leave and re-enter before hover is armed again.

## Range context and icons

The chart adds half the LP range width on each side and extends further when needed to include the current price. LP bounds form a highlighted band; the current-price marker is never clamped to that band. The detailed view labels the outer axis and LP bounds separately. The domain never extends below zero. Unknown or invalid ranges show no invented band.

Token badges appear next to both assets; chain icons sit next to the network. USDG uses a bundled icon matched by network and contract address. The other fixture tokens use monogram fallbacks because the API supplies no verified logo URLs. Robinhood uses its provided avatar. See Resources/Icons/ATTRIBUTION.md.

The dark surface is pure black to join the camera strip. The native window shadow is disabled. Escape handling is local to the panel and requires no global keyboard or Accessibility permission.

## Wallet identity and financial colors

The header uses a local native port of blo’s Ethereum blockies algorithm and a shortened wallet address. See THIRD_PARTY_NOTICES.md for upstream attribution and license. No ENS name is inferred. Unclaimed fees are green; P&L and pool P&L use green for positive, red for negative, and neutral for zero or unavailable values. The fee label remains unclaimed because the displayed value is pending fees, not fees already collected.
