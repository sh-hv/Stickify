import SwiftUI
import UIKit
import SDWebImage
import SDWebImageWebPCoder

func tr(_ ar: String, _ en: String) -> String {
    (UserDefaults.standard.string(forKey: "lang") ?? "ar") == "ar" ? ar : en
}

enum Palette {
    static let colors: [Color] = [.green, .blue, .purple, .pink, .orange, .teal]
}

struct StickerMeta: Codable, Identifiable, Hashable {
    var id: String
    var emojis: [String]
}

struct PackMeta: Codable, Identifiable {
    var id: String
    var name: String
    var publisher: String
    var animated: Bool
    var stickers: [StickerMeta]
}

final class Library: ObservableObject {
    @Published var packs: [PackMeta] = []
    let root: URL
    private let cache = NSCache<NSString, UIImage>()

    init() {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("StickifyLib")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        root = d
        if let data = try? Data(contentsOf: d.appendingPathComponent("packs.json")),
           let p = try? JSONDecoder().decode([PackMeta].self, from: data) { packs = p }
    }

    func persist() {
        if let d = try? JSONEncoder().encode(packs) {
            try? d.write(to: root.appendingPathComponent("packs.json"))
        }
    }

    func url(_ sid: String) -> URL { root.appendingPathComponent(sid + ".webp") }

    func data(_ sid: String) -> Data? { try? Data(contentsOf: url(sid)) }

    func writeSticker(_ sid: String, _ data: Data) {
        try? data.write(to: url(sid))
        cache.removeObject(forKey: sid as NSString)
    }

    func thumb(_ sid: String) -> UIImage {
        if let c = cache.object(forKey: sid as NSString) { return c }
        guard let d = data(sid) else { return UIImage() }
        let opts: [SDImageCoderOption: Any] = [.decodeFirstFrameOnly: true]
        let img = SDImageWebPCoder.shared.decodedImage(with: d, options: opts) ?? UIImage()
        cache.setObject(img, forKey: sid as NSString)
        return img
    }

    func addPack(name: String, publisher: String, animated: Bool) -> String {
        let p = PackMeta(id: UUID().uuidString, name: name, publisher: publisher, animated: animated, stickers: [])
        packs.append(p)
        persist()
        return p.id
    }

    func rename(_ id: String, name: String) {
        guard let i = packs.firstIndex(where: { $0.id == id }) else { return }
        packs[i].name = name
        persist()
    }

    func deletePack(_ id: String) {
        guard let i = packs.firstIndex(where: { $0.id == id }) else { return }
        for s in packs[i].stickers { try? FileManager.default.removeItem(at: url(s.id)) }
        packs.remove(at: i)
        persist()
    }

    func deleteAll() {
        for p in packs { for s in p.stickers { try? FileManager.default.removeItem(at: url(s.id)) } }
        packs = []
        persist()
    }

    func addSticker(_ packID: String, data: Data, emojis: [String]) {
        guard let i = packs.firstIndex(where: { $0.id == packID }) else { return }
        let sid = UUID().uuidString
        writeSticker(sid, data)
        packs[i].stickers.append(StickerMeta(id: sid, emojis: emojis))
        persist()
    }

    func setEmojis(_ packID: String, _ sid: String, _ emojis: [String]) {
        guard let i = packs.firstIndex(where: { $0.id == packID }),
              let j = packs[i].stickers.firstIndex(where: { $0.id == sid }) else { return }
        packs[i].stickers[j].emojis = emojis
        persist()
    }

    func deleteSticker(_ packID: String, _ sid: String) {
        guard let i = packs.firstIndex(where: { $0.id == packID }) else { return }
        try? FileManager.default.removeItem(at: url(sid))
        packs[i].stickers.removeAll { $0.id == sid }
        persist()
    }
}

enum WhatsApp {
    static func send(_ pack: PackMeta, lib: Library) -> String? {
        guard pack.stickers.count >= 3 else {
            return tr("لازم 3 ستيكرات على الأقل (الحد الأقصى 30)", "You need at least 3 stickers (max 30)")
        }
        guard let wa = URL(string: "whatsapp://stickerPack"), UIApplication.shared.canOpenURL(wa) else {
            return tr("واتساب غير مثبت على الجهاز", "WhatsApp is not installed")
        }
        let list = Array(pack.stickers.prefix(30))
        let side: CGFloat = 96
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        let first = lib.thumb(list[0].id)
        let tray = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
            first.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let trayPNG = tray.pngData() else { return tr("فشل إنشاء أيقونة الحزمة", "Failed to create tray icon") }
        var items: [[String: Any]] = []
        for s in list {
            guard let d = lib.data(s.id) else { continue }
            let em = s.emojis.isEmpty ? ["😀"] : [s.emojis[0]]
            items.append(["image_data": d.base64EncodedString(), "emojis": em])
        }
        let json: [String: Any] = [
            "identifier": pack.id + "." + String(list.count),
            "name": pack.name,
            "publisher": pack.publisher,
            "tray_image": trayPNG.base64EncodedString(),
            "is_animated_sticker_pack": pack.animated,
            "animated_sticker_pack": pack.animated,
            "stickers": items
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else {
            return tr("فشل تجهيز البيانات", "Failed to prepare data")
        }
        UIPasteboard.general.setItems(
            [["net.whatsapp.third-party.sticker-pack": data]],
            options: [.localOnly: true, .expirationDate: Date(timeIntervalSinceNow: 60)]
        )
        UIApplication.shared.open(wa)
        return nil
    }
}

@main
struct StickifyApp: App {
    @StateObject private var lib = Library()
    @AppStorage("lang") private var lang = "ar"
    @AppStorage("theme") private var theme = 0
    @AppStorage("accent") private var accent = 0

    init() { SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared) }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .id(lang)
                .environmentObject(lib)
                .environment(\.layoutDirection, lang == "ar" ? .rightToLeft : .leftToRight)
                .tint(Palette.colors[min(accent, Palette.colors.count - 1)])
                .preferredColorScheme(theme == 1 ? .light : (theme == 2 ? .dark : nil))
        }
    }
}
