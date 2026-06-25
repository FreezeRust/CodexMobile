import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    let projectID: UUID
    let chatID: UUID

    @State private var input = ""
    @State private var isStreaming = false
    @State private var errorText: String?
    @State private var showModelPicker = false
    @State private var pendingAttachments: [Attachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var quoting: String?      // text being quoted in the next message
    @State private var codeViewer: CodeViewerData?
    @State private var selectionText: String?
    @State private var streamingMessageID: UUID?

    private var chat: Chat? {
        store.projects.first(where: { $0.id == projectID })?.chats.first(where: { $0.id == chatID })
    }
    private var selections: [ModelSelection] { settings.availableSelections() }
    private var currentProvider: AIProvider? { settings.provider(for: chat?.selection?.providerID) }

    var body: some View {
        ZStack {
            if let bg = settings.bgColor { bg.ignoresSafeArea() }
            VStack(spacing: 0) {
                messagesList
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal).padding(.vertical, 4)
                }
                quoteBar
                attachmentStrip
                inputBar
            }
        }
        .navigationTitle(chat?.title ?? "Чат")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showModelPicker) { modelPicker }
        .sheet(item: $codeViewer) { data in
            CodeViewerSheet(fileName: data.name, language: data.language, content: data.content) {
                store.attachFiles([GeneratedFile(name: data.name, language: data.language, content: data.content)],
                                  projectID: projectID)
            }
        }
        .sheet(item: Binding(get: { selectionText.map { SelText(text: $0) } },
                             set: { selectionText = $0?.text })) { sel in
            TextSelectionSheet(fullText: sel.text) { asked in
                input = "Про этот фрагмент:\n\"\(asked)\"\n\n"
            }
        }
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
                        MessageBubble(
                            message: msg,
                            isStreamingThis: streamingMessageID == msg.id,
                            onQuote: { quoting = msg.content },
                            onToggleMark: {
                                store.updateMessage(msg.id, projectID: projectID, chatID: chatID) {
                                    $0.isMarked.toggle()
                                }
                            },
                            onCopy: { UIPasteboard.general.string = msg.content },
                            onSelectText: { selectionText = msg.content },
                            onPollAnswer: { opt in
                                store.setPollAnswer(opt, messageID: msg.id, projectID: projectID, chatID: chatID)
                            },
                            onSaveImage: { att in saveImageAsFile(att) },
                            onOpenCode: { name, lang, content in
                                codeViewer = CodeViewerData(name: name, language: lang, content: content)
                            }
                        )
                        .id(msg.id)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    }
                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .padding()
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: chat?.messages.count)
            }
            // Auto-scroll only nudges to bottom as content grows; user can scroll freely.
            .onChange(of: chat?.messages.last?.content) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
            }
            .onChange(of: chat?.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
            }
        }
    }

    // MARK: - Quote bar

    @ViewBuilder private var quoteBar: some View {
        if let q = quoting {
            HStack(spacing: 8) {
                Rectangle().fill(settings.accentColor).frame(width: 3)
                Text(q).lineLimit(2).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { quoting = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial)
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
                if currentProvider?.supportsImages == true {
                    Button { Task { await generateImage() } } label: {
                        Label("Сгенерировать картинку", systemImage: "wand.and.stars")
                    }
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(settings.accentColor)
            }

            TextField("Сообщение…", text: $input, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

            Button {
                Task { await send() }
            } label: {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? AnyShapeStyle(settings.accentGradient)
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
                    Image(systemName: "cpu")
                    Text(chat?.selection?.model ?? "Модель").font(.caption.bold()).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(settings.accentColor.opacity(0.18), in: Capsule())
            }
        }
    }

    private var modelPicker: some View {
        NavigationStack {
            List {
                if selections.isEmpty {
                    ContentUnavailableView("Нет моделей", systemImage: "cpu",
                        description: Text("Добавь нейросеть по API в «Настройки → Нейросети»."))
                } else {
                    ForEach(settings.providers) { p in
                        Section(p.name) {
                            ForEach(p.models, id: \.self) { m in
                                let sel = ModelSelection(providerID: p.id, model: m, displayName: "\(p.name) · \(m)")
                                modelRow(sel)
                            }
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
                Image(systemName: "cpu").foregroundStyle(settings.accentColor)
                Text(sel.model).foregroundStyle(.primary)
                Spacer()
                if chat?.selection?.id == sel.id {
                    Image(systemName: "checkmark").foregroundStyle(settings.accentColor)
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

    private func saveImageAsFile(_ att: Attachment) {
        // Store base64 image as a project file so it can be exported in the zip.
        store.attachFiles([GeneratedFile(name: att.fileName, language: "image-base64", content: att.base64)],
                          projectID: projectID)
    }

    // MARK: - Image generation

    @MainActor private func generateImage() async {
        guard let provider = currentProvider, provider.supportsImages else { return }
        let prompt = input.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { errorText = "Напиши описание картинки в поле ввода."; return }
        errorText = nil; input = ""

        store.appendMessage(Message(role: .user, content: "🎨 \(prompt)"), projectID: projectID, chatID: chatID)
        store.appendMessage(Message(role: .assistant, content: "Генерирую изображение…"),
                            projectID: projectID, chatID: chatID)
        isStreaming = true; defer { isStreaming = false }

        let client = AIClient(provider: provider, model: chat?.selection?.model ?? provider.primaryModel)
        do {
            let b64 = try await client.generateImage(prompt: prompt)
            if b64.isEmpty {
                store.updateLastAssistantMessage("⚠️ Не удалось получить изображение.", projectID: projectID, chatID: chatID)
            } else {
                let att = Attachment(kind: .image, fileName: "generated_\(Int(Date().timeIntervalSince1970)).png",
                                     mimeType: "image/png", base64: b64)
                store.updateMessage(currentAssistantID(), projectID: projectID, chatID: chatID) {
                    $0.content = "Готово ✨"
                    $0.attachments = [att]
                }
            }
            store.save()
        } catch {
            store.updateLastAssistantMessage("⚠️ \(error.localizedDescription)", projectID: projectID, chatID: chatID)
            store.save()
        }
    }

    private func currentAssistantID() -> UUID {
        chat?.messages.last(where: { $0.role == .assistant })?.id ?? UUID()
    }

    // MARK: - Send

    @MainActor private func send() async {
        guard let sel = chat?.selection else {
            errorText = "Сначала выбери модель (кнопка вверху справа)."
            return
        }
        var text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        errorText = nil

        let atts = pendingAttachments
        let quote = quoting
        if let q = quote { text = "> \(q)\n\n\(text)" }
        input = ""; pendingAttachments = []; quoting = nil

        store.appendMessage(Message(role: .user, content: text, attachments: atts, quoted: quote),
                            projectID: projectID, chatID: chatID)
        store.appendMessage(Message(role: .assistant, content: ""),
                            projectID: projectID, chatID: chatID)

        guard let provider = settings.provider(for: sel.providerID) else {
            store.updateLastAssistantMessage("⚠️ Провайдер не найден. Открой «Настройки → Нейросети».",
                                             projectID: projectID, chatID: chatID)
            store.save(); return
        }

        isStreaming = true
        streamingMessageID = currentAssistantID()
        defer { isStreaming = false; streamingMessageID = nil }

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
            if acc.isEmpty {
                store.updateLastAssistantMessage(
                    "⚠️ Пустой ответ. Проверь модель «\(sel.model)», Base URL и ключ.",
                    projectID: projectID, chatID: chatID)
            }
            // Parse poll / image requests
            let aid = currentAssistantID()
            if let poll = ResponseParser.extractPoll(from: acc) {
                store.updateMessage(aid, projectID: projectID, chatID: chatID) {
                    $0.poll = poll
                    $0.content = ResponseParser.stripControlBlocks(acc)
                }
            }
            if let imgPrompt = ResponseParser.extractImagePrompt(from: acc), provider.supportsImages {
                if let b64 = try? await client.generateImage(prompt: imgPrompt), !b64.isEmpty {
                    let att = Attachment(kind: .image, fileName: "ai_image.png", mimeType: "image/png", base64: b64)
                    store.updateMessage(aid, projectID: projectID, chatID: chatID) {
                        $0.attachments.append(att)
                        $0.content = ResponseParser.stripControlBlocks(acc)
                    }
                }
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

// MARK: - Helper identifiable wrappers for sheets

struct CodeViewerData: Identifiable {
    let id = UUID()
    let name: String
    let language: String
    let content: String
}
struct SelText: Identifiable { let id = UUID(); let text: String }

// MARK: - Message bubble

struct MessageBubble: View {
    @EnvironmentObject var settings: SettingsStore
    let message: Message
    var isStreamingThis: Bool
    var onQuote: () -> Void
    var onToggleMark: () -> Void
    var onCopy: () -> Void
    var onSelectText: () -> Void
    var onPollAnswer: (String) -> Void
    var onSaveImage: (Attachment) -> Void
    var onOpenCode: (_ name: String, _ language: String, _ content: String) -> Void

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 36) }
            if !isUser { avatar }
            VStack(alignment: .leading, spacing: 8) {
                if !isUser { roleHeader }
                if let q = message.quoted, !q.isEmpty {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.55)).frame(width: 2)
                        Text(q).font(.caption2).italic().lineLimit(3)
                            .foregroundStyle(isUser ? .white.opacity(0.85) : .secondary)
                    }
                }
                attachmentsView
                contentView
                if let poll = message.poll {
                    PollView(poll: poll, accent: settings.accentColor) { onPollAnswer($0) }
                }
                if message.isMarked {
                    Label("Подчёркнуто", systemImage: "highlighter")
                        .font(.caption2).foregroundStyle(settings.accentColor)
                }
            }
            .padding(12)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isUser ? .clear : .white.opacity(0.06))
            )
            .contextMenu {
                Button { onCopy() } label: { Label("Копировать", systemImage: "doc.on.doc") }
                Button { onSelectText() } label: { Label("Выбор текста", systemImage: "selection.pin.in.out") }
                Button { onQuote() } label: { Label("Цитировать", systemImage: "quote.opening") }
                Button { onToggleMark() } label: {
                    Label(message.isMarked ? "Снять подчёркивание" : "Подчеркнуть", systemImage: "highlighter")
                }
            }
            if isUser { avatar }
            if !isUser { Spacer(minLength: 36) }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(isUser ? AnyShapeStyle(settings.accentGradient)
                                 : AnyShapeStyle(Color.gray.opacity(0.25)))
                .frame(width: 28, height: 28)
            Image(systemName: isUser ? "person.fill" : "sparkle")
                .font(.caption2)
                .foregroundStyle(isUser ? .white : settings.accentColor)
        }
    }

    private var roleHeader: some View {
        HStack(spacing: 6) {
            Text("Ассистент").font(.caption2.bold()).foregroundStyle(.secondary)
            if isStreamingThis {
                TypingDots(color: settings.accentColor)
            }
        }
    }

    @ViewBuilder private var attachmentsView: some View {
        ForEach(message.attachments) { a in
            if a.kind == .image, let data = Data(base64Encoded: a.base64), let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 230, maxHeight: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1)))
                    .contextMenu {
                        Button { onSaveImage(a) } label: { Label("Сохранить в файлы", systemImage: "square.and.arrow.down") }
                    }
            } else {
                Label(a.fileName, systemImage: "paperclip")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var contentView: some View {
        if message.content.isEmpty && message.attachments.isEmpty {
            TypingDots(color: isUser ? .white : settings.accentColor)
        } else if isUser {
            Text(message.content)
                .foregroundStyle(.white)
                .underline(message.isMarked)
        } else {
            TypingBody(text: message.content, isUser: false, isStreaming: isStreamingThis,
                       onOpenCode: onOpenCode)
                .underline(message.isMarked)
        }
    }

    @ViewBuilder private var bubbleBackground: some View {
        if isUser { settings.accentGradient }
        else { (settings.cardColor ?? Color(.secondarySystemBackground)) }
    }
}

// MARK: - Typing dots

struct TypingDots: View {
    let color: Color
    @State private var phase = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(color)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.35)
                    .scaleEffect(phase == i ? 1.0 : 0.7)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.25)) { phase = (phase + 1) % 3 }
            }
        }
    }
}

// MARK: - Poll view

struct PollView: View {
    let poll: Poll
    let accent: Color
    var onAnswer: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(poll.question, systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline.bold())
            ForEach(poll.options, id: \.self) { opt in
                Button { onAnswer(opt) } label: {
                    HStack {
                        Image(systemName: poll.selected == opt ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(accent)
                        Text(opt).foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .background(poll.selected == opt ? accent.opacity(0.18) : Color.gray.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            if let sel = poll.selected {
                Text("Твой ответ: \(sel)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 280)
    }
}
