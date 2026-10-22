import SwiftUI

@main
struct StickifyApp: App {
    @AppStorage("isDarkMode") var isDarkMode = false
    @AppStorage("language") var language = "ar"
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .environment(\.locale, Locale(identifier: language == "ar" ? "ar" : "en"))
        }
    }
}
