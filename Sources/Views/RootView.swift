import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ProjectsView()
                .tabItem { Label("Проекты", systemImage: "folder") }

            CodexWebView(urlString: "https://chatgpt.com/codex")
                .ignoresSafeArea(edges: .bottom)
                .tabItem { Label("Codex", systemImage: "globe") }

            SettingsView()
                .tabItem { Label("Нейросети", systemImage: "brain") }
        }
        .tint(.green)
    }
}
