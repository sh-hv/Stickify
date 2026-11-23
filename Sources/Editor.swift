import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import SDWebImage

enum Source {
    case image(UIImage)
    case gif([UIImage], [Double])
    case video(URL)
}

struct EditJob: Identifiable {
    let id = UUID()
    let source: Source
}

struct Movie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: dst)
            return Movie(url: dst)
        }
    }
}

enum CropShape: CaseIterable, Identifiable {
    case square, r43, r34, r169, r916, free
    var id: Self { self }
    var title: String {
        switch self {
        case .square: return tr("مربع", "Square")
        case .r43: return "4:3"
        case .r34: return "3:4"
        case .r169: return "16:9"
        case .r916: return "9:16"
        case .free: return tr("مخصص", "Free")
        }
    }
    var ratio: CGFloat? {
        switch self {
        case .square: return 1
        case .r43: return 4.0 / 3.0
        case .r34: return 3.0 / 4.0
        case .r169: return 16.0 / 9.0
        case .r916: return 9.0 / 16.0
        case .free: return nil
        }
    }
    func rect(_ S: CGFloat) -> CGRect {
        guard let r = ratio else { return CGRect(x: 0, y: 0, width: S, height: S) }
        var w = S, h = S
        if r >= 1 { h = S / r } else { w = S * r }
        return CGRect(x: (S - w) / 2, y: (S - h) / 2, width: w, height: h)
    }
}

struct EditParams {
    var S: CGFloat
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var shape: CropShape = .square
    var lasso: [CGPoint] = []
    var text: String = ""
    var textColor: Color = .white
    var textSize: CGFloat = 56
    var textPos: CGPoint = CGPoint(x: 0.5, y: 0.8)

    func render(_ src: UIImage) -> UIImage {
        let k = 512 / S
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: f).image { ctx in
            let c = ctx.cgContext
            c.saveGState()
            if shape == .free {
                if lasso.count > 2 {
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: lasso[0].x * k, y: lasso[0].y * k))
                    for pt in lasso.dropFirst() { path.addLine(to: CGPoint(x: pt.x * k, y: pt.y * k)) }
                    path.closeSubpath()
                    c.addPath(path)
                    c.clip()
                }
            } else {
                let r = shape.rect(S)
                c.clip(to: CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k))
            }
            c.translateBy(x: 256 + offset.width * k, y: 256 + offset.height * k)
            c.scaleBy(x: scale, y: scale)
            let s = min(512 / src.size.width, 512 / src.size.height)
            let w = src.size.width * s, h = src.size.height * s
            src.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            c.restoreGState()
            if !text.isEmpty {
                let font = UIFont.systemFont(ofSize: textSize * k, weight: .heavy)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(textColor),
                    .strokeColor: UIColor.black,
                    .strokeWidth: -6
                ]
                let str = NSAttributedString(string: text, attributes: attrs)
                let sz = str.size()
                str.draw(at: CGPoint(x: textPos.x * 512 - sz.width / 2, y: textPos.y * 512 - sz.height / 2))
            }
        }
    }
}

struct CropDim: Shape {
    var shape: CropShape
    var S: CGFloat
    var lasso: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        if shape == .free {
            guard lasso.count > 2 else { return Path() }
            p.move(to: lasso[0])
            for pt in lasso.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
        } else {
            p.addRect(shape.rect(S))
        }
        return p
    }
}

enum Media {
    case image(UIImage)
    case frames([UIImage], [Double])
    case player(AVPlayer)
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.backgroundColor = .clear
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.player = player
        return v
    }
    func updateUIView(_ v: PlayerUIView, context: Context) { v.playerLayer.player = player }
}

struct FramesView: View {
    let frames: [UIImage]
    let delays: [Double]
    var body: some View {
        let total = max(0.04, delays.reduce(0, +))
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
            Image(uiImage: frames[index(t)]).resizable().scaledToFit()
        }
    }
    private func index(_ t: Double) -> Int {
        var acc = 0.0
        for (i, d) in delays.enumerated() {
            acc += d
            if t < acc { return i }
        }
        return frames.count - 1
    }
}

final class VideoController: ObservableObject {
    let player = AVPlayer()
    var start = 0.0
    var end = 3.0
    private var obs: Any?

    func load(url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.isMuted = true
        obs = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.04, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            if t.seconds >= self.end - 0.02 { self.seek(self.start) }
        }
        seek(start)
        player.play()
    }

    func seek(_ t: Double) {
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
    }

    func setRange(start: Double, end: Double) {
        self.start = start
        self.end = end
        seek(start)
        player.play()
    }

    func stop() { player.pause() }

    deinit {
        if let o = obs { player.removeTimeObserver(o) }
        player.pause()
    }
}

struct EditCanvas: View {
    let media: Media
    @Binding var p: EditParams
    var drawing: Bool
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    @State private var isDrawing = false

    var body: some View {
        let S = p.S
        let move = DragGesture()
            .updating($drag) { v, s, _ in s = v.translation }
            .onEnded { v in
                p.offset = CGSize(width: p.offset.width + v.translation.width,
                                  height: p.offset.height + v.translation.height)
            }
        let zoom = MagnificationGesture()
            .updating($pinch) { v, s, _ in s = v }
            .onEnded { v in p.scale = min(8, max(0.2, p.scale * v)) }
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.18))
            mediaView(S)
                .scaleEffect(p.scale * pinch)
                .offset(x: p.offset.width + drag.width, y: p.offset.height + drag.height)
            CropDim(shape: p.shape, S: S, lasso: p.lasso)
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            outline
            if !p.text.isEmpty { textView(S) }
            if drawing { Color.clear.contentShape(Rectangle()).gesture(lassoGesture) }
        }
        .frame(width: S, height: S)
        .clipped()
        .coordinateSpace(name: "canvas")
        .gesture(move.simultaneously(with: zoom), including: drawing ? .none : .all)
    }

    @ViewBuilder private func mediaView(_ S: CGFloat) -> some View {
        switch media {
        case .image(let img):
            Image(uiImage: img).resizable().scaledToFit().frame(width: S, height: S)
        case .frames(let fr, let ds):
            FramesView(frames: fr, delays: ds).frame(width: S, height: S)
        case .player(let pl):
            PlayerView(player: pl).frame(width: S, height: S)
        }
    }

    @ViewBuilder private var outline: some View {
        if p.shape == .free {
            Path { path in
                if let f = p.lasso.first {
                    path.move(to: f)
                    for pt in p.lasso.dropFirst() { path.addLine(to: pt) }
                    if p.lasso.count > 2 { path.closeSubpath() }
                }
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .allowsHitTesting(false)
        } else {
            Path(p.shape.rect(p.S)).stroke(Color.white.opacity(0.9), lineWidth: 1.5).allowsHitTesting(false)
        }
    }

    private var lassoGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
            .onChanged { v in
                if !isDrawing { isDrawing = true; p.lasso = [] }
                if let l = p.lasso.last, hypot(l.x - v.location.x, l.y - v.location.y) < 4 { return }
                p.lasso.append(v.location)
            }
            .onEnded { _ in isDrawing = false }
    }

    private func textView(_ S: CGFloat) -> some View {
        Text(p.text)
            .font(.system(size: p.textSize, weight: .heavy))
            .foregroundColor(p.textColor)
            .shadow(color: .black, radius: 1)
            .shadow(color: .black, radius: 1)
            .fixedSize()
            .gesture(
                DragGesture(coordinateSpace: .named("canvas")).onChanged { v in
                    p.textPos = CGPoint(x: min(1, max(0, v.location.x / S)),
                                        y: min(1, max(0, v.location.y / S)))
                }
            )
            .position(x: p.textPos.x * S, y: p.textPos.y * S)
    }
}

struct TrimBar: View {
    @Binding var start: Double
    @Binding var end: Double
    let winStart: Double
    let winEnd: Double
    let thumbs: [UIImage]
    var onChange: () -> Void
    private let H: CGFloat = 56
    private let hw: CGFloat = 18
    private let minLen = Imaging.minSeconds
    private let maxLen = Imaging.maxSeconds

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let span = max(0.1, winEnd - winStart)
            let x0 = min(W, max(0, CGFloat((start - winStart) / span) * W))
            let x1 = min(W, max(0, CGFloat((end - winStart) / span) * W))
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(thumbs.indices, id: \.self) { i in
                        Image(uiImage: thumbs[i]).resizable().scaledToFill()
                            .frame(width: W / CGFloat(max(1, thumbs.count)), height: H).clipped()
                    }
                }
                .frame(width: W, height: H, alignment: .leading)
                .background(Color.gray.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Rectangle().fill(Color.black.opacity(0.6)).frame(width: max(0, x0), height: H)
                Rectangle().fill(Color.black.opacity(0.6)).frame(width: max(0, W - x1), height: H).offset(x: x1)
                Rectangle().stroke(Color.yellow, lineWidth: 3).frame(width: max(hw * 2, x1 - x0), height: H).offset(x: x0)

                handle("chevron.compact.right")
                    .offset(x: x0)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim")).onChanged { v in
                        var s = winStart + Double((v.location.x - hw / 2) / W) * span
                        s = max(winStart, min(s, end - minLen))
                        s = max(s, end - maxLen)
                        start = max(0, s)
                        onChange()
                    })
                handle("chevron.compact.left")
                    .offset(x: x1 - hw)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim")).onChanged { v in
                        var e = winStart + Double((v.location.x + hw / 2) / W) * span
                        e = min(winEnd, max(e, start + minLen))
                        e = min(e, start + maxLen)
                        end = e
                        onChange()
                    })
            }
            .frame(width: W, height: H)
            .coordinateSpace(name: "trim")
        }
        .frame(height: H)
    }

    private func handle(_ icon: String) -> some View {
        Rectangle().fill(Color.yellow).frame(width: hw, height: H)
            .overlay(Image(systemName: icon).foregroundColor(.black))
    }
}

struct EmojiGrid: View {
    @Binding var selection: String
    static let all: [String] = ["❤️"] + Array("😀😁😂🤣😊😍🥰😘😎🤩🥳😜🤪😏😴🤔🙄😮😢😭😡🤯😱🥶🤢🤡👻💀👽🤖🎃👍👎👏🙌🙏💪👀🧡💛💚💙💜🖤💔🔥✨🌟💯🎉🎂🍕🍔🍟🍺🎮🚗🐶🐱🐼🦁🐸🙈").map { String($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("اختر إيموجي واحد للستيكر", "Pick one emoji for the sticker")).font(.footnote).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 6) {
                ForEach(EmojiGrid.all, id: \.self) { e in
                    Button { selection = e } label: {
                        Text(e).font(.system(size: 28)).frame(width: 44, height: 44)
                            .background(selection == e ? Color.accentColor.opacity(0.3) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct AnimView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> SDAnimatedImageView {
        let v = SDAnimatedImageView()
        v.contentMode = .scaleAspectFit
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.image = SDAnimatedImage(data: data)
        return v
    }
    func updateUIView(_ v: SDAnimatedImageView, context: Context) {}
}

struct EmojiSheet: View {
    @Binding var selection: String
    let data: Data?
    let warning: String?
    var onSave: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let data {
                        ZStack(alignment: .bottomTrailing) {
                            AnimView(data: data).frame(width: 160, height: 160)
                            Text(selection).font(.system(size: 44)).padding(6)
                        }
                    }
                    if let data {
                        Text(String(format: "%.0f KB", Double(data.count) / 1024)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let warning {
                        Text(tr("تحذير: ", "Warning: ") + warning).font(.footnote).foregroundStyle(.orange)
                    }
                    EmojiGrid(selection: $selection)
                }.padding()
            }
            .navigationTitle(tr("الإيموجي", "Emoji"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("حفظ", "Save"), action: onSave)
                }
            }
        }
    }
}

struct StickerEditor: View {
    let packID: String
    let animatedPack: Bool
    let source: Source
    @EnvironmentObject var lib: Library
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vc = VideoController()

    @State private var original: UIImage?
    @State private var working: UIImage?
    @State private var p = EditParams(S: min(UIScreen.main.bounds.width - 32, 400))
    @State private var removeBG = false
    @State private var drawing = false
    @State private var vidDur = 0.0
    @State private var start = 0.0
    @State private var end = 3.0
    @State private var thumbs: [UIImage] = []
    @State private var winStart = 0.0
    @State private var winEnd = 1.0
    @State private var zoomed = false
    @State private var busy = false
    @State private var error: String?
    @State private var pendingData: Data?
    @State private var warning: String?
    @State private var emoji = "😀"
    @State private var showEmoji = false

    private var isImage: Bool { if case .image = source { return true }; return false }
    private var isVideo: Bool { if case .video = source { return true }; return false }
    private var isGif: Bool { if case .gif = source { return true }; return false }

    private var media: Media? {
        switch source {
        case .image: if let w = working { return .image(w) } else { return nil }
        case .gif(let fr, let d): return .frames(fr, d)
        case .video: return .player(vc.player)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    canvas
                    if isVideo && vidDur > 0 { trimSection }
                    if isVideo || isGif {
                        Text(tr("الدقة 512×512 و15 فريم بالثانية، حسب متطلبات واتساب", "512×512 at 15 fps, per WhatsApp requirements"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    shapeChips
                    if p.shape == .free { lassoControls }
                    zoomRow
                    textRow
                    if isImage { Toggle(tr("حذف تلقائي للخلفية", "Auto remove background"), isOn: $removeBG) }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }.padding()
            }
            .navigationTitle(tr("تعديل الستيكر", "Edit sticker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("إلغاء", "Cancel")) { vc.stop(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if busy { ProgressView() }
                    else { Button(tr("التالي", "Next"), action: export).disabled(media == nil) }
                }
            }
            .task { await prepare() }
            .onChange(of: removeBG) { on in toggleBG(on) }
            .sheet(isPresented: $showEmoji) {
                EmojiSheet(selection: $emoji, data: pendingData, warning: warning) {
                    if let d = pendingData { lib.addSticker(packID, data: d, emojis: [emoji]) }
                    showEmoji = false
                    vc.stop()
                    dismiss()
                }
            }
        }
    }

    private var canvas: some View {
        Group {
            if let m = media {
                EditCanvas(media: m, p: $p, drawing: drawing && p.shape == .free)
            } else {
                ProgressView().frame(width: p.S, height: p.S)
            }
        }
    }

    private var frameStep: Double { 1.0 / Imaging.videoFPS }

    private var trimSection: some View {
        VStack(spacing: 8) {
            TrimBar(start: $start, end: $end, winStart: winStart, winEnd: winEnd, thumbs: thumbs) {
                vc.setRange(start: start, end: end)
            }
            HStack {
                nudgeGroup(tr("البداية", "Start"), value: start,
                           minus: { nudgeStart(-frameStep) }, plus: { nudgeStart(frameStep) })
                Spacer()
                nudgeGroup(tr("النهاية", "End"), value: end,
                           minus: { nudgeEnd(-frameStep) }, plus: { nudgeEnd(frameStep) })
            }
            HStack {
                Text(String(format: tr("المدة %.2f ث (الحد الأقصى 10)", "Length %.2fs (max 10)"), end - start))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { toggleZoom() } label: {
                    Label(zoomed ? tr("إلغاء التكبير", "Zoom out") : tr("تكبير الشريط", "Zoom timeline"),
                          systemImage: zoomed ? "minus.magnifyingglass" : "plus.magnifyingglass")
                        .font(.caption)
                }
            }
        }
    }

    private func nudgeGroup(_ title: String, value: Double, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Button(action: minus) { Image(systemName: "minus.circle") }
            Text(String(format: "%.2f", value)).font(.caption.monospacedDigit()).frame(minWidth: 44)
            Button(action: plus) { Image(systemName: "plus.circle") }
        }.buttonStyle(.borderless)
    }

    private var shapeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(CropShape.allCases) { s in
                    Button {
                        p.shape = s
                        if s != .free { drawing = false }
                    } label: {
                        Text(s.title).padding(.horizontal, 14).padding(.vertical, 8)
                            .background(p.shape == s ? Color.accentColor : Color.gray.opacity(0.2), in: Capsule())
                            .foregroundStyle(p.shape == s ? Color.white : Color.primary)
                    }
                }
            }
        }
    }

    private var lassoControls: some View {
        HStack {
            Toggle(tr("ارسم حدود القص بإصبعك", "Draw the cut outline"), isOn: $drawing)
            Button(tr("مسح", "Clear")) { p.lasso = [] }
        }
    }

    private var zoomRow: some View {
        HStack {
            Image(systemName: "minus.magnifyingglass")
            Slider(value: $p.scale, in: 0.2...5)
            Image(systemName: "plus.magnifyingglass")
            Button { p.scale = 1; p.offset = .zero } label: { Image(systemName: "arrow.counterclockwise") }
        }
    }

    private var textRow: some View {
        VStack(spacing: 8) {
            TextField(tr("أضف نص على الستيكر", "Add text to sticker"), text: $p.text).textFieldStyle(.roundedBorder)
            if !p.text.isEmpty {
                HStack {
                    ColorPicker("", selection: $p.textColor).labelsHidden()
                    Slider(value: $p.textSize, in: 24...120)
                }
                Text(tr("اسحب النص على الصورة لتحريكه", "Drag the text on the image to move it"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func prepare() async {
        switch source {
        case .image(let ui):
            original = ui; working = ui
        case .gif(let fr, _):
            original = fr.first; working = fr.first
        case .video(let url):
            let d = (try? await AVURLAsset(url: url).load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
            vidDur = d.isFinite ? d : 0
            guard vidDur > 0 else { error = tr("تعذر قراءة الفيديو", "Could not read the video"); return }
            start = 0
            end = min(Imaging.maxSeconds, vidDur)
            winStart = 0
            winEnd = vidDur
            vc.start = start
            vc.end = end
            vc.load(url: url)
            await buildThumbs()
        }
    }

    private func buildThumbs() async {
        guard case .video(let url) = source else { return }
        let a = winStart, b = winEnd
        let t = await Task.detached { () -> [UIImage] in
            let n = 12
            var out: [UIImage] = []
            for i in 0..<n {
                let time = a + (b - a) * (Double(i) + 0.5) / Double(n)
                if let img = Imaging.videoFrame(url: url, at: time) { out.append(img) }
            }
            return out
        }.value
        thumbs = t
    }

    private func toggleZoom() {
        zoomed.toggle()
        if zoomed {
            winStart = max(0, start - 1)
            winEnd = min(vidDur, max(end + 1, winStart + 1))
        } else {
            winStart = 0
            winEnd = vidDur
        }
        Task { await buildThumbs() }
    }

    private func nudgeStart(_ d: Double) {
        var s = start + d
        s = max(0, min(s, end - Imaging.minSeconds))
        s = max(s, end - Imaging.maxSeconds)
        start = s
        vc.setRange(start: start, end: end)
    }

    private func nudgeEnd(_ d: Double) {
        var x = end + d
        x = min(vidDur, max(x, start + Imaging.minSeconds))
        x = min(x, start + Imaging.maxSeconds)
        end = x
        vc.setRange(start: start, end: end)
    }

    private func toggleBG(_ on: Bool) {
        guard let o = original else { return }
        if !on { working = o; return }
        busy = true; error = nil
        Task.detached(priority: .userInitiated) {
            let m = Imaging.removeBackground(o)
            await MainActor.run {
                busy = false
                if let m { working = m }
                else { error = tr("تعذر حذف الخلفية، جرّب صورة فيها عنصر واضح", "Could not remove the background, try a photo with a clear subject") }
            }
        }
    }

    private func export() {
        guard !busy else { return }
        vc.stop()
        let params = p
        busy = true; error = nil
        let src = source
        let w = working
        let st = start
        let len = max(0.5, end - start)
        Task.detached(priority: .userInitiated) {
            var frames: [UIImage] = []
            var durs: [Double] = []
            switch src {
            case .image:
                if let w { frames = [params.render(w)]; durs = [0.1] }
            case .gif(let fr, let d):
                frames = fr.map { params.render($0) }
                durs = d
            case .video(let url):
                frames = Imaging.videoFrames(url: url, start: st, length: len) { params.render($0) }
                durs = Array(repeating: 1.0 / Imaging.videoFPS, count: frames.count)
            }
            let data = frames.isEmpty ? nil : Imaging.encode(frames: frames, durations: durs)
            let warn = data.flatMap { WebPInfo.warning($0, animated: frames.count > 1) }
            await MainActor.run {
                busy = false
                if let data {
                    pendingData = data
                    warning = warn
                    showEmoji = true
                } else {
                    error = tr("تعذر ضغط الستيكر ليدخل حد واتساب، جرّب مقطع أقصر أو أبسط", "Could not compress to WhatsApp's limit, try a shorter or simpler clip")
                    if isVideo { vc.setRange(start: start, end: end) }
                }
            }
        }
    }
}
