import AppKit
import AVFoundation
import CoreGraphics

/// Composites panel frames into a MacBook and writes an H.264 MP4. The scene is built at 2x: a
/// laptop (bezel, notch cut, base) on a soft backdrop, the artwork as wallpaper, a macOS menu bar,
/// the captured panel at the display's real point size, and a rendered pointer that follows the
/// scripted clicks in Demo.swift. A slow zoom moves into the notch while the panel is open and pulls
/// back out at the end, so the whole Mac is visible yet the numbers stay legible.
/// Usage: compose <frames-dir> <background-image> <out.mp4> <width> <height> <fps>
let args = CommandLine.arguments
guard args.count == 7, let width = Int(args[4]), let height = Int(args[5]), let fps = Int32(args[6]) else { print("usage: compose <dir> <bg> <out.mp4> <w> <h> <fps>"); exit(2) }
let dir = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[3])
try? FileManager.default.removeItem(at: out)

guard let wallpaper = NSImage(contentsOfFile: args[2]), let wallCG = wallpaper.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("no background"); exit(1) }
let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
guard !files.isEmpty else { print("no frames"); exit(1) }
// Recorder timings: "seconds width height" per frame, used to align the pointer with the app's timeline.
let timings: [Double] = ((try? String(contentsOf: dir.appendingPathComponent("timings.txt"), encoding: .utf8)) ?? "")
    .split(separator: "\n").compactMap { Double($0.split(separator: " ").first ?? "") }
let heights: [Double] = ((try? String(contentsOf: dir.appendingPathComponent("timings.txt"), encoding: .utf8)) ?? "")
    .split(separator: "\n").compactMap { line in let p = line.split(separator: " "); return p.count > 2 ? Double(p[2]) : nil }
// Demo.swift expands at 1.4 s after launch; the first frame taller than the strip marks that moment.
let firstExpanded = zip(timings, heights).first { $0.1 > 80 }?.0 ?? 1.4
let timeOffset = firstExpanded - 1.4

// Layout in output pixels, then scaled by S for the 2x scene. A full 16:10 MacBook with its base.
let S: CGFloat = 2
let W = CGFloat(width) * S, H = CGFloat(height) * S
let lidOuter = CGRect(x: 180 * S, y: 40 * S, width: 1560 * S, height: 990 * S)          // top-down coordinates
let bezel: CGFloat = 14 * S
let display = lidOuter.insetBy(dx: bezel, dy: bezel)                                        // 1532 x 962 output px, 16:10
let pointScale = display.width / (1512 * S) * S                                              // scene px per screen point
let menuBarHeight = 32 * pointScale
let notchWidth = 180 * pointScale
let base = CGRect(x: 150 * S, y: lidOuter.maxY - 2 * S, width: 1620 * S, height: 20 * S)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func context(_ w: Int, _ h: Int, data: UnsafeMutableRawPointer? = nil, bytesPerRow: Int = 0) -> CGContext {
    CGContext(data: data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}
/// Top-down rect to CG (y up) rect within the scene.
func cg(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }
func cg(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: H - p.y) }
func rounded(_ r: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX + bottom, y: r.minY))
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX, y: r.minY + bottom), radius: bottom)
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX + top, y: r.maxY), radius: top)
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY - top), radius: top)
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX - bottom, y: r.minY), radius: bottom)
    p.closeSubpath()
    return p
}
func symbol(_ name: String, pointSize: CGFloat) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium)) else { return nil }
    return NSImage(size: base.size, flipped: false) { rect in base.draw(in: rect); NSColor.white.withAlphaComponent(0.92).set(); rect.fill(using: .sourceAtop); return true }
}

// Static scene ------------------------------------------------------------------------------------
let sceneContext = context(Int(W), Int(H))
let backGradient = CGGradient(colorsSpace: colorSpace, colors: [CGColor(srgbRed: 0.17, green: 0.10, blue: 0.11, alpha: 1), CGColor(srgbRed: 0.05, green: 0.04, blue: 0.05, alpha: 1)] as CFArray, locations: [0, 1])!
sceneContext.drawLinearGradient(backGradient, start: CGPoint(x: W / 2, y: H), end: CGPoint(x: W / 2, y: 0), options: [])
// Base (the body of the laptop seen edge-on) with a lid lip notch in the middle.
sceneContext.saveGState()
sceneContext.setShadow(offset: CGSize(width: 0, height: -10 * S), blur: 40 * S, color: CGColor(gray: 0, alpha: 0.55))
sceneContext.addPath(rounded(cg(base), top: 4 * S, bottom: 10 * S)); sceneContext.setFillColor(CGColor(srgbRed: 0.42, green: 0.42, blue: 0.44, alpha: 1)); sceneContext.fillPath()
sceneContext.restoreGState()
let baseShade = CGGradient(colorsSpace: colorSpace, colors: [CGColor(gray: 1, alpha: 0.25), CGColor(gray: 0, alpha: 0.35)] as CFArray, locations: [0, 1])!
sceneContext.saveGState(); sceneContext.addPath(rounded(cg(base), top: 4 * S, bottom: 10 * S)); sceneContext.clip()
sceneContext.drawLinearGradient(baseShade, start: cg(CGPoint(x: 0, y: base.minY)), end: cg(CGPoint(x: 0, y: base.maxY)), options: []); sceneContext.restoreGState()
let lip = CGRect(x: W / 2 - 90 * S, y: base.minY, width: 180 * S, height: 5 * S)
sceneContext.addPath(rounded(cg(lip), top: 0, bottom: 5 * S)); sceneContext.setFillColor(CGColor(srgbRed: 0.30, green: 0.30, blue: 0.32, alpha: 1)); sceneContext.fillPath()
// Lid: bezel with a soft shadow and a hairline edge highlight.
sceneContext.saveGState()
sceneContext.setShadow(offset: CGSize(width: 0, height: -16 * S), blur: 60 * S, color: CGColor(gray: 0, alpha: 0.6))
sceneContext.addPath(rounded(cg(lidOuter), top: 30 * S, bottom: 30 * S)); sceneContext.setFillColor(CGColor(srgbRed: 0.055, green: 0.055, blue: 0.06, alpha: 1)); sceneContext.fillPath()
sceneContext.restoreGState()
sceneContext.addPath(rounded(cg(lidOuter), top: 30 * S, bottom: 30 * S)); sceneContext.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); sceneContext.setLineWidth(1.5 * S); sceneContext.strokePath()
// Display with wallpaper, menu bar and the notch cut.
sceneContext.saveGState()
sceneContext.addPath(rounded(cg(display), top: 18 * S, bottom: 18 * S)); sceneContext.clip()
let cover = max(display.width / CGFloat(wallCG.width), display.height / CGFloat(wallCG.height))
let drawW = CGFloat(wallCG.width) * cover, drawH = CGFloat(wallCG.height) * cover
sceneContext.interpolationQuality = .high
sceneContext.draw(wallCG, in: CGRect(x: display.midX - drawW / 2, y: H - display.maxY + (display.height - drawH) / 2, width: drawW, height: drawH))
let menuBar = CGRect(x: display.minX, y: display.minY, width: display.width, height: menuBarHeight)
sceneContext.setFillColor(CGColor(gray: 0, alpha: 0.18)); sceneContext.fill(cg(menuBar))
let ns = NSGraphicsContext(cgContext: sceneContext, flipped: false)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
let textColor = NSColor.white.withAlphaComponent(0.92)
let baselineY = H - (menuBar.minY + menuBar.height / 2)
var x = display.minX + 22 * pointScale
if let apple = symbol("apple.logo", pointSize: 14 * pointScale / S) {
    let size = CGSize(width: apple.size.width * S, height: apple.size.height * S)
    apple.draw(in: CGRect(x: x, y: baselineY - size.height / 2, width: size.width, height: size.height)); x += size.width + 22 * pointScale
}
for (i, item) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
    let s = NSAttributedString(string: item, attributes: [.font: NSFont.systemFont(ofSize: 13 * pointScale, weight: i == 0 ? .bold : .regular), .foregroundColor: textColor])
    s.draw(at: CGPoint(x: x, y: baselineY - s.size().height / 2)); x += s.size().width + 20 * pointScale
}
var right = display.maxX - 20 * pointScale
let clock = NSAttributedString(string: "Mon Sep 21  9:41 AM", attributes: [.font: NSFont.systemFont(ofSize: 13 * pointScale, weight: .regular), .foregroundColor: textColor])
right -= clock.size().width; clock.draw(at: CGPoint(x: right, y: baselineY - clock.size().height / 2))
for name in ["magnifyingglass", "wifi", "battery.100percent"].reversed() {
    guard let image = symbol(name, pointSize: 14 * pointScale / S) else { continue }
    let size = CGSize(width: image.size.width * S, height: image.size.height * S)
    right -= size.width + 16 * pointScale
    image.draw(in: CGRect(x: right, y: baselineY - size.height / 2, width: size.width, height: size.height))
}
NSGraphicsContext.restoreGraphicsState()
// The camera housing: a black cut into the menu bar. The panel's strip sits over it when collapsed.
let notch = CGRect(x: display.midX - notchWidth / 2, y: display.minY, width: notchWidth, height: menuBarHeight)
sceneContext.addPath(rounded(cg(notch), top: 0, bottom: 10 * pointScale)); sceneContext.setFillColor(CGColor(gray: 0, alpha: 1)); sceneContext.fillPath()
sceneContext.restoreGState()
let scene = sceneContext.makeImage()!

// Pointer script --------------------------------------------------------------------------------
// Targets in panel points from the panel's top-left (the panel is 400 points wide when expanded).
struct Key { let t: Double; let target: (CGFloat) -> CGPoint; let click: Bool }
func panelPoint(_ x: CGFloat, _ y: CGFloat) -> (CGFloat) -> CGPoint { { widthPt in CGPoint(x: x - widthPt / 2, y: y) } }   // relative to the panel's top centre
let parked: (CGFloat) -> CGPoint = { _ in CGPoint(x: 330, y: 300) }
let keys: [Key] = [
    Key(t: 0.2, target: parked, click: false),
    Key(t: 1.2, target: panelPoint(300, 18), click: false),        // hover the strip; it expands at 1.4
    Key(t: 3.8, target: panelPoint(200, 226), click: false),       // first position row
    Key(t: 4.2, target: panelPoint(200, 226), click: true),
    Key(t: 7.2, target: panelPoint(56, 64), click: false),         // "< Positions"
    Key(t: 7.6, target: panelPoint(56, 64), click: true),
    Key(t: 8.5, target: panelPoint(326, 143), click: false),       // HOLD
    Key(t: 8.8, target: panelPoint(326, 143), click: true),
    Key(t: 9.7, target: panelPoint(289, 143), click: false),       // USD
    Key(t: 10.0, target: panelPoint(289, 143), click: true),
    Key(t: 10.7, target: panelPoint(300, 18), click: false),       // header strip: click to close
    Key(t: 11.0, target: panelPoint(300, 18), click: true),
    Key(t: 12.4, target: parked, click: false),
]
func smooth(_ t: Double) -> Double { let c = min(1, max(0, t)); return c * c * (3 - 2 * c) }
/// Pointer position (in panel-relative points) and the age of the most recent click, if within 0.4 s.
func pointer(at t: Double, widthPt: CGFloat) -> (CGPoint, Double?) {
    var a = keys[0], b = keys[0]
    for k in keys { if k.t <= t { a = k } else { b = k; break } }
    if b.t <= a.t { b = a }
    let p0 = a.target(widthPt), p1 = b.target(widthPt)
    let f = b.t > a.t ? smooth((t - a.t) / (b.t - a.t)) : 1
    let click = keys.filter { $0.click && $0.t <= t && t - $0.t < 0.4 }.last.map { t - $0.t }
    return (CGPoint(x: p0.x + (p1.x - p0.x) * f, y: p0.y + (p1.y - p0.y) * f), click)
}
/// The classic arrow pointer as a path (tip at the origin, units in points), black with a white edge,
/// so it stays crisp at any zoom and needs no running app to supply a cursor image.
let cursorPath: CGPath = {
    let p = CGMutablePath()
    for (i, pt) in [(0, 0), (0, 17), (4.6, 13.2), (7.6, 19.6), (10.2, 18.4), (7.3, 12.2), (12.4, 12.2)].enumerated() {
        let point = CGPoint(x: pt.0, y: pt.1)
        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
    }
    p.closeSubpath()
    return p
}()

// Zoom: full laptop at rest, then in on the notch while the panel is open.
func zoom(at t: Double) -> CGFloat {
    let zoomIn = 1 + 0.95 * smooth((t - 0.5) / 1.4)
    let zoomOut = 1 + 0.95 * (1 - smooth((t - 11.3) / 1.3))
    return CGFloat(min(zoomIn, zoomOut))
}

// Encode ------------------------------------------------------------------------------------------
let writer = try! AVAssetWriter(outputURL: out, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 9_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: fps * 2],
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
writer.startWriting(); writer.startSession(atSourceTime: .zero)

let preRoll = Int(fps) / 2, postRoll = Int(fps)
var sequence: [(file: String, t: Double)] = []
for i in 0..<preRoll { sequence.append((files[0], (timings.first ?? 0) - Double(preRoll - i) / Double(fps) - timeOffset)) }
for (i, f) in files.enumerated() { sequence.append((f, (i < timings.count ? timings[i] : Double(i) / Double(fps)) - timeOffset)) }
for i in 0..<postRoll { sequence.append((files.last!, (timings.last ?? 0) + Double(i + 1) / Double(fps) - timeOffset)) }

let frameContext = context(Int(W), Int(H))
let panelScale = pointScale / 2   // captures are 2x
var frameIndex: Int64 = 0
for (file, t) in sequence {
    guard let panel = NSImage(contentsOf: dir.appendingPathComponent(file))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    frameContext.draw(scene, in: CGRect(x: 0, y: 0, width: W, height: H))
    let pw = CGFloat(panel.width) * panelScale, ph = CGFloat(panel.height) * panelScale
    let panelRect = CGRect(x: display.midX - pw / 2, y: display.minY, width: pw, height: ph)
    frameContext.interpolationQuality = .high
    frameContext.draw(panel, in: cg(panelRect))
    // Pointer and click ripple.
    let widthPt = CGFloat(panel.width) / 2
    let (rel, clickAge) = pointer(at: t, widthPt: widthPt)
    let tip = CGPoint(x: display.midX + rel.x * pointScale, y: display.minY + rel.y * pointScale)
    if let age = clickAge {
        let f = CGFloat(age / 0.4)
        let radius = (6 + 20 * f) * pointScale
        frameContext.setStrokeColor(CGColor(gray: 1, alpha: 0.7 * (1 - f))); frameContext.setLineWidth(2 * pointScale)
        frameContext.strokeEllipse(in: CGRect(x: tip.x - radius, y: H - tip.y - radius, width: radius * 2, height: radius * 2))
    }
    frameContext.saveGState()
    frameContext.translateBy(x: tip.x, y: H - tip.y)
    frameContext.scaleBy(x: pointScale, y: -pointScale)          // points, y down from the tip
    frameContext.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 3, color: CGColor(gray: 0, alpha: 0.45))
    frameContext.addPath(cursorPath); frameContext.setFillColor(CGColor(gray: 0, alpha: 1)); frameContext.fillPath()
    frameContext.addPath(cursorPath); frameContext.setStrokeColor(CGColor(gray: 1, alpha: 1)); frameContext.setLineWidth(1.2); frameContext.setLineJoin(.round); frameContext.strokePath()
    frameContext.restoreGState()
    guard let composed = frameContext.makeImage() else { continue }
    // Viewport for the zoom, kept inside the scene and biased toward the panel.
    let z = zoom(at: t)
    let vw = W / z, vh = H / z
    let focus = CGPoint(x: display.midX, y: display.minY + 190 * pointScale)
    var vx = focus.x - vw / 2, vy = focus.y - vh / 2
    vx = min(max(0, vx), W - vw); vy = min(max(0, vy), H - vh)
    // CGImage.cropping uses image (top-down) coordinates, unlike the drawing context.
    guard let cropped = composed.cropping(to: CGRect(x: vx, y: vy, width: vw, height: vh)) else { continue }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let buffer else { continue }
    CVPixelBufferLockBaseAddress(buffer, [])
    let ctx = context(width, height, data: CVPixelBufferGetBaseAddress(buffer), bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    while !input.isReadyForMoreMediaData { usleep(2_000) }
    adaptor.append(buffer, withPresentationTime: CMTime(value: frameIndex, timescale: fps))
    frameIndex += 1
}
input.markAsFinished()
let group = DispatchGroup(); group.enter()
writer.finishWriting { group.leave() }
group.wait()
print("wrote \(out.path): \(frameIndex) frames, \(Double(frameIndex) / Double(fps)) s, time offset \(String(format: "%.2f", timeOffset)) s, status \(writer.status.rawValue)\(writer.error.map { " error \($0)" } ?? "")")
