import Foundation

@main struct Check {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let e = try JSONDecoder().decode(Envelope.self, from: data)
        let positions = try require(e.data)
        assert(e.success && positions.count == 2)
        assert(Set(positions.map(\.id)).count == 2)
        assert(number(total(positions.map { $0.underlying_value?.value })) == "1,867.45")
        assert(number(total(positions.map(\.unclaimed))) == "140.71")
        assert(number(total(positions.map { $0.performance?["usd"]?.pnl?.value })) == "119.69")
        assert(number(total(positions.map { $0.performance?["hodl"]?.pnl?.value })) == "143.50")
        assert(positions.allSatisfy { $0.rangeFraction != nil && $0.rangeFraction! > 0 && $0.rangeFraction! < 1 })
        let context = try require(PriceRangeContext(lower: 100, upper: 200, current: 150))
        assert(context.domainLower == 50 && context.domainUpper == 250)
        assert(context.lowerFraction == 0.25 && context.upperFraction == 0.75 && context.currentFraction == 0.5)
        let below = try require(PriceRangeContext(lower: 100, upper: 200, current: 20))
        assert(below.currentFraction < below.lowerFraction && below.currentFraction > 0)
        let above = try require(PriceRangeContext(lower: 100, upper: 200, current: 300))
        assert(above.currentFraction > above.upperFraction && above.currentFraction < 1)
        let nearZero = try require(PriceRangeContext(lower: 1, upper: 5, current: 0))
        assert(nearZero.domainLower == 0 && nearZero.currentFraction == 0)
        assert(PriceRangeContext(lower: 1, upper: 1, current: 1) == nil)
        assert(PriceRangeContext(lower: 1, upper: 2, current: .infinity) == nil)
        assert(RevertClient.valid(RevertClient.sampleWallet))
        assert(!RevertClient.valid("0x123"))
        assert(!RevertClient.valid("0x" + String(repeating: "g", count: 40)))
        assert(total([Decimal(1), nil]) == nil)
        assert(money(nil) == "—")
        for value in ["\"1.125\"", "1.125"] {
            let amount = try JSONDecoder().decode(Amount.self, from: Data(value.utf8))
            assert(amount.value == Decimal(string: "1.125"))
        }
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var rows = json["data"] as! [[String: Any]]
        rows[0].removeValue(forKey: "underlying_value")
        rows[0]["performance"] = NSNull()
        rows[0]["uncollected_fees0"] = NSNull()
        json["data"] = rows
        let missing = try JSONDecoder().decode(Envelope.self, from: JSONSerialization.data(withJSONObject: json))
        assert(missing.data![0].underlying_value == nil)
        assert(missing.data![0].performance == nil)
        assert(missing.data![0].unclaimed == nil)
        let url = try RevertClient.url(wallet: RevertClient.sampleWallet, cursor: "1789447492_2726168")
        assert(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.contains(URLQueryItem(name: "cursor", value: "1789447492_2726168")))
        print("PASS: fixture decoding, exact totals, P&L benchmarks, mixed numeric types, missing fields, ranges, wallet validation, cursor encoding.")
    }
    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw RevertError.malformed }; return value
    }
}
