import SwiftUI

struct RootView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ZStack {
            if let bg = settings.theme.background {
                bg.ignoresSafeArea()
            }
            TabView {
                ProjectsView()
                    .tabItem { Label("Проекты", systemImage: "square.stack.3d.up.fill") }
                SettingsView()
                    .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
            }
        }
        .tint(settings.accent.color)
    }
}
