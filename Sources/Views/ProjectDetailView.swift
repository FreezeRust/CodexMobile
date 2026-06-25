import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var session: SessionStore
    let projectID: UUID

    @State private var showingNewChat = false
    @State private var newChatTitle = ""

    private var project: Project? { store.projects.first(where: { $0.id == projectID }) }

    var body: some View {
        ZStack {
            if let bg = settings.theme.background { bg.ignoresSafeArea() }
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
                                        Image(systemName: chat.selection?.source == .codex ? "bolt.fill" : "cpu")
                                        Text(chat.selection?.displayName ?? "Модель не выбрана")
                                    }
                                    .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section("Файлы (\(project.files.count))") {
                        if project.files.isEmpty {
                            Text("Файлы появятся, когда ИИ сгенерирует код")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                        ForEach(project.files) { file in
                            NavigationLink { FileDetailView(file: file) } label: {
                                Label(file.name, systemImage: "doc.text.fill")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(settings.theme.background == nil ? .visible : .hidden)
        }
        .navigationTitle(project?.name ?? "Проект")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert("Новый чат", isPresented: $showingNewChat) {
            TextField("Тема чата", text: $newChatTitle)
            Button("Создать") {
                let t = newChatTitle.trimmingCharacters(in: .whitespaces)
                let sel = settings.availableSelections(codexLoggedIn: session.isCodexLoggedIn).first
                _ = store.addChat(to: projectID, title: t.isEmpty ? "Новый чат" : t, selection: sel)
                newChatTitle = ""
            }
            Button("Отмена", role: .cancel) { newChatTitle = "" }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showingNewChat = true } label: { Image(systemName: "plus.bubble.fill") }
        }
    }
}
