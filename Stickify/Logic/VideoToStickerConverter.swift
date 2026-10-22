import AVFoundation
import UIKit

class VideoConverter {
    static func convert(videoURL: URL, completion: @escaping (UIImage, Data) -> Void){
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        let duration = min(CMTimeGetSeconds(asset.duration), 3.0)
        Task{
            var frames: [UIImage] = []
            for i in 0..<30 {
                let time = CMTime(seconds: Double(i) * duration / 30.0, preferredTimescale: 600)
                if let cg = try? generator.copyCGImage(at: time, actualTime: nil){
                    frames.append(UIImage(cgImage: cg).resized(to: CGSize(width: 512, height: 512)))
                }
            }
            if let first = frames.first { completion(first, first.pngData()!) }
        }
    }
}
