import SwiftUI
import WebKit

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
    @State private var showHistory = false
    @State private var showPreview = false

    private var file: GeneratedFile? {
        store.project(projectID)?.files.first(where: { $0.id == fileID })
    }
    private var isHTML: Bool {
        let n = file?.name.lowercased() ?? ""
        return n.hasSuffix(".html") || n.hasSuffix(".htm") || (file?.language.lowercased() == "html")
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
                    CodeWithLineNumbers(content: file?.content ?? "")
                }
            }
        }
        .navigationTitle(file?.name ?? "Файл")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showShare) { if let exportedURL { ShareSheet(items: [exportedURL]) } }
        .sheet(isPresented: $showHistory) {
            if let file { FileHistoryView(projectID: projectID, fileID: fileID, file: file) }
        }
        .sheet(isPresented: $showPreview) {
            if let file { HTMLPreviewSheet(html: file.content, title: file.name) }
        }
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
                    if isHTML {
                        Button { showPreview = true } label: { Label("Предпросмотр HTML", systemImage: "safari") }
                    }
                    Button { showHistory = true } label: {
                        Label("История изменений (\(file?.history.count ?? 0))", systemImage: "clock.arrow.circlepath")
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

// MARK: - Code with line numbers

struct CodeWithLineNumbers: View {
    let content: String
    private var lines: [String] {
        content.isEmpty ? [""] : content.components(separatedBy: "\n")
    }
    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, _ in
                        Text("\(i + 1)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - HTML preview

struct HTMLPreviewSheet: View {
    @Environment(\.dismiss) var dismiss
    let html: String
    let title: String

    var body: some View {
        NavigationStack {
            HTMLWebView(html: html)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                }
        }
    }
}

struct HTMLWebView: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.isOpaque = false
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        web.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - File history

struct FileHistoryView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let projectID: UUID
    let fileID: UUID
    let file: GeneratedFile

    var body: some View {
        NavigationStack {
            ZStack {
                if let bg = settings.bgColor { bg.ignoresSafeArea() }
                if file.history.isEmpty {
                    ContentUnavailableView("Нет истории", systemImage: "clock",
                        description: Text("Версии появятся после правок файла."))
                } else {
                    List {
                        Section("Текущая версия") {
                            Text("\(file.content.components(separatedBy: "\n").count) строк")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Предыдущие версии") {
                            ForEach(file.history) { v in
                                NavigationLink {
                                    VersionDetail(projectID: projectID, fileID: fileID, version: v)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(v.note.isEmpty ? "Версия" : v.note).font(.subheadline)
                                        Text(v.savedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(settings.bgColor == nil ? .visible : .hidden)
                }
            }
            .navigationTitle("История")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

struct VersionDetail: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let projectID: UUID
    let fileID: UUID
    let version: FileVersion

    var body: some View {
        ZStack {
            if let bg = settings.bgColor { bg.ignoresSafeArea() }
            CodeWithLineNumbers(content: version.content)
        }
        .navigationTitle(version.savedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    store.restoreFileVersion(fileID, versionID: version.id, projectID: projectID)
                    dismiss()
                } label: { Label("Откатить", systemImage: "arrow.uturn.backward") }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
