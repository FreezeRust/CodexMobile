import SwiftUI
import WebKit

/// Wraps the bridge's live web view so the Cloudflare/Turnstile checkbox is
/// tappable inside a small window.
struct BridgeWebContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let web = CodexBridge.shared.webView
        web.alpha = 1
        web.isUserInteractionEnabled = true
        web.removeFromSuperview()           // detach from the offscreen parking spot
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// A small, pretty "verify you are human" window shown only when needed.
struct VerificationSheet: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var bridge = CodexBridge.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(settings.accent.gradient.opacity(0.25)).frame(width: 38, height: 38)
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(settings.accent.gradient)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Проверка безопасности").font(.headline)
                    Text("Нажми галочку, чтобы продолжить").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            // The live challenge, framed in a small card.
            BridgeWebContainer()
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
                .padding(.horizontal, 14)

            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.8)
                Text(bridge.status.isEmpty ? "Ожидание подтверждения…" : bridge.status)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 14)
        }
        .background(settings.theme.card ?? Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 18)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }
}

/// Overlay host that shows the verification window over the chat when needed.
struct VerificationOverlay: ViewModifier {
    @ObservedObject var bridge = CodexBridge.shared
    func body(content: Content) -> some View {
        ZStack {
            content
            if bridge.needsVerification {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .transition(.opacity)
                VerificationSheet()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: bridge.needsVerification)
    }
}

extension View {
    func codexVerificationOverlay() -> some View { modifier(VerificationOverlay()) }
}
