import Foundation
import CryptoKit

/// Free and Pro. Free is the complete read-only tracker; Pro adds convenience and depth.
enum Tier: String, Codable, Sendable, Equatable {
    case free, pro
    var title: String { self == .pro ? "Pro" : "Free" }
}

/// Everything the UI gates on. Derived from the active tier in one place so adding a feature is a
/// single line here and a single `store.entitlements.x` check at the call site.
struct Entitlements: Equatable, Sendable {
    let tier: Tier
    /// Lifetime P&L benchmarks offered in the switch. Revert supplies usd, hodl, eth, token0, token1.
    let benchmarks: [String]
    /// Seconds between automatic refreshes while healthy.
    let refreshInterval: Int
    let launchAtLogin: Bool
    let outOfRangeAlerts: Bool
    let maxWallets: Int
    /// Closed positions with realized P&L, withdrawals and collected fees.
    let closedPositions: Bool
    init(tier: Tier) {
        self.tier = tier
        switch tier {
        case .free:
            benchmarks = ["usd", "hodl"]; refreshInterval = 60; launchAtLogin = false; outOfRangeAlerts = false; maxWallets = 1; closedPositions = false
        case .pro:
            benchmarks = ["usd", "hodl", "eth", "token0", "token1"]; refreshInterval = 15; launchAtLogin = true; outOfRangeAlerts = true; maxWallets = 5; closedPositions = true
        }
    }
}

/// Offline-verifiable license. A key is `POOLSIDE-<payload>-<signature>` where both parts are
/// base64url without padding, the payload is compact JSON and the signature is Ed25519 over the
/// payload bytes. Verification needs only the embedded public key: no server, no network, no account.
struct License: Equatable, Sendable {
    struct Payload: Codable, Equatable, Sendable {
        /// Tier granted.
        let t: Tier
        /// Licensee identifier, typically an email or order number. Shown in settings.
        let id: String
        /// Expiry as Unix seconds. Absent means perpetual.
        let exp: Double?
        /// Issue time as Unix seconds.
        let iat: Double
    }
    enum Failure: LocalizedError, Equatable {
        case format, signature, expired(Date)
        var errorDescription: String? {
            switch self {
            case .format: "That doesn’t look like a Poolside key. Keys start with POOLSIDE- and have three parts."
            case .signature: "This key was not issued by Poolside or has been altered."
            case .expired(let date): "This key expired on \(date.formatted(date: .abbreviated, time: .omitted))."
            }
        }
    }
    /// Ed25519 public key for keys issued by `license.sh`. Replace when rotating; old keys stop verifying.
    static let publicKeyBase64 = "BWxiK7baPlIaHFKwLf1MNMH+uySv84YDD6Q7ksy+x5A="
    static let prefix = "POOLSIDE"
    static let defaultsKey = "license"

    let payload: Payload
    let key: String
    var tier: Tier { payload.t }
    var expires: Date? { payload.exp.map(Date.init(timeIntervalSince1970:)) }

    /// Parses and verifies. Whitespace and line breaks inside a pasted key are ignored.
    static func verify(_ raw: String, publicKeyBase64: String = publicKeyBase64, now: Date = Date()) -> Result<License, Failure> {
        let key = raw.filter { !$0.isWhitespace }
        let parts = key.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0].uppercased() == prefix,
              let payloadData = base64url(parts[1]), let signature = base64url(parts[2]),
              let keyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { return .failure(.format) }
        guard publicKey.isValidSignature(signature, for: payloadData) else { return .failure(.signature) }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: payloadData) else { return .failure(.format) }
        if let exp = payload.exp, now.timeIntervalSince1970 >= exp { return .failure(.expired(Date(timeIntervalSince1970: exp))) }
        return .success(License(payload: payload, key: "\(prefix)-\(parts[1])-\(parts[2])"))
    }
    /// Signs a payload. Used by the issuing tool and by tests; the app never holds a private key.
    static func issue(_ payload: Payload, privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        let signature = try privateKey.signature(for: data)
        return "\(prefix)-\(base64url(data))-\(base64url(signature))"
    }
    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "_").replacingOccurrences(of: "/", with: ".").replacingOccurrences(of: "=", with: "")
    }
    static func base64url(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "_", with: "+").replacingOccurrences(of: ".", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
    /// Loads the saved key and re-verifies it, so an expired or tampered key silently drops to Free.
    static func load(from defaults: UserDefaults = .standard, now: Date = Date()) -> License? {
        guard let saved = defaults.string(forKey: defaultsKey) else { return nil }
        return try? verify(saved, now: now).get()
    }
    func save(to defaults: UserDefaults = .standard) { defaults.set(key, forKey: Self.defaultsKey) }
    static func clear(from defaults: UserDefaults = .standard) { defaults.removeObject(forKey: defaultsKey) }
}
