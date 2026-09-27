import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Grabs window-only frames of the Poolside panel at a fixed rate until the app quits or the time
/// limit passes. Usage: recorder <frames-dir> <fps> <max-seconds>
// ScreenCaptureKit needs a WindowServer connection; NSApplication.shared creates it.
_ = NSApplication.shared
let args = CommandLine.arguments
guard args.count == 4, let fps = Double(args[2]), let limit = Double(args[3]) else { print("usage: recorder <dir> <fps> <seconds>"); exit(2) }
let dir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

func poolsidePID() -> pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: "local.luma.lp.prototype").first?.processIdentifier }
/// The statusBar-level panel is the app's largest on-screen window; the menu-bar item is tiny.
func panelWindow(for pid: pid_t) async -> SCWindow? {
    guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
    return content.windows.filter { $0.owningApplication?.processID == pid && $0.isOnScreen }.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
}
/// A zero output size keeps the capture at the window's native pixel size as it resizes.
func capture(_ filter: SCContentFilter) -> CGImage? {
    let config = SCStreamConfiguration()
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var image: CGImage?
    Task {
        image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        semaphore.signal()
    }
    semaphore.wait()
    return image
}
/// Single-window captures arrive on a display-sized transparent canvas; trim to the panel itself.
func cropped(_ image: CGImage) -> CGImage? {
    switch image.alphaInfo {
    case .none, .noneSkipLast, .noneSkipFirst: return image
    default: break
    }
    guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return image }
    let w = image.width, h = image.height, bpr = image.bytesPerRow, bpp = image.bitsPerPixel / 8
    let alphaFirst = [.premultipliedFirst, .first, .noneSkipFirst].contains(image.alphaInfo)
    let ai = alphaFirst ? 0 : bpp - 1
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where bytes[y * bpr + x * bpp + ai] > 8 {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
}

// Wait for the app and its panel.
var deadline = Date().addingTimeInterval(15)
var pid: pid_t? = nil, window: SCWindow? = nil
while Date() < deadline {
    if let p = poolsidePID(), let w = await panelWindow(for: p) { pid = p; window = w; break }
    try? await Task.sleep(for: .milliseconds(50))
}
guard let pid, var window else { print("no Poolside panel found"); exit(1) }
print("recording panel of pid \(pid) at \(fps) fps")
let interval = 1.0 / fps
let start = Date()
var index = 0
var timings: [String] = []
while Date().timeIntervalSince(start) < limit {
    let t = Date().timeIntervalSince(start)
    if NSRunningApplication(processIdentifier: pid) == nil { print("app quit at \(t)"); break }
    if let image = capture(SCContentFilter(desktopIndependentWindow: window)), let image = cropped(image) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(String(format: "f%05d.png", index)))
        timings.append(String(format: "%.4f %d %d", t, image.width, image.height))
        index += 1
    } else if let p = poolsidePID(), let w = await panelWindow(for: p) { window = w }
    let next = start.addingTimeInterval(Double(index) * interval)
    let wait = next.timeIntervalSinceNow
    if wait > 0 { try? await Task.sleep(for: .milliseconds(wait * 1000)) }
}
try? timings.joined(separator: "\n").write(to: dir.appendingPathComponent("timings.txt"), atomically: true, encoding: .utf8)
print("saved \(index) frames")
