import SwiftUI

/// Live viewer for a code/file block opened from a message.
struct CodeViewerSheet: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) var dismiss
    let fileName: String
    let language: String
    let content: String
    var onSaveToProject: (() -> Void)?

    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let bg = settings.bgColor { bg.ignoresSafeArea() }
                ScrollView([.vertical, .horizontal]) {
                    HStack(alignment: .top, spacing: 10) {
                        // line numbers
                        Text(lineNumbers)
                            .font(settings.codeFont.font(size: 12))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .multilineTextAlignment(.trailing)
                        Text(content)
                            .font(settings.codeFont.font(size: 12))
                            .textSelection(.enabled)
                    }
                    .padding()
                }
            }
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = content
                            copied = true
                        } label: { Label("Копировать всё", systemImage: "doc.on.doc") }
                        if let onSaveToProject {
                            Button { onSaveToProject(); dismiss() } label: {
                                Label("Сохранить в файлы проекта", systemImage: "square.and.arrow.down")
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
    }

    private var lineNumbers: String {
        let count = max(content.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        return (1...count).map(String.init).joined(separator: "\n")
    }
}

/// Text selection sheet: select part of a message, then Copy or Ask about it.
struct TextSelectionSheet: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) var dismiss
    let fullText: String
    var onAsk: (String) -> Void

    @State private var selection = ""

    var body: some View {
        NavigationStack {
            ZStack {
                if let bg = settings.bgColor { bg.ignoresSafeArea() }
                VStack(spacing: 0) {
                    Text("Выдели нужный фрагмент текста ниже")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(8)
                        .background(.ultraThinMaterial)
                    SelectableTextView(text: fullText, selectedText: $selection)
                        .padding(8)
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = selection.isEmpty ? fullText : selection
                            dismiss()
                        } label: {
                            Label("Копировать", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        Button {
                            onAsk(selection.isEmpty ? fullText : selection)
                            dismiss()
                        } label: {
                            Label("Спросить", systemImage: "sparkles")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(settings.accentGradient, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Выбор текста")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

/// UITextView wrapper that reports the user's current selection.
struct SelectableTextView: UIViewRepresentable {
    let text: String
    @Binding var selectedText: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.backgroundColor = .clear
        tv.font = .preferredFont(forTextStyle: .body)
        tv.text = text
        tv.delegate = context.coordinator
        // pre-select all so "Ask"/"Copy" works even without manual selection
        return tv
    }
    func updateUIView(_ uiView: UITextView, context: Context) {}

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: SelectableTextView
        init(_ p: SelectableTextView) { parent = p }
        func textViewDidChangeSelection(_ textView: UITextView) {
            if let range = textView.selectedTextRange,
               let t = textView.text(in: range) {
                parent.selectedText = t
            }
        }
    }
}
