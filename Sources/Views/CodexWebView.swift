import SwiftUI
import WebKit

/// Shared cookie-persistent web session for Codex login.
enum CodexWebSession {
    static func clearCookies() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             for: records, completionHandler: {})
        }
    }
}

/// Embedded Codex / ChatGPT login. Detects successful login.
struct CodexLoginView: UIViewRepresentable {
    let urlString: String
    var onLoginDetected: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoginDetected: onLoginDetected) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        if let url = URL(string: urlString) { web.load(URLRequest(url: url)) }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoginDetected: () -> Void
        init(onLoginDetected: @escaping () -> Void) { self.onLoginDetected = onLoginDetected }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            // Heuristic: reaching the app/workspace pages means we're logged in.
            if url.contains("chatgpt.com") && !url.contains("/auth") && !url.contains("login") {
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    if cookies.contains(where: { $0.name.contains("session") || $0.name.contains("__Secure") }) {
                        DispatchQueue.main.async { self.onLoginDetected() }
                    }
                }
            }
        }
    }
}

/// Full-screen sheet hosting the Codex login.
struct CodexLoginSheet: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            CodexLoginView(urlString: "https://chatgpt.com/codex") {
                session.isCodexLoggedIn = true
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Вход в Codex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Закрыть") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if session.isCodexLoggedIn {
                Label("Вошёл", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}
