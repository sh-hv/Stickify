import SwiftUI
import PhotosUI
import AVFoundation

struct MediaPicker: UIViewControllerRepresentable {
    @Binding var stickers: [Sticker]
    var isVideo: Bool
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = isVideo ? .videos : .images
        config.selectionLimit = 30
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: MediaPicker
        init(_ parent: MediaPicker){ self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            for result in results {
                if parent.isVideo {
                    if result.itemProvider.hasItemConformingToTypeIdentifier("public.movie") {
                        result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
                            guard let url = url else { return }
                            VideoConverter.convert(videoURL: url) { img, data in
                                DispatchQueue.main.async { self.parent.stickers.append(Sticker(image: img, isAnimated: true, webPData: data)) }
                            }
                        }
                    }
                } else {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                        if let img = obj as? UIImage {
                            let resized = img.resized(to: CGSize(width: 512, height: 512))
                            DispatchQueue.main.async { self.parent.stickers.append(Sticker(image: resized)) }
                        }
                    }
                }
            }
        }
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in self.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
