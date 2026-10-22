import SwiftUI
import PhotosUI

struct CreatePackView: View {
    @ObservedObject var store: StickerStore
    @Environment(\.dismiss) var dismiss
    @State var packName = ""
    @State var publisher = ""
    @State var selectedType = 0
    @State var stickers: [Sticker] = []
    @State var showPicker = false
    
    var body: some View {
        NavigationStack{
            Form{
                Section("معلومات الحزمة"){
                    TextField("اسم الحزمة", text: $packName)
                    TextField("اسم الناشر", text: $publisher)
                }
                Section{
                    Picker("نوع الحزمة", selection: $selectedType){
                        Text("صور ثابتة").tag(0)
                        Text("متحركة GIF / فيديو").tag(1)
                    }.pickerStyle(.segmented)
                }
                Section("الستيكرات \(stickers.count)/30"){
                    ScrollView(.horizontal, showsIndicators: false){
                        HStack{
                            Button{ showPicker = true } label: {
                                VStack{ Image(systemName: "plus"); Text("اضافة") }.frame(width: 80, height: 80).background(Color.green.opacity(0.15)).cornerRadius(12)
                            }
                            ForEach(stickers){ s in
                                Image(uiImage: s.image).resizable().scaledToFill().frame(width: 80, height: 80).clipped().cornerRadius(12).overlay(Text(s.emoji).offset(y: 25))
                            }
                        }
                    }
                    if selectedType == 1 { Text("سيتم تحويل الفيديو الى WebP متحرك 512x512 بضغط ذكي بدون تقطيع فريمات - نضحي بالدقة ونحافظ على السلاسة").font(.caption).foregroundColor(.orange) }
                }
                Button("حفظ حزمة Stickify"){
                    guard !packName.isEmpty, !publisher.isEmpty, stickers.count >= 3 else { return }
                    let pack = StickerPack(name: packName, publisher: publisher, trayImage: stickers.first!.image, stickers: stickers)
                    store.packs.append(pack)
                    dismiss()
                }.disabled(packName.isEmpty || stickers.count < 3)
            }
            .navigationTitle("حزمة جديدة")
            .sheet(isPresented: $showPicker){ MediaPicker(stickers: $stickers, isVideo: selectedType == 1) }
        }
    }
}
