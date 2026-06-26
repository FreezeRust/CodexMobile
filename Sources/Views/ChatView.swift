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
                            onPollConfirm: { opt in
                                store.confirmPoll(messageID: msg.id, projectID: projectID, chatID: chatID)
                                Task { await sendPollChoice(opt) }
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

    private var currentModelLabel: String {
        guard let sel = chat?.selection else { return "Модель" }
        if let p = settings.provider(for: sel.providerID), p.isGift {
            return p.displayName(for: sel.model)
        }
        return sel.model
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showModelPicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                    Text(currentModelLabel).font(.caption.bold()).lineLimit(1)
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
                        Section(p.isGift ? "🎁 \(p.name)" : p.name) {
                            ForEach(p.models, id: \.self) { m in
                                let shown = p.isGift ? p.displayName(for: m) : m
                                let sel = ModelSelection(providerID: p.id, model: m,
                                                         displayName: p.isGift ? shown : "\(p.name) · \(m)")
                                modelRow(sel, label: shown)
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

    private func modelRow(_ sel: ModelSelection, label: String) -> some View {
        Button {
            store.setSelection(sel, projectID: projectID, chatID: chatID)
            showModelPicker = false
        } label: {
            HStack {
                Image(systemName: "cpu").foregroundStyle(settings.accentColor)
                Text(label).foregroundStyle(.primary)
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
        var placeholder = Message(role: .assistant, content: "")
        placeholder.generatingImage = true
        store.appendMessage(placeholder, projectID: projectID, chatID: chatID)
        let aid = currentAssistantID()
        isStreaming = true; defer { isStreaming = false }

        let client = AIClient(provider: provider, model: chat?.selection?.model ?? provider.primaryModel)
        let b64 = await imageBase64(client: client, prompt: prompt)
        if b64.isEmpty {
            store.updateMessage(aid, projectID: projectID, chatID: chatID) {
                $0.generatingImage = false
                $0.content = "⚠️ Не удалось создать изображение. Попробуй ещё раз."
            }
        } else {
            let att = Attachment(kind: .image, fileName: "generated_\(Int(Date().timeIntervalSince1970)).png",
                                 mimeType: "image/png", base64: b64)
            store.updateMessage(aid, projectID: projectID, chatID: chatID) {
                $0.generatingImage = false
                $0.content = ""
                $0.attachments = [att]
            }
        }
        store.save()
    }

    /// Try the dedicated images endpoint; if it fails, generate via chat (image link).
    private func imageBase64(client: AIClient, prompt: String) async -> String {
        if let b64 = try? await client.generateImage(prompt: prompt), !b64.isEmpty { return b64 }
        if let b64 = try? await client.generateImageViaChat(prompt: prompt), !b64.isEmpty { return b64 }
        return ""
    }

    private func currentAssistantID() -> UUID {
        chat?.messages.last(where: { $0.role == .assistant })?.id ?? UUID()
    }

    // MARK: - System message (prompt + project instructions + skills)

    private func buildSystemMessage() -> Message {
        var parts: [String] = []
        if !settings.systemPrompt.isEmpty { parts.append(settings.systemPrompt) }
        if let project = store.project(projectID) {
            if !project.instructions.trimmingCharacters(in: .whitespaces).isEmpty {
                parts.append("Инструкции проекта:\n\(project.instructions)")
            }
            let skills = project.skills.filter { $0.enabled }
            if !skills.isEmpty {
                let list = skills.map { "• \($0.name): \($0.detail)" }.joined(separator: "\n")
                parts.append("Доступные навыки (используй при необходимости):\n\(list)")
            }
            if !project.files.isEmpty {
                let names = project.files.prefix(20).map { $0.name }.joined(separator: ", ")
                parts.append("Файлы проекта: \(names)")
            }
            // Board state for the AI to read & act on
            if !project.board.nodes.isEmpty {
                var b = "Доска задач (узлы):\n"
                for n in project.board.nodes {
                    b += "  - \(n.done ? "✓" : "○") \(n.title)"
                    if !n.detail.isEmpty { b += " — \(n.detail)" }
                    b += "\n"
                }
                if !project.board.edges.isEmpty {
                    b += "Связи:\n"
                    for e in project.board.edges {
                        let a = project.board.nodes.first { $0.id == e.from }?.title ?? "?"
                        let c = project.board.nodes.first { $0.id == e.to }?.title ?? "?"
                        b += "  \(a) — \(c)\n"
                    }
                }
                parts.append(b)
            }
        }
        return Message(role: .system, content: parts.joined(separator: "\n\n"))
    }

    private func conversationHistory() -> [Message] {
        var history: [Message] = [buildSystemMessage()]
        history += (chat?.messages.filter { !($0.role == .assistant && $0.content.isEmpty) } ?? [])
        return history
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
        await runAssistantTurn(selection: sel)
    }

    /// Sends the confirmed poll choice back to the AI so it continues.
    @MainActor private func sendPollChoice(_ choice: String) async {
        guard let sel = chat?.selection else { return }
        store.appendMessage(Message(role: .user, content: "Выбран вариант: \(choice)"),
                            projectID: projectID, chatID: chatID)
        await runAssistantTurn(selection: sel)
    }

    /// One assistant reply turn: streams, then parses poll/tasks/image/files.
    @MainActor private func runAssistantTurn(selection sel: ModelSelection) async {
        guard let provider = settings.provider(for: sel.providerID) else {
            store.appendMessage(Message(role: .assistant,
                content: "⚠️ Провайдер не найден. Открой «Настройки → Нейросети»."),
                projectID: projectID, chatID: chatID)
            return
        }
        store.appendMessage(Message(role: .assistant, content: ""), projectID: projectID, chatID: chatID)
        let aid = currentAssistantID()

        isStreaming = true
        streamingMessageID = aid
        defer { isStreaming = false; streamingMessageID = nil }

        let client = AIClient(provider: provider, model: sel.model)
        var acc = ""
        var showingImagePanel = false
        do {
            for try await token in client.stream(messages: conversationHistory()) {
                acc += token
                // If the model is producing an image answer, swap to the generation panel
                // instead of showing raw "Processing image" / links.
                if !showingImagePanel && ResponseParser.looksLikeImageAnswer(acc) {
                    showingImagePanel = true
                    store.updateMessage(aid, projectID: projectID, chatID: chatID) {
                        $0.generatingImage = true
                        $0.content = ""
                    }
                }
                if !showingImagePanel {
                    store.updateLastAssistantMessage(acc, projectID: projectID, chatID: chatID)
                }
            }
            if acc.isEmpty {
                store.updateLastAssistantMessage(
                    "⚠️ Пустой ответ. Проверь модель «\(sel.model)», Base URL и ключ.",
                    projectID: projectID, chatID: chatID)
            }
            await finalizeReply(acc, aid: aid, provider: provider, client: client)
        } catch {
            errorText = error.localizedDescription
            store.updateLastAssistantMessage(acc.isEmpty ? "⚠️ \(error.localizedDescription)" : acc,
                                             projectID: projectID, chatID: chatID)
            store.save()
        }
    }

    @MainActor private func finalizeReply(_ acc: String, aid: UUID,
                                          provider: AIProvider, client: AIClient) async {
        let poll = ResponseParser.extractPoll(from: acc)
        let tasks = ResponseParser.extractTasks(from: acc)

        // Case A: the model returned an image link in chat — download & attach it.
        if let urlStr = ResponseParser.firstImageURL(in: acc) {
            store.updateMessage(aid, projectID: projectID, chatID: chatID) {
                $0.generatingImage = true
                $0.content = ""
            }
            let b64 = await AIClient.downloadBase64(urlStr) ?? ""
            store.updateMessage(aid, projectID: projectID, chatID: chatID) {
                $0.generatingImage = false
                if !b64.isEmpty {
                    $0.attachments.append(Attachment(kind: .image,
                        fileName: "image_\(Int(Date().timeIntervalSince1970)).png",
                        mimeType: "image/png", base64: b64))
                    $0.content = ResponseParser.stripImageNoise(acc)
                } else {
                    // download failed — at least keep a tappable note
                    $0.content = ResponseParser.stripImageNoise(acc).isEmpty
                        ? "Изображение готово, но не удалось загрузить предпросмотр."
                        : ResponseParser.stripImageNoise(acc)
                }
            }
            store.save()
            return
        }

        let cleaned = ResponseParser.stripControlBlocks(acc)
        store.updateMessage(aid, projectID: projectID, chatID: chatID) {
            $0.generatingImage = false
            $0.content = cleaned
            if let poll { $0.poll = poll }
            if let tasks { $0.tasks = tasks }
        }

        // Explicit ```image prompt``` request (if a provider has a real images endpoint)
        if let imgPrompt = ResponseParser.extractImagePrompt(from: acc), provider.supportsImages {
            store.updateMessage(aid, projectID: projectID, chatID: chatID) { $0.generatingImage = true }
            let b64 = await imageBase64(client: client, prompt: imgPrompt)
            store.updateMessage(aid, projectID: projectID, chatID: chatID) {
                $0.generatingImage = false
                if !b64.isEmpty {
                    $0.attachments.append(Attachment(kind: .image, fileName: "ai_image.png",
                                                     mimeType: "image/png", base64: b64))
                }
            }
        }

        // Folders to create
        for path in ResponseParser.extractFolders(from: acc) {
            store.addFolder(projectID: projectID, path: path)
        }
        // Deletions (files or folders)
        for path in ResponseParser.extractDeletions(from: acc) {
            deletePath(path)
        }

        // Terminal commands requested by the AI
        let runCommands = ResponseParser.extractTerminalCommands(from: acc)
        if !runCommands.isEmpty {
            var results = ""
            for c in runCommands {
                let out = store.runTerminal(c, projectID: projectID, fromAI: true)
                results += "$ \(c)\n\(out)\n"
            }
            // Feed results back so the AI can react in the chat too
            store.appendMessage(Message(role: .assistant,
                content: "🖥️ Терминал:\n```\n\(results.trimmingCharacters(in: .whitespacesAndNewlines))\n```"),
                projectID: projectID, chatID: chatID)
        }

        // Board operations
        for op in ResponseParser.extractBoardOps(from: acc) {
            applyBoardOp(op)
        }

        // Save generated files (with history-aware updates)
        let files = CodeExtractor.extract(from: acc)
        for f in files { upsertFile(f) }
        store.save()

        // If the AI planned tasks, execute them one by one.
        if let tasks, !tasks.isEmpty {
            await executeTasks(tasks, messageID: aid)
        }
    }

    /// Parse one board operation line from the AI.
    /// Formats: add "Title" | "detail" ; done "Title" ; del "Title" ; link "A" -> "B"
    @MainActor private func applyBoardOp(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        func quoted(_ s: String) -> [String] {
            var out: [String] = []; var cur = ""; var inside = false
            for ch in s { if ch == "\"" { if inside { out.append(cur); cur = "" }; inside.toggle() } else if inside { cur.append(ch) } }
            return out
        }
        let args = quoted(line)
        let lower = line.lowercased()
        if lower.hasPrefix("add") {
            guard let title = args.first else { return }
            store.addNode(projectID: projectID, title: title, detail: args.count >= 2 ? args[1] : "")
        } else if lower.hasPrefix("done") {
            guard let title = args.first, let n = store.findNode(titled: title, projectID: projectID) else { return }
            store.toggleNodeDone(n.id, projectID: projectID)
        } else if lower.hasPrefix("link") || lower.hasPrefix("connect") {
            guard args.count >= 2,
                  let a = store.findNode(titled: args[0], projectID: projectID),
                  let b = store.findNode(titled: args[1], projectID: projectID) else { return }
            store.connectNodes(a.id, b.id, projectID: projectID)
        } else if lower.hasPrefix("del") {
            guard let title = args.first, let n = store.findNode(titled: title, projectID: projectID) else { return }
            store.deleteNode(n.id, projectID: projectID)
        }
    }

    /// Delete a file by name or a folder (with everything inside).
    @MainActor private func deletePath(_ path: String) {
        var clean = path
        if clean.hasSuffix("/") { clean.removeLast() }
        let files = store.project(projectID)?.files ?? []
        if let folder = files.first(where: { $0.isDirectory && $0.name == clean }) {
            store.deleteFolder(projectID: projectID, path: folder.name)
        } else if files.contains(where: { $0.name.hasPrefix(clean + "/") }) {
            store.deleteFolder(projectID: projectID, path: clean)
        } else if let f = files.first(where: { $0.name == clean }) {
            store.deleteFile(f.id, projectID: projectID)
        }
    }

    /// Create or update a project file, keeping change history.
    @MainActor private func upsertFile(_ file: GeneratedFile) {
        if let existing = store.project(projectID)?.files.first(where: { $0.name == file.name }) {
            store.updateFile(existing.id, projectID: projectID, content: file.content, note: "ИИ обновил")
        } else {
            store.attachFiles([file], projectID: projectID)
        }
    }

    /// Runs AI-planned tasks sequentially: marks running → asks AI to do it → done.
    @MainActor private func executeTasks(_ tasks: [AgentTask], messageID: UUID) async {
        guard let sel = chat?.selection, let provider = settings.provider(for: sel.providerID) else { return }
        let client = AIClient(provider: provider, model: sel.model)

        for task in tasks {
            store.setTaskStatus(.running, taskID: task.id, messageID: messageID, projectID: projectID, chatID: chatID)
            store.appendMessage(Message(role: .assistant, content: "▶️ Выполняю: \(task.title)"),
                                projectID: projectID, chatID: chatID)
            let aid = currentAssistantID()
            isStreaming = true; streamingMessageID = aid

            var hist = conversationHistory()
            hist.append(Message(role: .user,
                content: "Выполни ТОЛЬКО эту задачу из плана: «\(task.title)». Дай результат (код в блоке с // file: если это файл). Не выводи блок tasks снова."))
            var acc = ""
            do {
                for try await token in client.stream(messages: hist) {
                    acc += token
                    store.updateLastAssistantMessage(acc, projectID: projectID, chatID: chatID)
                }
                store.updateMessage(aid, projectID: projectID, chatID: chatID) {
                    $0.content = ResponseParser.stripControlBlocks(acc)
                }
                for f in CodeExtractor.extract(from: acc) { upsertFile(f) }
                store.setTaskStatus(.done, taskID: task.id, messageID: messageID, projectID: projectID, chatID: chatID)
            } catch {
                store.updateLastAssistantMessage("⚠️ \(error.localizedDescription)", projectID: projectID, chatID: chatID)
                store.setTaskStatus(.failed, taskID: task.id, messageID: messageID, projectID: projectID, chatID: chatID)
            }
            isStreaming = false; streamingMessageID = nil
            store.save()
        }
        store.appendMessage(Message(role: .assistant, content: "✅ Все задачи выполнены."),
                            projectID: projectID, chatID: chatID)
        store.save()
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
struct PreviewImg: Identifiable { let id = UUID(); let image: UIImage }

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
    var onPollConfirm: (String) -> Void
    var onSaveImage: (Attachment) -> Void
    var onOpenCode: (_ name: String, _ language: String, _ content: String) -> Void

    @State private var previewImage: UIImage?

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
                if !message.tasks.isEmpty {
                    TaskChecklistView(tasks: message.tasks, accent: settings.accentColor)
                }
                if let poll = message.poll {
                    PollView(poll: poll, accent: settings.accentColor,
                             onAnswer: { onPollAnswer($0) },
                             onConfirm: { onPollConfirm($0) })
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
        .sheet(item: Binding(get: { previewImage.map { PreviewImg(image: $0) } },
                             set: { previewImage = $0?.image })) { p in
            ImagePreviewSheet(image: p.image, fileName: "image.png")
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
                    .onTapGesture { previewImage = ui }
                    .contextMenu {
                        Button {
                            UIImageWriteToSavedPhotosAlbum(ui, nil, nil, nil)
                        } label: { Label("Скачать в Фото", systemImage: "square.and.arrow.down") }
                        Button { onSaveImage(a) } label: { Label("Сохранить в файлы", systemImage: "doc") }
                        Button { previewImage = ui } label: { Label("Открыть", systemImage: "arrow.up.left.and.arrow.down.right") }
                    }
            } else {
                Label(a.fileName, systemImage: "paperclip")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var contentView: some View {
        if message.generatingImage {
            ImageGeneratingView(accent: settings.accentGradient)
        } else if message.content.isEmpty && message.attachments.isEmpty {
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
    var onConfirm: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(poll.question, systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline.bold())
            ForEach(poll.options, id: \.self) { opt in
                Button { if !poll.confirmed { onAnswer(opt) } } label: {
                    HStack {
                        Image(systemName: poll.selected == opt ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(accent)
                        Text(opt).foregroundStyle(.primary)
                        Spacer()
                        if poll.confirmed && poll.selected == opt {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(accent)
                        }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .background(poll.selected == opt ? accent.opacity(0.18) : Color.gray.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(poll.confirmed)
            }
            if poll.confirmed, let sel = poll.selected {
                Label("Подтверждено: \(sel)", systemImage: "checkmark.circle.fill")
                    .font(.caption2).foregroundStyle(accent)
            } else if let sel = poll.selected {
                Button {
                    onConfirm(sel)
                } label: {
                    Label("Подтвердить выбор", systemImage: "paperplane.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(.white)
                        .background(accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                Text("Выбери вариант и подтверди").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 300)
    }
}

// MARK: - Agent task checklist

struct TaskChecklistView: View {
    let tasks: [AgentTask]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checklist").foregroundStyle(accent)
                Text("План задач (\(tasks.filter { $0.status == .done }.count)/\(tasks.count))")
                    .font(.caption.bold())
            }
            ForEach(tasks) { t in
                HStack(spacing: 8) {
                    icon(for: t.status)
                    Text(t.title)
                        .font(.caption)
                        .strikethrough(t.status == .done)
                        .foregroundStyle(t.status == .done ? .secondary : .primary)
                    Spacer()
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 320)
    }

    @ViewBuilder private func icon(for status: AgentTask.Status) -> some View {
        switch status {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .running: ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
        case .done:    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
        case .failed:  Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
