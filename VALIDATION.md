# Validation

Validated locally on September 19, 2026 (America/New_York).

- Native Apple-silicon app compiled with Swift 6.3.3 and the installed macOS 15.4 SDK, deployment target macOS 14.
- Ad-hoc app signing succeeded. No notarization or distribution signing was performed.
- `validate.sh` passed: snapshot decoding, portfolio/fee/P&L totals, decimal strings and numbers, missing values, range fractions, wallet validation, and cursor encoding.
- Live API pagination checked at limit=1: two distinct positions, second page terminal.
- UI checked in the actual AppKit/SwiftUI app: welcome, saved-example entry, invalid address, example-wallet selection, appearance selection, live fetch, USD/HOLD switch, position detail, collapse and expansion.
- Dark and light dashboard screenshots inspected. Fixed a wrapped segmented-control label and improved light-theme green contrast.
- Live app fetch returned $1,867.55 pooled, $140.84 unclaimed, +$119.91 USD P&L during QA; the bundled earlier snapshot intentionally retains its original values.
- Wallet persistence verified on app restart.

Not yet exercised: rate-limit responses, offline recovery, empty wallet UI against a live empty fixture, protocol schemas other than this v4 fixture, physical camera occlusion on multiple Mac models, full-screen applications, screen hot-plug, VoiceOver, and long-running polling. These remain release QA requirements.

## Compact redesign verification

Rebuilt successfully. Inspected native light/dark layouts, wallet and appearance onboarding, live fetching, USD/HOLD changes, position detail and back navigation, and collapsed/expanded states. Native panel animation now preserves the hosting view; duration is 300 ms. Range graphics use actual normalized pool prices. Financial parsing and aggregation are unchanged. Reduce Motion is respected in code; the OS preference was not changed during QA.

## Wider range / keyboard refinement

Range validation passed for normal padding, prices above and below LP bounds, zero-floor domains, invalid bounds, and infinite prices. Native dark-mode QA verified the widened band, separate domain/LP labels, bundled icons, arrow-free rows, and Escape collapse followed by reopen. Dark panel and header now share pure black and the native shadow is disabled.

## Dismissal regression and wallet identity

Verified a close-control click remains collapsed with the cursor left over the notch. HoverGate regression tests cover a stationary cursor for 60 seconds, leaving and re-entering, the 180 ms entry delay, and repeated dismissal. WalletIconData matches upstream blo JavaScript pixel and HSL palette reference vectors for the example wallet; capitalization is normalized and different addresses produce different output. Native screenshot inspected for identicon/short address, green unclaimed fees, and positive P&L coloring.
