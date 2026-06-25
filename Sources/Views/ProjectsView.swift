import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                themedBackground
                content
            }
            .navigationTitle("Проекты")
            .navigationDestination(for: UUID.self) { id in
                if store.projects.contains(where: { $0.id == id }) {
                    ProjectDetailView(projectID: id)
                }
            }
            .toolbar { toolbarContent }
            .alert("Новый проект", isPresented: $showingNew) {
                TextField("Название проекта", text: $newName)
                Button("Создать") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { store.addProject(name: n) }
                    newName = ""
                }
                Button("Отмена", role: .cancel) { newName = "" }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if store.projects.isEmpty {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(settings.accent.gradient.opacity(0.2)).frame(width: 110, height: 110)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(settings.accent.gradient)
                }
                Text("Нет проектов").font(.title2.bold())
                Text("Создай первый проект, чтобы начать чат с ИИ\nи генерировать файлы прямо на телефоне.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showingNew = true
                } label: {
                    Label("Создать проект", systemImage: "plus")
                        .font(.headline).padding(.horizontal, 22).padding(.vertical, 12)
                        .background(settings.accent.gradient, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
            .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.projects) { project in
                        NavigationLink(value: project.id) {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { store.deleteProject(project) } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder private var themedBackground: some View {
        if let bg = settings.theme.background { bg.ignoresSafeArea() }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showingNew = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
        }
    }
}

struct ProjectCard: View {
    @EnvironmentObject var settings: SettingsStore
    let project: Project

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(settings.accent.gradient.opacity(0.22))
                    .frame(width: 48, height: 48)
                Image(systemName: "folder.fill")
                    .foregroundStyle(settings.accent.gradient)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.headline).foregroundStyle(.primary)
                HStack(spacing: 10) {
                    Label("\(project.chats.count)", systemImage: "bubble.left.and.bubble.right.fill")
                    Label("\(project.files.count)", systemImage: "doc.fill")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(cardBG, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.06)))
    }

    private var cardBG: Color {
        settings.theme.card ?? Color(.secondarySystemBackground)
    }
}
