import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    let projectID: UUID

    @State private var showingNewChat = false
    @State private var newChatTitle = ""
    @State private var showingNewFile = false
    @State private var newFileName = ""
    @State private var showShare = false
    @State private var zipURL: URL?

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
                    Section {
                        if project.files.isEmpty {
                            Text("Файлы появятся, когда ИИ сгенерирует код — или создай вручную")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                        ForEach(project.files) { file in
                            NavigationLink {
                                FileDetailView(projectID: projectID, fileID: file.id)
                            } label: {
                                Label(file.name, systemImage: "doc.text.fill")
                            }
                        }
                        .onDelete { idx in
                            idx.map { project.files[$0] }.forEach { store.deleteFile($0.id, projectID: projectID) }
                        }
                        Button { newFileName = "new_file.txt"; showingNewFile = true } label: {
                            Label("Создать файл", systemImage: "doc.badge.plus")
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
            TextField("Имя файла", text: $newFileName)
            Button("Создать") {
                let n = newFileName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { store.addEmptyFile(projectID: projectID, name: n) }
                newFileName = ""
            }
            Button("Отмена", role: .cancel) { newFileName = "" }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button { showingNewChat = true } label: { Label("Новый чат", systemImage: "plus.bubble") }
                Button { newFileName = "new_file.txt"; showingNewFile = true } label: {
                    Label("Новый файл", systemImage: "doc.badge.plus")
                }
                if !(project?.files.isEmpty ?? true) {
                    Button { exportZip() } label: { Label("Экспорт проекта .zip", systemImage: "doc.zipper") }
                }
            } label: { Image(systemName: "plus.circle.fill") }
        }
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
