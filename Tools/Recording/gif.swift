import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Converts the demo MP4 to an animated GIF. Usage: gif <in.mp4> <out.gif> <width> <fps>
/// Frames are downsampled to the target rate and scaled to the target width; the GIF loops forever.
_ = NSApplication.shared
let args = CommandLine.arguments
guard args.count == 5, let width = Int(args[3]), let fps = Int32(args[4]) else { print("usage: gif <in.mp4> <out.gif> <width> <fps>"); exit(2) }
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
guard let track = asset.tracks(withMediaType: .video).first else { print("no video track"); exit(1) }
let size = track.naturalSize.applying(track.preferredTransform)
let scale = CGFloat(width) / abs(size.width)
let outSize = CGSize(width: CGFloat(width), height: (abs(size.height) * scale).rounded())

guard let reader = try? AVAssetReader(asset: asset) else { print("cannot read asset"); exit(1) }
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(output)
reader.startReading()

let out = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: out)
guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, 0, nil) else { print("no gif destination"); exit(1) }
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

let step = max(1, Int(round(Double(30) / Double(fps))))
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: Int(outSize.width), height: Int(outSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
context.interpolationQuality = .high
var frame = 0, written = 0
while let buffer = output.copyNextSampleBuffer(), CMSampleBufferGetImageBuffer(buffer) != nil {
    guard let cg = CMSampleBufferGetImageBuffer(buffer).map({ buf -> CGImage? in
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        let src = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: CVPixelBufferGetWidth(buf), height: CVPixelBufferGetHeight(buf), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return src?.makeImage()
    }) ?? nil else { frame += 1; continue }
    if frame % step == 0 {
        context.draw(cg, in: CGRect(origin: .zero, size: outSize))
        if let scaled = context.makeImage() {
            CGImageDestinationAddImage(destination, scaled, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(step) / 30.0]] as CFDictionary)
            written += 1
        }
    }
    frame += 1
}
guard CGImageDestinationFinalize(destination) else { print("finalize failed"); exit(1) }
print("wrote \(out.path): \(written) frames of \(frame)")
