import SwiftUI

struct ContentView: View {
    @StateObject var store = StickerStore()
    @State var showCreate = false
    var body: some View {
        NavigationStack {
            Group {
                if store.packs.isEmpty {
                    VStack(spacing: 15){
                        Image(systemName: "face.smiling.inverse").font(.system(size: 70)).foregroundColor(.green)
                        Text("لا توجد حزم بعد").font(.title3.bold())
                        Text("اضغط + لانشاء حزمة Stickify جديدة").foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(store.packs) { pack in
                        HStack{
                            Image(uiImage: pack.trayImage).resizable().frame(width: 60, height: 60).cornerRadius(12)
                            VStack(alignment: .leading){
                                Text(pack.name).bold()
                                Text(pack.publisher).font(.caption).foregroundColor(.secondary)
                                Text("\(pack.stickers.count) ستيكر").font(.caption2)
                            }
                            Spacer()
                            Button("للواتساب"){
                                WhatsAppManager.shared.sendToWhatsApp(pack: pack)
                            }.buttonStyle(.bordered).tint(.green)
                        }
                    }
                }
            }
            .navigationTitle("Stickify")
            .toolbar{
                ToolbarItem(placement: .navigationBarTrailing){
                    Button{ showCreate = true } label: { Image(systemName: "plus.circle.fill").font(.title2).tint(.green) }
                }
                ToolbarItem(placement: .navigationBarLeading){
                    NavigationLink(destination: SettingsView()){ Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showCreate){ CreatePackView(store: store) }
        }
    }
}
