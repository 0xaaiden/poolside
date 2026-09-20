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

## Top-anchor / footer regression

Opening and closing frame interpolation tests verify a constant top edge and horizontal center at 101 progress values on positive, zero, and negative screen origins. Native app checked for collapse/reopen, no footer, and working header refresh. The window frame constraint override prevents menu-bar safe-area displacement; SwiftUI expansion layout animation was removed.

## Running-build verification and reveal refinement

Found both the legacy Luma LP executable and Poolside running; quit the legacy copy and restarted Poolside. Process inspection confirmed only Poolside remained. The active native app shows no footer. Verified collapse/reopen and full content visibility with the mounted-content reveal. Compilation and signing passed.

## Smoothness and idle-cost pass

Validated locally on September 20, 2026 (America/New_York).

- Store migrated to the Observation framework; the display link drives width, height and reveal progress as analytic springs (0.34 s response, 0.86 damping) and SwiftUI navigation shares the same curve.
- `validate.sh` extended and passing: spring convergence, settle time between 0.2 s and 1 s, overshoot under 2%, velocity matches the numerical derivative, retargeting is continuous in value and velocity, critically damped branch, panel top edge and horizontal center constant across 241 frames on positive, zero and negative screen origins, mid-flight reversal, event-driven hover gate (arm, cancel, dwell, suppression after dismissal, re-arm after leaving), partial sums and ≈ formatting, cached totals, case-insensitive token lookup, cached formatters.
- Compiled with no warnings against the newest compatible SDK selected automatically by `sdk.sh` (MacOSX26.5 on this machine; the earlier manual 15.4 override is no longer needed).
- Launched the built app: process stays alive, idle CPU 0.0% across three samples where the previous 50 ms mouse poll ran continuously.

Not exercised in this pass: visual inspection (Screen Recording permission was not available to the build shell), keyboard routing back to the frontmost app after a key panel collapses, hover dwell on real hardware, and 120 Hz frame pacing on a ProMotion display. These need a manual check.

## Close blink regression

Reported: clicking the header to close felt slow and blinked. Cause: the collapse path ordered the panel out and back in to release keyboard focus, which tore down and rebuilt the window for a frame and dropped the first spring frames. Fix: the panel no longer re-orders on collapse; the header toggle never changes key status (`becomesKeyOnlyIfNeeded` plus a body-only click monitor), closing uses a critically damped 0.24 s spring, and the header height and hint now follow the reveal value instead of flipping 4 points and swapping text the instant a transition starts. Validation adds monotone, no-overshoot and 150 ms checks for the closing spring. Rebuilt with no warnings and relaunched; visual confirmation still requires a manual check.

## Other-wallet decoding failure

Reported: entering 0xD360…Af6b showed “The data couldn’t be read because it isn’t in the correct format.” Cause: this wallet holds a Uniswap v3 position and Revert serializes `fee_tier` as the string "100" for v3 rows while the v4 fixture had an integer, so `Int` decoding failed for the whole page. Fix: lenient `Whole` and `Flag` decoders for integers and booleans, per-row decoding with a skipped-row notice, decoding errors that name the field path, and full-range handling (bounds spanning 39 orders of magnitude no longer produce a degenerate axis; the upper bound prints as ∞). The saved live response decodes through the real model code: 1 position, 0 skipped, USDC / Owem:org, fee tier 100, in range, full range. Validation adds coverage for stringified integers and booleans, mixed rows, skipped garbage rows, named error paths and full-range contexts. Rebuilt with no warnings and relaunched.

## License tier

Added Free/Pro entitlements and offline Ed25519 license keys. `validate.sh` covers: issue and verify round-trip, whitespace and lowercase-prefix tolerance in pasted keys, payload tampering and wrong-issuer rejection, six malformed formats, expiry enforced at verification and again on load, the embedded production public key being a valid 32-byte key that rejects test-signed keys, persistence round-trip in an isolated defaults suite, and Pro entitlements being strictly wider than Free with every benchmark present in Revert’s performance map. `license.sh` issued a perpetual and an expiring key with the real signing key; both verify, and a one-character alteration is rejected. App rebuilt with no warnings and relaunched. Not exercised: pasting a key in the live UI, SMAppService registration from an ad-hoc-signed bundle outside /Applications, and notification delivery, which need a manual check.

## Multiple wallets and closed positions

`validate.sh` now also decodes the bundled closed fixture (two Aerodrome positions on Base, zero skips, exited flag, close after open date) and checks realized totals ($143.68 withdrawn, $13.97 collected, +$7.18 USD P&L), the `active=false` query, and the wallet book: trimming, invalid input, Free limit refusal, case-insensitive duplicate selection keeping stored casing, select and remove fallbacks, migration from the single `wallet` default, save/reload, a stale active pointer falling back to the first wallet, and invalid or duplicate entries dropped on load. The initializer bug that surfaced (load left the last-added wallet active instead of honoring the saved pointer) was fixed before release. App rebuilt with no warnings and relaunched; the existing install migrated its saved wallet into the book. Not exercised in the live UI: the wallet menu, adding a second wallet on Pro, and the Closed tab against a live wallet.

## Large wallets and token icons

A reported wallet with 303 open positions (all Robinhood-chain Uniswap v4, four API pages of about 460 KB each) made the panel lag. Timing the data layer ruled it out: one page decodes in 22 ms, totals for 300 positions take 1 ms and per-row derived values 12 ms. The new offscreen benchmark (`bench.sh`, `Validation/Bench.swift`) lays the real `IslandView` out in an `NSHostingView` with that wallet: before, the first layout after data took 962 ms and each of 60 simulated spring frames 22 ms; after switching the list to `LazyVStack` and collapsing the range graphic into one `Canvas` plus an animatable marker shape, 18 ms and 0.8 ms. `validate.sh` still passes. The icon store was exercised against the live proxy: USDC and WETH on mainnet and USDG on Robinhood resolved within 0.6 s, the native zero address and an unknown network name fell back to monograms without a request, three files landed in the cache directory and a fresh instance served WETH from disk. Not exercised: the fixed build against the 303-position wallet in the live UI, and icon rendering in the running panel, which need a manual look.
