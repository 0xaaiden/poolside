import Foundation
import CryptoKit

/// Developer-side issuing tool. Never ships in the app.
///   license.sh keys                       generate a signing keypair (prints the public key to embed)
///   license.sh issue <id> [YYYY-MM-DD]    issue a Pro key for a licensee, optionally expiring
///   license.sh verify <key>               verify a key against the embedded public key
@main struct LicenseTool {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let keyPath = ProcessInfo.processInfo.environment["POOLSIDE_SIGNING_KEY"] ?? ".license/private.key"
        switch args.first {
        case "keys":
            guard !FileManager.default.fileExists(atPath: keyPath) else { fail("\(keyPath) already exists. Delete it to rotate; existing keys will stop verifying.") }
            let key = Curve25519.Signing.PrivateKey()
            try FileManager.default.createDirectory(atPath: (keyPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try key.rawRepresentation.base64EncodedString().write(toFile: keyPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath)
            print("Private key written to \(keyPath) (keep it out of git; it is gitignored).")
            print("Public key, paste into License.publicKeyBase64:")
            print(key.publicKey.rawRepresentation.base64EncodedString())
        case "issue":
            guard args.count >= 2 else { fail("usage: license.sh issue <id> [YYYY-MM-DD]") }
            let key = try loadKey(keyPath)
            var exp: Double?
            if args.count >= 3 {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
                guard let date = f.date(from: args[2]) else { fail("expiry must be YYYY-MM-DD") }
                exp = date.timeIntervalSince1970
            }
            let payload = License.Payload(t: .pro, id: args[1], exp: exp, iat: Date().timeIntervalSince1970.rounded())
            let issued = try License.issue(payload, privateKey: key)
            guard case .success = License.verify(issued, publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()) else { fail("self-check failed") }
            if key.publicKey.rawRepresentation.base64EncodedString() != License.publicKeyBase64 {
                FileHandle.standardError.write(Data("warning: this signing key does not match License.publicKeyBase64 in the app; the app will reject this key.\n".utf8))
            }
            print(issued)
        case "verify":
            guard args.count == 2 else { fail("usage: license.sh verify <key>") }
            switch License.verify(args[1]) {
            case .success(let l): print("valid \(l.tier.title) license for \(l.payload.id)" + (l.expires.map { ", expires \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ", perpetual"))
            case .failure(let e): fail(e.localizedDescription)
            }
        default: fail("usage: license.sh keys | issue <id> [YYYY-MM-DD] | verify <key>")
        }
    }
    static func loadKey(_ path: String) throws -> Curve25519.Signing.PrivateKey {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { fail("no signing key at \(path); run license.sh keys") }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }
    static func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
}
