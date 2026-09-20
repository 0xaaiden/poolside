import SwiftUI

private let gain = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0.40, green: 0.81, blue: 0.55, alpha: 1)
        : NSColor(srgbRed: 0.22, green: 0.40, blue: 0.29, alpha: 1)
})
private let surface = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor.black
        : NSColor(srgbRed: 0.973, green: 0.970, blue: 0.958, alpha: 1)
})
private let loss = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0.92, green: 0.40, blue: 0.39, alpha: 1)
        : NSColor(srgbRed: 0.61, green: 0.28, blue: 0.24, alpha: 1)
})
private func tone(_ value: Decimal?) -> Color { guard let value, value != 0 else { return .secondary }; return value < 0 ? loss : gain }
/// One curve for navigation, onboarding steps and benchmark selection, matching the native panel spring.
private let motion = Animation.spring(response: Spring.panel.response, dampingFraction: Spring.panel.dampingFraction)
private let partialHelp = "Some positions are missing this value, so the total is partial."

struct QuietButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle()).opacity(configuration.isPressed ? 0.5 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(hover ? .primary : .secondary)
                .frame(width: 25, height: 25).background(.primary.opacity(hover ? 0.065 : 0), in: Circle())
        }.help(label).accessibilityLabel(label).onHover { hover = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hover)
    }
}
/// Identicon pixels are derived once per address, not on every header evaluation.
@MainActor private enum WalletIcons {
    static var cache: [String: WalletIconData] = [:]
    static func icon(for address: String) -> WalletIconData {
        if let icon = cache[address] { return icon }
        if cache.count > 64 { cache.removeAll() }
        let icon = WalletIconData(address: address)
        cache[address] = icon
        return icon
    }
}
struct WalletAvatar: View {
    let address: String
    var body: some View {
        Group {
            if RevertClient.valid(address) {
                let icon = WalletIcons.icon(for: address)
                Canvas { context, size in
                    let side = size.width / 8
                    for y in 0..<8 {
                        for x in 0..<8 {
                            let hsl = icon.palette[icon.pixels[y * 4 + min(x, 7 - x)]]
                            let light = Double(hsl[2]) / 100, saturation = Double(hsl[1]) / 100
                            let brightness = light + saturation * min(light, 1 - light)
                            let hsvSaturation = brightness == 0 ? 0 : 2 * (1 - light / brightness)
                            let color = Color(hue: Double(hsl[0]) / 360, saturation: hsvSaturation, brightness: brightness)
                            context.fill(Path(CGRect(x: CGFloat(x) * side, y: CGFloat(y) * side, width: side, height: side)), with: .color(color), style: FillStyle(antialiased: false))
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 3))
            } else { Image(systemName: "person.crop.circle").resizable().scaledToFit().foregroundStyle(.secondary) }
        }.accessibilityHidden(true)
    }
}
struct IslandView: View {
    var store: Store
    let cameraWidth: CGFloat
    let topHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var width: CGFloat { max(400, cameraWidth + 160) }
    var bodyHeight: CGFloat { store.bodyHeight }
    // The spring overshoots by a fraction of a percent; opacity and offset must not.
    var reveal: CGFloat { CGFloat(min(1, max(0, store.revealProgress))) }
    private func toggle() { store.expand(!store.expanded) }
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button(action: toggle) {
                    HStack(spacing: 6) {
                        WalletAvatar(address: store.displayWallet).frame(width: 14, height: 14)
                        Text(store.shortWallet).font(.system(size: 8, weight: .medium, design: .monospaced)).lineLimit(1)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    }.accessibilityLabel("Wallet \(store.shortWallet)")
                    Color.clear.frame(width: cameraWidth)
                    Button(action: toggle) {
                    Group {
                        if reveal > 0.5 { Text(store.hasKeyFocus ? "esc to close" : "click to close").font(.system(size: 9)).foregroundStyle(.white.opacity(0.38)) }
                        else { Text(store.error != nil ? "stale" : store.onboarding ? "set up" : money(store.pnl, signed: true)).font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(store.error != nil ? loss : tone(store.pnl.value)) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    }.accessibilityLabel(store.expanded ? "Collapse Poolside" : "Expand Poolside")
                }.foregroundStyle(.white.opacity(0.7)).frame(height: topHeight + 4 * (1 - reveal)).background(.black)
                .zIndex(1)
                .buttonStyle(.plain)
                ZStack(alignment: .top) {
                    if store.onboarding { Onboarding(store: store).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 5))) }
                    else if let id = store.selected, let p = store.position(id: id) {
                        DetailView(store: store, p: p).id(id).transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 8)))
                    } else { Dashboard(store: store).transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : -8))) }
                }.frame(width: width, height: bodyHeight, alignment: .top).background(surface)
                    .offset(y: reduceMotion ? 0 : -24 * (1 - reveal))
                    .opacity(reveal)
                    .allowsHitTesting(store.expanded && reveal > 0.95)
                    .accessibilityHidden(!store.expanded)
        }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(surface)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 13 + 7 * reveal, bottomTrailingRadius: 13 + 7 * reveal))
            .preferredColorScheme(store.scheme).tint(.primary).buttonStyle(QuietButton())
            .animation(reduceMotion ? nil : motion, value: store.selected)
            .animation(reduceMotion ? nil : motion, value: store.onboarding)
        }.ignoresSafeArea()
    }
}
func benchmarkLabel(_ key: String, position: Position? = nil) -> String {
    switch key {
    case "usd": "USD"
    case "hodl": "HOLD"
    case "eth": "ETH"
    case "token0": position?.symbol0 ?? "Token 0"
    case "token1": position?.symbol1 ?? "Token 1"
    default: key.uppercased()
    }
}
struct BenchmarkSwitch: View {
    var store: Store
    var keys: [String]
    var position: Position? = nil
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            ForEach(keys, id: \.self) { key in
                Button {
                    withAnimation(reduceMotion ? nil : motion) { store.benchmark = key }
                } label: {
                    Text(benchmarkLabel(key, position: position)).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        .foregroundStyle(store.benchmark == key ? .primary : .tertiary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background { if store.benchmark == key { RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.07)).matchedGeometryEffect(id: "benchmark", in: selection) } }
                }.accessibilityLabel("Lifetime P&L versus \(benchmarkLabel(key, position: position))")
                    .accessibilityAddTraits(store.benchmark == key ? .isSelected : [])
            }
            if store.entitlements.tier == .free { ProHint(store: store, label: "ETH", help: "ETH and per-token benchmarks are part of Pro") }
        }.help("Lifetime P&L benchmark for open positions")
    }
}
/// A locked chip for a Pro feature. Clicking opens the license step.
struct ProHint: View {
    var store: Store
    let label: String
    let help: String
    var body: some View {
        Button { store.settings(step: 2) } label: {
            HStack(spacing: 3) { Image(systemName: "lock").font(.system(size: 7)); Text(label) }.font(.system(size: 9, weight: .medium)).foregroundStyle(.quaternary)
                .padding(.horizontal, 7).padding(.vertical, 4)
        }.help(help).accessibilityLabel("\(label), Pro feature. Opens license settings.")
    }
}
struct ProBadge: View {
    var body: some View {
        Text("PRO").font(.system(size: 7, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            .padding(.horizontal, 4).padding(.vertical, 2).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("Pro license active")
    }
}
/// Wallet picker in the dashboard title. One wallet shows a plain label; more become a menu.
struct WalletMenu: View {
    var store: Store
    var body: some View {
        if store.demo {
            Text("Liquidity · example").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        } else {
            Menu {
                ForEach(store.wallets, id: \.self) { address in
                    Button { store.selectWallet(address) } label: {
                        HStack { Text(Store.short(address)); if address.lowercased() == store.wallet.lowercased() { Image(systemName: "checkmark") } }
                    }
                }
                Divider()
                Button(store.canAddWallet ? "Add wallet…" : store.entitlements.tier == .pro ? "Manage wallets…" : "Add wallets with Pro…") { store.settings(step: 1) }
            } label: {
                HStack(spacing: 5) {
                    WalletAvatar(address: store.wallet).frame(width: 11, height: 11)
                    Text(store.shortWallet).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    if store.wallets.count > 1 { Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold)).foregroundStyle(.tertiary) }
                }
            }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help(store.wallets.count > 1 ? "Switch wallet" : "Wallet")
                .accessibilityLabel("Wallet \(store.shortWallet). \(store.wallets.count) tracked.")
        }
    }
}
/// Open / Closed list scope. Closed is a Pro feature and shows as a locked chip on Free.
struct ScopeSwitch: View {
    var store: Store
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            chip("Open", closed: false)
            if store.entitlements.closedPositions { chip("Closed", closed: true) }
            else { ProHint(store: store, label: "Closed", help: "Closed positions with realized P&L are part of Pro") }
        }
    }
    func chip(_ label: String, closed: Bool) -> some View {
        Button { withAnimation(reduceMotion ? nil : motion) { store.setScope(closed: closed) } } label: {
            Text(label).font(.system(size: 9, weight: .medium))
                .foregroundStyle(store.showClosed == closed ? .primary : .tertiary)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background { if store.showClosed == closed { RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.07)).matchedGeometryEffect(id: "scope", in: selection) } }
        }.accessibilityAddTraits(store.showClosed == closed ? .isSelected : [])
    }
}
struct Dashboard: View {
    var store: Store
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var ready: Bool { store.fetchedAt != nil || store.demo }
    var closedReady: Bool { store.closedFetchedAt != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                WalletMenu(store: store)
                if store.entitlements.tier == .pro { ProBadge() }
                Spacer()
                RefreshControl(store: store)
                IconButton(symbol: "slider.horizontal.3", label: "Wallets and appearance") { store.settings() }
            }.padding(.bottom, 8)
            DataNotice(store: store)
            if store.showClosed { closedSummary } else { openSummary }
            Rectangle().fill(.primary.opacity(0.09)).frame(height: 0.5)
            HStack(spacing: 6) {
                ScopeSwitch(store: store)
                Text("\(store.showClosed ? store.closed.count : store.positions.count)").foregroundStyle(.tertiary)
                Spacer()
                Text(store.showClosed ? "Withdrawn / P&L" : "Pooled / P&L").foregroundStyle(.tertiary)
            }.font(.system(size: 9)).padding(.top, 8).padding(.bottom, 4)
            ScrollView {
                VStack(spacing: 0) {
                    if store.showClosed {
                        if store.closed.isEmpty { empty(loading: store.loadingClosed, text: store.loadingClosed ? "Finding closed positions…" : store.error != nil ? "Closed positions unavailable" : closedReady ? "No closed positions" : "—") }
                        ForEach(store.closed) { p in
                            Button { withAnimation(reduceMotion ? nil : motion) { store.selected = p.id } } label: { PositionRow(p: p, benchmark: store.benchmark) }
                        }
                    } else {
                        if store.positions.isEmpty { empty(loading: store.loading, text: store.loading ? "Finding positions…" : store.error != nil ? "Positions unavailable" : "No active positions") }
                        ForEach(store.positions) { p in
                            Button { withAnimation(reduceMotion ? nil : motion) { store.selected = p.id } } label: { PositionRow(p: p, benchmark: store.benchmark) }
                        }
                    }
                }
            }.scrollIndicators(.hidden).frame(maxHeight: .infinity)
        }.padding(.horizontal, 20).padding(.top, 11).padding(.bottom, 13)
    }
    var openSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(ready ? money(store.pooled) : "—").font(.system(size: 30, weight: .regular)).tracking(-1.1).monospacedDigit()
                    .contentTransition(.numericText()).animation(reduceMotion ? nil : .smooth(duration: 0.35), value: store.pooled)
                    .accessibilityLabel("Pooled assets \(money(store.pooled))")
                    .help(store.pooled.complete ? "" : partialHelp)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Unclaimed").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(ready ? money(store.fees) : "—").foregroundStyle(ready && store.fees.value != nil ? gain : .secondary).font(.system(size: 13, weight: .medium)).monospacedDigit().contentTransition(.numericText())
                        .help(store.fees.complete ? "" : partialHelp)
                }
            }
            HStack(spacing: 5) {
                Text(ready ? money(store.pnl, signed: true) : "—").foregroundStyle(tone(store.pnl.value)).contentTransition(.numericText())
                    .help(store.pnl.complete ? "" : partialHelp)
                Text("lifetime").foregroundStyle(.tertiary)
                Spacer()
                BenchmarkSwitch(store: store, keys: store.portfolioBenchmarks)
            }.font(.system(size: 10)).padding(.top, 7).padding(.bottom, 13)
        }
    }
    var closedSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(closedReady ? money(store.realized, signed: true) : "—").font(.system(size: 30, weight: .regular)).tracking(-1.1).monospacedDigit().foregroundStyle(tone(store.realized.value))
                    .contentTransition(.numericText()).animation(reduceMotion ? nil : .smooth(duration: 0.35), value: store.realized)
                    .accessibilityLabel("Realized P&L \(money(store.realized, signed: true))")
                    .help(store.realized.complete ? "" : partialHelp)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Fees collected").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(closedReady ? money(store.closedTotals.collected) : "—").foregroundStyle(closedReady && store.closedTotals.collected.value != nil ? gain : .secondary).font(.system(size: 13, weight: .medium)).monospacedDigit().contentTransition(.numericText())
                        .help(store.closedTotals.collected.complete ? "" : partialHelp)
                }
            }
            HStack(spacing: 5) {
                Text(closedReady ? money(store.closedTotals.withdrawn) : "—").foregroundStyle(.secondary).contentTransition(.numericText())
                Text("withdrawn · realized P&L").foregroundStyle(.tertiary)
                Spacer()
                BenchmarkSwitch(store: store, keys: store.portfolioBenchmarks)
            }.font(.system(size: 10)).padding(.top, 7).padding(.bottom, 13)
        }
    }
    func empty(loading: Bool, text: String) -> some View {
        HStack(spacing: 9) {
            if loading { ProgressView().controlSize(.mini) }
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}
struct PositionRow: View {
    let p: Position
    let benchmark: String
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    AssetIcon(network: p.network, address: p.token0, symbol: p.symbol0)
                    Text(p.symbol0).foregroundStyle(.primary)
                    Text("/").foregroundStyle(.quaternary)
                    AssetIcon(network: p.network, address: p.token1, symbol: p.symbol1)
                    Text(p.symbol1).foregroundStyle(.secondary)
                }.font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack(spacing: 7) {
                    ChainIcon(network: p.network)
                    Text(p.network.capitalized).font(.system(size: 9)).foregroundStyle(.tertiary)
                    if p.closed {
                        Text(p.closedDate.map { "closed \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "closed").font(.system(size: 9)).foregroundStyle(.tertiary)
                    } else {
                        RangeBar(context: p.priceContext, active: p.inRange).frame(width: 82, height: 12)
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                Text(money(p.closed ? p.withdrawals_value?.value : p.underlying_value?.value)).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                Text(money(p.performance?[benchmark]?.pnl?.value, signed: true)).font(.system(size: 10)).foregroundStyle(tone(p.performance?[benchmark]?.pnl?.value)).contentTransition(.numericText())
            }.monospacedDigit()
        }.padding(.vertical, 11).padding(.horizontal, 6)
            .background(.primary.opacity(hover ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle()).onHover { hover = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hover)
            .help(p.closed ? "\(p.pair) · Closed · Fees collected \(money(p.fees_value?.value))" : "\(p.pair) · \(p.inRange ? "In range" : "Out of range or unknown") · Unclaimed \(money(p.unclaimed))")
    }
}
@MainActor private enum IconAssets {
    static let images: [String: NSImage] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        var result: [String: NSImage] = [:]
        for (name, ext) in [("usdg", "svg"), ("robinhood", "jpg")] {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Icons"), let image = NSImage(contentsOf: url) { result[name] = image }
        }
        return result
    }()
}
struct AssetIcon: View {
    let network: String
    let address: String
    let symbol: String
    // Symbols alone are not identities. Only this verified fixture address gets the USDG mark.
    var knownUSDG: Bool { network == "robinhood" && address.lowercased() == "0x5fc5360d0400a0fd4f2af552add042d716f1d168" }
    var body: some View {
        Group {
            if knownUSDG, let image = IconAssets.images["usdg"] {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                ZStack {
                    Circle().fill(.primary.opacity(0.09))
                    Text(String(symbol.prefix(2))).font(.system(size: 6, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }.frame(width: 15, height: 15).accessibilityHidden(true)
    }
}
struct ChainIcon: View {
    let network: String
    var body: some View {
        Group {
            if network == "robinhood", let image = IconAssets.images["robinhood"] {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "network").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }.frame(width: 11, height: 11).clipShape(Circle()).accessibilityHidden(true)
    }
}
struct RangeBar: View {
    let context: PriceRangeContext?
    let active: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                if let context {
                    RoundedRectangle(cornerRadius: 2).fill(gain.opacity(0.13))
                        .frame(width: g.size.width * (context.upperFraction - context.lowerFraction), height: 8)
                        .offset(x: g.size.width * context.lowerFraction)
                    ForEach([context.lowerFraction, context.upperFraction], id: \.self) { bound in
                        Rectangle().fill(gain.opacity(0.6)).frame(width: 1, height: 8).offset(x: (g.size.width - 1) * bound)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(0..<21, id: \.self) { i in
                        Rectangle().fill(.primary.opacity(i % 5 == 0 ? 0.22 : 0.10)).frame(width: 1, height: i % 5 == 0 ? 7 : 4)
                        if i < 20 { Spacer(minLength: 0) }
                    }
                }
                if let context {
                    Capsule().fill(active ? gain : loss).frame(width: 2, height: 10)
                        .offset(x: max(0, (g.size.width - 2) * context.currentFraction))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: context.currentFraction)
                }
            }.frame(height: g.size.height)
        }.accessibilityLabel(context == nil ? "Price range unavailable" : context?.fullRange == true ? "Full range position, always in range" : "\(active ? "In range" : "Out of range or unknown"). Highlighted LP bounds on a wider price axis, with current price marker")
            .help("Highlighted band: your LP range. Marker: current price. Axis includes 50% extra range width on each side and expands for out-of-range prices.")
    }
}
struct RefreshControl: View {
    var store: Store
    var body: some View {
        if !store.demo {
            if store.loading { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 25, height: 25) }
            else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let stale = store.sourceDate.map { context.date.timeIntervalSince($0) > 300 } ?? false
                    IconButton(symbol: stale ? "clock.badge.exclamationmark" : "arrow.clockwise", label: "Refresh positions. " + (store.sourceDate.map { "Last updated " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "No update yet")) { store.refresh() }
                }
            }
        }
    }
}
struct DataNotice: View {
    var store: Store
    var body: some View {
        if let error = store.error { Text(error).font(.system(size: 9)).foregroundStyle(loss).lineLimit(2).help(error).padding(.bottom, 8) }
        else if let notice = store.notice { Text(notice).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2).help(notice).padding(.bottom, 8) }
    }
}
struct DetailView: View {
    var store: Store
    let p: Position
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { store.selected = nil } label: { HStack(spacing: 5) { Image(systemName: "chevron.left").font(.system(size: 9)); Text("Positions").font(.system(size: 10)) } }.foregroundStyle(.secondary)
                Spacer()
                if p.closed { Text("Closed").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 2).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3)) }
                Text("#\(p.nft_id.map { String($0.value) } ?? "—")").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                RefreshControl(store: store)
            }.padding(.bottom, 18)
            DataNotice(store: store)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            AssetIcon(network: p.network, address: p.token0, symbol: p.symbol0)
                            Text(p.symbol0); Text("/").foregroundStyle(.tertiary)
                            AssetIcon(network: p.network, address: p.token1, symbol: p.symbol1)
                            Text(p.symbol1)
                        }.font(.system(size: 19, weight: .medium)).tracking(-0.5)
                        HStack(spacing: 5) {
                            ChainIcon(network: p.network)
                            Text("\(p.network.capitalized) · \(p.exchange == "uniswapv4" ? "Uniswap v4" : p.exchange) · \(p.fee_tier.map { number(Decimal($0.value) / 10000) + "%" } ?? "—")")
                        }.font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    if p.closed {
                        HStack { metric("Deposited", money(p.deposits_value?.value)); Spacer(); metric("Withdrawn", money(p.withdrawals_value?.value), trailing: true) }
                        HStack { metric("Fees collected", money(p.fees_value?.value), color: p.fees_value == nil ? .secondary : gain); Spacer()
                            metric("Closed", p.closedDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—", trailing: true) }
                        Text("Opened \(p.openedDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—") · LP bounds \(p.priceContext?.fullRange == true ? "full range" : "\(price(p.price_lower?.value)) – \(price(p.price_upper?.value))")").font(.system(size: 9)).foregroundStyle(.tertiary)
                    } else {
                    HStack { metric("Pooled", money(p.underlying_value?.value)); Spacer(); metric("Unclaimed", money(p.unclaimed), trailing: true, color: p.unclaimed == nil ? .secondary : gain) }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(p.inRange ? (p.priceContext?.fullRange == true ? "In range · full range" : "In range") : "Out of range / unknown").foregroundStyle(p.inRange ? gain : loss)
                            Spacer(); Text("\(p.symbol1) / \(p.symbol0)").foregroundStyle(.tertiary)
                        }.font(.system(size: 9))
                        RangeBar(context: p.priceContext, active: p.inRange).frame(height: 15)
                        HStack {
                            Text(price(p.priceContext.map { Decimal($0.domainLower) }))
                            Spacer(); Text("now \(price(p.pool_price?.value))").foregroundStyle(.primary); Spacer()
                            Text(price(p.priceContext.map { Decimal($0.domainUpper) }))
                        }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                        Text(p.priceContext?.fullRange == true ? "LP bounds  full range" : "LP bounds  \(price(p.price_lower?.value)) – \(price(p.price_upper?.value))").font(.system(size: 9)).foregroundStyle(gain)
                    }.padding(.vertical, 3)
                    }
                    Divider().opacity(0.5)
                    HStack { Text("Lifetime performance").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); BenchmarkSwitch(store: store, keys: store.entitlements.benchmarks, position: p) }
                    HStack {
                        metric("P&L", money(p.performance?[store.benchmark]?.pnl?.value, signed: true), color: tone(p.performance?[store.benchmark]?.pnl?.value))
                        Spacer(); metric("Pool P&L", money(p.performance?[store.benchmark]?.pool_pnl?.value, signed: true), trailing: true, color: tone(p.performance?[store.benchmark]?.pool_pnl?.value))
                    }
                    HStack {
                        metric("ROI", p.performance?[store.benchmark]?.roi.map { number($0.value) + "%" } ?? "—")
                        Spacer(); metric("Fee APR", p.performance?[store.benchmark]?.fee_apr.map { number($0.value) + "%" } ?? "—", trailing: true)
                    }
                    Text("\(number(p.age?.value, digits: 1)) days \(p.closed ? "held" : "old") · APR is annualized historical performance.").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Divider().opacity(0.5)
                    if p.closed {
                        Text("Withdrawn amounts").font(.system(size: 9)).foregroundStyle(.tertiary)
                        HStack { metric(p.symbol0, number(p.total_withdrawn0?.value, digits: 4)); Spacer(); metric(p.symbol1, number(p.total_withdrawn1?.value, digits: 4), trailing: true) }
                    } else {
                        HStack { metric(p.symbol0, number(p.current_amount0?.value, digits: 4)); Spacer(); metric(p.symbol1, number(p.current_amount1?.value, digits: 4), trailing: true) }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Pool").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Text(p.pool).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Autocompounding \(p.autocompounding.map { $0.value ? "on" : "off" } ?? "unknown")").font(.system(size: 9)).foregroundStyle(.tertiary)
                }.padding(.bottom, 10)
            }.scrollIndicators(.hidden)
        }.padding(20)
    }
    func metric(_ label: String, _ value: String, trailing: Bool = false, color: Color = .primary) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 5) {
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 17, weight: .regular)).monospacedDigit().foregroundStyle(color).contentTransition(.numericText())
        }
    }
}
struct Onboarding: View {
    @Bindable var store: Store
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var appeared = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WalletAvatar(address: store.displayWallet).frame(width: 24, height: 24).offset(x: appeared || reduceMotion ? 0 : -4)
                Spacer()
                HStack(spacing: 4) { ForEach(0..<3) { i in Capsule().fill(.primary.opacity(store.step == i ? 0.55 : 0.1)).frame(width: store.step == i ? 13 : 4, height: 3) } }.accessibilityLabel("Step \(store.step + 1) of 3")
            }.padding(.bottom, 22)
            VStack(alignment: .leading, spacing: 9) {
                Text(store.step == 0 ? "Liquidity. At a glance." : store.step == 1 ? (store.wallets.isEmpty ? "Add your wallet." : "Your wallets.") : "Set the tone.").font(.system(size: 23, weight: .medium)).tracking(-0.7)
                Text(store.step == 0 ? "Your positions, fees and P&L.\nA quiet place at the top of your Mac." : store.step == 1 ? (store.wallets.isEmpty ? "A public address is all you need. Revert reads your positions. No connection or signing." : "Pick which wallet to show, or add another. Switch any time from the dashboard title.") : "Follow your Mac or choose an appearance. Add a Pro key for faster refresh, more benchmarks, range alerts and launch at login.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }.id(store.step).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 4)))
            Group {
                if store.step == 1 {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(store.wallets, id: \.self) { address in
                            HStack(spacing: 8) {
                                Button { store.selectWallet(address) } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: address.lowercased() == store.wallet.lowercased() ? "checkmark.circle.fill" : "circle").font(.system(size: 10)).foregroundStyle(address.lowercased() == store.wallet.lowercased() ? .primary : .quaternary)
                                        WalletAvatar(address: address).frame(width: 12, height: 12)
                                        Text(Store.short(address)).font(.system(size: 10, design: .monospaced))
                                    }
                                }.accessibilityLabel("Show wallet \(Store.short(address))").accessibilityAddTraits(address.lowercased() == store.wallet.lowercased() ? .isSelected : [])
                                Spacer()
                                IconButton(symbol: "xmark", label: "Remove wallet \(Store.short(address))") { store.removeWallet(address) }.scaleEffect(0.8)
                            }.frame(height: 18)
                        }
                        if store.canAddWallet {
                            HStack(spacing: 6) {
                                TextField(store.wallets.isEmpty ? "0x address" : "Add another 0x address", text: $store.walletInput).font(.system(size: 11, design: .monospaced)).textFieldStyle(.plain).padding(10).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.08), lineWidth: 0.5))
                                    .onSubmit { store.addWallet() }
                                if !store.wallets.isEmpty {
                                    Button("Add") { store.addWallet() }.font(.system(size: 10, weight: .medium)).disabled(store.walletInput.trimmingCharacters(in: .whitespaces).isEmpty)
                                        .padding(.horizontal, 10).padding(.vertical, 10).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            if store.wallets.isEmpty { Button("Use example wallet") { store.walletInput = RevertClient.sampleWallet }.font(.system(size: 10)).foregroundStyle(.secondary) }
                        } else if store.entitlements.tier == .free {
                            HStack(spacing: 4) { Text("Track up to \(Entitlements(tier: .pro).maxWallets) wallets with").font(.system(size: 9)).foregroundStyle(.tertiary); ProHint(store: store, label: "Pro", help: "Multiple wallets are part of Pro") }
                        } else {
                            Text("Poolside tracks up to \(store.entitlements.maxWallets) wallets. Remove one to add another.").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                    }
                } else if store.step == 2 {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            ForEach(["system", "light", "dark"], id: \.self) { mode in
                                Button { store.theme = mode } label: {
                                    HStack(spacing: 6) { Image(systemName: mode == "system" ? "circle.lefthalf.filled" : mode == "light" ? "sun.max" : "moon"); Text(mode.capitalized) }
                                        .font(.system(size: 10)).frame(maxWidth: .infinity).padding(.vertical, 11)
                                        .background(.primary.opacity(store.theme == mode ? 0.08 : 0.025), in: RoundedRectangle(cornerRadius: 7))
                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.primary.opacity(store.theme == mode ? 0.2 : 0.04), lineWidth: 0.5))
                                }.accessibilityAddTraits(store.theme == mode ? .isSelected : [])
                            }
                        }
                        LicenseSection(store: store)
                    }
                } else {
                    HStack(spacing: 16) {
                        RangeBar(context: PriceRangeContext(lower: 0.95, upper: 1.05, current: 0.984), active: true).frame(width: 82, height: 14)
                        Text("Less checking. More focus.").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.accessibilityLabel("Illustration of a position range")
                }
            }.padding(.top, 20)
            Spacer(minLength: 8)
            if let error = store.error { Text(error).font(.system(size: 9)).foregroundStyle(loss).padding(.bottom, 8) }
            HStack {
                Button(store.step == 0 ? "Explore example" : "Back") {
                    if store.step == 0 { store.loadDemo() } else { withAnimation(reduceMotion ? nil : motion) { store.step -= 1; store.error = nil } }
                }.foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.error = nil
                    if store.step == 1 {
                        let typed = store.walletInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !typed.isEmpty, !store.addWallet() { return }
                        if store.wallets.isEmpty { store.error = RevertError.invalidWallet.localizedDescription; return }
                        withAnimation(reduceMotion ? nil : motion) { store.step += 1 }
                    }
                    else if store.step < 2 { withAnimation(reduceMotion ? nil : motion) { store.step += 1 } }
                    else { store.connect() }
                } label: {
                    HStack(spacing: 8) { Text(store.step == 2 ? "Open Poolside" : "Continue"); Image(systemName: "arrow.right").font(.system(size: 9)) }
                        .padding(.horizontal, 13).padding(.vertical, 9).background(.primary.opacity(0.07), in: Capsule())
                }
            }.font(.system(size: 11, weight: .medium))
        }.padding(24).onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { appeared = true } }
    }
}
struct LicenseSection: View {
    @Bindable var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(store.entitlements.tier == .pro ? "Poolside Pro" : "Poolside Free").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                if store.entitlements.tier == .pro { ProBadge() }
                Spacer()
                if let license = store.license {
                    Text(license.payload.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                    Button("Remove") { store.removeLicense() }.font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            if store.license == nil {
                HStack(spacing: 6) {
                    TextField("POOLSIDE-… key", text: $store.licenseInput).font(.system(size: 10, design: .monospaced)).textFieldStyle(.plain).padding(8)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.08), lineWidth: 0.5))
                        .onSubmit { store.applyLicense() }
                    Button("Unlock") { store.applyLicense() }.font(.system(size: 10, weight: .medium)).disabled(store.licenseInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.horizontal, 10).padding(.vertical, 8).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            if let message = store.licenseMessage { Text(message).font(.system(size: 9)).foregroundStyle(store.license == nil && message != "Back on Free." ? loss : .secondary).lineLimit(2) }
            VStack(alignment: .leading, spacing: 6) {
                proToggle("Launch at login", isOn: Binding(get: { store.launchAtLogin && store.entitlements.launchAtLogin }, set: { store.setLaunchAtLogin($0) }), enabled: store.entitlements.launchAtLogin)
                proToggle("Notify when a position leaves or re-enters its range", isOn: Binding(get: { store.alertsEnabled && store.entitlements.outOfRangeAlerts }, set: { store.setAlerts($0) }), enabled: store.entitlements.outOfRangeAlerts)
                Text("Refreshes every \(store.entitlements.refreshInterval) s · \(store.entitlements.benchmarks.count) P&L benchmarks · \(store.entitlements.maxWallets) wallet\(store.entitlements.maxWallets == 1 ? "" : "s")\(store.entitlements.closedPositions ? " · closed positions" : "")").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
    func proToggle(_ label: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 5) { Text(label); if !enabled { Image(systemName: "lock").font(.system(size: 7)).foregroundStyle(.quaternary) } }
        }.toggleStyle(.switch).controlSize(.mini).font(.system(size: 10)).disabled(!enabled).help(enabled ? "" : "Part of Pro")
    }
}
