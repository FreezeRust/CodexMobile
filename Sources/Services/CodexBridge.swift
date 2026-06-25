import Foundation
import WebKit

/// Drives the logged-in Codex/ChatGPT web session headlessly to run a prompt
/// and capture the answer back into OpenVolt's native chat.
///
/// NOTE: This automates the web UI (the only way to use a Codex *account* without
/// an API key). It depends on ChatGPT's DOM and may need selector updates over time.
@MainActor
final class CodexBridge: NSObject, ObservableObject {
    static let shared = CodexBridge()

    private var webView: WKWebView?
    private var ready = false

    enum BridgeError: LocalizedError {
        case notLoggedIn, timeout, noResponse
        var errorDescription: String? {
            switch self {
            case .notLoggedIn: return "Нет активной сессии Codex. Войди в «Настройки → Codex»."
            case .timeout:     return "Codex не ответил вовремя. Попробуй ещё раз."
            case .noResponse:  return "Не удалось получить ответ из Codex."
            }
        }
    }

    /// Build/reuse a hidden web view that shares cookies with the login session.
    private func ensureWebView() -> WKWebView {
        if let w = webView { return w }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()        // shares the logged-in cookies
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        w.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView = w
        return w
    }

    /// Ensure the chat page is loaded and ready.
    private func loadIfNeeded() async throws {
        let w = ensureWebView()
        if ready, let url = w.url?.absoluteString, url.contains("chatgpt.com") { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let delegate = LoadDelegate { result in cont.resume(with: result) }
            self.loadDelegate = delegate
            w.navigationDelegate = delegate
            w.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
        }
        ready = true
        // small settle delay for SPA hydration
        try await Task.sleep(nanoseconds: 1_500_000_000)
    }

    private var loadDelegate: LoadDelegate?

    /// Sends a prompt through Codex and streams the answer via the callback.
    func send(prompt: String, onUpdate: @escaping (String) -> Void) async throws {
        try await loadIfNeeded()
        guard let w = webView else { throw BridgeError.noResponse }

        // 1) inject the prompt into the composer and submit
        let escaped = prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let injectJS = """
        (function() {
          const text = `\(escaped)`;
          const ta = document.querySelector('#prompt-textarea, textarea, div[contenteditable="true"]');
          if (!ta) return 'NO_INPUT';
          if (ta.tagName === 'TEXTAREA') {
            const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value').set;
            setter.call(ta, text);
            ta.dispatchEvent(new Event('input', {bubbles:true}));
          } else {
            ta.focus();
            document.execCommand('insertText', false, text);
            ta.dispatchEvent(new Event('input', {bubbles:true}));
          }
          // try to click the send button
          setTimeout(() => {
            const btn = document.querySelector('button[data-testid="send-button"], button[aria-label*="Send"], button[aria-label*="Отправить"]');
            if (btn) btn.click();
            else {
              const ev = new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true});
              ta.dispatchEvent(ev);
            }
          }, 150);
          return 'OK';
        })();
        """

        let result = try await eval(w, injectJS)
        if (result as? String) == "NO_INPUT" {
            throw BridgeError.notLoggedIn   // composer not present => not authenticated
        }

        // 2) poll the DOM for the latest assistant message until it stops growing
        let readJS = """
        (function() {
          const nodes = document.querySelectorAll('[data-message-author-role="assistant"]');
          if (!nodes.length) return '';
          return nodes[nodes.length-1].innerText || '';
        })();
        """

        var last = ""
        var stableCount = 0
        for _ in 0..<120 {   // up to ~60s
            try await Task.sleep(nanoseconds: 500_000_000)
            let current = (try? await eval(w, readJS)) as? String ?? ""
            if current != last {
                last = current
                stableCount = 0
                if !current.isEmpty { onUpdate(current) }
            } else if !current.isEmpty {
                stableCount += 1
                if stableCount >= 4 { break }   // ~2s unchanged => done
            }
        }
        if last.isEmpty { throw BridgeError.timeout }
    }

    private func eval(_ w: WKWebView, _ js: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            w.evaluateJavaScript(js) { value, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: value) }
            }
        }
    }

    func reset() { ready = false; webView = nil }

    // Internal load delegate
    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        let done: (Result<Void, Error>) -> Void
        private var finished = false
        init(done: @escaping (Result<Void, Error>) -> Void) { self.done = done }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished else { return }; finished = true; done(.success(()))
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !finished else { return }; finished = true; done(.failure(error))
        }
    }
}
