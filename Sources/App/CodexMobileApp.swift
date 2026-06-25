import SwiftUI

@main
struct OpenVoltApp: App {
    @StateObject private var appStore = AppStore()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appStore)
                .environmentObject(settings)
                .tint(settings.accentColor)
                .preferredColorScheme(settings.resolvedScheme)
        }
    }
}
