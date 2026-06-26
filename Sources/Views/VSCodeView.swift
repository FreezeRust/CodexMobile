import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A VS Code–style IDE interface adapted for iPhone (landscape-friendly).
struct VSCodeView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    let projectID: UUID
    var onExit: () -> Void

    enum SideTab { case explorer, search, board, skills, settings }
    @State private var sidebarOpen = true
    @State private var activeTab: SideTab = .explorer
    @State private var openFileID: UUID?
    @State private var openTabs: [UUID] = []
    @State private var draft: String = ""
    @State private var panelOpen = false
    @State private var aiOpen = false
    @State private var termInput = ""
    @State private var searchText = ""

    // rename / new dialogs
    @State private var renameTarget: GeneratedFile?
    @State private var renameText = ""
    @State private var newFolderDialog = false
    @State private var newName = ""
    @State private var newIsFolder = false

    // live drag deltas (added to persisted sizes)
    @State private var dragSidebar: CGFloat = 0
    @State private var dragPanel: CGFloat = 0
    @State private var dragAI: CGFloat = 0

    // AI chat
    @State private var aiInput = ""
    @State private var aiMessages: [Message] = []
    @State private var aiBusy = false
    @State private var aiSelection: ModelSelection?
    @State private var showAIModelPicker = false
    @State private var aiAttachments: [Attachment] = []
    @State private var aiPhotoItems: [PhotosPickerItem] = []
    @State private var showAIFileImporter = false

    // palette
    private let cActivity = Color(hex: 0x333333)
    private let cSidebar  = Color(hex: 0x252526)
    private let cEditor   = Color(hex: 0x1E1E1E)
    private let cTabBar   = Color(hex: 0x2D2D2D)
    private let cStatus   = Color(hex: 0x007ACC)
    private let cText     = Color(hex: 0xD4D4D4)
    private let cMuted    = Color(hex: 0x858585)

    private var project: Project? { store.project(projectID) }
    private var files: [GeneratedFile] { (project?.files ?? []).filter { !$0.isDirectory } }
    private var openFile: GeneratedFile? { files.first { $0.id == openFileID } }
    private var codeFont: Font { settings.codeFont.font(size: settings.ideFontSize) }

    private var sidebarW: CGFloat { max(150, min(360, settings.ideSidebarWidth + dragSidebar)) }
    private var panelH: CGFloat { max(120, min(420, settings.idePanelHeight + dragPanel)) }
    private var aiW: CGFloat { max(220, min(440, settings.ideAIWidth + dragAI)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            cEditor.ignoresSafeArea()
            VStack(spacing: 0) {
                topTabBar
                HStack(spacing: 0) {
                    activityBar
                    if sidebarOpen {
                        sidebar.frame(width: sidebarW).transition(.move(edge: .leading))
                        resizeHandleV { dragSidebar = $0 } commit: {
                            settings.ideSidebarWidth = Double(sidebarW); dragSidebar = 0
                        }
                    }
                    editorColumn
                    if aiOpen {
                        resizeHandleV { dragAI = -$0 } commit: {
                            settings.ideAIWidth = Double(aiW); dragAI = 0
                        }
                        aiPanel.frame(width: aiW).transition(.move(edge: .trailing))
                    }
                }
                statusBar
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: sidebarOpen)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: panelOpen)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: aiOpen)
        .onAppear {
            if openFileID == nil, let first = files.first {
                openFileID = first.id; openTabs = [first.id]; draft = first.content
            }
        }
        .alert("Переименовать", isPresented: Binding(get: { renameTarget != nil },
                                                     set: { if !$0 { renameTarget = nil } })) {
            TextField("Имя", text: $renameText)
            Button("Сохранить") {
                if let t = renameTarget, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    if t.isDirectory { store.renameFolder(t.id, projectID: projectID, newName: renameText) }
                    else { store.renameFile(t.id, projectID: projectID, name: renameText) }
                }
                renameTarget = nil
            }
            Button("Отмена", role: .cancel) { renameTarget = nil }
        }
        .alert(newIsFolder ? "Новая папка" : "Новый файл", isPresented: $newFolderDialog) {
            TextField(newIsFolder ? "путь/папка" : "имя.расш", text: $newName)
            Button("Создать") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty {
                    if newIsFolder { store.addFolder(projectID: projectID, path: n) }
                    else { store.addEmptyFile(projectID: projectID, name: n) }
                }
                newName = ""
            }
            Button("Отмена", role: .cancel) { newName = "" }
        }
    }

    // MARK: - Top tab bar

    private var topTabBar: some View {
        HStack(spacing: 0) {
            Button { onExit() } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(cText)
                    .frame(width: 38, height: 35).background(cActivity)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(openTabs, id: \.self) { id in
                        if let f = files.first(where: { $0.id == id }) { fileTab(f) }
                    }
                }
            }
            Spacer(minLength: 0)
            Button { aiOpen.toggle() } label: {
                Image(systemName: "sparkles").font(.caption)
                    .foregroundStyle(aiOpen ? cText : cMuted)
                    .frame(width: 40, height: 35).background(cTabBar)
            }
        }
        .background(cTabBar)
    }

    private func fileTab(_ f: GeneratedFile) -> some View {
        let active = f.id == openFileID
        return HStack(spacing: 6) {
            Image(systemName: iconFor(f.name)).font(.caption2).foregroundStyle(iconColor(f.name))
            Text(shortName(f.name)).font(.caption).foregroundStyle(active ? cText : cMuted)
            Button {
                openTabs.removeAll { $0 == f.id }
                if openFileID == f.id { selectFile(files.first { openTabs.contains($0.id) }) }
            } label: { Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(cMuted) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(active ? cEditor : cTabBar)
        .overlay(alignment: .top) { if active { Rectangle().fill(cStatus).frame(height: 1.5) } }
        .onTapGesture { selectFile(f) }
    }

    // MARK: - Activity bar

    private var activityBar: some View {
        VStack(spacing: 20) {
            activityIcon("doc.on.doc", .explorer)
            activityIcon("magnifyingglass", .search)
            activityIcon("rectangle.split.3x1", .board)
            activityIcon("wand.and.stars", .skills)
            Spacer()
            activityIcon("gearshape", .settings)
        }
        .padding(.vertical, 14)
        .frame(width: settings.ideActivityBarWidth)
        .frame(maxHeight: .infinity)
        .background(cActivity)
    }

    private func activityIcon(_ icon: String, _ tab: SideTab) -> some View {
        Button {
            if activeTab == tab && sidebarOpen { sidebarOpen = false }
            else { activeTab = tab; sidebarOpen = true }
        } label: {
            Image(systemName: icon).font(.title3)
                .foregroundStyle(activeTab == tab && sidebarOpen ? cText : cMuted)
                .overlay(alignment: .leading) {
                    if activeTab == tab && sidebarOpen {
                        Rectangle().fill(cText).frame(width: 2).offset(x: -14)
                    }
                }
        }
    }

    // MARK: - Sidebar (switches by tab)

    private var sidebar: some View {
        Group {
            switch activeTab {
            case .explorer: explorerPanel
            case .search:   searchPanel
            case .board:    boardPanel
            case .skills:   skillsPanel
            case .settings: settingsPanel
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(cSidebar)
    }

    private var explorerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("ПРОВОДНИК") {
                Menu {
                    Button { newIsFolder = false; newName = "file.txt"; newFolderDialog = true } label: {
                        Label("Новый файл", systemImage: "doc.badge.plus")
                    }
                    Button { newIsFolder = true; newName = "folder"; newFolderDialog = true } label: {
                        Label("Новая папка", systemImage: "folder.badge.plus")
                    }
                } label: { Image(systemName: "plus").font(.caption).foregroundStyle(cMuted) }
            }
            Text(project?.name.uppercased() ?? "ПРОЕКТ").font(.caption.bold()).foregroundStyle(cText)
                .padding(.horizontal, 12).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(project?.files ?? []) { f in explorerRow(f) }
                }
            }
        }
    }

    private func explorerRow(_ f: GeneratedFile) -> some View {
        let depth = f.name.filter { $0 == "/" }.count
        return HStack(spacing: 6) {
            Image(systemName: f.isDirectory ? "folder.fill" : iconFor(f.name))
                .font(.caption2).foregroundStyle(f.isDirectory ? Color(hex: 0xC09553) : iconColor(f.name))
            Text(shortName(f.name)).font(.caption).foregroundStyle(cText).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5).padding(.leading, CGFloat(12 + depth * 12)).padding(.trailing, 8)
        .background(f.id == openFileID ? Color.white.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { if !f.isDirectory { openInTab(f) } }
        .contextMenu {
            Button { renameTarget = f; renameText = f.name } label: { Label("Переименовать", systemImage: "pencil") }
            if f.isDirectory {
                Button(role: .destructive) { store.deleteFolder(projectID: projectID, path: f.name) } label: {
                    Label("Удалить папку", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) { store.deleteFile(f.id, projectID: projectID) } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ПОИСК") { EmptyView() }
            TextField("Найти в файлах", text: $searchText)
                .textFieldStyle(.plain).font(.caption).foregroundStyle(cText)
                .padding(8).background(Color(hex: 0x3C3C3C)).cornerRadius(4).padding(.horizontal, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults, id: \.0) { (id, name, line) in
                        Button { if let f = files.first(where: { $0.id == id }) { openInTab(f) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shortName(name)).font(.caption2.bold()).foregroundStyle(cText)
                                Text(line).font(.caption2).foregroundStyle(cMuted).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                        }
                    }
                }
            }
        }
    }
    private var searchResults: [(UUID, String, String)] {
        guard searchText.count >= 2 else { return [] }
        var out: [(UUID, String, String)] = []
        for f in files {
            for line in f.content.components(separatedBy: "\n") where line.localizedCaseInsensitiveContains(searchText) {
                out.append((f.id, f.name, line.trimmingCharacters(in: .whitespaces)))
                if out.count > 50 { return out }
            }
        }
        return out
    }

    private var boardPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("ДОСКА") {
                Button { store.addNode(projectID: projectID, title: "Задача") } label: {
                    Image(systemName: "plus").font(.caption).foregroundStyle(cMuted)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(project?.board.nodes ?? []) { n in
                        HStack(spacing: 8) {
                            Image(systemName: n.done ? "checkmark.circle.fill" : "circle")
                                .font(.caption).foregroundStyle(n.done ? cStatus : cMuted)
                                .onTapGesture { store.toggleNodeDone(n.id, projectID: projectID) }
                            Text(n.title).font(.caption).foregroundStyle(cText).strikethrough(n.done)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                    if (project?.board.nodes.isEmpty ?? true) {
                        Text("Открой полную доску из проекта").font(.caption2).foregroundStyle(cMuted)
                            .padding(12)
                    }
                }
            }
        }
    }

    private var skillsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("НАВЫКИ") {
                Button { store.addSkill(Skill(name: "Навык", detail: "описание"), projectID: projectID) } label: {
                    Image(systemName: "plus").font(.caption).foregroundStyle(cMuted)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !(project?.instructions.isEmpty ?? true) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ИНСТРУКЦИИ").font(.system(size: 10, weight: .bold)).foregroundStyle(cMuted)
                            Text(project?.instructions ?? "").font(.caption2).foregroundStyle(cText).lineLimit(4)
                        }.padding(.horizontal, 12)
                    }
                    ForEach(project?.skills ?? []) { s in
                        HStack(spacing: 8) {
                            Image(systemName: s.enabled ? "checkmark.circle.fill" : "circle")
                                .font(.caption).foregroundStyle(s.enabled ? cStatus : cMuted)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).font(.caption.bold()).foregroundStyle(cText)
                                Text(s.detail).font(.caption2).foregroundStyle(cMuted).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 3)
                        .contextMenu {
                            Button(role: .destructive) { store.deleteSkill(s.id, projectID: projectID) } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("НАСТРОЙКИ IDE") { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sliderRow("Размер шрифта", value: $settings.ideFontSize, range: 9...22, unit: "pt")
                    sliderRow("Ширина боковой панели", value: $settings.ideSidebarWidth, range: 150...360, unit: "")
                    sliderRow("Высота нижней панели", value: $settings.idePanelHeight, range: 120...420, unit: "")
                    sliderRow("Ширина ИИ-чата", value: $settings.ideAIWidth, range: 220...440, unit: "")
                    sliderRow("Ширина Activity Bar", value: $settings.ideActivityBarWidth, range: 40...70, unit: "")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Шрифт кода").font(.caption.bold()).foregroundStyle(cText)
                        Picker("", selection: $settings.codeFont) {
                            ForEach(CodeFont.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.menu).tint(cText)
                    }
                }
                .padding(12)
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.bold()).foregroundStyle(cText)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)").font(.caption2).foregroundStyle(cMuted)
            }
            Slider(value: value, in: range).tint(cStatus)
        }
    }

    private func sectionHeader<T: View>(_ title: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(cMuted)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - Editor column (editor + bottom panel)

    private var editorColumn: some View {
        VStack(spacing: 0) {
            editorArea
            if panelOpen {
                resizeHandleH { dragPanel = -$0 } commit: {
                    settings.idePanelHeight = Double(panelH); dragPanel = 0
                }
                bottomPanel.frame(height: panelH).transition(.move(edge: .bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorArea: some View {
        ZStack {
            cEditor
            if let f = openFile {
                HStack(alignment: .top, spacing: 0) {
                    gutter(for: draft)
                    TextEditor(text: $draft)
                        .font(codeFont).foregroundStyle(cText)
                        .scrollContentBackground(.hidden).background(cEditor)
                        .onChange(of: draft) { _, v in
                            store.updateFile(f.id, projectID: projectID, content: v, note: "VS Code")
                        }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "bolt.fill").font(.system(size: 44)).foregroundStyle(cMuted)
                    Text("OpenVolt IDE").font(.title3).foregroundStyle(cMuted)
                    Text("Открой файл в проводнике").font(.caption).foregroundStyle(cMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gutter(for text: String) -> some View {
        let count = max(text.components(separatedBy: "\n").count, 1)
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(1...count, id: \.self) { n in
                    Text("\(n)").font(codeFont).foregroundStyle(cMuted)
                        .frame(height: settings.ideFontSize * 1.35)
                }
            }.padding(.top, 8)
        }
        .frame(width: 36).background(cEditor).disabled(true)
    }

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("ТЕРМИНАЛ").font(.system(size: 11, weight: .semibold)).foregroundStyle(cText)
                Spacer()
                Button { store.clearTerminal(projectID: projectID) } label: {
                    Image(systemName: "trash").font(.caption2).foregroundStyle(cMuted)
                }
                Button { panelOpen = false } label: {
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(cMuted)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7).background(cTabBar)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(project?.terminalHistory ?? []) { e in
                            Text("\(e.fromAI ? "🤖 " : "$ ")\(e.command)").foregroundStyle(Color(hex: 0x4EC9B0))
                            if !e.output.isEmpty {
                                Text(e.output).foregroundStyle(e.isError ? Color(hex: 0xF48771) : cText)
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .font(settings.codeFont.font(size: settings.ideFontSize - 1))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .onChange(of: project?.terminalHistory.count) { _, _ in
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            HStack(spacing: 6) {
                Text("➜").foregroundStyle(Color(hex: 0x4EC9B0))
                TextField("команда…", text: $termInput)
                    .textFieldStyle(.plain).foregroundStyle(cText)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onSubmit(runTerm)
            }
            .font(settings.codeFont.font(size: settings.ideFontSize - 1))
            .padding(.horizontal, 10).padding(.vertical, 8).background(cEditor)
        }
        .background(cEditor)
    }

    // MARK: - AI panel (right)

    private var aiPanel: some View {
        VStack(spacing: 0) {
            // Header with model selector
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(cStatus)
                Button { showAIModelPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(currentAIModelLabel).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(cText).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(cMuted)
                    }
                }
                Spacer()
                Button { aiMessages.removeAll() } label: {
                    Image(systemName: "trash").font(.caption2).foregroundStyle(cMuted)
                }
                Button { aiOpen = false } label: { Image(systemName: "xmark").font(.caption2).foregroundStyle(cMuted) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).background(cTabBar)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if aiMessages.isEmpty {
                            Text("Спроси ИИ про код, прикрепи фото или файл — он видит открытый файл проекта.")
                                .font(.caption2).foregroundStyle(cMuted).padding(.top, 8)
                        }
                        ForEach(aiMessages) { m in aiBubble(m) }
                        Color.clear.frame(height: 1).id("aiend")
                    }.padding(10)
                }
                .onChange(of: aiMessages.last?.content) { _, _ in
                    withAnimation { proxy.scrollTo("aiend", anchor: .bottom) }
                }
            }

            // Pending attachments strip
            if !aiAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(aiAttachments) { a in
                            HStack(spacing: 4) {
                                Image(systemName: a.kind == .image ? "photo.fill" : "doc.fill").font(.system(size: 9))
                                Text(shortName(a.fileName)).font(.system(size: 9)).lineLimit(1)
                                Button { aiAttachments.removeAll { $0.id == a.id } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 9))
                                }
                            }
                            .foregroundStyle(cText)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color(hex: 0x3C3C3C)).cornerRadius(6)
                        }
                    }.padding(.horizontal, 10)
                }
                .padding(.vertical, 5).background(cSidebar)
            }

            // Input row: media + text + send
            HStack(spacing: 6) {
                Menu {
                    PhotosPicker(selection: $aiPhotoItems, matching: .images) {
                        Label("Фото", systemImage: "photo")
                    }
                    Button { showAIFileImporter = true } label: { Label("Файл", systemImage: "doc") }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(cStatus).font(.title3)
                }
                TextField("Спроси про код…", text: $aiInput, axis: .vertical)
                    .textFieldStyle(.plain).font(.caption).foregroundStyle(cText)
                    .lineLimit(1...4)
                    .padding(8).background(Color(hex: 0x3C3C3C)).cornerRadius(6)
                Button { Task { await sendAI() } } label: {
                    Image(systemName: aiBusy ? "stop.circle" : "arrow.up.circle.fill")
                        .foregroundStyle(canSendAI ? cStatus : cMuted).font(.title3)
                }.disabled(!canSendAI)
            }
            .padding(10).background(cSidebar)
        }
        .background(cSidebar)
        .onChange(of: aiPhotoItems) { _, items in Task { await loadAIPhotos(items) } }
        .fileImporter(isPresented: $showAIFileImporter,
                      allowedContentTypes: [.item], allowsMultipleSelection: true) { handleAIFiles($0) }
        .sheet(isPresented: $showAIModelPicker) { aiModelPicker }
    }

    private func aiBubble(_ m: Message) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.role == .user ? "Ты" : "ИИ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(m.role == .user ? cStatus : Color(hex: 0x4EC9B0))
            ForEach(m.attachments) { a in
                if a.kind == .image, let d = Data(base64Encoded: a.base64), let ui = UIImage(data: d) {
                    Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Label(shortName(a.fileName), systemImage: "paperclip").font(.system(size: 10)).foregroundStyle(cMuted)
                }
            }
            if !m.content.isEmpty || m.attachments.isEmpty {
                Text(m.content.isEmpty ? "…" : m.content)
                    .font(.caption).foregroundStyle(cText).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(m.role == .user ? Color.white.opacity(0.05) : cSidebar)
        .cornerRadius(8)
    }

    private var aiModelPicker: some View {
        NavigationStack {
            List {
                ForEach(settings.providers) { p in
                    Section(p.isGift ? "🎁 \(p.name)" : p.name) {
                        ForEach(p.models, id: \.self) { m in
                            let shown = p.isGift ? p.displayName(for: m) : m
                            let sel = ModelSelection(providerID: p.id, model: m,
                                                     displayName: p.isGift ? shown : "\(p.name) · \(m)")
                            Button {
                                aiSelection = sel; showAIModelPicker = false
                            } label: {
                                HStack {
                                    Image(systemName: "cpu").foregroundStyle(settings.accentColor)
                                    Text(shown).foregroundStyle(.primary)
                                    Spacer()
                                    if aiSelection?.id == sel.id || (aiSelection == nil && p.isDefault && m == p.models.first) {
                                        Image(systemName: "checkmark").foregroundStyle(settings.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Выбор модели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showAIModelPicker = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var canSendAI: Bool {
        !aiBusy && (!aiInput.trimmingCharacters(in: .whitespaces).isEmpty || !aiAttachments.isEmpty)
    }
    private var currentAIModelLabel: String {
        if let sel = aiSelection {
            if let p = settings.provider(for: sel.providerID), p.isGift { return p.displayName(for: sel.model) }
            return sel.model
        }
        return settings.defaultProvider.map { p in
            p.isGift ? p.displayName(for: p.primaryModel) : p.primaryModel
        } ?? "Модель"
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 14) {
            Button { sidebarOpen.toggle() } label: { Image(systemName: "sidebar.left").font(.caption2) }
            Button { panelOpen.toggle() } label: {
                HStack(spacing: 3) { Image(systemName: "terminal"); Text("Терминал") }.font(.caption2)
            }
            Button { aiOpen.toggle() } label: {
                HStack(spacing: 3) { Image(systemName: "sparkles"); Text("ИИ") }.font(.caption2)
            }
            Spacer()
            if let f = openFile {
                Text(langLabel(f.name)).font(.caption2)
                Text("\(draft.components(separatedBy: "\n").count) стр").font(.caption2)
            }
            Image(systemName: "bolt.fill").font(.caption2)
            Text("OpenVolt").font(.caption2)
        }
        .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 5).background(cStatus)
    }

    // MARK: - Resize handles

    private func resizeHandleV(onDrag: @escaping (CGFloat) -> Void, commit: @escaping () -> Void) -> some View {
        Rectangle().fill(Color.black.opacity(0.001)).frame(width: 10)
            .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1))
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { onDrag($0.translation.width) }.onEnded { _ in commit() })
    }
    private func resizeHandleH(onDrag: @escaping (CGFloat) -> Void, commit: @escaping () -> Void) -> some View {
        Rectangle().fill(Color.black.opacity(0.001)).frame(height: 10)
            .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1))
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { onDrag($0.translation.height) }.onEnded { _ in commit() })
    }

    // MARK: - Actions

    private func selectFile(_ f: GeneratedFile?) {
        guard let f else { openFileID = nil; return }
        openFileID = f.id; draft = f.content
    }
    private func openInTab(_ f: GeneratedFile) {
        if !openTabs.contains(f.id) { openTabs.append(f.id) }
        selectFile(f)
    }
    private func runTerm() {
        let c = termInput.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        store.runTerminal(c, projectID: projectID); termInput = ""
    }

    @MainActor private func sendAI() async {
        let text = aiInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || !aiAttachments.isEmpty else { return }
        // resolve provider + model from selection (fallback to default)
        let provider: AIProvider
        let model: String
        if let sel = aiSelection, let p = settings.provider(for: sel.providerID) {
            provider = p; model = sel.model
        } else if let p = settings.defaultProvider {
            provider = p; model = p.primaryModel
        } else {
            aiMessages.append(Message(role: .assistant, content: "Добавь нейросеть в настройках."))
            return
        }

        let atts = aiAttachments
        aiInput = ""; aiAttachments = []
        aiMessages.append(Message(role: .user, content: text, attachments: atts))
        aiMessages.append(Message(role: .assistant, content: ""))
        aiBusy = true; defer { aiBusy = false }

        var history: [Message] = [Message(role: .system,
            content: "Ты помощник-программист в IDE OpenVolt. Отвечай кратко. Текущий файл: \(openFile?.name ?? "нет").\n\(openFile.map { "Содержимое:\n\($0.content.prefix(2000))" } ?? "")")]
        history += aiMessages.filter { !($0.role == .assistant && $0.content.isEmpty) }

        let client = AIClient(provider: provider, model: model)
        var acc = ""
        do {
            for try await tok in client.stream(messages: history) {
                acc += tok
                if let i = aiMessages.lastIndex(where: { $0.role == .assistant }) { aiMessages[i].content = acc }
            }
            if acc.isEmpty, let i = aiMessages.lastIndex(where: { $0.role == .assistant }) {
                aiMessages[i].content = "⚠️ Пустой ответ."
            }
        } catch {
            if let i = aiMessages.lastIndex(where: { $0.role == .assistant }) {
                aiMessages[i].content = "⚠️ \(error.localizedDescription)"
            }
        }
    }

    private func loadAIPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                aiAttachments.append(Attachment(kind: .image, fileName: "image_\(aiAttachments.count + 1).jpg",
                                                mimeType: "image/jpeg", base64: data.base64EncodedString()))
            }
        }
        aiPhotoItems = []
    }
    private func handleAIFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                aiAttachments.append(Attachment(kind: .file, fileName: url.lastPathComponent,
                                                mimeType: "application/octet-stream",
                                                base64: data.base64EncodedString()))
            }
        }
    }

    // MARK: - Helpers

    private func shortName(_ path: String) -> String { String(path.split(separator: "/").last ?? "") }
    private func langLabel(_ name: String) -> String {
        let e = (name as NSString).pathExtension.lowercased()
        switch e {
        case "js": return "JavaScript"; case "ts": return "TypeScript"
        case "py": return "Python"; case "swift": return "Swift"
        case "html": return "HTML"; case "css": return "CSS"; case "json": return "JSON"
        case "java": return "Java"; case "md": return "Markdown"
        default: return e.isEmpty ? "Plain" : e.uppercased()
        }
    }
    private func iconFor(_ name: String) -> String {
        let e = (name as NSString).pathExtension.lowercased()
        switch e {
        case "js","ts","py","swift","java": return "curlybraces"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "list.bullet.indent"
        case "md": return "doc.richtext"
        default: return "doc"
        }
    }
    private func iconColor(_ name: String) -> Color {
        let e = (name as NSString).pathExtension.lowercased()
        switch e {
        case "js": return Color(hex: 0xE8D44D); case "ts": return Color(hex: 0x3178C6)
        case "html": return Color(hex: 0xE44D26); case "css": return Color(hex: 0x2965F1)
        case "json": return Color(hex: 0xCBCB41); case "py": return Color(hex: 0x3572A5)
        case "swift": return Color(hex: 0xF05138)
        default: return Color(hex: 0x9CDCFE)
        }
    }
}
