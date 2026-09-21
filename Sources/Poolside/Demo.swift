import AppKit
import SwiftUI

/// Scripted walkthrough for recordings. Active only when `POOLSIDE_DEMO_FIXTURE` names a positions
/// envelope on disk: the app then shows that data for the launch arguments' wallet, makes no network
/// requests, plays a fixed timeline (expand, open a position, switch benchmark, collapse) and quits.
/// Nothing here runs in a normal launch, and the wallet book is never written.
@MainActor enum DemoRecording {
    static var fixture: String? { ProcessInfo.processInfo.environment["POOLSIDE_DEMO_FIXTURE"] }
    static func start(store: Store) {
        guard let fixture else { return }
        Task {
            store.polling?.cancel(); store.refreshTask?.cancel(); store.closedTask?.cancel()
            store.requestID = UUID(); store.loading = false
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: fixture))
                store.positions = try RevertClient.decode(data).data ?? []
                store.fetchedAt = Date(); store.error = nil; store.notice = nil; store.onboarding = false; store.selected = nil
            } catch { store.error = error.localizedDescription }
            let motion = Animation.spring(response: Spring.panel.response, dampingFraction: Spring.panel.dampingFraction)
            let steps: [(Double, @MainActor () -> Void)] = [
                (1.4, { store.expand(true) }),
                (4.2, { withAnimation(motion) { store.selected = store.positions.first?.id } }),
                (7.6, { withAnimation(motion) { store.selected = nil } }),
                (8.8, { withAnimation(motion) { store.benchmark = "hodl" } }),
                (10.0, { withAnimation(motion) { store.benchmark = "usd" } }),
                (11.0, { store.expand(false) }),
                (12.6, { NSApp.terminate(nil) }),
            ]
            var elapsed = 0.0
            for (at, action) in steps {
                try? await Task.sleep(for: .seconds(at - elapsed)); elapsed = at
                action()
            }
        }
    }
}
