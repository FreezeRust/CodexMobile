import SwiftUI

@main
struct OpenVoltApp: App {
    @StateObject private var appStore = AppStore()
    @StateObject private var settings = SettingsStore()
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(appStore)
                    .environmentObject(settings)

                if showOnboarding {
                    OnboardingView { withAnimation(.easeInOut(duration: 0.4)) { showOnboarding = false } }
                        .environmentObject(settings)
                        .environmentObject(appStore)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .tint(settings.accentColor)
            .preferredColorScheme(settings.resolvedScheme)
            .onAppear { showOnboarding = !settings.hasOnboarded }
        }
    }
}
