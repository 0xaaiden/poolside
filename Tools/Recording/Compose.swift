import AppKit
import AVFoundation
import CoreGraphics

/// Composites panel frames over the Last Light artwork and writes an H.264 MP4.
/// Usage: compose <frames-dir> <background-image> <out.mp4> <width> <height> <fps>
let args = CommandLine.arguments
guard args.count == 7, let width = Int(args[4]), let height = Int(args[5]), let fps = Int32(args[6]) else { print("usage: compose <dir> <bg> <out.mp4> <w> <h> <fps>"); exit(2) }
let dir = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[3])
try? FileManager.default.removeItem(at: out)

guard let bgImage = NSImage(contentsOfFile: args[2]), let bgCG = bgImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("no background"); exit(1) }
let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
guard !files.isEmpty else { print("no frames"); exit(1) }

// Background: cover-crop, favouring the upper part of the artwork so the sun stays in frame.
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func makeContext() -> CGContext { CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)! }
let bgContext = makeContext()
let scale = max(CGFloat(width) / CGFloat(bgCG.width), CGFloat(height) / CGFloat(bgCG.height))
let drawW = CGFloat(bgCG.width) * scale, drawH = CGFloat(bgCG.height) * scale
bgContext.interpolationQuality = .high
bgContext.draw(bgCG, in: CGRect(x: (CGFloat(width) - drawW) / 2, y: CGFloat(height) - drawH, width: drawW, height: drawH))
// A soft darkening at the very top so the black panel reads as part of the display edge.
let gradient = CGGradient(colorsSpace: colorSpace, colors: [CGColor(gray: 0, alpha: 0.35), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 1])!
bgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: 0, y: CGFloat(height) - 140), options: [])
let background = bgContext.makeImage()!

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
var frameIndex: Int64 = 0
for name in sequence {
    guard let panel = NSImage(contentsOf: dir.appendingPathComponent(name))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let buffer else { continue }
    CVPixelBufferLockBaseAddress(buffer, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height))
    // Panel frames are 2x captures; draw them 1:1 at the top centre so the strip meets the display edge.
    let pw = CGFloat(panel.width), ph = CGFloat(panel.height)
    ctx.interpolationQuality = .high
    ctx.draw(panel, in: CGRect(x: (CGFloat(width) - pw) / 2, y: CGFloat(height) - ph, width: pw, height: ph))
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
