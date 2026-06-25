import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    ContentUnavailableView(
                        "Нет проектов",
                        systemImage: "folder.badge.plus",
                        description: Text("Создай свой первый проект, чтобы начать чат с ИИ и генерировать файлы.")
                    )
                } else {
                    List {
                        ForEach(store.projects) { project in
                            NavigationLink(value: project.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.name).font(.headline)
                                    Text("\(project.chats.count) чатов · \(project.files.count) файлов")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { idx in
                            idx.map { store.projects[$0] }.forEach(store.deleteProject)
                        }
                    }
                }
            }
            .navigationTitle("Проекты")
            .navigationDestination(for: UUID.self) { id in
                if let project = store.projects.first(where: { $0.id == id }) {
                    ProjectDetailView(projectID: project.id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("Новый проект", isPresented: $showingNew) {
                TextField("Название проекта", text: $newName)
                Button("Создать") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { store.addProject(name: name) }
                    newName = ""
                }
                Button("Отмена", role: .cancel) { newName = "" }
            }
        }
    }
}
