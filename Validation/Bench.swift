import AppKit
import SwiftUI

/// Offscreen layout benchmark for the dashboard with a large wallet. Builds the real IslandView in
/// an NSHostingView, then times the first layout after data arrives, a data refresh, a burst of frame
/// resizes like the ones the panel spring produces, and a collapse/expand cycle. Run with bench.sh.
@main struct Bench {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let positions = try RevertClient.decode(data).data ?? []
        let store = Store()
        store.onboarding = false
        let clock = ContinuousClock()
        let host = NSHostingView(rootView: IslandView(store: store, cameraWidth: 180, topHeight: 32))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 332), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 332)
        store.expanded = true; store.revealProgress = 1
        func pass() { host.layoutSubtreeIfNeeded(); host.display() }
        pass()
        let first = clock.measure { store.positions = positions; pass() }
        print("positions: \(positions.count)")
        print("first layout after data:     \(ms(first)) ms")
        let refresh = clock.measure { store.positions = positions; pass() }
        print("relayout after refresh:      \(ms(refresh)) ms")
        let frames = clock.measure {
            for i in 0..<60 {
                let t = Double(i) / 59
                store.revealProgress = t
                host.frame = NSRect(x: 0, y: 0, width: 340 + 60 * t, height: 36 + 296 * t)
                pass()
            }
        }
        print("60 spring frames:            \(ms(frames)) ms  (\(ms(frames) / 60) ms per frame)")
        let toggle = clock.measure { store.expanded = false; pass(); store.expanded = true; pass() }
        print("collapse + expand:           \(ms(toggle)) ms")
    }
    static func ms(_ d: Duration) -> Double { (Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15).rounded() }
}
