import UIKit

struct Sticker: Identifiable, Hashable {
    let id = UUID()
    var image: UIImage
    var emoji: String = "😍"
    var isAnimated: Bool = false
    var webPData: Data?
}

struct StickerPack: Identifiable {
    let id = UUID()
    var name: String
    var publisher: String
    var trayImage: UIImage
    var stickers: [Sticker]
    var trayImageData: Data { trayImage.pngData() ?? Data() }
}

class StickerStore: ObservableObject {
    @Published var packs: [StickerPack] = []
}
