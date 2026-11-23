import SwiftUI
import UIKit
import Compression
import UniformTypeIdentifiers

enum Zip {
    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    static func write(entries: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        for e in entries {
            let name = Data(e.name.utf8)
            let crc = crc32(e.data)
            let offset = UInt32(out.count)
            let size = UInt32(e.data.count)
            out.le32(0x04034b50); out.le16(20); out.le16(0x0800); out.le16(0)
            out.le16(0); out.le16(0x21)
            out.le32(crc); out.le32(size); out.le32(size)
            out.le16(UInt16(name.count)); out.le16(0)
            out.append(name); out.append(e.data)
            central.le32(0x02014b50); central.le16(20); central.le16(20); central.le16(0x0800); central.le16(0)
            central.le16(0); central.le16(0x21)
            central.le32(crc); central.le32(size); central.le32(size)
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0)
            central.le32(0); central.le32(offset)
            central.append(name)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.le32(0x06054b50); out.le16(0); out.le16(0)
        out.le16(UInt16(entries.count)); out.le16(UInt16(entries.count))
        out.le32(UInt32(central.count)); out.le32(cdOffset); out.le16(0)
        return out
    }

    static func read(_ d: Data) -> [String: Data]? {
        let bytes = [UInt8](d)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | (Int(bytes[o + 1]) << 8) }
        func u32(_ o: Int) -> Int { u16(o) | (u16(o + 2) << 16) }
        guard bytes.count >= 22 else { return nil }
        var eocd = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65535)
        while i >= lowest {
            if u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var result: [String: Data] = [:]
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x02014b50 else { return nil }
            let method = u16(p + 10)
            let csize = u32(p + 20)
            let usize = u32(p + 24)
            let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32)
            let lho = u32(p + 42)
            guard p + 46 + nlen <= bytes.count else { return nil }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + elen + clen
            guard lho + 30 <= bytes.count else { return nil }
            let ds = lho + 30 + u16(lho + 26) + u16(lho + 28)
            guard ds + csize <= bytes.count else { return nil }
            let comp = Data(bytes[ds..<(ds + csize)])
            if method == 0 {
                result[name] = comp
            } else if method == 8 {
                guard let inflated = inflate(comp, usize) else { return nil }
                result[name] = inflated
            } else { return nil }
        }
        return result
    }

    static func inflate(_ d: Data, _ size: Int) -> Data? {
        if size == 0 { return Data() }
        var out = Data(count: size)
        let n = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            d.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, size,
                    src.bindMemory(to: UInt8.self).baseAddress!, d.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        return n == size ? out : nil
    }
}

extension Data {
    mutating func le16(_ v: UInt16) {
        append(UInt8(v & 0xFF)); append(UInt8(v >> 8))
    }
    mutating func le32(_ v: UInt32) {
        for i in 0..<4 { append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) }
    }
}

extension Library {
    func makeBackup() -> URL? {
        guard let idx = try? JSONEncoder().encode(packs) else { return nil }
        var entries: [(name: String, data: Data)] = [("packs.json", idx)]
        for p in packs {
            for s in p.stickers {
                if let d = data(s.id) { entries.append((s.id + ".webp", d)) }
            }
        }
        let zip = Zip.write(entries: entries)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Stickify-backup-\(f.string(from: Date())).zip")
        do { try zip.write(to: url); return url } catch { return nil }
    }

    func restore(_ zip: Data) -> Int? {
        guard let files = Zip.read(zip),
              let idx = files["packs.json"],
              let incoming = try? JSONDecoder().decode([PackMeta].self, from: idx) else { return nil }
        var n = 0
        for var p in incoming {
            p.stickers = p.stickers.filter { files[$0.id + ".webp"] != nil }
            for s in p.stickers {
                if let d = files[s.id + ".webp"] { writeSticker(s.id, d) }
            }
            if let i = packs.firstIndex(where: { $0.id == p.id }) { packs[i] = p } else { packs.append(p) }
            n += 1
        }
        persist()
        return n
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.zip, .data], asCopy: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(_ f: @escaping (URL?) -> Void) { onPick = f }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
