import SwiftUI
struct SettingsView: View {
    @AppStorage("isDarkMode") var isDarkMode = false
    @AppStorage("language") var language = "ar"
    var body: some View {
        Form{
            Section("المظهر"){ Toggle("الوضع الداكن", isOn: $isDarkMode) }
            Section("اللغة"){
                Picker("اللغة", selection: $language){
                    Text("العربية").tag("ar")
                    Text("English").tag("en")
                }
            }
            Section("Stickify"){ Text("الاصدار 1.0 - صنع بحب").foregroundColor(.secondary) }
        }.navigationTitle("الاعدادات")
    }
}
