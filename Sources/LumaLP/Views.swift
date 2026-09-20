import SwiftUI

private let gain = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0.60, green: 0.75, blue: 0.65, alpha: 1)
        : NSColor(srgbRed: 0.22, green: 0.40, blue: 0.29, alpha: 1)
})
private let surface = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0.055, green: 0.055, blue: 0.059, alpha: 1)
        : NSColor(srgbRed: 0.973, green: 0.970, blue: 0.958, alpha: 1)
})
private let loss = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0.83, green: 0.59, blue: 0.55, alpha: 1)
        : NSColor(srgbRed: 0.61, green: 0.28, blue: 0.24, alpha: 1)
})
private func tone(_ value: Decimal?) -> Color { (value ?? 0) < 0 ? loss : gain }

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
struct LumaMark: View {
    var body: some View {
        ZStack {
            Circle().trim(from: 0.08, to: 0.92).stroke(lineWidth: 1).frame(width: 14, height: 14).rotationEffect(.degrees(-30)).offset(x: -4)
            Circle().trim(from: 0.08, to: 0.92).stroke(lineWidth: 1).frame(width: 14, height: 14).rotationEffect(.degrees(150)).offset(x: 4)
        }.frame(width: 24, height: 18).accessibilityHidden(true)
    }
}
struct IslandView: View {
    @ObservedObject var store: Store
    let cameraWidth: CGFloat
    let topHeight: CGFloat
    @State private var hoverTask: Task<Void, Never>?
    @State private var inhibitHover = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var width: CGFloat { max(400, cameraWidth + 160) }
    var bodyHeight: CGFloat { store.onboarding ? 326 : store.selected != nil ? 430 : 320 }
    private func toggle() { inhibitHover = true; hoverTask?.cancel(); store.expand(!store.expanded) }
    var body: some View {
        VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button(action: toggle) {
                    HStack(spacing: 6) {
                        LumaMark().scaleEffect(0.65).frame(width: 18)
                        Text(store.expanded ? "luma" : store.demo ? "demo" : "\(store.positions.count) LP").font(.system(size: 10, weight: .medium))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    }.accessibilityLabel("Luma overview")
                    Color.clear.frame(width: cameraWidth)
                    Button(action: toggle) {
                    Group {
                        if store.expanded { Image(systemName: "minus").font(.system(size: 10, weight: .medium)) }
                        else { Text(store.error != nil ? "stale" : store.onboarding ? "set up" : money(store.pnl, signed: true)).font(.system(size: 10, weight: .medium)).monospacedDigit() }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    }.accessibilityLabel(store.expanded ? "Collapse Luma" : "Expand Luma")
                }.foregroundStyle(.white.opacity(0.7)).frame(height: topHeight + (store.expanded ? 0 : 4)).background(.black)
                .buttonStyle(.plain)
                .onHover { inside in
                    hoverTask?.cancel()
                    if !inside { inhibitHover = false }
                    if inside && !store.expanded && !inhibitHover {
                        hoverTask = Task { try? await Task.sleep(for: .milliseconds(180)); if !Task.isCancelled { store.expand(true) } }
                    }
                }
            if store.expanded {
                ZStack(alignment: .top) {
                    if store.onboarding { Onboarding(store: store).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 5))) }
                    else if let id = store.selected, let p = store.positions.first(where: { $0.id == id }) {
                        DetailView(store: store, p: p).id(id).transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 8)))
                    } else { Dashboard(store: store).transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : -8))) }
                }.frame(width: width, height: bodyHeight, alignment: .top).background(surface)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -8)))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(store.expanded ? surface : .black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: store.expanded ? 20 : 13, bottomTrailingRadius: store.expanded ? 20 : 13))
            .preferredColorScheme(store.scheme).tint(.primary).buttonStyle(QuietButton())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: store.selected)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: store.onboarding)
    }
}
struct BenchmarkSwitch: View {
    @ObservedObject var store: Store
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["usd", "hodl"], id: \.self) { key in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { store.benchmark = key }
                } label: {
                    Text(key == "usd" ? "USD" : "HOLD").font(.system(size: 9, weight: .medium))
                        .foregroundStyle(store.benchmark == key ? .primary : .tertiary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background { if store.benchmark == key { RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.07)).matchedGeometryEffect(id: "benchmark", in: selection) } }
                }.accessibilityLabel("Lifetime P&L versus \(key == "usd" ? "USD" : "holding")")
                    .accessibilityAddTraits(store.benchmark == key ? .isSelected : [])
            }
        }.help("Lifetime P&L benchmark for open positions")
    }
}
struct Dashboard: View {
    @ObservedObject var store: Store
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var ready: Bool { store.fetchedAt != nil || store.demo }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(store.demo ? "Example wallet" : "\(store.wallet.prefix(6))…\(store.wallet.suffix(4))").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                IconButton(symbol: "slider.horizontal.3", label: "Wallet and appearance") { store.settings() }
            }.padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline) {
                Text(ready ? money(store.pooled) : "—").font(.system(size: 30, weight: .regular)).tracking(-1.1).monospacedDigit()
                    .contentTransition(.numericText()).animation(reduceMotion ? nil : .smooth(duration: 0.35), value: store.pooled)
                    .accessibilityLabel("Pooled assets \(money(store.pooled))")
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Unclaimed").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(ready ? money(store.fees) : "—").font(.system(size: 13, weight: .medium)).monospacedDigit().contentTransition(.numericText())
                }
            }
            HStack(spacing: 5) {
                Text(ready ? money(store.pnl, signed: true) : "—").foregroundStyle(tone(store.pnl)).contentTransition(.numericText())
                Text("lifetime").foregroundStyle(.tertiary)
                Spacer()
                BenchmarkSwitch(store: store)
            }.font(.system(size: 10)).padding(.top, 7).padding(.bottom, 13)
            Rectangle().fill(.primary.opacity(0.09)).frame(height: 0.5)
            HStack {
                Text("Positions").foregroundStyle(.secondary)
                Text("\(store.positions.count)").foregroundStyle(.tertiary)
                Spacer()
                Text("Pooled / P&L").foregroundStyle(.tertiary)
            }.font(.system(size: 9)).padding(.top, 12).padding(.bottom, 4)
            ScrollView {
                VStack(spacing: 0) {
                    if store.positions.isEmpty {
                        HStack(spacing: 9) {
                            if store.loading { ProgressView().controlSize(.mini) }
                            Text(store.loading ? "Finding positions…" : store.error != nil ? "Positions unavailable" : "No active positions").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 32)
                    }
                    ForEach(store.positions) { p in
                        Button { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.selected = p.id } } label: { PositionRow(p: p, benchmark: store.benchmark) }
                    }
                }
            }.scrollIndicators(.hidden).frame(maxHeight: .infinity)
            Footer(store: store).padding(.top, 8)
        }.padding(.horizontal, 20).padding(.top, 11).padding(.bottom, 13)
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
                    Text(p.symbol0).foregroundStyle(.primary)
                    Text("/").foregroundStyle(.quaternary)
                    Text(p.symbol1).foregroundStyle(.secondary)
                }.font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack(spacing: 7) {
                    Text(p.network.capitalized).font(.system(size: 9)).foregroundStyle(.tertiary)
                    RangeBar(fraction: p.rangeFraction, active: p.in_range == true).frame(width: 56, height: 10)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                Text(money(p.underlying_value?.value)).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                Text(money(p.performance?[benchmark]?.pnl?.value, signed: true)).font(.system(size: 10)).foregroundStyle(tone(p.performance?[benchmark]?.pnl?.value)).contentTransition(.numericText())
            }.monospacedDigit()
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .medium)).foregroundStyle(.tertiary)
                .opacity(hover ? 1 : 0).offset(x: hover ? 0 : -3).frame(width: 6)
        }.padding(.vertical, 11).padding(.horizontal, 6)
            .background(.primary.opacity(hover ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle()).onHover { hover = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hover)
            .help("\(p.pair) · \(p.in_range == true ? "In range" : "Out of range or unknown") · Unclaimed \(money(p.unclaimed))")
    }
}
struct RangeBar: View {
    let fraction: Double?
    let active: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<21, id: \.self) { i in
                        Rectangle().fill(.primary.opacity(i % 5 == 0 ? 0.22 : 0.10)).frame(width: 1, height: i % 5 == 0 ? 7 : 4)
                        if i < 20 { Spacer(minLength: 0) }
                    }
                }
                if let fraction {
                    Capsule().fill(active ? gain : loss).frame(width: 2, height: 10)
                        .offset(x: max(0, (g.size.width - 2) * fraction))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: fraction)
                }
            }.frame(height: g.size.height)
        }.accessibilityLabel("\(active ? "In range" : "Out of range or unknown"). Current price marker")
    }
}
struct Footer: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let error = store.error { Text(error).font(.system(size: 9)).foregroundStyle(loss).lineLimit(2).help(error) }
            HStack(spacing: 5) {
                Circle().fill(store.error != nil ? loss : Color.primary.opacity(0.3)).frame(width: 3, height: 3)
                if store.demo { Text("Saved example · Sep 20") }
                else if let date = store.sourceDate {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("\(context.date.timeIntervalSince(date) > 300 ? "Stale · " : "")Revert · \(date.formatted(date: .omitted, time: .shortened))")
                    }
                } else { Text("Revert Finance") }
                Spacer()
                if store.loading { ProgressView().controlSize(.mini).scaleEffect(0.65).frame(width: 14, height: 14) }
                else if store.demo { Button("Use wallet") { store.settings() } }
                else { Button { store.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 9)).frame(width: 18, height: 14) }.help("Refresh positions").accessibilityLabel("Refresh positions") }
            }.font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}
struct DetailView: View {
    @ObservedObject var store: Store
    let p: Position
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { store.selected = nil } label: { HStack(spacing: 5) { Image(systemName: "chevron.left").font(.system(size: 9)); Text("Positions").font(.system(size: 10)) } }.foregroundStyle(.secondary)
                Spacer()
                Text("#\(p.nft_id.map(String.init) ?? "—")").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(p.pair).font(.system(size: 19, weight: .medium)).tracking(-0.5)
                        Text("\(p.network.capitalized) · \(p.exchange == "uniswapv4" ? "Uniswap v4" : p.exchange) · \(p.fee_tier.map { number(Decimal($0) / 10000) + "%" } ?? "—")").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    HStack { metric("Pooled", money(p.underlying_value?.value)); Spacer(); metric("Unclaimed", money(p.unclaimed), trailing: true) }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(p.in_range == true ? "In range" : "Out of range / unknown").foregroundStyle(p.in_range == true ? gain : loss)
                            Spacer(); Text("\(p.symbol1) / \(p.symbol0)").foregroundStyle(.tertiary)
                        }.font(.system(size: 9))
                        RangeBar(fraction: p.rangeFraction, active: p.in_range == true).frame(height: 15)
                        HStack { Text(number(p.price_lower?.value, digits: 3)); Spacer(); Text(number(p.pool_price?.value, digits: 3)).foregroundStyle(.primary); Spacer(); Text(number(p.price_upper?.value, digits: 3)) }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    }.padding(.vertical, 3)
                    Divider().opacity(0.5)
                    HStack { Text("Lifetime performance").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); BenchmarkSwitch(store: store) }
                    HStack {
                        metric("P&L", money(p.performance?[store.benchmark]?.pnl?.value, signed: true), color: tone(p.performance?[store.benchmark]?.pnl?.value))
                        Spacer(); metric("Pool P&L", money(p.performance?[store.benchmark]?.pool_pnl?.value, signed: true), trailing: true)
                    }
                    HStack {
                        metric("ROI", p.performance?[store.benchmark]?.roi.map { number($0.value) + "%" } ?? "—")
                        Spacer(); metric("Fee APR", p.performance?[store.benchmark]?.fee_apr.map { number($0.value) + "%" } ?? "—", trailing: true)
                    }
                    Text("\(number(p.age?.value, digits: 1)) days old · APR is annualized historical performance.").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Divider().opacity(0.5)
                    HStack { metric(p.symbol0, number(p.current_amount0?.value, digits: 4)); Spacer(); metric(p.symbol1, number(p.current_amount1?.value, digits: 4), trailing: true) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Pool").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Text(p.pool).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Autocompounding \(p.autocompounding == true ? "on" : p.autocompounding == false ? "off" : "unknown")").font(.system(size: 9)).foregroundStyle(.tertiary)
                }.padding(.bottom, 10)
            }.scrollIndicators(.hidden)
            Footer(store: store).padding(.top, 10)
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
    @ObservedObject var store: Store
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var appeared = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LumaMark().foregroundStyle(.secondary).offset(x: appeared || reduceMotion ? 0 : -4)
                Spacer()
                HStack(spacing: 4) { ForEach(0..<3) { i in Capsule().fill(.primary.opacity(store.step == i ? 0.55 : 0.1)).frame(width: store.step == i ? 13 : 4, height: 3) } }.accessibilityLabel("Step \(store.step + 1) of 3")
            }.padding(.bottom, 22)
            VStack(alignment: .leading, spacing: 9) {
                Text(store.step == 0 ? "Liquidity. At a glance." : store.step == 1 ? "Add your wallet." : "Set the tone.").font(.system(size: 23, weight: .medium)).tracking(-0.7)
                Text(store.step == 0 ? "Your positions, fees and P&L.\nA quiet place at the top of your Mac." : store.step == 1 ? "A public address is all you need. Revert reads your positions. No connection or signing." : "Follow your Mac or choose an appearance.\nHover to open. Click the strip to close.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }.id(store.step).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 4)))
            Group {
                if store.step == 1 {
                    VStack(alignment: .leading, spacing: 9) {
                        TextField("0x address", text: $store.wallet).font(.system(size: 11, design: .monospaced)).textFieldStyle(.plain).padding(10).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.08), lineWidth: 0.5))
                        Button("Use example wallet") { store.wallet = RevertClient.sampleWallet }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                } else if store.step == 2 {
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
                } else {
                    HStack(spacing: 16) {
                        RangeBar(fraction: 0.34, active: true).frame(width: 82, height: 14)
                        Text("Less checking. More focus.").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.accessibilityLabel("Illustration of a position range")
                }
            }.padding(.top, 20)
            Spacer(minLength: 8)
            if let error = store.error { Text(error).font(.system(size: 9)).foregroundStyle(loss).padding(.bottom, 8) }
            HStack {
                Button(store.step == 0 ? "Explore example" : "Back") {
                    if store.step == 0 { store.loadDemo() } else { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.step -= 1; store.error = nil } }
                }.foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.error = nil
                    if store.step == 1 && !RevertClient.valid(store.wallet.trimmingCharacters(in: .whitespacesAndNewlines)) { store.error = RevertError.invalidWallet.localizedDescription }
                    else if store.step < 2 { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.step += 1 } }
                    else { store.connect() }
                } label: {
                    HStack(spacing: 8) { Text(store.step == 2 ? "Open Luma" : "Continue"); Image(systemName: "arrow.right").font(.system(size: 9)) }
                        .padding(.horizontal, 13).padding(.vertical, 9).background(.primary.opacity(0.07), in: Capsule())
                }
            }.font(.system(size: 11, weight: .medium))
        }.padding(24).onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { appeared = true } }
    }
}
