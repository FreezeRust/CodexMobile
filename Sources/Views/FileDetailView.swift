import SwiftUI

struct FileDetailView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var store: AppStore
    let projectID: UUID
    let fileID: UUID

    @State private var draft: String = ""
    @State private var isEditing = false
    @State private var showShare = false
    @State private var exportedURL: URL?
    @State private var showRename = false
    @State private var renameText = ""

    private var file: GeneratedFile? {
        store.project(projectID)?.files.first(where: { $0.id == fileID })
    }

    var body: some View {
        ZStack {
            if let bg = settings.bgColor { bg.ignoresSafeArea() }
            Group {
                if isEditing {
                    TextEditor(text: $draft)
                        .font(.system(.footnote, design: .monospaced))
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(settings.cardColor ?? Color(.secondarySystemBackground))
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        Text(file?.content ?? "")
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
        }
        .navigationTitle(file?.name ?? "Файл")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showShare) { if let exportedURL { ShareSheet(items: [exportedURL]) } }
        .alert("Переименовать файл", isPresented: $showRename) {
            TextField("Имя файла", text: $renameText)
            Button("Сохранить") {
                if !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.renameFile(fileID, projectID: projectID, name: renameText)
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear { draft = file?.content ?? "" }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if isEditing {
                Button("Готово") {
                    store.updateFile(fileID, projectID: projectID, content: draft)
                    isEditing = false
                }.bold()
            } else {
                Menu {
                    Button { draft = file?.content ?? ""; isEditing = true } label: {
                        Label("Редактировать", systemImage: "pencil")
                    }
                    Button { renameText = file?.name ?? ""; showRename = true } label: {
                        Label("Переименовать", systemImage: "character.cursor.ibeam")
                    }
                    Button { export() } label: { Label("Поделиться", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button(role: .destructive) { store.deleteFile(fileID, projectID: projectID) } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func export() {
        guard let file else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
        do {
            try file.content.data(using: .utf8)?.write(to: url, options: .atomic)
            exportedURL = url; showShare = true
        } catch { print("Export failed: \(error)") }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
