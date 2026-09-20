import AppKit
import Observation

/// Token icons through Revert's Codex proxy. Rows ask for an icon by network and address; the
/// requests that arrive within a few milliseconds are folded into one POST, results are cached in
/// memory and on disk, and a token the proxy does not know keeps its monogram without asking again.
/// Only the tokens of positions actually on screen are ever requested.
@Observable @MainActor final class TokenIcons {
    static let shared = TokenIcons()
    /// Codex network ids for Revert network names. Unknown networks keep the monogram fallback.
    nonisolated static let networkIDs: [String: Int] = [
        "mainnet": 1, "ethereum": 1, "optimism": 10, "bnb": 56, "unichain": 130, "polygon": 137, "sonic": 146,
        "zksync": 324, "robinhood": 4663, "base": 8453, "arbitrum": 42161, "celo": 42220, "avalanche": 43114,
        "linea": 59144, "berachain": 80094, "blast": 81457, "scroll": 534352,
    ]
    nonisolated static let endpoint = URL(string: "https://api.revert.finance/v1/proxy/codex-icons")!
    /// The proxy only answers requests that present Revert's own origin.
    nonisolated static let origin = "https://revert.finance"
    /// Icons above this many bytes are not plausible 32-pixel token marks and are discarded.
    nonisolated static let maxBytes = 512 * 1024

    private(set) var images: [String: NSImage] = [:]
    private enum State { case queued, loading, missing }
    @ObservationIgnored private var states: [String: State] = [:]
    @ObservationIgnored private var queue: [(key: String, network: String, address: String)] = []
    @ObservationIgnored private var flush: Task<Void, Never>?
    @ObservationIgnored private let directory: URL?

    init(directory: URL? = TokenIcons.defaultDirectory) {
        self.directory = directory
    }
    static var defaultDirectory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Poolside").appendingPathComponent("TokenIcons")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func key(_ network: String, _ address: String) -> String { "\(network):\(address.lowercased())" }

    /// The cached image, or nil while it loads. Calling this from a view body is fine: it only
    /// schedules work and never changes observed state synchronously.
    func image(network: String, address: String) -> NSImage? {
        let key = Self.key(network, address)
        if let image = images[key] { return image }
        if states[key] == nil, Self.networkIDs[network] != nil {
            states[key] = .queued
            queue.append((key, network, address))
            scheduleFlush()
        }
        return nil
    }
    private func scheduleFlush() {
        guard flush == nil else { return }
        flush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard let self else { return }
            flush = nil
            await drain()
        }
    }
    private func drain() async {
        let batch = queue; queue.removeAll()
        guard !batch.isEmpty else { return }
        var remaining: [(key: String, network: String, address: String)] = []
        for item in batch {
            if let image = Self.loadFromDisk(key: item.key, in: directory) { images[item.key] = image; states[item.key] = nil }
            else { states[item.key] = .loading; remaining.append(item) }
        }
        guard !remaining.isEmpty else { return }
        let ids = remaining.map { Request.ID(address: $0.address.lowercased(), networkId: Self.networkIDs[$0.network] ?? 0) }
        guard let urls = await Self.lookup(ids) else {
            // Network or proxy failure: forget these so the next scroll or refresh asks again.
            for item in remaining { states[item.key] = nil }
            return
        }
        var downloads: [(key: String, url: URL)] = []
        for item in remaining {
            if let url = urls["\(Self.networkIDs[item.network] ?? 0):\(item.address.lowercased())"] { downloads.append((item.key, url)) }
            else { states[item.key] = .missing }
        }
        let fetched = await Self.download(downloads)
        for item in downloads {
            if let data = fetched[item.key], let image = NSImage(data: data) {
                images[item.key] = image; states[item.key] = nil
                Self.saveToDisk(data, key: item.key, in: directory)
            } else { states[item.key] = .missing }
        }
    }

    struct Request: Encodable { struct ID: Encodable { let address: String; let networkId: Int }; let ids: [ID] }
    private struct Response: Decodable {
        struct Token: Decodable { struct Info: Decodable { let imageSmallUrl: String? }; let address: String; let networkId: Int; let info: Info? }
        struct Payload: Decodable { let tokens: [Token] }
        let success: Bool
        let data: Payload?
    }
    /// One POST for the whole batch. Returns image URLs keyed by "networkId:address"; nil when the
    /// request itself failed, as opposed to succeeding with tokens the proxy does not know.
    nonisolated static func lookup(_ ids: [Request.ID]) async -> [String: URL]? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        guard let body = try? JSONEncoder().encode(Request(ids: ids)) else { return nil }
        request.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let decoded = try? JSONDecoder().decode(Response.self, from: data), decoded.success else { return nil }
        var result: [String: URL] = [:]
        for token in decoded.data?.tokens ?? [] {
            guard let text = token.info?.imageSmallUrl, let url = URL(string: text), url.scheme == "https" else { continue }
            result["\(token.networkId):\(token.address.lowercased())"] = url
        }
        return result
    }
    /// Downloads a few images at a time so a wallet with many tokens does not open dozens of connections.
    nonisolated static func download(_ items: [(key: String, url: URL)]) async -> [String: Data] {
        var result: [String: Data] = [:]
        await withTaskGroup(of: (String, Data?).self) { group in
            var iterator = items.makeIterator()
            var running = 0
            func start(_ item: (key: String, url: URL)) {
                group.addTask {
                    var request = URLRequest(url: item.url); request.timeoutInterval = 20
                    guard let (data, response) = try? await URLSession.shared.data(for: request),
                          (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                          data.count <= maxBytes else { return (item.key, nil) }
                    return (item.key, data)
                }
            }
            while running < 6, let item = iterator.next() { start(item); running += 1 }
            for await (key, data) in group {
                if let data { result[key] = data }
                if let item = iterator.next() { start(item) }
            }
        }
        return result
    }
    nonisolated static func fileName(for key: String) -> String {
        key.map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) } + ".img"
    }
    nonisolated static func loadFromDisk(key: String, in directory: URL?) -> NSImage? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(fileName(for: key))) else { return nil }
        return NSImage(data: data)
    }
    nonisolated static func saveToDisk(_ data: Data, key: String, in directory: URL?) {
        guard let directory else { return }
        try? data.write(to: directory.appendingPathComponent(fileName(for: key)), options: .atomic)
    }
}
