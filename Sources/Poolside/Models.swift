import Foundation

/// Physical-pointer gate: layout-generated hover events cannot rearm a dismissed notch.
struct HoverGate {
    private(set) var suppressed = false
    private var enteredAt: TimeInterval?
    mutating func dismiss() { suppressed = true; enteredAt = nil }
    mutating func update(inside: Bool, now: TimeInterval) -> Bool {
        guard inside else { suppressed = false; enteredAt = nil; return false }
        guard !suppressed else { return false }
        guard let enteredAt else { self.enteredAt = now; return false }
        if now - enteredAt >= 0.18 { dismiss(); return true }
        return false
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
    let nft_id: Int?
    let network: String
    let exchange: String
    let pool: String
    let token0: String
    let token1: String
    let tokens: [String: Token]
    let underlying_value: Amount?
    let fees_value: Amount?
    let uncollected_fees0: Amount?
    let uncollected_fees1: Amount?
    let current_amount0: Amount?
    let current_amount1: Amount?
    let pool_price: Amount?
    let price_lower: Amount?
    let price_upper: Amount?
    let fee_tier: Int?
    let in_range: Bool?
    let exited: Bool?
    let now_ts: Double?
    let age: Amount?
    let autocompounding: Bool?
    let performance: [String: Performance]?
    var id: String { "\(network):\(exchange):\(pool):\(nft_id.map(String.init) ?? "unknown")" }
    func token(_ address: String) -> Token? { tokens.first { $0.key.lowercased() == address.lowercased() }?.value }
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
struct PriceRangeContext: Sendable {
    let domainLower: Double
    let domainUpper: Double
    let lowerFraction: Double
    let upperFraction: Double
    let currentFraction: Double
    init?(lower: Double, upper: Double, current: Double) {
        guard lower.isFinite, upper.isFinite, current.isFinite, lower >= 0, upper > lower, current >= 0 else { return nil }
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
struct Envelope: Decodable, Sendable {
    let success: Bool
    let data: [Position]?
    let pagination: Pagination?
    let exited_count: Int?
}
struct Pagination: Decodable, Sendable {
    let has_next: Bool
    let next_cursor: String?
    let total_count: Int?
}
enum RevertError: LocalizedError {
    case invalidWallet, rejected(Int), malformed, pagination, tooManyPages
    var errorDescription: String? {
        switch self {
        case .invalidWallet: "Enter a 0x address with 40 hexadecimal characters."
        case .rejected(let code): "Revert returned HTTP \(code). Try refreshing shortly."
        case .malformed: "Revert returned an unsupported response. Your previous data is preserved."
        case .pagination: "Revert pagination did not advance. The incomplete update was discarded."
        case .tooManyPages: "This wallet exceeds the prototype’s 100-page limit."
        }
    }
}
enum RevertClient {
    static let sampleWallet = "0x4c77ca7ff8e548806fdc88e4dfa8ea1e493a450a"
    static func valid(_ address: String) -> Bool { address.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil }
    static func url(wallet: String, cursor: String? = nil) throws -> URL {
        guard valid(wallet) else { throw RevertError.invalidWallet }
        var c = URLComponents(string: "https://api.revert.finance/v1/positions/account/\(wallet)")!
        c.queryItems = [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "active", value: "true"), URLQueryItem(name: "with-v4", value: "true"), URLQueryItem(name: "with-ekubo", value: "true")]
        if let cursor { c.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        return c.url!
    }
    static func fetch(wallet: String) async throws -> [Position] {
        var positions: [Position] = [], cursor: String?, seen = Set<String>()
        for _ in 0..<100 {
            var request = URLRequest(url: try url(wallet: wallet, cursor: cursor))
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw RevertError.rejected((response as? HTTPURLResponse)?.statusCode ?? 0) }
            let e = try JSONDecoder().decode(Envelope.self, from: data)
            guard e.success, let page = e.data, let pagination = e.pagination else { throw RevertError.malformed }
            positions += page
            if !pagination.has_next {
                var ids = Set<String>()
                return positions.filter { ids.insert($0.id).inserted }
            }
            guard let next = pagination.next_cursor, !next.isEmpty, seen.insert(next).inserted else { throw RevertError.pagination }
            cursor = next
        }
        throw RevertError.tooManyPages
    }
    static func sample() throws -> [Position] {
        #if SWIFT_PACKAGE
        let data = try Data(contentsOf: Bundle.module.url(forResource: "sample", withExtension: "json")!)
        #else
        let data = try Data(contentsOf: Bundle.main.url(forResource: "sample", withExtension: "json")!)
        #endif
        guard let positions = try JSONDecoder().decode(Envelope.self, from: data).data else { throw RevertError.malformed }
        return positions
    }
}
func total(_ values: [Decimal?]) -> Decimal? {
    guard values.allSatisfy({ $0 != nil }) else { return nil }
    return values.compactMap { $0 }.reduce(0, +)
}
func number(_ value: Decimal?, digits: Int = 2) -> String {
    guard let value else { return "—" }
    let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = digits; f.minimumFractionDigits = digits
    return f.string(from: NSDecimalNumber(decimal: value)) ?? "—"
}
func money(_ value: Decimal?, signed: Bool = false) -> String {
    guard let value else { return "—" }
    return (value < 0 ? "−" : signed && value > 0 ? "+" : "") + "$" + number(abs(value))
}
