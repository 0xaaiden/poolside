import SwiftUI
import AppKit
import Observation
import QuartzCore
import ServiceManagement
import UserNotifications

/// Observation tracks per-property reads, so a view that only shows the wallet is not re-evaluated when
/// the reveal progress changes 120 times a second during the panel animation.
@Observable @MainActor final class Store {
    /// Open positions of the active wallet.
    var positions: [Position] = [] { didSet { totals = Totals(positions) } }
    private(set) var totals = Totals([])
    /// Exited positions of the active wallet, loaded on demand (Pro).
    var closed: [Position] = [] { didSet { closedTotals = ClosedTotals(closed) } }
    private(set) var closedTotals = ClosedTotals([])
    var closedFetchedAt: Date?
    var loadingClosed = false
    var showClosed = false
    var loading = false
    var error: String?
    /// Non-fatal information from the last update, such as rows that could not be read.
    var notice: String?
    var demo = false
    var fetchedAt: Date?
    var book = WalletBook.load() { didSet { book.save(); resize?() } }
    var walletInput = ""
    var onboarding = WalletBook.load().isEmpty
    var step = 0 { didSet { resize?() } }
    var license: License? = License.load()
    var licenseInput = ""
    var licenseMessage: String?
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var alertsEnabled = UserDefaults.standard.bool(forKey: "alerts")
    /// Privacy mask: every money and unit figure renders as ••• while on.
    var masked = UserDefaults.standard.bool(forKey: "masked") {
        didSet { UserDefaults.standard.set(masked, forKey: "masked"); DisplayMask.on = masked }
    }
    var entitlements: Entitlements { Entitlements(tier: license?.tier ?? .free) }
    var expanded = false
    var revealProgress: Double = 0
    var hasKeyFocus = false
    var selected: String? { didSet { resize?() } }
    var benchmark = "usd"
    var theme = UserDefaults.standard.string(forKey: "theme") ?? "system" {
        didSet { UserDefaults.standard.set(theme, forKey: "theme") }
    }
    @ObservationIgnored var resize: (() -> Void)?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var closedTask: Task<Void, Never>?
    @ObservationIgnored var requestID = UUID()
    @ObservationIgnored var polling: Task<Void, Never>?
    /// Last known data per wallet, so switching wallets is instant and never blanks the panel.
    struct Snapshot { var positions: [Position]; var fetchedAt: Date?; var closed: [Position]; var closedFetchedAt: Date? }
    @ObservationIgnored var cache: [String: Snapshot] = [:]
    init() {
        // First launch needs the onboarding panel open; later launches start as a quiet strip.
        expanded = onboarding
        revealProgress = onboarding ? 1 : 0
        DisplayMask.on = masked
    }
    var wallet: String { book.active ?? "" }
    var wallets: [String] { book.wallets }
    var displayWallet: String { demo ? RevertClient.sampleWallet : wallet }
    /// A wallet's custom label, or its shortened address when unlabeled.
    func name(for address: String) -> String { book.label(address) ?? Self.short(address) }
    var shortWallet: String { Self.short(displayWallet) }
    var displayName: String { name(for: displayWallet) }
    func renameWallet(_ address: String, to name: String) { book.rename(address, to: name) }
    static func short(_ address: String) -> String { RevertClient.valid(address) ? "\(address.prefix(6))…\(address.suffix(4))" : "Add wallet" }
    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var pooled: Sum { totals.pooled }
    var fees: Sum { totals.fees }
    var pnl: Sum { totals.pnl[benchmark] ?? .unavailable }
    var realized: Sum { closedTotals.pnl[benchmark] ?? .unavailable }
    /// Portfolio-level benchmarks. token0/token1 are per position and only offered in the detail view.
    var portfolioBenchmarks: [String] { entitlements.benchmarks.filter { !$0.hasPrefix("token") } }
    var scheme: ColorScheme? { theme == "system" ? nil : theme == "dark" ? .dark : .light }
    var sourceDate: Date? { positions.compactMap(\.sourceTimestamp).min().map(Date.init(timeIntervalSince1970:)) }
    var canAddWallet: Bool { wallets.count < entitlements.maxWallets }
    func position(id: String) -> Position? { positions.first { $0.id == id } ?? closed.first { $0.id == id } }
    /// Panel body height for the current screen. Onboarding grows with the wallet list.
    var bodyHeight: CGFloat {
        if onboarding { return step == 2 ? 442 : step == 1 ? 326 + CGFloat(min(wallets.count, 5)) * 26 : 326 }
        return selected != nil ? 410 : 300
    }
    func expand(_ value: Bool) {
        guard expanded != value else { resize?(); return }
        // The window owns expansion. A second SwiftUI layout animation shifts the content.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { expanded = value }
        resize?()
    }
    func loadDemo() {
        requestID = UUID()
        refreshTask?.cancel(); closedTask?.cancel(); polling?.cancel(); loading = false; loadingClosed = false
        do {
            positions = try RevertClient.sample(); closed = []; closedFetchedAt = nil; showClosed = false
            demo = true; onboarding = false; error = nil; notice = nil; fetchedAt = nil; selected = nil; expand(true)
        } catch { self.error = error.localizedDescription }
    }
    /// Adds the typed address (or selects it if already tracked). Returns false with an error shown otherwise.
    @discardableResult func addWallet() -> Bool {
        let typed = walletInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = book
        switch next.add(typed, limit: entitlements.maxWallets) {
        case .invalid: error = RevertError.invalidWallet.localizedDescription; return false
        case .full: error = entitlements.tier == .pro ? "Poolside tracks up to \(entitlements.maxWallets) wallets." : "Tracking more than one wallet is part of Pro."; return false
        case .added, .selectedExisting: break
        }
        error = nil; walletInput = ""
        let switched = next.active != book.active
        book = next
        if switched { activateWallet() }
        return true
    }
    func removeWallet(_ address: String) {
        let wasActive = book.active?.lowercased() == address.lowercased()
        book.remove(address); cache[address.lowercased()] = nil
        if wasActive { activateWallet() }
    }
    func selectWallet(_ address: String) {
        guard address.lowercased() != wallet.lowercased() else { return }
        book.select(address); activateWallet()
        if !onboarding { refresh(); startPolling() }
    }
    /// Swaps in the cached snapshot for the active wallet and cancels in-flight requests for the old one.
    private func activateWallet() {
        requestID = UUID(); refreshTask?.cancel(); closedTask?.cancel(); loading = false; loadingClosed = false
        selected = nil; error = nil; notice = nil; demo = false
        let snapshot = cache[wallet.lowercased()]
        positions = snapshot?.positions ?? []; fetchedAt = snapshot?.fetchedAt
        closed = snapshot?.closed ?? []; closedFetchedAt = snapshot?.closedFetchedAt
    }
    private func remember() {
        guard RevertClient.valid(wallet), !demo else { return }
        cache[wallet.lowercased()] = Snapshot(positions: positions, fetchedAt: fetchedAt, closed: closed, closedFetchedAt: closedFetchedAt)
    }
    func connect() {
        if !walletInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !addWallet() { return }
        guard RevertClient.valid(wallet) else { error = RevertError.invalidWallet.localizedDescription; return }
        if demo { demo = false; activateWallet() }
        selected = nil; onboarding = false; notice = nil
        expand(true); refresh(); startPolling()
    }
    func refresh() {
        guard !demo, !loading, RevertClient.valid(wallet) else { return }
        loading = true; error = nil
        let id = UUID(); requestID = id
        let requestedWallet = wallet
        if showClosed { loadClosed(force: true) }
        refreshTask = Task {
            defer { if requestID == id { loading = false } }
            do {
                let fetched = try await RevertClient.fetch(wallet: requestedWallet)
                guard !Task.isCancelled, requestedWallet == wallet, !demo else { return }
                let before = positions
                positions = fetched.positions; fetchedAt = Date()
                notifyRangeChanges(from: before, to: fetched.positions)
                notice = fetched.skipped == 0 ? nil : "\(fetched.skipped) position\(fetched.skipped == 1 ? "" : "s") could not be read and \(fetched.skipped == 1 ? "is" : "are") not shown."
                remember()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
    /// Switches the list between open and closed positions. Closed data loads on first view and
    /// again when older than five minutes; open data keeps polling regardless.
    func setScope(closed show: Bool) {
        guard !show || entitlements.closedPositions else { return }
        showClosed = show
        if show { loadClosed(force: false) }
    }
    func loadClosed(force: Bool) {
        guard entitlements.closedPositions, !loadingClosed else { return }
        if !force, let at = closedFetchedAt, Date().timeIntervalSince(at) < 300 { return }
        if demo {
            do { closed = try RevertClient.sample(closed: true); closedFetchedAt = Date() } catch { self.error = error.localizedDescription }
            return
        }
        guard RevertClient.valid(wallet) else { return }
        loadingClosed = true
        let requestedWallet = wallet
        closedTask = Task {
            defer { if requestedWallet == wallet { loadingClosed = false } }
            do {
                let fetched = try await RevertClient.fetch(wallet: requestedWallet, active: false)
                guard !Task.isCancelled, requestedWallet == wallet, !demo else { return }
                closed = fetched.positions.sorted { ($0.closedDate ?? .distantPast) > ($1.closedDate ?? .distantPast) }
                closedFetchedAt = Date()
                if fetched.skipped > 0 { notice = "\(fetched.skipped) closed position\(fetched.skipped == 1 ? "" : "s") could not be read." }
                remember()
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
                try? await Task.sleep(for: .seconds(error == nil ? entitlements.refreshInterval : 180))
                if !Task.isCancelled { refresh() }
            }
        }
    }
    func settings(step: Int = 1) {
        requestID = UUID()
        refreshTask?.cancel(); closedTask?.cancel(); polling?.cancel(); loading = false; loadingClosed = false
        onboarding = true; self.step = step; error = nil; walletInput = ""; licenseMessage = nil; licenseInput = license?.key ?? ""; expand(true)
    }
    func applyLicense() {
        switch License.verify(licenseInput) {
        case .success(let verified):
            verified.save(); license = verified
            licenseMessage = "Pro unlocked for \(verified.payload.id)" + (verified.expires.map { " until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "") + "."
        case .failure(let failure):
            licenseMessage = failure.localizedDescription
        }
        enforceEntitlements()
    }
    func removeLicense() {
        License.clear(); license = nil; licenseInput = ""; licenseMessage = "Back on Free."
        enforceEntitlements()
    }
    /// Dropping to Free keeps every saved wallet but only the active one stays reachable until Pro returns.
    private func enforceEntitlements() {
        if !entitlements.benchmarks.contains(benchmark) { benchmark = "usd" }
        if !entitlements.launchAtLogin, launchAtLogin { setLaunchAtLogin(false) }
        if !entitlements.outOfRangeAlerts, alertsEnabled { setAlerts(false) }
        if !entitlements.closedPositions { showClosed = false }
    }
    func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { licenseMessage = error.localizedDescription }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    func setAlerts(_ on: Bool) {
        alertsEnabled = on; UserDefaults.standard.set(on, forKey: "alerts")
        if on { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
    }
    /// Pro: a notification when a position leaves or re-enters its range between refreshes.
    func notifyRangeChanges(from before: [Position], to after: [Position]) {
        guard entitlements.outOfRangeAlerts, alertsEnabled, !before.isEmpty else { return }
        let previous = Dictionary(before.map { ($0.id, $0.inRange) }, uniquingKeysWith: { a, _ in a })
        for p in after {
            guard let was = previous[p.id], was != p.inRange else { continue }
            let content = UNMutableNotificationContent()
            content.title = p.inRange ? "\(p.pair) is back in range" : "\(p.pair) left its range"
            content.body = "\(name(for: wallet)) · \(p.network.capitalized) · now \(price(p.pool_price?.value)) · pooled \(money(p.underlying_value?.value))"
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "range-\(p.id)", content: content, trigger: nil))
        }
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // This panel intentionally occupies the menu-bar/notch area, outside visibleFrame.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var panel: IslandPanel!
    var status: NSStatusItem!
    var hosting: NSHostingView<IslandView>?
    var observers: [NSObjectProtocol] = []
    var monitors: [Any] = []
    var topHeight: CGFloat = 32
    var motion: PanelMotion?
    var displayLink: CADisplayLink?
    var screen: NSScreen { NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0] }
    var cameraWidth: CGFloat {
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea { return r.minX - l.maxX }
        return 160
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        // Clicks make the panel key only where it matters (a text field, or the body via the monitor
        // below). The header toggle never changes focus, so closing is a single uninterrupted motion.
        panel.becomesKeyOnlyIfNeeded = true
        store.resize = { [weak self] in self?.layout(animated: true) }
        layout(); panel.orderFrontRegardless()
        if store.onboarding { panel.makeKey() }
        // The strip toggles on click, so no pointer tracking runs at all. The local monitor exists
        // only for focus-on-body-click and Escape; it needs no global monitors or permissions.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown], handler: { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDown where store.expanded && event.window === panel && event.locationInWindow.y < panel.frame.height - topHeight:
                if !panel.isKeyWindow { panel.makeKey() }
            case .keyDown where event.keyCode == 53 && store.expanded: store.expand(false); return nil
            default: break
            }
            return event
        }) { monitors.append(monitor) }
        for (name, key) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.hasKeyFocus = key }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Poolside")
        let menu = NSMenu()
        for (title, action, key) in [("Show Poolside", #selector(show), ""), ("Wallet & appearance…", #selector(settings), ","), ("Quit Poolside", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        status.menu = menu
        if !store.onboarding { store.refresh(); store.startPolling() }
        DemoRecording.start(store: store)
    }
    func layout(animated: Bool = false) {
        let top = max(32, screen.safeAreaInsets.top)
        topHeight = top
        let camera = cameraWidth
        let expandedWidth = max(400, camera + 160), collapsedWidth = camera + 180
        let bodyHeight = store.bodyHeight
        let size = store.expanded ? CGSize(width: expandedWidth, height: bodyHeight + top) : CGSize(width: collapsedWidth, height: top + 4)
        if hosting == nil {
            let view = NSHostingView(rootView: IslandView(store: store, cameraWidth: camera, topHeight: top))
            view.sizingOptions = []
            hosting = view; panel.contentView = view
        } else if !animated {
            hosting?.rootView = IslandView(store: store, cameraWidth: camera, topHeight: top)
        }
        let reveal: Double = store.expanded ? 1 : 0
        if animated && !store.reduceMotion {
            let now = CACurrentMediaTime()
            let current = motion?.sample(at: now) ?? PanelMotion.Sample(size: panel.frame.size, reveal: store.revealProgress)
            motion = PanelMotion(spring: store.expanded ? .panel : .panelClose, from: current, to: size, reveal: reveal, at: now)
            startDisplayLink()
        } else {
            stopDisplayLink()
            store.revealProgress = reveal
            panel.setFrame(topAnchoredFrame(size: size, top: screen.frame.maxY, centerX: screen.frame.midX), display: true)
        }
    }
    /// Frames are produced on the display's own refresh clock, so the motion is 120 Hz on ProMotion
    /// and free of timer jitter.
    func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    func stopDisplayLink() {
        displayLink?.invalidate(); displayLink = nil; motion = nil
    }
    @objc func step(_ link: CADisplayLink) {
        guard let motion else { stopDisplayLink(); return }
        let time = link.targetTimestamp
        var sample = motion.sample(at: time)
        let done = motion.settled(sample, at: time)
        if done { sample = motion.target }
        store.revealProgress = sample.reveal.value
        panel.setFrame(topAnchoredFrame(size: sample.size, top: screen.frame.maxY, centerX: screen.frame.midX), display: true)
        if done { stopDisplayLink() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        stopDisplayLink()
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
    @objc func show() { store.expand(true); panel.makeKeyAndOrderFront(nil) }
    @objc func settings() { store.settings(); panel.makeKeyAndOrderFront(nil) }
    @objc func quit() { NSApp.terminate(nil) }
}
@main struct PoolsideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
