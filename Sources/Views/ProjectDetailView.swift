import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    let projectID: UUID

    @State private var showingNewChat = false
    @State private var newChatTitle = ""

    private var project: Project? { store.projects.first(where: { $0.id == projectID }) }

    var body: some View {
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
                            VStack(alignment: .leading) {
                                Text(chat.title).font(.headline)
                                Text("\(chat.messages.count) сообщений")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Файлы (\(project.files.count))") {
                    if project.files.isEmpty {
                        Text("Файлы появятся здесь, когда ИИ сгенерирует код")
                            .foregroundStyle(.secondary).font(.caption)
                    }
                    ForEach(project.files) { file in
                        NavigationLink {
                            FileDetailView(file: file)
                        } label: {
                            Label(file.name, systemImage: "doc.text")
                        }
                    }
                }
            }
        }
        .navigationTitle(project?.name ?? "Проект")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewChat = true } label: {
                    Image(systemName: "plus.bubble")
                }
            }
        }
        .alert("Новый чат", isPresented: $showingNewChat) {
            TextField("Тема чата", text: $newChatTitle)
            Button("Создать") {
                let title = newChatTitle.trimmingCharacters(in: .whitespaces)
                _ = store.addChat(to: projectID,
                                  title: title.isEmpty ? "Без названия" : title,
                                  providerID: settings.defaultProvider?.id)
                newChatTitle = ""
            }
            Button("Отмена", role: .cancel) { newChatTitle = "" }
        }
    }
}
