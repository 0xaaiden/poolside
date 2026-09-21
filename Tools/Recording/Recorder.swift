import AppKit
import CoreGraphics

/// Grabs window-only frames of the Poolside panel at a fixed rate until the app quits or the time
/// limit passes. Usage: recorder <frames-dir> <fps> <max-seconds>
let args = CommandLine.arguments
guard args.count == 4, let fps = Double(args[2]), let limit = Double(args[3]) else { print("usage: recorder <dir> <fps> <seconds>"); exit(2) }
let dir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

func poolsidePID() -> pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: "local.luma.lp.prototype").first?.processIdentifier }
func window(for pid: pid_t) -> CGWindowID? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
        if let id = w[kCGWindowNumber as String] as? CGWindowID, let layer = w[kCGWindowLayer as String] as? Int, layer == 25 { return id }
    }
    return nil
}
// Wait for the app and its panel.
var deadline = Date().addingTimeInterval(15)
var pid: pid_t? = nil, wid: CGWindowID? = nil
while Date() < deadline {
    if let p = poolsidePID(), let w = window(for: p) { pid = p; wid = w; break }
    usleep(50_000)
}
guard let pid, var wid else { print("no Poolside panel found"); exit(1) }
print("recording window \(wid) of pid \(pid) at \(fps) fps")
let interval = 1.0 / fps
let start = Date()
var index = 0
var timings: [String] = []
while Date().timeIntervalSince(start) < limit {
    let t = Date().timeIntervalSince(start)
    if NSRunningApplication(processIdentifier: pid) == nil { print("app quit at \(t)"); break }
    if CGWindowListCreateImage(.null, .optionIncludingWindow, wid, [.boundsIgnoreFraming, .bestResolution]) == nil, let p = poolsidePID(), let w = window(for: p) { wid = w }
    if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, wid, [.boundsIgnoreFraming, .bestResolution]) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(String(format: "f%05d.png", index)))
        timings.append(String(format: "%.4f %d %d", t, image.width, image.height))
        index += 1
    }
    let next = start.addingTimeInterval(Double(index) * interval)
    let wait = next.timeIntervalSinceNow
    if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
}
try? timings.joined(separator: "\n").write(to: dir.appendingPathComponent("timings.txt"), atomically: true, encoding: .utf8)
print("saved \(index) frames")
