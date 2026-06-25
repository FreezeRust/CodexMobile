import Foundation
import WebKit
import UIKit

/// Shared desktop-class user agent so Codex shows the full PC login/confirmation flow.
let kCodexUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
    "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

/// Drives the logged-in Codex/ChatGPT web session to run prompts and capture answers
/// into OpenVolt's native chat. When a bot check appears, it surfaces a small
/// verification window instead of a full page.
@MainActor
final class CodexBridge: NSObject, ObservableObject {
    static let shared = CodexBridge()

    /// The single web view shared with the login session (same cookie store).
    let webView: WKWebView

    /// When true, the UI should present the small "verify you are human" window.
    @Published var needsVerification = false
    /// Human-readable status for nice UI feedback.
    @Published var status: String = ""

    private var prepared = false

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()       // shares logged-in cookies
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        super.init()
        webView.customUserAgent = kCodexUserAgent
        // Keep it alive & processing while off-screen by parking it in the key window.
        parkOffscreen()
    }

    enum BridgeError: LocalizedError {
        case notLoggedIn, timeout, noInput
        var errorDescription: String? {
            switch self {
            case .notLoggedIn: return "Нужно войти в Codex. Открой «Настройки → Codex»."
            case .timeout:     return "Codex не ответил вовремя. Попробуй ещё раз."
            case .noInput:     return "Не удалось найти поле ввода Codex."
            }
        }
    }

    // MARK: - Lifecycle

    /// Park the web view as a tiny, near-invisible subview of the key window so
    /// the page keeps running (and challenges can complete) even when not shown.
    private func parkOffscreen() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.keyWindow else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.parkOffscreen() }
            return
        }
        webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        webView.alpha = 0.02
        webView.isUserInteractionEnabled = false
        if webView.superview == nil { window.addSubview(webView) }
    }

    /// Load chatgpt.com once.
    func prepare() async {
        if webView.superview == nil { parkOffscreen() }   // ensure it lives in the window
        if prepared, let url = webView.url?.absoluteString, url.contains("chatgpt.com") { return }
        await load(URLString: "https://chatgpt.com/")
        prepared = true
        try? await Task.sleep(nanoseconds: 1_200_000_000)
    }

    private func load(URLString: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let d = LoadDelegate { cont.resume() }
            self.loadDelegate = d
            webView.navigationDelegate = d
            webView.load(URLRequest(url: URL(string: URLString)!))
        }
    }
    private var loadDelegate: LoadDelegate?

    // MARK: - Page state probe

    enum PageState: String { case ready = "READY", challenge = "CHALLENGE", login = "LOGIN", loading = "LOADING" }

    private let probeJS = """
    (function(){
      try {
        if (document.querySelector('iframe[src*="challenges.cloudflare.com"], iframe[src*="turnstile"], #challenge-stage, #cf-challenge-running, [id^="cf-chl"]')) return 'CHALLENGE';
        var t = (document.body && document.body.innerText) ? document.body.innerText : '';
        if (/verify you are human|подтвердите, что вы человек|are you human|проверка безопасности/i.test(t)) return 'CHALLENGE';
        var href = location.href;
        if (href.indexOf('/auth')>-1 || href.indexOf('login')>-1 || document.querySelector('input[type=password]')) return 'LOGIN';
        if (document.querySelector('#prompt-textarea, textarea, div[contenteditable="true"]')) return 'READY';
        return 'LOADING';
      } catch(e){ return 'LOADING'; }
    })();
    """

    private func probe() async -> PageState {
        let v = (try? await eval(probeJS)) as? String ?? "LOADING"
        return PageState(rawValue: v) ?? .loading
    }

    /// Wait until the composer is ready. Surfaces the verification window if a
    /// bot check appears, and resolves once the user passes it.
    private func waitUntilReady(timeout: TimeInterval = 90) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch await probe() {
            case .ready:
                if needsVerification { needsVerification = false; parkOffscreen() }
                status = ""
                return
            case .challenge:
                status = "Нужна проверка, что ты не робот"
                needsVerification = true       // -> UI shows the small window
            case .login:
                needsVerification = false
                throw BridgeError.notLoggedIn
            case .loading:
                status = "Загрузка Codex…"
            }
            try await Task.sleep(nanoseconds: 600_000_000)
        }
        throw BridgeError.timeout
    }

    // MARK: - Send a prompt

    func send(prompt: String, onUpdate: @escaping (String) -> Void) async throws {
        await prepare()
        try await waitUntilReady()

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
          setTimeout(() => {
            const btn = document.querySelector('button[data-testid="send-button"], button[aria-label*="Send"], button[aria-label*="Отправить"]');
            if (btn && !btn.disabled) btn.click();
            else {
              const ev = new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true});
              ta.dispatchEvent(ev);
            }
          }, 200);
          return 'OK';
        })();
        """
        status = "Отправляю запрос через Codex…"
        let r = try await eval(injectJS)
        if (r as? String) == "NO_INPUT" { throw BridgeError.noInput }

        let readJS = """
        (function() {
          const nodes = document.querySelectorAll('[data-message-author-role="assistant"]');
          if (!nodes.length) return '';
          return nodes[nodes.length-1].innerText || '';
        })();
        """

        var last = ""
        var stable = 0
        status = "Codex думает…"
        for _ in 0..<160 {                 // up to ~80s
            try await Task.sleep(nanoseconds: 500_000_000)
            // a challenge can appear mid-stream too
            if await probe() == .challenge { try await waitUntilReady() }
            let cur = (try? await eval(readJS)) as? String ?? ""
            if cur != last {
                last = cur; stable = 0
                if !cur.isEmpty { onUpdate(cur) }
            } else if !cur.isEmpty {
                stable += 1
                if stable >= 5 { break }    // ~2.5s unchanged => finished
            }
        }
        status = ""
        if last.isEmpty { throw BridgeError.timeout }
    }

    private func eval(_ js: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            webView.evaluateJavaScript(js) { v, e in
                if let e { cont.resume(throwing: e) } else { cont.resume(returning: v) }
            }
        }
    }

    func reset() {
        prepared = false
        CodexWebSession.clearCookies()
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        let done: () -> Void
        private var fired = false
        init(done: @escaping () -> Void) { self.done = done }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { fire() }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { fire() }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { fire() }
        private func fire() { guard !fired else { return }; fired = true; done() }
    }
}
