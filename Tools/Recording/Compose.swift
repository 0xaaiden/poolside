import AppKit
import AVFoundation
import CoreGraphics

/// Composites panel frames into the top of a MacBook display and writes an H.264 MP4: dark bezel
/// with rounded corners over a soft backdrop, the artwork as wallpaper, a macOS menu bar, and the
/// captured panel scaled to the display's real point size so it sits where the notch would be.
/// Usage: compose <frames-dir> <background-image> <out.mp4> <width> <height> <fps>
let args = CommandLine.arguments
guard args.count == 7, let width = Int(args[4]), let height = Int(args[5]), let fps = Int32(args[6]) else { print("usage: compose <dir> <bg> <out.mp4> <w> <h> <fps>"); exit(2) }
let dir = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[3])
try? FileManager.default.removeItem(at: out)

guard let wallpaper = NSImage(contentsOfFile: args[2]), let wallCG = wallpaper.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("no background"); exit(1) }
let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
guard !files.isEmpty else { print("no frames"); exit(1) }

// Layout. The laptop spans nearly the full width; its display continues past the bottom edge, so
// this reads as the top of a MacBook. `pointScale` is pixels per screen point for a 1512-point-wide
// display (14-inch MacBook Pro), and panel captures are 2x, so they are drawn at pointScale / 2.
let W = CGFloat(width), H = CGFloat(height)
let bezelOuter = CGRect(x: 44, y: -40, width: W - 88, height: H + 40 + 40)   // CG coordinates: y grows upward; top edge at H - 52
let bezelTop = H - 52
let bezelSide: CGFloat = 16, bezelTopThickness: CGFloat = 16
let display = CGRect(x: bezelOuter.minX + bezelSide, y: -60, width: bezelOuter.width - 2 * bezelSide, height: bezelTop - bezelTopThickness + 60)
let pointScale = display.width / 1512
let menuBarHeight = 32 * pointScale

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func makeContext() -> CGContext { CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)! }
func roundedTop(_ r: CGRect, radius: CGFloat) -> CGPath {
    // Rounded at the top corners only; the bottom is off canvas.
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX, y: r.minY))
    p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX + radius, y: r.maxY), radius: radius)
    p.addLine(to: CGPoint(x: r.maxX - radius, y: r.maxY))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY - radius), radius: radius)
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
    p.closeSubpath()
    return p
}
func symbol(_ name: String, pointSize: CGFloat) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium)) else { return nil }
    let tinted = NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect); NSColor.white.withAlphaComponent(0.92).set(); rect.fill(using: .sourceAtop); return true
    }
    return tinted
}

let backdrop = makeContext()
// Backdrop: a deep, slightly warm gradient so the black bezel still separates from it.
let backGradient = CGGradient(colorsSpace: colorSpace, colors: [CGColor(srgbRed: 0.16, green: 0.09, blue: 0.10, alpha: 1), CGColor(srgbRed: 0.05, green: 0.04, blue: 0.05, alpha: 1)] as CFArray, locations: [0, 1])!
backdrop.drawLinearGradient(backGradient, start: CGPoint(x: W / 2, y: H), end: CGPoint(x: W / 2, y: 0), options: [])
// Bezel with a soft shadow and a hairline highlight on the top edge.
backdrop.saveGState()
backdrop.setShadow(offset: CGSize(width: 0, height: -18), blur: 60, color: CGColor(gray: 0, alpha: 0.6))
backdrop.addPath(roundedTop(CGRect(x: bezelOuter.minX, y: bezelOuter.minY, width: bezelOuter.width, height: bezelTop - bezelOuter.minY), radius: 34))
backdrop.setFillColor(CGColor(srgbRed: 0.055, green: 0.055, blue: 0.06, alpha: 1)); backdrop.fillPath()
backdrop.restoreGState()
backdrop.addPath(roundedTop(CGRect(x: bezelOuter.minX, y: bezelOuter.minY, width: bezelOuter.width, height: bezelTop - bezelOuter.minY), radius: 34))
backdrop.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); backdrop.setLineWidth(1.5); backdrop.strokePath()
// Display: wallpaper cover-cropped and top-aligned, clipped to rounded inner corners.
backdrop.saveGState()
backdrop.addPath(roundedTop(display, radius: 20)); backdrop.clip()
let scale = max(display.width / CGFloat(wallCG.width), (display.height + 200) / CGFloat(wallCG.height))
let drawW = CGFloat(wallCG.width) * scale, drawH = CGFloat(wallCG.height) * scale
backdrop.interpolationQuality = .high
backdrop.draw(wallCG, in: CGRect(x: display.midX - drawW / 2, y: display.maxY - drawH, width: drawW, height: drawH))
// Menu bar: a faint darkening plus the usual items, drawn with AppKit text on top of the CG context.
backdrop.setFillColor(CGColor(gray: 0, alpha: 0.18))
backdrop.fill(CGRect(x: display.minX, y: display.maxY - menuBarHeight, width: display.width, height: menuBarHeight))
let ns = NSGraphicsContext(cgContext: backdrop, flipped: false)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
let textColor = NSColor.white.withAlphaComponent(0.92)
var x = display.minX + 22 * pointScale
let baseline = display.maxY - menuBarHeight / 2
if let apple = symbol("apple.logo", pointSize: 14 * pointScale) {
    apple.draw(in: CGRect(x: x, y: baseline - apple.size.height / 2, width: apple.size.width, height: apple.size.height))
    x += apple.size.width + 22 * pointScale
}
for (i, item) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
    let s = NSAttributedString(string: item, attributes: [.font: NSFont.systemFont(ofSize: 13 * pointScale, weight: i == 0 ? .bold : .regular), .foregroundColor: textColor])
    s.draw(at: CGPoint(x: x, y: baseline - s.size().height / 2)); x += s.size().width + 20 * pointScale
}
var right = display.maxX - 20 * pointScale
let clock = NSAttributedString(string: "Mon Sep 21  9:41 AM", attributes: [.font: NSFont.systemFont(ofSize: 13 * pointScale, weight: .regular), .foregroundColor: textColor])
right -= clock.size().width; clock.draw(at: CGPoint(x: right, y: baseline - clock.size().height / 2))
for name in ["magnifyingglass", "wifi", "battery.100percent"].reversed() {
    guard let image = symbol(name, pointSize: 14 * pointScale) else { continue }
    right -= image.size.width + 16 * pointScale
    image.draw(in: CGRect(x: right, y: baseline - image.size.height / 2, width: image.size.width, height: image.size.height))
}
NSGraphicsContext.restoreGraphicsState()
backdrop.restoreGState()
let background = backdrop.makeImage()!

let writer = try! AVAssetWriter(outputURL: out, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: fps * 2],
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
writer.startWriting(); writer.startSession(atSourceTime: .zero)

// Hold the first and last frames briefly so the loop has a resting state.
let sequence = Array(repeating: files.first!, count: Int(fps) / 2) + files + Array(repeating: files.last!, count: Int(fps))
let panelScale = pointScale / 2   // captures are 2x
var frameIndex: Int64 = 0
for name in sequence {
    guard let panel = NSImage(contentsOf: dir.appendingPathComponent(name))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let buffer else { continue }
    CVPixelBufferLockBaseAddress(buffer, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pw = CGFloat(panel.width) * panelScale, ph = CGFloat(panel.height) * panelScale
    ctx.interpolationQuality = .high
    ctx.draw(panel, in: CGRect(x: display.midX - pw / 2, y: display.maxY - ph, width: pw, height: ph))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    while !input.isReadyForMoreMediaData { usleep(2_000) }
    adaptor.append(buffer, withPresentationTime: CMTime(value: frameIndex, timescale: fps))
    frameIndex += 1
}
input.markAsFinished()
let group = DispatchGroup(); group.enter()
writer.finishWriting { group.leave() }
group.wait()
print("wrote \(out.path): \(frameIndex) frames, \(Double(frameIndex) / Double(fps)) s, status \(writer.status.rawValue)\(writer.error.map { " error \($0)" } ?? "")")
