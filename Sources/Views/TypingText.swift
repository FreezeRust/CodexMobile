import SwiftUI

/// Renders message content with the selected typing animation.
/// While the message is the actively streaming one, it animates reveal;
/// finished messages render fully.
struct TypingBody: View {
    @EnvironmentObject var settings: SettingsStore
    let text: String
    let isUser: Bool
    let isStreaming: Bool          // this specific message is currently being written
    let onOpenCode: (_ name: String, _ language: String, _ content: String) -> Void

    @State private var revealed = ""
    @State private var task: Task<Void, Never>?

    var body: some View {
        Group {
            if shouldAnimate {
                animatedView
            } else {
                RenderedMessage(text: text, isUser: isUser, onOpenCode: onOpenCode)
            }
        }
        .onChange(of: text) { _, newValue in
            if shouldAnimate { animate(to: newValue) }
        }
        .onAppear {
            if shouldAnimate { animate(to: text) } else { revealed = text }
        }
        .onDisappear { task?.cancel() }
    }

    private var shouldAnimate: Bool {
        isStreaming && settings.typingAnimation != .instant && !text.contains("```")
        // For code-heavy messages we render structured blocks instantly to avoid jank.
    }

    @ViewBuilder private var animatedView: some View {
        switch settings.typingAnimation {
        case .fade:
            Text(inlineMarkdown(revealed))
                .foregroundStyle(isUser ? .white : .primary)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.25), value: revealed)
        case .wave:
            WaveText(text: revealed, isUser: isUser)
        default:
            Text(inlineMarkdown(revealed.isEmpty ? " " : revealed))
                .foregroundStyle(isUser ? .white : .primary)
        }
    }

    private func animate(to newValue: String) {
        task?.cancel()
        // If new value just appends, continue from current revealed length.
        let start = newValue.hasPrefix(revealed) ? revealed.count : 0
        task = Task { @MainActor in
            let chars = Array(newValue)
            if start == 0 { revealed = "" }
            switch settings.typingAnimation {
            case .character, .fade, .wave:
                var idx = start
                while idx < chars.count {
                    if Task.isCancelled { return }
                    revealed = String(chars[0...idx])
                    idx += 1
                    try? await Task.sleep(nanoseconds: 9_000_000) // ~110 chars/s
                }
            case .word:
                let words = newValue.split(separator: " ", omittingEmptySubsequences: false)
                var built = ""
                for (k, w) in words.enumerated() {
                    if Task.isCancelled { return }
                    built += (k == 0 ? "" : " ") + w
                    revealed = built
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }
            case .instant:
                revealed = newValue
            }
            revealed = newValue
        }
    }
}

/// Word-by-word wave appearance.
struct WaveText: View {
    let text: String
    let isUser: Bool
    var words: [String] { text.split(separator: " ").map(String.init) }

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                Text(w)
                    .foregroundStyle(isUser ? .white : .primary)
                    .offset(y: 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7).delay(Double(i) * 0.01), value: words.count)
            }
        }
    }
}

/// Simple flow layout for wrapping words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
