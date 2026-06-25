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

/// Full Codex login web view with desktop-grade flow (password, 2FA, confirmation).
struct CodexLoginView: UIViewRepresentable {
    var onLoginDetected: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoginDetected: onLoginDetected) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = .desktop // full desktop confirmation flow

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        // Desktop user agent so OpenAI shows the full PC login + confirmation.
        web.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        context.coordinator.webView = web
        web.load(URLRequest(url: URL(string: "https://chatgpt.com/codex")!))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoginDetected: () -> Void
        weak var webView: WKWebView?
        init(onLoginDetected: @escaping () -> Void) { self.onLoginDetected = onLoginDetected }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            guard url.contains("chatgpt.com"),
                  !url.contains("/auth"), !url.contains("login"), !url.contains("oauth") else { return }
            // Verify a real session cookie exists before marking logged in.
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let hasSession = cookies.contains {
                    $0.name.contains("session") || $0.name.hasPrefix("__Secure-next-auth")
                }
                if hasSession { DispatchQueue.main.async { self.onLoginDetected() } }
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
            ZStack(alignment: .top) {
                CodexLoginView { session.isCodexLoggedIn = true }
                    .ignoresSafeArea(edges: .bottom)
                if !session.isCodexLoggedIn {
                    Text("Войди в свой аккаунт Codex и подтверди вход — как на ПК")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(8).frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Вход в Codex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
            if session.isCodexLoggedIn {
                Button { dismiss() } label: {
                    Label("Готово", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
    }
}
