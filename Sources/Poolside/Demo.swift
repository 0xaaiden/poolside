import AppKit
import QuartzCore
import SwiftUI

/// Scripted walkthrough for recordings. Active only when `POOLSIDE_DEMO_FIXTURE` names a positions
/// envelope on disk: the app then shows that data for the launch arguments' wallet, makes no network
/// requests, plays a fixed timeline and quits. Nothing here runs in a normal launch, and the wallet
/// book is never written.
///
/// Optional environment:
/// - `POOLSIDE_DEMO_CLOSED`: a closed-positions envelope for the Closed tab beat.
/// - `POOLSIDE_DEMO_CLOCK`: a file that receives the host time (CACurrentMediaTime) the timeline
///   starts at, so a recorder can align captured frames and a rendered pointer to `steps` exactly.
@MainActor enum DemoRecording {
    static var fixture: String? { ProcessInfo.processInfo.environment["POOLSIDE_DEMO_FIXTURE"] }
    /// Seconds from timeline start. Recording/compositing tools mirror these values.
    static let timeline: [(Double, String)] = [
        (1.2, "expand"), (2.8, "hodl"), (3.6, "eth"), (4.4, "usd"), (5.4, "detail"), (8.4, "back"),
        (9.2, "closed"), (10.8, "open"), (11.6, "mask"), (12.8, "unmask"), (13.6, "collapse"), (15.0, "quit"),
    ]
    static func start(store: Store) {
        guard let fixture else { return }
        let env = ProcessInfo.processInfo.environment
        Task {
            store.polling?.cancel(); store.refreshTask?.cancel(); store.closedTask?.cancel()
            store.requestID = UUID(); store.loading = false
            let wasMasked = store.masked
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: fixture))
                store.positions = try RevertClient.decode(data).data ?? []
                store.fetchedAt = Date(); store.error = nil; store.notice = nil; store.onboarding = false; store.selected = nil
                if let closed = env["POOLSIDE_DEMO_CLOSED"] {
                    store.closed = try RevertClient.decode(Data(contentsOf: URL(fileURLWithPath: closed))).data ?? []
                    store.closedFetchedAt = Date()
                }
                if wasMasked { store.masked = false }
            } catch { store.error = error.localizedDescription }
            let motion = Animation.spring(response: Spring.panel.response, dampingFraction: Spring.panel.dampingFraction)
            @MainActor func act(_ name: String) {
                switch name {
                case "expand": store.expand(true)
                case "hodl", "eth", "usd": withAnimation(motion) { store.benchmark = name }
                case "detail": withAnimation(motion) { store.selected = store.positions.first?.id }
                case "back": withAnimation(motion) { store.selected = nil }
                case "closed": withAnimation(motion) { store.showClosed = true }
                case "open": withAnimation(motion) { store.showClosed = false }
                case "mask": store.masked = true
                case "unmask": store.masked = false
                case "collapse": store.expand(false)
                case "quit": store.masked = wasMasked; NSApp.terminate(nil)
                default: break
                }
            }
            // Deadlines are absolute so sleep latency does not accumulate across steps.
            let start = ContinuousClock.now
            if let path = env["POOLSIDE_DEMO_CLOCK"] {
                try? String(CACurrentMediaTime()).write(toFile: path, atomically: true, encoding: .utf8)
            }
            for (at, name) in timeline {
                try? await Task.sleep(until: start + .seconds(at), tolerance: .milliseconds(2), clock: .continuous)
                act(name)
            }
        }
    }
}
