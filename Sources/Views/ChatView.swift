import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var session: SessionStore
    let projectID: UUID
    let chatID: UUID

    @State private var input = ""
    @State private var isStreaming = false
    @State private var errorText: String?
    @State private var showModelPicker = false
    @State private var pendingAttachments: [Attachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false

    private var chat: Chat? {
        store.projects.first(where: { $0.id == projectID })?.chats.first(where: { $0.id == chatID })
    }
    private var selections: [ModelSelection] {
        settings.availableSelections(codexLoggedIn: session.isCodexLoggedIn)
    }

    var body: some View {
        ZStack {
            if let bg = settings.theme.background { bg.ignoresSafeArea() }
            VStack(spacing: 0) {
                messagesList
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                }
                attachmentStrip
                inputBar
            }
        }
        .navigationTitle(chat?.title ?? "Чат")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showModelPicker) { modelPicker }
        .onChange(of: photoItems) { _, items in Task { await loadPhotos(items) } }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleFiles(result)
        }
    }

    // MARK: - Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(chat?.messages ?? []) { msg in
                        MessageBubble(message: msg).id(msg.id)
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
    }

    // MARK: - Attachments strip

    @ViewBuilder private var attachmentStrip: some View {
        if !pendingAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pendingAttachments) { a in
                        HStack(spacing: 6) {
                            Image(systemName: a.kind == .image ? "photo.fill" : "doc.fill")
                            Text(a.fileName).lineLimit(1).font(.caption)
                            Button { pendingAttachments.removeAll { $0.id == a.id } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                PhotosPicker(selection: $photoItems, matching: .images) {
                    Label("Фото", systemImage: "photo")
                }
                Button { showFileImporter = true } label: { Label("Файл", systemImage: "doc") }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(settings.accent.color)
            }

            TextField("Спроси Codex…", text: $input, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

            Button {
                Task { await send() }
            } label: {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? AnyShapeStyle(settings.accent.gradient)
                                             : AnyShapeStyle(Color.gray))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        (!input.trimmingCharacters(in: .whitespaces).isEmpty || !pendingAttachments.isEmpty) && !isStreaming
    }

    // MARK: - Toolbar (model picker)

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showModelPicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: chat?.selection?.source == .codex ? "bolt.fill" : "cpu")
                    Text(shortModelName).font(.caption.bold())
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(settings.accent.color.opacity(0.18), in: Capsule())
            }
        }
    }

    private var shortModelName: String {
        chat?.selection?.model ?? "Модель"
    }

    private var modelPicker: some View {
        NavigationStack {
            List {
                if selections.isEmpty {
                    ContentUnavailableView("Нет доступных моделей", systemImage: "cpu",
                        description: Text("Добавь нейросеть по API или войди в Codex во вкладке «Настройки»."))
                } else {
                    let apiModels = selections.filter { $0.source == .api }
                    let codexModels = selections.filter { $0.source == .codex }
                    if !apiModels.isEmpty {
                        Section("Модели по API") {
                            ForEach(apiModels) { sel in modelRow(sel) }
                        }
                    }
                    if !codexModels.isEmpty {
                        Section("Модели Codex (через аккаунт)") {
                            ForEach(codexModels) { sel in modelRow(sel) }
                        }
                    }
                }
            }
            .navigationTitle("Выбор модели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showModelPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func modelRow(_ sel: ModelSelection) -> some View {
        Button {
            store.setSelection(sel, projectID: projectID, chatID: chatID)
            showModelPicker = false
        } label: {
            HStack {
                Image(systemName: sel.source == .codex ? "bolt.fill" : "cpu")
                    .foregroundStyle(settings.accent.color)
                Text(sel.displayName).foregroundStyle(.primary)
                Spacer()
                if chat?.selection?.id == sel.id {
                    Image(systemName: "checkmark").foregroundStyle(settings.accent.color)
                }
            }
        }
    }

    // MARK: - Attachment loading

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let name = "image_\(pendingAttachments.count + 1).jpg"
                pendingAttachments.append(Attachment(kind: .image, fileName: name,
                                                     mimeType: "image/jpeg",
                                                     base64: data.base64EncodedString()))
            }
        }
        photoItems = []
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                pendingAttachments.append(Attachment(kind: .file, fileName: url.lastPathComponent,
                                                     mimeType: "application/octet-stream",
                                                     base64: data.base64EncodedString()))
            }
        }
    }

    // MARK: - Send

    @MainActor private func send() async {
        guard let sel = chat?.selection else {
            errorText = "Сначала выбери модель (кнопка вверху справа)."
            return
        }
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        errorText = nil

        let atts = pendingAttachments
        input = ""; pendingAttachments = []

        store.appendMessage(Message(role: .user, content: text, attachments: atts),
                            projectID: projectID, chatID: chatID)
        store.appendMessage(Message(role: .assistant, content: ""),
                            projectID: projectID, chatID: chatID)

        // Codex models are not callable via API key — guide the user.
        if sel.source == .codex {
            store.updateLastAssistantMessage(
                "⚠️ Прямой вызов Codex-моделей через аккаунт пока не поддерживается API OpenAI. " +
                "Открой вкладку «Настройки» → «Codex» для работы в веб-Codex, либо выбери модель по API.",
                projectID: projectID, chatID: chatID)
            store.save()
            return
        }

        guard let provider = settings.provider(for: sel.providerID) else {
            errorText = "Провайдер не найден."
            return
        }

        isStreaming = true
        defer { isStreaming = false }

        var history: [Message] = []
        if !settings.systemPrompt.isEmpty {
            history.append(Message(role: .system, content: settings.systemPrompt))
        }
        history += (chat?.messages.filter { !($0.role == .assistant && $0.content.isEmpty) } ?? [])

        let client = AIClient(provider: provider, model: sel.model)
        var acc = ""
        do {
            for try await token in client.stream(messages: history) {
                acc += token
                store.updateLastAssistantMessage(acc, projectID: projectID, chatID: chatID)
            }
            store.save()
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

// MARK: - Message bubble

struct MessageBubble: View {
    @EnvironmentObject var settings: SettingsStore
    let message: Message
    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if !message.attachments.isEmpty {
                    ForEach(message.attachments) { a in
                        Label(a.fileName, systemImage: a.kind == .image ? "photo" : "doc")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(message.content.isEmpty ? "…" : message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(isUser ? .white : .primary)
            }
            .padding(12)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder private var bubbleBackground: some View {
        if isUser {
            settings.accent.gradient
        } else {
            (settings.theme.card ?? Color(.secondarySystemBackground))
        }
    }
}
