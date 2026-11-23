import UIKit
import Vision
import CoreImage
import ImageIO
import AVFoundation
import SDWebImage
import SDWebImageWebPCoder

enum WebPInfo {
    struct Report {
        var width = 0
        var height = 0
        var animated = false
        var frames = 0
        var minDur = Int.max
        var totalMs = 0
    }

    static func inspect(_ d: Data) -> Report? {
        let b = [UInt8](d)
        guard b.count > 20,
              String(decoding: b[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: b[8..<12], as: UTF8.self) == "WEBP" else { return nil }
        func le(_ o: Int, _ n: Int) -> Int {
            var v = 0
            for i in 0..<n { v |= Int(b[o + i]) << (8 * i) }
            return v
        }
        var r = Report()
        var p = 12
        while p + 8 <= b.count {
            let tag = String(decoding: b[p..<(p + 4)], as: UTF8.self)
            let size = le(p + 4, 4)
            let body = p + 8
            if tag == "VP8X", body + 10 <= b.count {
                r.animated = (b[body] & 0x02) != 0
                r.width = le(body + 4, 3) + 1
                r.height = le(body + 7, 3) + 1
            } else if tag == "ANMF", body + 16 <= b.count {
                r.frames += 1
                let dur = le(body + 12, 3)
                r.minDur = min(r.minDur, dur)
                r.totalMs += dur
            }
            p = body + size + (size & 1)
        }
        return r
    }

    static func warning(_ d: Data, animated: Bool) -> String? {
        guard let r = inspect(d) else { return tr("ملف WebP غير صالح", "Invalid WebP file") }
        if animated {
            if d.count > 500_000 { return tr("الحجم أكبر من 500KB", "Size is over 500KB") }
            if !r.animated || r.frames < 2 { return tr("الملف ليس متحركاً", "File is not animated") }
            if r.width != 512 || r.height != 512 { return tr("الأبعاد ليست 512×512", "Size is not 512×512") }
            if r.minDur < 8 { return tr("مدة فريم أقل من 8ms", "Frame duration under 8ms") }
            if r.totalMs > 10_000 { return tr("المدة أطول من 10 ثواني", "Longer than 10 seconds") }
        } else {
            if d.count > 100_000 { return tr("الحجم أكبر من 100KB", "Size is over 100KB") }
            if r.width != 0 && (r.width != 512 || r.height != 512) { return tr("الأبعاد ليست 512×512", "Size is not 512×512") }
        }
        return nil
    }
}

enum Imaging {
    static let videoFPS: Double = 15
    static let maxSeconds: Double = 10
    static let minSeconds: Double = 0.2

    static func normalize(_ img: UIImage, maxDim: CGFloat = 1280) -> UIImage {
        let s = min(1, maxDim / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func removeBackground(_ img: UIImage) -> UIImage? {
        guard #available(iOS 17.0, *), let cg = img.cgImage else { return nil }
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        do {
            try handler.perform([req])
            guard let obs = req.results?.first else { return nil }
            let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
            let ci = CIImage(cvPixelBuffer: buf)
            guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: out)
        } catch { return nil }
    }

    static func gifFrames(_ data: Data) -> (frames: [UIImage], delays: [Double])? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let n = CGImageSourceGetCount(src)
        guard n > 1 else { return nil }
        var frames: [UIImage] = []
        var delays: [Double] = []
        var total = 0.0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        for i in 0..<n {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, i, opts as CFDictionary) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let g = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = max(0.02, (g?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (g?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1)
            if total + d > maxSeconds { break }
            total += d
            frames.append(UIImage(cgImage: cg))
            delays.append(d)
        }
        return frames.count > 1 ? (frames, delays) : nil
    }

    static func videoFrame(url: URL, at t: Double, maxSize: CGFloat = 160) -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxSize, height: maxSize)
        let time = CMTime(seconds: t, preferredTimescale: 600)
        if let cg = try? gen.copyCGImage(at: time, actualTime: nil) { return UIImage(cgImage: cg) }
        return nil
    }

    static func videoFrames(url: URL, start: Double, length: Double, transform: (UIImage) -> UIImage) -> [UIImage] {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 768, height: 768)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let n = min(150, max(2, Int(length * videoFPS)))
        var frames: [UIImage] = []
        for i in 0..<n {
            autoreleasepool {
                let t = CMTime(seconds: start + Double(i) / videoFPS, preferredTimescale: 600)
                if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
                    frames.append(transform(UIImage(cgImage: cg)))
                } else if let last = frames.last {
                    frames.append(last)
                }
            }
        }
        return frames
    }

    static func resample(_ img: UIImage, _ s: CGFloat) -> UIImage {
        let small = CGSize(width: 512 * s, height: 512 * s)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        let a = UIGraphicsImageRenderer(size: small, format: f).image { _ in
            img.draw(in: CGRect(origin: .zero, size: small))
        }
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: f).image { _ in
            a.draw(in: CGRect(x: 0, y: 0, width: 512, height: 512))
        }
    }

    private static func encodeOnce(_ frames: [UIImage], _ durs: [Double], _ q: Double) -> Data? {
        let opts: [SDImageCoderOption: Any] = [.encodeCompressionQuality: q]
        if frames.count > 1 {
            var fr: [SDImageFrame] = []
            for (i, f) in frames.enumerated() {
                fr.append(SDImageFrame(image: f, duration: max(0.02, durs[i])))
            }
            guard let anim = SDImageCoderHelper.animatedImage(with: fr) else { return nil }
            return SDImageWebPCoder.shared.encodedData(with: anim, format: .webP, options: opts)
        }
        return SDImageWebPCoder.shared.encodedData(with: frames[0], format: .webP, options: opts)
    }

    static func encode(frames: [UIImage], durations: [Double]) -> Data? {
        guard !frames.isEmpty, durations.count == frames.count else { return nil }
        let animated = frames.count > 1
        let limit = animated ? 500_000 : 100_000
        let cands: [(CGFloat, Double)] = animated
            ? [(1, 0.75), (1, 0.55), (1, 0.35), (0.85, 0.5), (0.85, 0.3), (0.7, 0.4), (0.7, 0.25), (0.55, 0.3), (0.45, 0.2)]
            : [(1, 0.9), (1, 0.7), (1, 0.5), (0.85, 0.5), (0.7, 0.4), (0.55, 0.3)]
        for (s, q) in cands {
            let fr = s == 1 ? frames : frames.map { resample($0, s) }
            if animated && fr.count > 30 {
                let n = 20
                if let p1 = encodeOnce([fr[0]], [durations[0]], q),
                   let pn = encodeOnce(Array(fr.prefix(n)), Array(durations.prefix(n)), q) {
                    let delta = Double(max(0, pn.count - p1.count)) / Double(n - 1)
                    let est = Double(p1.count) + delta * Double(fr.count - 1)
                    if est > Double(limit) * 1.3 { continue }
                }
            }
            if let d = encodeOnce(fr, durations, q), d.count <= limit { return d }
        }
        return nil
    }
}
