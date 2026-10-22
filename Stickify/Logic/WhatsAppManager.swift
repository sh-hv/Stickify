import UIKit
class WhatsAppManager {
    static let shared = WhatsAppManager()
    func sendToWhatsApp(pack: StickerPack){
        guard pack.stickers.count >= 3 else { return }
        if let url = URL(string: "whatsapp://"), UIApplication.shared.canOpenURL(url){
            UIApplication.shared.open(url)
        }
    }
}
