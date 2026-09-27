# Poolside - Revert API and product design

## What the example actually returns

Inspected the [supplied account endpoint](https://api.revert.finance/v1/positions/account/0x4c77ca7ff8e548806fdc88e4dfa8ea1e493a450a?limit=100&active=true&with-v4=true&with-ekubo=true). The saved response has source timestamp **2026-09-20 00:16:06 UTC**. Values below describe that snapshot, not future live balances.

The response is `{success, data, pagination, exited_count}`. `data` contains **two active Uniswap v4 positions**, both on network **`robinhood`**, both in range, neither autocompounding. The API reports `exited_count: 2`; those closed positions are not included in this active response. The v4 and Ekubo flags enable inclusion; they do not imply this wallet has Ekubo positions.

| Metric | USDG / OPENAIx1L | SPY / USDG | Total |
|---|---:|---:|---:|
| Position NFT | 2726168 | 1728707 | 2 active |
| Pooled assets | $879.78 | $987.67 | **$1,867.45** |
| Unclaimed fees, current USD value | $132.43 | $8.29 | **$140.71** |
| Assets + unclaimed fees | $1,012.20 | $995.96 | **$2,008.17** |
| Lifetime P&L vs USD | +$119.95 | −$0.26 | **+$119.69** |
| Lifetime P&L vs HOLD | +$136.96 | +$6.54 | **+$143.50** |
| Pool P&L vs USD | +$120.01 | +$0.08 | +$120.10 |
| USD ROI | 13.44% | −0.0262% | Do not sum |
| Fee APR, USD benchmark | 1,125.54% | 19.22% | Do not average naively |
| Position age | 4.81 days | 15.80 days | - |
| Encoded fee tier | 5000 → 0.50% | 3000 → 0.30% | - |

The token symbols and network above are API metadata. They are not independent verification of token legitimacy, redemption rights, or underlying asset ownership.

### Balances and ranges

| Field | USDG / OPENAIx1L | SPY / USDG |
|---|---:|---:|
| Token 0 balance | 684.53305645 USDG | 1.12868871 SPY |
| Token 1 balance | 179.93761484 OPENAIx1L | 125.50734174 USDG |
| Current pool price, token1 per token0 | 0.89975204 | 762.51772631 |
| Lower price | 0.89368937 | 759.05257664 |
| Upper price | 0.92090488 | 786.87487509 |
| Current price above lower bound | 0.6784% | 0.4565% |

Pool prices are ratios from the pool; token USD quotes may differ. Do not reconstruct pool price from the token USD prices. In this fixture, `pool_price` matches `tokens[token0].prices.token1`. The SPY position is close to its lower bound; a range-status-only green badge would hide that information. A current-price marker and distance-to-boundary text are useful additions.

## Data contract and display mapping

| API fields | App use | Handling |
|---|---|---|
| `network`, `exchange`, `pool`, `nft_id` | Stable identity, network/protocol labels | Use a composite key, not NFT ID alone. Other protocols may require a different identity adapter. |
| `token0`, `token1`, `tokens[address]` | Pair, token names, decimals, USD quotes | Address lookup should ignore case. Keep network in token identity. Unknown tokens get a text fallback. |
| `current_amount0/1`, `underlying_value` | Pooled balances and current USD value | Amounts are already human-readable in this response. Do not divide again by token decimals. |
| `uncollected_fees0/1` | Pending fees | Multiply each amount by that token’s current USD quote, then sum. Missing price means unavailable, not $0. |
| `total_fees0/1`, `collected_fees0/1`, `fees_value` | Fee detail | Collected amounts are zero here, so total and unclaimed coincide. This fixture alone does not prove `fees_value` always means claimable fees. |
| `performance.usd` | Default lifetime USD P&L, ROI and APR | Label benchmark and period explicitly. |
| `performance.hodl` | LP performance relative to holding deposited assets | Separate benchmark; do not label it generic USD trading profit. |
| `performance.token0/token1/eth` | Optional future benchmark views | P&L units vary. Never sum different token-denominated P&Ls across pools. |
| `performance.*.pool_pnl`, `il`, `fee_apr` | Decomposition and fee yield | Display API values with benchmark context. Validate `il` sign/meaning before naming it “loss”; it is positive in one HOLD record here. |
| `price_lower/upper`, `pool_price`, `in_range` | Price range and earning status | Clamp marker for drawing; retain actual price. Label ratio orientation. |
| `tick_lower/upper`, `pool_tick`, `sqrt_price`, `liquidity` | Diagnostics / future calculations | Large integer quantities must not become floating-point IDs or raw balances. Supplied display prices avoid unnecessary tick math. |
| `fee_tier` | Pool fee | For these v4 static examples: integer / 10,000 = percent. Dynamic-fee flags and other protocols need explicit handling. |
| `age`, `first_mint_ts`, `ts`, `now_ts` | Position age, history start, data freshness | Keep source timestamp separate from local fetch time. |
| `total_deposits0/1`, `total_withdrawn0/1`, `deposits_value`, `withdrawals_value`, `diffs0/1` | Position accounting | These fields alone are not a verified USD cost basis. Preserve the backend’s benchmark accounting. |
| `owner`, `real_owner`, `exited`, `autocompounding`, `autocomp_deposited0/1` | Ownership and strategy context | Helpful for managed or staked positions; semantics need fixtures beyond this wallet. |
| `cash_flows` | Accounting context | Only three entries per position here: gas costs, unclaimed-fee state, current-amount state. They are not a complete transaction history or chart series. |
| `pagination` | Complete portfolio loading | Follow `next_cursor` as query parameter `cursor` until `has_next` is false. |

**Pagination was tested live:** `limit=1` returned NFT 2726168 and cursor `1789447492_2726168`; passing that cursor returned NFT 1728707 and `has_next=false`. All pages should succeed before replacing a cached portfolio. Deduplicate identities and stop repeated cursors.

### Accounting rules that matter

1. The balance × USD-quote sums reconcile to `underlying_value` in both records. Unclaimed fees are separate. Adding the derived unclaimed value gives the $2,008.17 assets-plus-fees snapshot above.
2. Use backend `performance.usd.pnl` for USD lifetime P&L. Subtracting `deposits_value` from current balances is not a substitute: Revert supports different pricing baselines and gas/reward adjustments.
3. [Revert’s benchmark definitions](https://docs.revert.finance/revert/position-analytics/uniswap-v4-positions) distinguish USD cash-flow pricing from HOLD pricing and include gas/rewards in total P&L. The prototype exposes USD and HOLD only.
4. ROI and APR are already percentage values. Do not multiply by 100. Do not sum position APRs or ROIs. Avoid a portfolio APR until cash-flow weighting is defined.
5. Very high annualized returns on a 4.81-day position need an age label and explanation. They are historical extrapolations, not a forecast.
6. `performance.eth` has zero ROI/APR despite nonzero P&L in this sample. Treat that as an unresolved provider question; do not promote this benchmark to the primary UI.
7. Decode financial strings and numbers as decimals. Missing/null data must remain unavailable. An HTTP 200 still requires `success=true` and a valid response shape.

## Product and visual direction

**Working name: Poolside.** A focused liquidity companion with three levels of information:

- **Collapsed:** black camera strip, position count on one side and benchmark P&L on the other. Stale/error status takes priority. Keep the camera’s center unobstructed.
- **Expanded:** pooled balance, unclaimed fees, lifetime P&L benchmark selector, and position cards with network, pool fee, P&L and range marker. Source freshness stays visible.
- **Position detail:** balances, current/lower/upper prices, P&L versus pool P&L, ROI, fee APR and age, strategy state, and a selectable pool ID.

The expanded panel uses graphite or warm off-white surfaces, mint accents, restrained borders, rounded cards, SF typography, and monospaced digits. Positive/negative values also have signs; range states have text/icons. Black remains around the camera in light mode.

**Reference findings:**

- [Stock Island](https://stock-island.com/): strongest reference for a quiet, purpose-specific financial companion. Keep its compact information hierarchy and natural expansion around the camera. Its discreet mode suggests an optional balance-hiding setting later. The site was inspected in a browser because the text fetch failed.
- [MacNotch](https://macnotch.io/): useful reference for expanded modules, customizable appearance, and display placement. Apply its hierarchy to a small set of LP cards rather than introducing unrelated modules.
- [Alcove](https://tryalcove.com/): useful additional reference for fluid expansion, live activities, and gestures. Spring transitions and reduced-motion equivalents are a polish milestone, not implemented animation behavior in this first build.
- [Apple NSScreen documentation](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc): derive the camera gap and safe area from screen geometry. The prototype uses AppKit NSPanel with a SwiftUI body and menu-bar controls.

### Onboarding

1. Explain the glanceable LP companion; offer the saved example immediately.
2. Enter a public wallet address; explain that it is sent to Revert and no signing is needed. Validate format; distinguish no positions from fetch failure.
3. Select System, Light or Dark; explain expansion/collapse; fetch live positions after completion.

Later onboarding can offer wallet labels, multiple accounts, screen selection and optional alerts. Ask for notification permission only when enabling alerts. ENS requires a separate resolver; it is not implemented.

## What is necessary beyond this endpoint

| Priority | Addition | Why |
|---|---|---|
| Before public release | Confirm Revert API access terms, authentication policy, rate limits, caching guidance, supported networks and schema stability | One unauthenticated successful request does not establish a supported public API contract or SLA. No published contract was established in this research. |
| Before public release | Provider fixtures for v3, v4 dynamic-fee pools, Ekubo, staked/managed/closed positions, null quotes and large wallets | The example validates only two v4 positions on one network. |
| Before public release | Durable per-wallet cache, Retry-After-aware backoff, sleep/wake handling, cancellation tests and source-time checks | Polling must remain honest and battery-conscious through network failures. |
| Before public release | Physical-notch, multiple-display, full-screen, VoiceOver, contrast, text-size and reduced-motion QA | The app must avoid camera/menu-bar collisions and remain usable on varied Macs. |
| Before public release | Signing, notarization, updates, app icon and privacy documentation | The delivered build is local and ad-hoc signed. |
| Next | Closed-position endpoint mode and verified lifetime portfolio accounting | The current active-only total excludes realized results from exited positions. |
| Next | Range alerts with persistence, hysteresis and cooldowns | Avoid notification spam during boundary oscillation. Requires local state across polls. |
| Next | History endpoint or locally recorded snapshots | Required for honest P&L charts and daily changes. Local history begins at installation and is not prior wallet performance. |
| Next | Pool analytics source | Pool TVL, swap volume, liquidity distribution and historical pool fee yield are absent here. |
| Later | Multiple wallets, privacy mask, pinning, launch at login, keyboard shortcut, configurable cadence | Personalization after data correctness and native behavior are solid. |

No wallet connection is necessary for this read-only MVP. Claims, rebalancing, and transaction signing would be a separate product scope.
