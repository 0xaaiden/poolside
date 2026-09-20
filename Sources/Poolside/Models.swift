import Foundation
import CoreGraphics

func topAnchoredFrame(size: CGSize, top: CGFloat, centerX: CGFloat) -> CGRect {
    CGRect(x: centerX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
}

/// Analytic damped spring. `response` is the undamped period; a damping fraction below 1 overshoots slightly.
/// The same parameters drive the native panel frame and the SwiftUI content so both move on one clock.
struct Spring: Sendable {
    static let panel = Spring(response: 0.34, dampingFraction: 0.86)
    /// Closing is quicker and critically damped: a strip that bounces reads as a glitch, not a flourish.
    static let panelClose = Spring(response: 0.24, dampingFraction: 1)
    let response: Double
    let dampingFraction: Double
    struct State: Equatable, Sendable {
        var value: Double
        var velocity: Double = 0
    }
    func state(from start: State, to target: Double, at t: Double) -> State {
        guard t > 0 else { return start }
        let w = 2 * .pi / response, z = dampingFraction
        let y0 = start.value - target, v0 = start.velocity
        let y: Double, dy: Double
        if z < 1 {
            let wd = w * (1 - z * z).squareRoot()
            let a = y0, b = (v0 + z * w * y0) / wd
            let e = exp(-z * w * t), c = cos(wd * t), s = sin(wd * t)
            y = e * (a * c + b * s)
            dy = e * ((wd * b - z * w * a) * c - (wd * a + z * w * b) * s)
        } else {
            let a = y0, b = v0 + w * y0
            let e = exp(-w * t)
            y = e * (a + b * t)
            dy = e * (b - w * (a + b * t))
        }
        return State(value: target + y, velocity: dy)
    }
    func settled(_ state: State, target: Double, tolerance: Double) -> Bool {
        abs(state.value - target) <= tolerance && abs(state.velocity) <= tolerance * 10
    }
}

/// Width, height and reveal progress share one spring segment. Retargeting mid-flight starts a new
/// segment from the current sampled position and velocity, so interruptions never jump.
struct PanelMotion: Sendable {
    struct Sample: Equatable, Sendable {
        var width: Spring.State
        var height: Spring.State
        var reveal: Spring.State
        init(width: Spring.State, height: Spring.State, reveal: Spring.State) { self.width = width; self.height = height; self.reveal = reveal }
        init(size: CGSize, reveal: Double) {
            width = Spring.State(value: size.width); height = Spring.State(value: size.height); self.reveal = Spring.State(value: reveal)
        }
        var size: CGSize { CGSize(width: width.value, height: height.value) }
    }
    static let timeout: Double = 2
    let spring: Spring
    let started: Double
    let start: Sample
    let targetSize: CGSize
    let targetReveal: Double
    init(spring: Spring = .panel, from start: Sample, to size: CGSize, reveal: Double, at time: Double) {
        self.spring = spring; self.start = start; targetSize = size; targetReveal = reveal; started = time
    }
    var target: Sample { Sample(size: targetSize, reveal: targetReveal) }
    func sample(at time: Double) -> Sample {
        let t = time - started
        return Sample(width: spring.state(from: start.width, to: targetSize.width, at: t),
                      height: spring.state(from: start.height, to: targetSize.height, at: t),
                      reveal: spring.state(from: start.reveal, to: targetReveal, at: t))
    }
    func settled(_ sample: Sample, at time: Double) -> Bool {
        time - started >= Self.timeout
            || (spring.settled(sample.width, target: targetSize.width, tolerance: 0.1)
                && spring.settled(sample.height, target: targetSize.height, tolerance: 0.1)
                && spring.settled(sample.reveal, target: targetReveal, tolerance: 0.001))
    }
}

/// Event-driven physical-pointer gate. Pointer movement arms or cancels a dwell timer; once the panel
/// opens, the gate stays closed until the pointer actually leaves, so layout-generated hover events
/// cannot reopen a dismissed notch. Nothing runs while the cursor is still.
struct HoverGate {
    enum Action: Equatable { case none, arm, cancel }
    private(set) var suppressed = false
    private(set) var armed = false
    mutating func dismiss() { suppressed = true; armed = false }
    mutating func moved(inside: Bool) -> Action {
        guard inside else {
            suppressed = false
            defer { armed = false }
            return armed ? .cancel : .none
        }
        guard !suppressed, !armed else { return .none }
        armed = true
        return .arm
    }
    /// Dwell elapsed. Opens once if the pointer is still inside, then suppresses until it leaves.
    mutating func dwellElapsed(inside: Bool) -> Bool {
        guard armed else { return false }
        armed = false
        guard inside else { return false }
        dismiss()
        return true
    }
}

/// Native port of bpierre/blo's MIT-licensed image/random algorithm. See THIRD_PARTY_NOTICES.md.
struct WalletIconData: Equatable {
    let pixels: [Int]
    let palette: [[Int]]
    init(address: String) {
        var seed = [UInt32](repeating: 0, count: 4)
        for (i, c) in address.lowercased().utf16.enumerated() { seed[i % 4] = seed[i % 4] &* 31 &+ UInt32(c) }
        func random() -> Double {
            let t = Int32(bitPattern: seed[0]) ^ (Int32(bitPattern: seed[0]) &<< 11)
            seed[0] = seed[1]; seed[1] = seed[2]; seed[2] = seed[3]
            let w = Int32(bitPattern: seed[3])
            seed[3] = UInt32(bitPattern: w ^ (w >> 19) ^ t ^ (t >> 8))
            return Double(seed[3]) / 2147483648
        }
        func color() -> [Int] {
            let h = random() * 360, s = 40 + random() * 60
            let l = (random() + random() + random() + random()) * 25
            return [Int(h), Int(s), Int(l)]
        }
        let main = color(), background = color(), spot = color()
        palette = [background, main, spot]
        pixels = (0..<32).map { _ in Int(random() * 2.3) }
    }
}

struct Amount: Decodable, Sendable {
    let value: Decimal
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")), !d.isNaN { value = d }
        else { value = try c.decode(Decimal.self) }
    }
}
/// Revert serializes integers as numbers for some protocols and as strings for others (fee_tier is
/// "100" on Uniswap v3 positions). Whole numbers are accepted in either form.
struct Whole: Decodable, Sendable, Equatable {
    let value: Int
    init(_ value: Int) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i; return }
        if let d = try? c.decode(Double.self), d.isFinite, d == d.rounded(), abs(d) < 9e15 { value = Int(d); return }
        let s = try c.decode(String.self).trimmingCharacters(in: .whitespaces)
        if let i = Int(s) { value = i; return }
        if let d = Double(s), d.isFinite, d == d.rounded(), abs(d) < 9e15 { value = Int(d); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected a whole number, got \(s)")
    }
}
/// Booleans may arrive as true/false, "true"/"false" or 0/1.
struct Flag: Decodable, Sendable, Equatable {
    let value: Bool
    init(_ value: Bool) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { value = b; return }
        if let i = try? c.decode(Int.self), i == 0 || i == 1 { value = i == 1; return }
        switch try c.decode(String.self).lowercased() {
        case "true", "1", "yes": value = true
        case "false", "0", "no": value = false
        case let other: throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected a boolean, got \(other)")
        }
    }
}
struct Token: Decodable, Sendable {
    let symbol: String?
    let name: String?
    let price: Amount?
    let decimals: Int?
}
struct Performance: Decodable, Sendable {
    let pnl: Amount?
    let pool_pnl: Amount?
    let roi: Amount?
    let apr: Amount?
    let fee_apr: Amount?
    let il: Amount?
}
struct Position: Decodable, Identifiable, Sendable {
    let nft_id: Whole?
    let network: String
    let exchange: String
    let pool: String
    let token0: String
    let token1: String
    let tokens: [String: Token]
    let underlying_value: Amount?
    /// Open: current value of unclaimed fees per Revert. Closed: value of all fees collected over the position's life.
    let fees_value: Amount?
    let deposits_value: Amount?
    let withdrawals_value: Amount?
    let total_withdrawn0: Amount?
    let total_withdrawn1: Amount?
    /// Last on-chain event for the position; for closed positions, the closing time.
    let ts: Amount?
    let first_mint_ts: Amount?
    let uncollected_fees0: Amount?
    let uncollected_fees1: Amount?
    let current_amount0: Amount?
    let current_amount1: Amount?
    let pool_price: Amount?
    let price_lower: Amount?
    let price_upper: Amount?
    let fee_tier: Whole?
    let in_range: Flag?
    let exited: Flag?
    let now_ts: Amount?
    let age: Amount?
    let autocompounding: Flag?
    let performance: [String: Performance]?
    var id: String { "\(network):\(exchange):\(pool):\(nft_id.map { String($0.value) } ?? "unknown")" }
    var inRange: Bool { in_range?.value == true }
    var closed: Bool { exited?.value == true }
    var sourceTimestamp: Double? { now_ts.map { NSDecimalNumber(decimal: $0.value).doubleValue } }
    var closedDate: Date? { closed ? ts.map { Date(timeIntervalSince1970: NSDecimalNumber(decimal: $0.value).doubleValue) } : nil }
    var openedDate: Date? { first_mint_ts.map { Date(timeIntervalSince1970: NSDecimalNumber(decimal: $0.value).doubleValue) } }
    /// Exact and lowercased keys hit the dictionary directly; the case-insensitive scan is the last resort.
    func token(_ address: String) -> Token? {
        if let t = tokens[address] { return t }
        let lower = address.lowercased()
        if let t = tokens[lower] { return t }
        return tokens.first { $0.key.lowercased() == lower }?.value
    }
    var symbol0: String { token(token0)?.symbol ?? String(token0.prefix(8)) }
    var symbol1: String { token(token1)?.symbol ?? String(token1.prefix(8)) }
    var pair: String { "\(symbol0) / \(symbol1)" }
    var unclaimed: Decimal? {
        guard let a = uncollected_fees0?.value, let b = uncollected_fees1?.value,
              let p = token(token0)?.price?.value, let q = token(token1)?.price?.value else { return nil }
        return a * p + b * q
    }
    var rangeFraction: Double? {
        guard let p = pool_price?.value, let l = price_lower?.value, let u = price_upper?.value, u > l else { return nil }
        return min(1, max(0, NSDecimalNumber(decimal: (p - l) / (u - l)).doubleValue))
    }
    var priceContext: PriceRangeContext? {
        guard let l = price_lower?.value, let u = price_upper?.value, let p = pool_price?.value else { return nil }
        return PriceRangeContext(lower: NSDecimalNumber(decimal: l).doubleValue,
                                 upper: NSDecimalNumber(decimal: u).doubleValue,
                                 current: NSDecimalNumber(decimal: p).doubleValue)
    }
}
/// Price axis adds half the LP width on each side, and includes an out-of-range spot price.
/// Full-range positions (bounds spanning more than nine orders of magnitude, as Uniswap's tick limits
/// produce) have no meaningful linear axis; they render as a band across the whole bar with the
/// marker centered.
struct PriceRangeContext: Sendable {
    let domainLower: Double
    let domainUpper: Double
    let lowerFraction: Double
    let upperFraction: Double
    let currentFraction: Double
    let fullRange: Bool
    init?(lower: Double, upper: Double, current: Double) {
        guard lower.isFinite, upper.isFinite, current.isFinite, lower >= 0, upper > lower, current >= 0 else { return nil }
        if lower == 0 || upper / lower >= 1e9 {
            domainLower = lower; domainUpper = upper
            lowerFraction = 0; upperFraction = 1; currentFraction = 0.5; fullRange = true
            return
        }
        fullRange = false
        let span = upper - lower
        let lo = max(0, min(lower - span * 0.5, current - span * 0.1))
        let hi = max(upper + span * 0.5, current + span * 0.1)
        guard hi.isFinite, hi > lo else { return nil }
        domainLower = lo; domainUpper = hi
        lowerFraction = (lower - lo) / (hi - lo)
        upperFraction = (upper - lo) / (hi - lo)
        currentFraction = (current - lo) / (hi - lo)
    }
}
/// Rows are decoded one at a time so a single position in an unexpected shape is skipped and counted
/// rather than failing the whole wallet.
struct Envelope: Decodable, Sendable {
    let success: Bool
    let data: [Position]?
    let skipped: Int
    let pagination: Pagination?
    let exited_count: Whole?
    private struct Blank: Decodable {}
    private enum Keys: String, CodingKey { case success, data, pagination, exited_count }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        success = try c.decode(Flag.self, forKey: .success).value
        pagination = try c.decodeIfPresent(Pagination.self, forKey: .pagination)
        exited_count = try c.decodeIfPresent(Whole.self, forKey: .exited_count)
        guard c.contains(.data), try !c.decodeNil(forKey: .data) else { data = nil; skipped = 0; return }
        var rows = try c.nestedUnkeyedContainer(forKey: .data)
        var positions: [Position] = [], skipped = 0
        while !rows.isAtEnd {
            if let position = try? rows.decode(Position.self) { positions.append(position) }
            else { _ = try? rows.decode(Blank.self); skipped += 1 }
        }
        data = positions; self.skipped = skipped
    }
}
struct Pagination: Decodable, Sendable {
    let has_next: Flag
    let next_cursor: String?
    let total_count: Whole?
}
enum RevertError: LocalizedError {
    case invalidWallet, rejected(Int), malformed, unsupported(String), pagination, tooManyPages
    var errorDescription: String? {
        switch self {
        case .invalidWallet: "Enter a 0x address with 40 hexadecimal characters."
        case .rejected(let code): "Revert returned HTTP \(code). Try refreshing shortly."
        case .malformed: "Revert returned an unsupported response. Your previous data is preserved."
        case .unsupported(let path): "Revert sent an unexpected value at ‘\(path)’. Your previous data is preserved."
        case .pagination: "Revert pagination did not advance. The incomplete update was discarded."
        case .tooManyPages: "This wallet exceeds the prototype’s 100-page limit."
        }
    }
}
enum RevertClient {
    static let sampleWallet = "0x4c77ca7ff8e548806fdc88e4dfa8ea1e493a450a"
    static func valid(_ address: String) -> Bool { address.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil }
    static func url(wallet: String, cursor: String? = nil, active: Bool = true) throws -> URL {
        guard valid(wallet) else { throw RevertError.invalidWallet }
        var c = URLComponents(string: "https://api.revert.finance/v1/positions/account/\(wallet)")!
        c.queryItems = [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "active", value: active ? "true" : "false"), URLQueryItem(name: "with-v4", value: "true"), URLQueryItem(name: "with-ekubo", value: "true")]
        if let cursor { c.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        return c.url!
    }
    struct Fetched: Sendable {
        let positions: [Position]
        /// Rows Revert returned that could not be read. Shown as a notice, not an error.
        let skipped: Int
    }
    static func decode(_ data: Data) throws -> Envelope {
        do { return try JSONDecoder().decode(Envelope.self, from: data) }
        catch let error as DecodingError {
            let context: DecodingError.Context? = switch error {
            case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c), .dataCorrupted(let c): c
            @unknown default: nil
            }
            let path = context?.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".") ?? ""
            throw path.isEmpty ? RevertError.malformed : RevertError.unsupported(path)
        }
    }
    /// `active: false` returns exited positions with deposits, withdrawals and collected fees filled in.
    static func fetch(wallet: String, active: Bool = true) async throws -> Fetched {
        var positions: [Position] = [], cursor: String?, seen = Set<String>(), skipped = 0
        for _ in 0..<100 {
            var request = URLRequest(url: try url(wallet: wallet, cursor: cursor, active: active))
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw RevertError.rejected((response as? HTTPURLResponse)?.statusCode ?? 0) }
            let e = try decode(data)
            guard e.success, let page = e.data, let pagination = e.pagination else { throw RevertError.malformed }
            positions += page; skipped += e.skipped
            if !pagination.has_next.value {
                var ids = Set<String>()
                return Fetched(positions: positions.filter { ids.insert($0.id).inserted }, skipped: skipped)
            }
            guard let next = pagination.next_cursor, !next.isEmpty, seen.insert(next).inserted else { throw RevertError.pagination }
            cursor = next
        }
        throw RevertError.tooManyPages
    }
    static func sample(closed: Bool = false) throws -> [Position] {
        let name = closed ? "sample-closed" : "sample"
        #if SWIFT_PACKAGE
        let data = try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json")!)
        #else
        let data = try Data(contentsOf: Bundle.main.url(forResource: name, withExtension: "json")!)
        #endif
        guard let positions = try decode(data).data else { throw RevertError.malformed }
        return positions
    }
}
/// A sum over positions. `complete` is false when at least one input was missing; `value` is nil only
/// when nothing at all was available. An empty portfolio sums to zero.
struct Sum: Equatable, Sendable {
    var value: Decimal?
    var complete: Bool
    static let unavailable = Sum(value: nil, complete: true)
}
func total(_ values: [Decimal?]) -> Sum {
    let present = values.compactMap { $0 }
    let value: Decimal? = values.isEmpty ? 0 : present.isEmpty ? nil : present.reduce(0, +)
    return Sum(value: value, complete: present.count == values.count)
}
/// Portfolio aggregates, computed once per positions update instead of on every view evaluation.
struct Totals: Equatable, Sendable {
    static let benchmarks = ["usd", "hodl"]
    let pooled: Sum
    let fees: Sum
    let pnl: [String: Sum]
    init(_ positions: [Position]) {
        pooled = total(positions.map { $0.underlying_value?.value })
        fees = total(positions.map(\.unclaimed))
        var pnl: [String: Sum] = [:]
        for key in Self.benchmarks { pnl[key] = total(positions.map { $0.performance?[key]?.pnl?.value }) }
        self.pnl = pnl
    }
}
/// Aggregates for exited positions. Withdrawn is what came back out, collected is lifetime fees
/// realized, and P&L is Revert's lifetime figure per benchmark.
struct ClosedTotals: Equatable, Sendable {
    let withdrawn: Sum
    let collected: Sum
    let pnl: [String: Sum]
    init(_ positions: [Position]) {
        withdrawn = total(positions.map { $0.withdrawals_value?.value })
        collected = total(positions.map { $0.fees_value?.value })
        var pnl: [String: Sum] = [:]
        for key in Totals.benchmarks + ["eth"] { pnl[key] = total(positions.map { $0.performance?[key]?.pnl?.value }) }
        self.pnl = pnl
    }
}
/// The tracked wallets and which one is showing. Addresses are compared case-insensitively; the
/// first-typed casing is kept for display. Migrates the original single "wallet" default.
struct WalletBook: Equatable, Sendable {
    static let walletsKey = "wallets", activeKey = "wallet"
    private(set) var wallets: [String] = []
    private(set) var active: String?
    init() {}
    init(wallets: [String], active: String?) {
        for w in wallets { _ = add(w, limit: Int.max) }
        self.active = nil
        if let active { select(active) }
        if self.active == nil { self.active = self.wallets.first }
    }
    static func load(from defaults: UserDefaults = .standard) -> WalletBook {
        let saved = defaults.stringArray(forKey: walletsKey) ?? []
        let legacy = defaults.string(forKey: activeKey)
        return WalletBook(wallets: saved.isEmpty ? [legacy].compactMap { $0 } : saved, active: legacy)
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(wallets, forKey: Self.walletsKey)
        if let active { defaults.set(active, forKey: Self.activeKey) } else { defaults.removeObject(forKey: Self.activeKey) }
    }
    func contains(_ address: String) -> Bool { wallets.contains { $0.lowercased() == address.lowercased() } }
    var isEmpty: Bool { wallets.isEmpty }
    enum AddResult: Equatable { case added, selectedExisting, invalid, full }
    /// Adds and selects. An address already in the book is selected instead; over the limit is refused.
    @discardableResult mutating func add(_ raw: String, limit: Int) -> AddResult {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RevertClient.valid(address) else { return .invalid }
        if let existing = wallets.first(where: { $0.lowercased() == address.lowercased() }) { active = existing; return .selectedExisting }
        guard wallets.count < limit else { return .full }
        wallets.append(address); active = address
        return .added
    }
    mutating func remove(_ address: String) {
        wallets.removeAll { $0.lowercased() == address.lowercased() }
        if active?.lowercased() == address.lowercased() { active = wallets.first }
    }
    mutating func select(_ address: String) {
        if let existing = wallets.first(where: { $0.lowercased() == address.lowercased() }) { active = existing }
    }
}
/// NumberFormatter construction is expensive; formatters are immutable after setup and thread-safe to read.
private final class Formatters: @unchecked Sendable {
    static let shared = Formatters()
    private let lock = NSLock()
    private var decimal: [Int: NumberFormatter] = [:]
    func decimal(digits: Int) -> NumberFormatter {
        lock.lock(); defer { lock.unlock() }
        if let f = decimal[digits] { return f }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = digits; f.minimumFractionDigits = digits
        decimal[digits] = f
        return f
    }
}
func number(_ value: Decimal?, digits: Int = 2) -> String {
    guard let value else { return "—" }
    return Formatters.shared.decimal(digits: digits).string(from: NSDecimalNumber(decimal: value)) ?? "—"
}
/// Prices beyond any plausible token value come from full-range tick limits; print them as ∞ rather
/// than a forty-digit number.
func price(_ value: Decimal?, digits: Int = 3) -> String {
    guard let value else { return "—" }
    if value >= Decimal(string: "1e30")! { return "∞" }
    return number(value, digits: digits)
}
func money(_ value: Decimal?, signed: Bool = false) -> String {
    guard let value else { return "—" }
    return (value < 0 ? "−" : signed && value > 0 ? "+" : "") + "$" + number(abs(value))
}
/// Partial sums are marked with ≈ rather than blanking the whole figure.
func money(_ sum: Sum, signed: Bool = false) -> String {
    (sum.complete || sum.value == nil ? "" : "≈") + money(sum.value, signed: signed)
}
