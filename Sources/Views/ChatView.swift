import SwiftUI

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    let projectID: UUID
    let chatID: UUID

    @State private var input = ""
    @State private var isStreaming = false
    @State private var errorText: String?

    private var chat: Chat? {
        store.projects.first(where: { $0.id == projectID })?
            .chats.first(where: { $0.id == chatID })
    }

    private var provider: AIProvider? {
        let pid = chat?.providerID
        return settings.providers.first(where: { $0.id == pid }) ?? settings.defaultProvider
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chat?.messages ?? []) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: chat?.messages.last?.content) { _, _ in
                    if let last = chat?.messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal)
            }

            HStack(spacing: 8) {
                TextField("Спроси Codex…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
            }
            .padding()
        }
        .navigationTitle(chat?.title ?? "Чат")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let p = provider {
                    Text(p.model).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func send() async {
        guard let provider else {
            errorText = "Сначала добавь нейросеть во вкладке «Нейросети»."
            return
        }
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        errorText = nil
        input = ""

        store.appendMessage(Message(role: .user, content: text),
                            projectID: projectID, chatID: chatID)
        store.appendMessage(Message(role: .assistant, content: ""),
                            projectID: projectID, chatID: chatID)

        isStreaming = true
        defer { isStreaming = false }

        let history = chat?.messages.filter { !$0.content.isEmpty || $0.role == .assistant } ?? []
        let client = AIClient(provider: provider)
        var acc = ""
        do {
            for try await token in client.stream(messages: history) {
                acc += token
                store.updateLastAssistantMessage(acc, projectID: projectID, chatID: chatID)
            }
            store.save()
            // Auto-extract any generated files into the project.
            let files = CodeExtractor.extract(from: acc)
            if !files.isEmpty { store.attachFiles(files, projectID: projectID) }
        } catch {
            errorText = error.localizedDescription
            store.updateLastAssistantMessage(acc.isEmpty ? "⚠️ \(error.localizedDescription)" : acc,
                                             projectID: projectID, chatID: chatID)
            store.save()
        }
    }
}

struct MessageBubble: View {
    let message: Message
    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.content.isEmpty ? "…" : message.content)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(isUser ? Color.green.opacity(0.25) : Color.gray.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
