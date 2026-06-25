import SwiftUI
import WebKit

/// Shared cookie-persistent web session helper.
enum CodexWebSession {
    static func clearCookies() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             for: records, completionHandler: {})
        }
    }
}

/// Hosts the SAME bridge web view full-screen for the login flow, so the very
/// session the user logs into is the one used to run prompts.
struct CodexLoginView: UIViewRepresentable {
    var onLoginDetected: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoginDetected: onLoginDetected) }

    func makeUIView(context: Context) -> WKWebView {
        let web = CodexBridge.shared.webView
        web.alpha = 1
        web.isUserInteractionEnabled = true
        web.removeFromSuperview()
        web.navigationDelegate = context.coordinator
        if web.url == nil || !(web.url?.absoluteString.contains("chatgpt.com") ?? false) {
            web.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoginDetected: () -> Void
        init(onLoginDetected: @escaping () -> Void) { self.onLoginDetected = onLoginDetected }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            guard url.contains("chatgpt.com"),
                  !url.contains("/auth"), !url.contains("login"), !url.contains("oauth") else { return }
            // Confirm an authenticated composer is present (not just any page).
            let js = "(document.querySelector('#prompt-textarea, textarea, div[contenteditable=\"true\"]') ? '1' : '0')"
            webView.evaluateJavaScript(js) { value, _ in
                if (value as? String) == "1" {
                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        let ok = cookies.contains { $0.name.contains("session") || $0.name.hasPrefix("__Secure-next-auth") }
                        if ok { DispatchQueue.main.async { self.onLoginDetected() } }
                    }
                }
            }
        }
    }
}

/// Full-screen sheet hosting the Codex login (desktop confirmation flow).
struct CodexLoginSheet: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) var dismiss
    @State private var loggedJustNow = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                CodexLoginView {
                    session.isCodexLoggedIn = true
                    loggedJustNow = true
                }
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
            .onDisappear {
                // Return the shared web view to its offscreen parking spot.
                CodexBridge.shared.webView.removeFromSuperview()
            }
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
