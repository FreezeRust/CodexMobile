import SwiftUI
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    let projectID: UUID

    @State private var showingNewChat = false
    @State private var newChatTitle = ""
    @State private var showingNewFile = false
    @State private var newFileName = ""
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var showShare = false
    @State private var zipURL: URL?
    @State private var showFolderImporter = false
    @State private var showSkills = false
    @State private var showInstructions = false
    @State private var showScaffolds = false
    @State private var showVSCode = false

    private var project: Project? { store.projects.first(where: { $0.id == projectID }) }

    var body: some View {
        ZStack {
            if let bg = settings.bgColor { bg.ignoresSafeArea() }
            List {
                if let project {
                    Section("Чаты") {
                        if project.chats.isEmpty {
                            Text("Пока нет чатов").foregroundStyle(.secondary)
                        }
                        ForEach(project.chats) { chat in
                            NavigationLink {
                                ChatView(projectID: projectID, chatID: chat.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chat.title).font(.headline)
                                    HStack(spacing: 6) {
                                        Image(systemName: "cpu")
                                        Text(chat.selection?.displayName ?? "Модель не выбрана")
                                    }
                                    .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section("Инструменты") {
                        NavigationLink {
                            BoardView(projectID: projectID)
                        } label: {
                            Label("Доска задач", systemImage: "rectangle.split.3x1.fill")
                        }
                        NavigationLink {
                            TerminalView(projectID: projectID)
                        } label: {
                            Label("Терминал", systemImage: "terminal.fill")
                        }
                        Button { showScaffolds = true } label: {
                            Label("Создать каркас проекта", systemImage: "square.grid.2x2.fill")
                        }
                        Button { showVSCode = true } label: {
                            Label("Режим VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    Section {
                        Button { showInstructions = true } label: {
                            HStack {
                                Label("Инструкции проекта", systemImage: "doc.plaintext")
                                Spacer()
                                if !(project.instructions.isEmpty) {
                                    Image(systemName: "checkmark").font(.caption).foregroundStyle(settings.accentColor)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        Button { showSkills = true } label: {
                            HStack {
                                Label("Навыки ИИ", systemImage: "wand.and.stars")
                                Spacer()
                                Text("\(project.skills.count)").font(.caption).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    } header: {
                        Text("Контекст для ИИ")
                    } footer: {
                        Text("Инструкции и навыки добавляются к каждому запросу ИИ в этом проекте.")
                    }

                    Section {
                        if project.files.isEmpty {
                            Text("Файлы появятся, когда ИИ сгенерирует код — или создай вручную / импортируй папку")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                        ForEach(project.files) { file in
                            if file.isDirectory {
                                HStack {
                                    Label(file.name, systemImage: "folder.fill")
                                        .foregroundStyle(settings.accentColor)
                                    Spacer()
                                }
                                .swipeActions {
                                    Button("Удалить", role: .destructive) {
                                        store.deleteFolder(projectID: projectID, path: file.name)
                                    }
                                }
                            } else {
                                NavigationLink {
                                    FileDetailView(projectID: projectID, fileID: file.id)
                                } label: {
                                    Label(file.name, systemImage: "doc.text.fill")
                                }
                            }
                        }
                        .onDelete { idx in
                            idx.map { project.files[$0] }.forEach {
                                if $0.isDirectory { store.deleteFolder(projectID: projectID, path: $0.name) }
                                else { store.deleteFile($0.id, projectID: projectID) }
                            }
                        }
                        Button { newFileName = "new_file.txt"; showingNewFile = true } label: {
                            Label("Создать файл", systemImage: "doc.badge.plus")
                        }
                        Button { newFolderName = "new_folder"; showingNewFolder = true } label: {
                            Label("Создать папку", systemImage: "folder.badge.plus")
                        }
                        Button { showFolderImporter = true } label: {
                            Label("Импортировать папку", systemImage: "square.and.arrow.down.on.square")
                        }
                    } header: {
                        HStack {
                            Text("Файлы (\(project.files.count))")
                            Spacer()
                            if !project.files.isEmpty {
                                Button { exportZip() } label: {
                                    Label("Экспорт .zip", systemImage: "doc.zipper").font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(settings.bgColor == nil ? .visible : .hidden)
        }
        .navigationTitle(project?.name ?? "Проект")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showShare) { if let zipURL { ShareSheet(items: [zipURL]) } }
        .sheet(isPresented: $showSkills) { SkillsView(projectID: projectID) }
        .sheet(isPresented: $showInstructions) { InstructionsEditor(projectID: projectID) }
        .sheet(isPresented: $showScaffolds) { ScaffoldPicker(projectID: projectID) }
        .fullScreenCover(isPresented: $showVSCode) {
            VSCodeView(projectID: projectID) { showVSCode = false }
        }
        .fileImporter(isPresented: $showFolderImporter,
                      allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            importFolder(result)
        }
        .alert("Новый чат", isPresented: $showingNewChat) {
            TextField("Тема чата", text: $newChatTitle)
            Button("Создать") {
                let t = newChatTitle.trimmingCharacters(in: .whitespaces)
                let sel = settings.availableSelections().first
                _ = store.addChat(to: projectID, title: t.isEmpty ? "Новый чат" : t, selection: sel)
                newChatTitle = ""
            }
            Button("Отмена", role: .cancel) { newChatTitle = "" }
        }
        .alert("Новый файл", isPresented: $showingNewFile) {
            TextField("Имя файла (можно путь: src/app.js)", text: $newFileName)
            Button("Создать") {
                let n = newFileName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { store.addEmptyFile(projectID: projectID, name: n) }
                newFileName = ""
            }
            Button("Отмена", role: .cancel) { newFileName = "" }
        }
        .alert("Новая папка", isPresented: $showingNewFolder) {
            TextField("Имя папки (можно путь: src/utils)", text: $newFolderName)
            Button("Создать") {
                let n = newFolderName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { store.addFolder(projectID: projectID, path: n) }
                newFolderName = ""
            }
            Button("Отмена", role: .cancel) { newFolderName = "" }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showVSCode = true } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button { showingNewChat = true } label: { Label("Новый чат", systemImage: "plus.bubble") }
                Button { newFileName = "new_file.txt"; showingNewFile = true } label: {
                    Label("Новый файл", systemImage: "doc.badge.plus")
                }
                Button { newFolderName = "new_folder"; showingNewFolder = true } label: {
                    Label("Новая папка", systemImage: "folder.badge.plus")
                }
                Button { showFolderImporter = true } label: { Label("Импорт папки", systemImage: "square.and.arrow.down.on.square") }
                if !(project?.files.isEmpty ?? true) {
                    Button { exportZip() } label: { Label("Экспорт проекта .zip", systemImage: "doc.zipper") }
                }
            } label: { Image(systemName: "plus.circle.fill") }
        }
    }

    private func importFolder(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let folder = urls.first else { return }
        guard folder.startAccessingSecurityScopedResource() else { return }
        defer { folder.stopAccessingSecurityScopedResource() }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return }
        var imported: [GeneratedFile] = []
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            // Relative path inside the folder, so structure is preserved in names.
            let rel = fileURL.path.replacingOccurrences(of: folder.path + "/", with: "")
            if let data = try? Data(contentsOf: fileURL) {
                let text = String(data: data, encoding: .utf8) ?? "(бинарный файл, \(data.count) байт)"
                let ext = fileURL.pathExtension
                imported.append(GeneratedFile(name: rel, language: ext.isEmpty ? "text" : ext, content: text))
            }
            if imported.count >= 200 { break }   // safety cap
        }
        if !imported.isEmpty { store.attachFiles(imported, projectID: projectID) }
    }

    private func exportZip() {
        guard let project else { return }
        var entries: [(name: String, data: Data)] = []
        for f in project.files {
            entries.append((name: f.name, data: Data(f.content.utf8)))
        }
        // include a small README of chats for context
        var readme = "# \(project.name)\n\nЭкспортировано из OpenVolt.\n\nФайлов: \(project.files.count)\n"
        readme += "Чатов: \(project.chats.count)\n"
        entries.append((name: "README.md", data: Data(readme.utf8)))

        let zipData = ZipArchive.make(files: entries)
        let safeName = project.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).zip")
        do {
            try zipData.write(to: url, options: .atomic)
            zipURL = url; showShare = true
        } catch { print("zip export failed: \(error)") }
    }
}

// MARK: - Instructions editor

struct InstructionsEditor: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let projectID: UUID
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 220)
                } header: {
                    Text("Инструкции проекта")
                } footer: {
                    Text("Например: «Пиши на TypeScript», «Соблюдай стиль Apple», «Комментируй код по-русски».")
                }
            }
            .navigationTitle("Инструкции")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        store.setInstructions(text, projectID: projectID); dismiss()
                    }.bold()
                }
            }
            .onAppear { text = store.project(projectID)?.instructions ?? "" }
        }
    }
}

// MARK: - Skills view

struct SkillsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let projectID: UUID

    @State private var editingSkill: Skill?
    @State private var showEditor = false

    private var skills: [Skill] { store.project(projectID)?.skills ?? [] }

    var body: some View {
        NavigationStack {
            ZStack {
                if let bg = settings.bgColor { bg.ignoresSafeArea() }
                List {
                    if skills.isEmpty {
                        Text("Навыки — это инструкции/умения, которыми ИИ пользуется в этом проекте. Например «Генератор тестов» или «Стиль README».")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(skills) { skill in
                        Button { editingSkill = skill; showEditor = true } label: {
                            HStack {
                                Image(systemName: skill.enabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(skill.enabled ? settings.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.name).font(.headline).foregroundStyle(.primary)
                                    Text(skill.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Удалить", role: .destructive) { store.deleteSkill(skill.id, projectID: projectID) }
                            Button(skill.enabled ? "Выкл" : "Вкл") {
                                var s = skill; s.enabled.toggle(); store.updateSkill(s, projectID: projectID)
                            }.tint(settings.accentColor)
                        }
                    }
                    Button { editingSkill = nil; showEditor = true } label: {
                        Label("Добавить навык", systemImage: "plus")
                    }
                }
                .scrollContentBackground(settings.bgColor == nil ? .visible : .hidden)
            }
            .navigationTitle("Навыки ИИ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .sheet(isPresented: $showEditor) { SkillEditor(projectID: projectID, skill: editingSkill) }
        }
    }
}

struct SkillEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let projectID: UUID
    let skill: Skill?

    @State private var name = ""
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Навык") {
                    TextField("Название", text: $name)
                    TextField("Что делает / как использовать", text: $detail, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(skill == nil ? "Новый навык" : "Изменить навык")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(name.isEmpty || detail.isEmpty)
                }
            }
            .onAppear { if let s = skill { name = s.name; detail = s.detail } }
        }
    }

    private func save() {
        if var s = skill {
            s.name = name; s.detail = detail
            store.updateSkill(s, projectID: projectID)
        } else {
            store.addSkill(Skill(name: name, detail: detail), projectID: projectID)
        }
        dismiss()
    }
}

// MARK: - Scaffold picker

struct ScaffoldPicker: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) var dismiss
    let projectID: UUID
    @State private var created: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if let bg = settings.bgColor { bg.ignoresSafeArea() }
                List {
                    Section {
                        ForEach(Scaffolder.all) { s in
                            Button {
                                let n = store.applyScaffold(s, projectID: projectID)
                                created = "\(s.title): \(s.folders.count) папок, \(n) файлов"
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: s.icon)
                                        .foregroundStyle(.white)
                                        .frame(width: 40, height: 40)
                                        .background(settings.accentGradient, in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title).font(.headline).foregroundStyle(.primary)
                                        Text(s.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(settings.accentColor)
                                }
                            }
                        }
                    } footer: {
                        Text("Создаётся структура папок и базовый код. Можно сразу редактировать и запускать (node для JS).")
                    }
                }
                .scrollContentBackground(settings.bgColor == nil ? .visible : .hidden)
            }
            .navigationTitle("Каркасы проектов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .alert("Готово!", isPresented: Binding(get: { created != nil }, set: { if !$0 { created = nil } })) {
                Button("Отлично") { dismiss() }
            } message: { Text(created ?? "") }
        }
    }
}
