import SwiftUI
import PhotosUI

struct AnimCell: View {
    let sid: String
    @EnvironmentObject var lib: Library
    @State private var data: Data?
    var body: some View {
        Group {
            if let data { AnimView(data: data) } else { Color.clear }
        }
        .allowsHitTesting(false)
        .task { data = lib.data(sid) }
    }
}

struct HomeView: View {
    @EnvironmentObject var lib: Library
    @State private var showNew = false
    @State private var showSettings = false
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if lib.packs.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Stickify")
            .navigationDestination(for: String.self) { id in PackView(packID: id) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                }
            }
            .sheet(isPresented: $showNew) { NewPackSheet { id in path.append(id) } }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "face.smiling").font(.system(size: 64)).foregroundStyle(.tint)
            Text(tr("ما عندك حزم ستيكرات بعد", "No sticker packs yet")).font(.title3.bold())
            Text(tr("اضغط + بالزاوية لإنشاء أول حزمة", "Tap + in the corner to create your first pack"))
                .foregroundStyle(.secondary)
        }.padding()
    }

    private var list: some View {
        List {
            ForEach(lib.packs) { pack in
                NavigationLink(value: pack.id) { PackRow(pack: pack) }
            }
            .onDelete { offsets in
                let ids = offsets.map { lib.packs[$0].id }
                for id in ids { lib.deletePack(id) }
            }
        }
    }
}

struct PackRow: View {
    @EnvironmentObject var lib: Library
    let pack: PackMeta
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let f = pack.stickers.first {
                    if pack.animated {
                        AnimCell(sid: f.id).padding(6)
                    } else {
                        Image(uiImage: lib.thumb(f.id)).resizable().scaledToFit().padding(6)
                    }
                } else {
                    Image(systemName: "face.smiling").foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.name).font(.headline)
                Text("\(pack.stickers.count)/30 · " + (pack.animated ? tr("متحركة", "Animated") : tr("صور", "Images")))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct NewPackSheet: View {
    @EnvironmentObject var lib: Library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("publisher") private var defaultPublisher = ""
    @State private var animated = false
    @State private var name = ""
    @State private var publisher = ""
    var onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("نوع الحزمة", "Pack type")) {
                    typeRow(false, "photo", tr("صور", "Images"), tr("قص وتكبير وإضافة نص", "Crop, zoom and add text"))
                    typeRow(true, "film", tr("متحركة (فيديو أو GIF)", "Animated (video or GIF)"), tr("تحويل فيديو أو GIF لستيكر", "Turn a video or GIF into a sticker"))
                }
                Section {
                    TextField(tr("اسم الحزمة", "Pack name"), text: $name)
                    TextField(tr("الناشر", "Publisher"), text: $publisher)
                }
            }
            .navigationTitle(tr("حزمة جديدة", "New pack"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { publisher = defaultPublisher }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("إلغاء", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("إنشاء", "Create")) {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let pub = publisher.trimmingCharacters(in: .whitespaces)
                        let id = lib.addPack(name: n, publisher: pub.isEmpty ? "Stickify" : pub, animated: animated)
                        dismiss()
                        onCreate(id)
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func typeRow(_ value: Bool, _ icon: String, _ title: String, _ sub: String) -> some View {
        Button { animated = value } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if animated == value { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
        }.buttonStyle(.plain)
    }
}

struct PackView: View {
    let packID: String
    @EnvironmentObject var lib: Library
    @State private var pick: PhotosPickerItem?
    @State private var job: EditJob?
    @State private var loading = false
    @State private var message: String?
    @State private var detail: StickerMeta?
    @State private var showRename = false
    @State private var newName = ""

    private var pack: PackMeta? { lib.packs.first { $0.id == packID } }

    var body: some View {
        Group {
            if let pack { content(pack) } else { Text("") }
        }
    }

    private func content(_ pack: PackMeta) -> some View {
        let filter: PHPickerFilter = pack.animated ? .any(of: [.videos, .images]) : .images
        return VStack(spacing: 10) {
            Text("\(pack.publisher) · \(pack.stickers.count)/30").font(.footnote).foregroundStyle(.secondary)
            ScrollView {
                if pack.stickers.isEmpty {
                    Text(pack.animated
                         ? tr("اضغط + واختر فيديو أو GIF", "Tap + and pick a video or GIF")
                         : tr("اضغط + واختر صورة", "Tap + and pick a photo"))
                        .foregroundStyle(.secondary).padding(.top, 60)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                    ForEach(pack.stickers) { s in
                        Button { detail = s } label: {
                            ZStack {
                                if pack.animated {
                                    AnimCell(sid: s.id)
                                } else {
                                    Image(uiImage: lib.thumb(s.id)).resizable().scaledToFit()
                                }
                            }
                            .padding(6)
                            .aspectRatio(1, contentMode: .fit)
                            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .bottomTrailing) {
                                Text(s.emojis.first ?? "").font(.caption).padding(3)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal)
            }
            Button {
                message = WhatsApp.send(pack, lib: lib)
            } label: {
                Label(tr("إضافة إلى واتساب", "Add to WhatsApp"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity).padding()
                    .foregroundStyle(.white)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 16))
            }.padding(.horizontal).padding(.bottom, 8)
        }
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Menu {
                        Button(tr("إعادة تسمية", "Rename")) { newName = pack.name; showRename = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                    PhotosPicker(selection: $pick, matching: filter) {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }.disabled(pack.stickers.count >= 30)
                }
            }
        }
        .overlay {
            if loading {
                ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .onChange(of: pick) { _ in Task { await loadPick(pack.animated) } }
        .fullScreenCover(item: $job) { j in
            StickerEditor(packID: packID, animatedPack: pack.animated, source: j.source)
        }
        .sheet(item: $detail) { s in StickerDetail(packID: packID, sticker: s) }
        .alert(tr("إعادة تسمية", "Rename"), isPresented: $showRename) {
            TextField(tr("اسم الحزمة", "Pack name"), text: $newName)
            Button(tr("حفظ", "Save")) {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { lib.rename(packID, name: n) }
            }
            Button(tr("إلغاء", "Cancel"), role: .cancel) {}
        }
        .alert(tr("تنبيه", "Notice"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    @MainActor
    private func loadPick(_ animated: Bool) async {
        guard let item = pick else { return }
        loading = true
        if animated, let m = try? await item.loadTransferable(type: Movie.self) {
            job = EditJob(source: .video(m.url))
        } else if let d = try? await item.loadTransferable(type: Data.self) {
            if animated {
                if let g = Imaging.gifFrames(d) {
                    job = EditJob(source: .gif(g.frames, g.delays))
                } else {
                    message = tr("الحزمة المتحركة تقبل فيديو أو GIF فقط", "Animated packs accept video or GIF only")
                }
            } else if let ui = UIImage(data: d) {
                job = EditJob(source: .image(Imaging.normalize(ui)))
            }
        }
        loading = false
        pick = nil
    }
}

struct StickerDetail: View {
    let packID: String
    let sticker: StickerMeta
    @EnvironmentObject var lib: Library
    @Environment(\.dismiss) private var dismiss
    @State private var emoji = "😀"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let d = lib.data(sticker.id) {
                        ZStack(alignment: .bottomTrailing) {
                            AnimView(data: d).frame(width: 200, height: 200)
                            Text(emoji).font(.system(size: 48)).padding(6)
                        }
                    }
                    EmojiGrid(selection: $emoji)
                    Button(role: .destructive) {
                        lib.deleteSticker(packID, sticker.id)
                        dismiss()
                    } label: { Label(tr("حذف الستيكر", "Delete sticker"), systemImage: "trash") }
                }.padding()
            }
            .navigationTitle(tr("ستيكر", "Sticker"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { emoji = sticker.emojis.first ?? "😀" }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("تم", "Done")) {
                        lib.setEmojis(packID, sticker.id, [emoji])
                        dismiss()
                    }
                }
            }
        }
    }
}

enum SettingsSheet: Identifiable {
    case share(URL)
    case picker
    var id: String {
        switch self {
        case .share(let u): return "share-" + u.absoluteString
        case .picker: return "picker"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var lib: Library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lang") private var lang = "ar"
    @AppStorage("theme") private var theme = 0
    @AppStorage("accent") private var accent = 0
    @AppStorage("publisher") private var publisher = ""

    @State private var sheet: SettingsSheet?
    @State private var showWipe = false
    @State private var status: String?

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                appearanceSection
                Section(tr("افتراضيات", "Defaults")) {
                    TextField(tr("اسم الناشر الافتراضي", "Default publisher name"), text: $publisher)
                }
                backupSection
                Section(tr("حول", "About")) {
                    HStack { Text(tr("الإصدار", "Version")); Spacer(); Text("1.3").foregroundStyle(.secondary) }
                }
                linksSection
                Section {
                    Button(tr("مسح كل البيانات", "Delete all data"), role: .destructive) { showWipe = true }
                }
                Section {
                    Text("أبرأ ذمتي من أي استخدام غير لائق للتطبيق")
                        .foregroundStyle(.red).font(.footnote.bold())
                    Text("I disclaim any responsibility for inappropriate use of this app")
                        .foregroundStyle(.red).font(.footnote.bold())
                }
            }
            .navigationTitle(tr("الإعدادات", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(tr("تم", "Done")) { dismiss() } }
            }
            .confirmationDialog(tr("مسح كل الحزم والستيكرات؟", "Delete all packs and stickers?"),
                                isPresented: $showWipe, titleVisibility: .visible) {
                Button(tr("مسح", "Delete"), role: .destructive) { lib.deleteAll() }
            }
            .sheet(item: $sheet) { s in
                switch s {
                case .share(let u):
                    ShareSheet(url: u)
                case .picker:
                    DocumentPicker { url in handlePick(url) }
                }
            }
        }
    }

    private var languageSection: some View {
        Section(tr("اللغة", "Language")) {
            Picker("", selection: $lang) {
                Text("العربية").tag("ar")
                Text("English").tag("en")
            }.pickerStyle(.segmented)
        }
    }

    private var appearanceSection: some View {
        Section(tr("المظهر", "Appearance")) {
            Picker("", selection: $theme) {
                Text(tr("تلقائي", "System")).tag(0)
                Text(tr("فاتح", "Light")).tag(1)
                Text(tr("داكن", "Dark")).tag(2)
            }.pickerStyle(.segmented)
            HStack(spacing: 14) {
                Text(tr("لون التطبيق", "Accent color"))
                Spacer()
                ForEach(0..<Palette.colors.count, id: \.self) { i in
                    Circle().fill(Palette.colors[i]).frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.primary, lineWidth: accent == i ? 3 : 0))
                        .onTapGesture { accent = i }
                }
            }
        }
    }

    private var backupSection: some View {
        Section(tr("النسخ الاحتياطي", "Backup")) {
            Button {
                if let u = lib.makeBackup() { status = nil; sheet = .share(u) }
                else { status = tr("تعذر إنشاء النسخة", "Could not create the backup") }
            } label: { Label(tr("إنشاء نسخة احتياطية (ZIP)", "Create backup (ZIP)"), systemImage: "square.and.arrow.up") }
            .disabled(lib.packs.isEmpty)
            Button {
                status = nil
                sheet = .picker
            } label: {
                Label(tr("استرجاع من نسخة احتياطية", "Restore from backup"), systemImage: "square.and.arrow.down")
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var linksSection: some View {
        Section(tr("حسابي", "Follow me")) {
            linkRow(logo: "XLogo", title: "Spidey", url: "https://x.com/sh_hhv")
        }
    }

    @ViewBuilder
    private func linkRow(logo: String, title: String, url: String) -> some View {
        if let u = URL(string: url) {
            Link(destination: u) {
                HStack(spacing: 12) {
                    logoImage(logo)
                    Text(title)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func logoImage(_ name: String) -> some View {
        if UIImage(named: name) != nil {
            Image(name).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 22, height: 22).foregroundStyle(.primary)
        } else {
            Image(systemName: "link").frame(width: 22, height: 22)
        }
    }

    private func handlePick(_ url: URL?) {
        sheet = nil
        guard let url else { return }
        guard let d = try? Data(contentsOf: url), let n = lib.restore(d) else {
            status = tr("الملف غير صالح أو تالف", "The file is invalid or corrupted")
            return
        }
        status = tr("تم استرجاع \(n) حزمة", "Restored \(n) pack(s)")
    }
}
