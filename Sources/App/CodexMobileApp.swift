import SwiftUI

@main
struct CodexMobileApp: App {
    @StateObject private var appStore = AppStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appStore)
                .environmentObject(settings)
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}
