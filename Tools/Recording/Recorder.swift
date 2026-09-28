import AppKit
import CoreMedia
import CoreVideo
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Records the Poolside panel as a continuous 60 fps ScreenCaptureKit stream.
///
/// The filter includes only Poolside's windows on the built-in display, so the menu bar, wallpaper
/// and every other app are excluded and the panel arrives on a transparent canvas. The source rect is
/// a fixed region centered under the notch, captured at the display's native pixel scale, so frames
/// never rescale while the panel springs open. Each complete frame is written as a PNG with its
/// host-clock presentation time, which Demo.swift's POOLSIDE_DEMO_CLOCK file aligns to the timeline.
///
/// Usage: recorder <frames-dir> <max-seconds> [region-width-pt] [region-height-pt]
_ = NSApplication.shared // ScreenCaptureKit needs a WindowServer connection.
let args = CommandLine.arguments
guard args.count >= 3, let limit = Double(args[2]) else { print("usage: recorder <dir> <seconds> [w-pt] [h-pt]"); exit(2) }
let dir = URL(fileURLWithPath: args[1])
let regionW = args.count > 3 ? Double(args[3]) ?? 640 : 640
let regionH = args.count > 4 ? Double(args[4]) ?? 540 : 540
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

func poolsidePID() -> pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: "local.luma.lp.prototype").first?.processIdentifier }

final class FrameWriter: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "poolside.recorder.write", qos: .userInitiated)
    let dir: URL
    private var index = 0
    private var lines: [(Int, Double)] = []
    init(dir: URL) { self.dir = dir }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        let w = CVPixelBufferGetWidth(pixels), h = CVPixelBufferGetHeight(pixels), bpr = CVPixelBufferGetBytesPerRow(pixels)
        let data = Data(bytes: CVPixelBufferGetBaseAddress(pixels)!, count: bpr * h)
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        let i = index; index += 1
        queue.async { [self] in
            guard let provider = CGDataProvider(data: data as CFData),
                  let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
            let url = dir.appendingPathComponent(String(format: "f%05d.png", i))
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            lines.append((i, time))
        }
    }
    func finish() -> Int {
        queue.sync {
            try? lines.sorted { $0.0 < $1.0 }.map { String(format: "%d %.6f", $0.0, $0.1) }
                .joined(separator: "\n").write(to: dir.appendingPathComponent("timings.txt"), atomically: true, encoding: .utf8)
            return lines.count
        }
    }
}

// Wait for the app to put its panel on screen.
var deadline = Date().addingTimeInterval(20)
var target: (SCRunningApplication, SCDisplay)?
while Date() < deadline, target == nil {
    if let pid = poolsidePID(), let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
       let app = content.applications.first(where: { $0.processID == pid }),
       content.windows.contains(where: { $0.owningApplication?.processID == pid && $0.isOnScreen && $0.frame.width > 100 }),
       let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) ?? content.displays.first {
        target = (app, display)
    } else {
        try? await Task.sleep(for: .milliseconds(40))
    }
}
guard let (app, display) = target else { print("no Poolside panel found"); exit(1) }

let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
let scale = Double(filter.pointPixelScale)
let config = SCStreamConfiguration()
config.sourceRect = CGRect(x: Double(display.width) / 2 - regionW / 2, y: 0, width: regionW, height: regionH)
config.width = Int(regionW * scale)
config.height = Int(regionH * scale)
config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
config.pixelFormat = kCVPixelFormatType_32BGRA
config.colorSpaceName = CGColorSpace.sRGB
config.backgroundColor = .clear
config.showsCursor = false
config.queueDepth = 8

let writer = FrameWriter(dir: dir)
let stream = SCStream(filter: filter, configuration: config, delegate: nil)
try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: DispatchQueue(label: "poolside.recorder.capture", qos: .userInteractive))
try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in stream.startCapture { e in if let e { c.resume(throwing: e) } else { c.resume() } } }
print("recording \(config.width)x\(config.height) px (\(scale)x) of display \(display.displayID) at 60 fps")
let start = Date()
while Date().timeIntervalSince(start) < limit, poolsidePID() != nil { try? await Task.sleep(for: .milliseconds(50)) }
await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in stream.stopCapture { _ in c.resume() } }
print("saved \(writer.finish()) frames")
