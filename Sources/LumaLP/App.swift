import SwiftUI
import AppKit
import QuartzCore

@MainActor final class Store: ObservableObject {
    @Published var positions: [Position] = []
    @Published var loading = false
    @Published var error: String?
    @Published var demo = false
    @Published var fetchedAt: Date?
    @Published var wallet = UserDefaults.standard.string(forKey: "wallet") ?? ""
    @Published var onboarding = UserDefaults.standard.string(forKey: "wallet") == nil
    @Published var step = 0
    @Published var expanded = true
    @Published var selected: String? { didSet { resize?() } }
    @Published var benchmark = "usd"
    @Published var theme = UserDefaults.standard.string(forKey: "theme") ?? "system" {
        didSet { UserDefaults.standard.set(theme, forKey: "theme") }
    }
    var resize: (() -> Void)?
    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var refreshTask: Task<Void, Never>?
    var requestID = UUID()
    var polling: Task<Void, Never>?
    var pooled: Decimal? { total(positions.map { $0.underlying_value?.value }) }
    var fees: Decimal? { total(positions.map(\.unclaimed)) }
    var pnl: Decimal? { total(positions.map { $0.performance?[benchmark]?.pnl?.value }) }
    var scheme: ColorScheme? { theme == "system" ? nil : theme == "dark" ? .dark : .light }
    var sourceDate: Date? { positions.compactMap(\.now_ts).min().map(Date.init(timeIntervalSince1970:)) }
    func expand(_ value: Bool) {
        guard expanded != value else { resize?(); return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { expanded = value }
        resize?()
    }
    func loadDemo() {
        requestID = UUID()
        refreshTask?.cancel(); polling?.cancel(); loading = false
        do { positions = try RevertClient.sample(); demo = true; onboarding = false; error = nil; fetchedAt = nil; selected = nil; expand(true) }
        catch { self.error = error.localizedDescription }
    }
    func connect() {
        wallet = wallet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RevertClient.valid(wallet) else { error = RevertError.invalidWallet.localizedDescription; return }
        positions = []; selected = nil; fetchedAt = nil; demo = false; onboarding = false
        UserDefaults.standard.set(wallet, forKey: "wallet"); expand(true); refresh(); startPolling()
    }
    func refresh() {
        guard !demo, !loading, RevertClient.valid(wallet) else { return }
        loading = true; error = nil
        let id = UUID(); requestID = id
        let requestedWallet = wallet
        refreshTask = Task {
            defer { if requestID == id { loading = false } }
            do {
                let values = try await RevertClient.fetch(wallet: requestedWallet)
                guard !Task.isCancelled, requestedWallet == wallet, !demo else { return }
                positions = values; fetchedAt = Date()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
    func startPolling() {
        polling?.cancel()
        polling = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(error == nil ? 60 : 180))
                if !Task.isCancelled { refresh() }
            }
        }
    }
    func settings() {
        requestID = UUID()
        refreshTask?.cancel(); polling?.cancel(); loading = false
        onboarding = true; step = 1; error = nil; expand(true)
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var panel: IslandPanel!
    var status: NSStatusItem!
    var screenObserver: NSObjectProtocol?
    var hosting: NSHostingView<IslandView>?
    var screen: NSScreen { NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0] }
    var cameraWidth: CGFloat {
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea { return r.minX - l.maxX }
        return 160
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        store.resize = { [weak self] in self?.layout(animated: true) }
        layout(); panel.orderFrontRegardless()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Luma LP")
        let menu = NSMenu()
        for (title, action, key) in [("Show Luma LP", #selector(show), ""), ("Wallet & appearance…", #selector(settings), ","), ("Quit Luma LP", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        status.menu = menu
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.layout() } }
        if !store.onboarding { store.refresh(); store.startPolling() }
    }
    func layout(animated: Bool = false) {
        let top = max(32, screen.safeAreaInsets.top)
        let width: CGFloat = store.expanded ? max(400, cameraWidth + 160) : cameraWidth + 180
        let bodyHeight: CGFloat = store.onboarding ? 326 : store.selected != nil ? 430 : 320
        let height: CGFloat = store.expanded ? bodyHeight + top : top + 4
        if hosting == nil {
            let view = NSHostingView(rootView: IslandView(store: store, cameraWidth: cameraWidth, topHeight: top))
            view.sizingOptions = []
            hosting = view; panel.contentView = view
        } else if !animated {
            hosting?.rootView = IslandView(store: store, cameraWidth: cameraWidth, topHeight: top)
        }
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        if animated && !store.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.30
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.28, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else { panel.setFrame(frame, display: true) }
    }
    @objc func show() { store.expand(true); panel.makeKeyAndOrderFront(nil) }
    @objc func settings() { store.settings(); panel.makeKeyAndOrderFront(nil) }
    @objc func quit() { NSApp.terminate(nil) }
}
@main struct LumaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
