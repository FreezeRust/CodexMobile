import SwiftUI

@main
struct OpenVoltApp: App {
    @StateObject private var appStore = AppStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appStore)
                .environmentObject(settings)
                .environmentObject(session)
                .tint(settings.accent.color)
                .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}
