import SwiftUI

/// A VS Code–style IDE interface adapted for iPhone (landscape-friendly).
struct VSCodeView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    let projectID: UUID
    var onExit: () -> Void

    enum SideTab { case explorer, search, terminal }
    @State private var sidebarOpen = true
    @State private var activeTab: SideTab = .explorer
    @State private var openFileID: UUID?
    @State private var openTabs: [UUID] = []
    @State private var draft: String = ""
    @State private var panelOpen = false
    @State private var termInput = ""
    @State private var searchText = ""

    // VS Code dark palette
    private let cActivity = Color(hex: 0x333333)
    private let cSidebar  = Color(hex: 0x252526)
    private let cEditor   = Color(hex: 0x1E1E1E)
    private let cPanel    = Color(hex: 0x1E1E1E)
    private let cTabBar   = Color(hex: 0x2D2D2D)
    private let cStatus   = Color(hex: 0x007ACC)
    private let cText     = Color(hex: 0xD4D4D4)
    private let cMuted    = Color(hex: 0x858585)

    private var project: Project? { store.project(projectID) }
    private var files: [GeneratedFile] { (project?.files ?? []).filter { !$0.isDirectory } }
    private var openFile: GeneratedFile? { files.first { $0.id == openFileID } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            cEditor.ignoresSafeArea()
            VStack(spacing: 0) {
                topTabBar
                HStack(spacing: 0) {
                    activityBar
                    if sidebarOpen {
                        sidebar
                            .frame(width: 230)
                            .transition(.move(edge: .leading))
                    }
                    Divider().overlay(Color.black)
                    editorArea
                }
                if panelOpen { bottomPanel.frame(height: 220).transition(.move(edge: .bottom)) }
                statusBar
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sidebarOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: panelOpen)
        .onAppear {
            if openFileID == nil, let first = files.first {
                openFileID = first.id; openTabs = [first.id]; draft = first.content
            }
        }
    }

    // MARK: - Top tab bar (open files)

    private var topTabBar: some View {
        HStack(spacing: 0) {
            Button { onExit() } label: {
                Image(systemName: "xmark")
                    .font(.caption).foregroundStyle(cText)
                    .frame(width: 38, height: 35)
                    .background(cActivity)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(openTabs, id: \.self) { id in
                        if let f = files.first(where: { $0.id == id }) { fileTab(f) }
                    }
                }
            }
            Spacer(minLength: 0)
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
        VStack(spacing: 22) {
            activityIcon("doc.on.doc", .explorer)
            activityIcon("magnifyingglass", .search)
            activityIcon("terminal", .terminal)
            Spacer()
            Image(systemName: "gearshape").foregroundStyle(cMuted).font(.title3)
        }
        .padding(.vertical, 14)
        .frame(width: 48)
        .frame(maxHeight: .infinity)
        .background(cActivity)
    }

    private func activityIcon(_ icon: String, _ tab: SideTab) -> some View {
        Button {
            if activeTab == tab && sidebarOpen { sidebarOpen = false }
            else { activeTab = tab; sidebarOpen = true; if tab == .terminal { panelOpen = true } }
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(activeTab == tab && sidebarOpen ? cText : cMuted)
                .overlay(alignment: .leading) {
                    if activeTab == tab && sidebarOpen {
                        Rectangle().fill(cText).frame(width: 2).offset(x: -14)
                    }
                }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch activeTab {
            case .explorer: explorerPanel
            case .search:   searchPanel
            case .terminal: explorerPanel
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(cSidebar)
    }

    private var explorerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ПРОВОДНИК").font(.system(size: 11, weight: .semibold)).foregroundStyle(cMuted)
                .padding(.horizontal, 12).padding(.vertical, 8)
            HStack {
                Text(project?.name.uppercased() ?? "ПРОЕКТ").font(.caption.bold()).foregroundStyle(cText)
                Spacer()
                Menu {
                    Button { newFile() } label: { Label("Новый файл", systemImage: "doc.badge.plus") }
                } label: { Image(systemName: "plus").font(.caption).foregroundStyle(cMuted) }
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(project?.files ?? []) { f in
                        explorerRow(f)
                    }
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
            if !f.isDirectory {
                Button(role: .destructive) { store.deleteFile(f.id, projectID: projectID) } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ПОИСК").font(.system(size: 11, weight: .semibold)).foregroundStyle(cMuted)
                .padding(.horizontal, 12).padding(.top, 8)
            TextField("Найти в файлах", text: $searchText)
                .textFieldStyle(.plain).font(.caption).foregroundStyle(cText)
                .padding(8).background(Color(hex: 0x3C3C3C)).cornerRadius(4)
                .padding(.horizontal, 10)
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

    // MARK: - Editor

    private var editorArea: some View {
        ZStack {
            cEditor
            if let f = openFile {
                HStack(alignment: .top, spacing: 0) {
                    // gutter line numbers
                    gutter(for: draft)
                    TextEditor(text: $draft)
                        .font(settings.codeFont.font(size: 13))
                        .foregroundStyle(cText)
                        .scrollContentBackground(.hidden)
                        .background(cEditor)
                        .onChange(of: draft) { _, newValue in
                            store.updateFile(f.id, projectID: projectID, content: newValue, note: "VS Code")
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
                    Text("\(n)").font(settings.codeFont.font(size: 12)).foregroundStyle(cMuted)
                        .frame(height: 17.5)
                }
            }
            .padding(.top, 8)
        }
        .frame(width: 38)
        .background(cEditor)
        .disabled(true)
    }

    // MARK: - Bottom panel (terminal)

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("ТЕРМИНАЛ").font(.system(size: 11, weight: .semibold)).foregroundStyle(cText)
                Text("ПРОБЛЕМЫ").font(.system(size: 11)).foregroundStyle(cMuted)
                Spacer()
                Button { store.clearTerminal(projectID: projectID) } label: {
                    Image(systemName: "trash").font(.caption2).foregroundStyle(cMuted)
                }
                Button { panelOpen = false } label: {
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(cMuted)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(cTabBar)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(project?.terminalHistory ?? []) { e in
                            Text("\(e.fromAI ? "🤖 " : "$ ")\(e.command)")
                                .foregroundStyle(Color(hex: 0x4EC9B0))
                            if !e.output.isEmpty {
                                Text(e.output).foregroundStyle(e.isError ? Color(hex: 0xF48771) : cText)
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .font(settings.codeFont.font(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
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
            .font(settings.codeFont.font(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(cPanel)
        }
        .background(cPanel)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 14) {
            Button { sidebarOpen.toggle() } label: {
                Image(systemName: "sidebar.left").font(.caption2)
            }
            Button { panelOpen.toggle() } label: {
                HStack(spacing: 3) { Image(systemName: "terminal"); Text("Терминал") }.font(.caption2)
            }
            Spacer()
            if let f = openFile {
                Text(langLabel(f.name)).font(.caption2)
                Text("\(draft.components(separatedBy: "\n").count) строк").font(.caption2)
            }
            Image(systemName: "bolt.fill").font(.caption2)
            Text("OpenVolt").font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(cStatus)
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
    private func newFile() {
        store.addEmptyFile(projectID: projectID, name: "new_\(Int(Date().timeIntervalSince1970)).txt")
    }
    private func runTerm() {
        let c = termInput.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        store.runTerminal(c, projectID: projectID)
        termInput = ""
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
        case "js","ts": return "curlybraces"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush"
        case "json": return "list.bullet.indent"
        case "md": return "doc.richtext"
        case "py","swift","java": return "curlybraces"
        default: return "doc"
        }
    }
    private func iconColor(_ name: String) -> Color {
        let e = (name as NSString).pathExtension.lowercased()
        switch e {
        case "js": return Color(hex: 0xE8D44D)
        case "ts": return Color(hex: 0x3178C6)
        case "html": return Color(hex: 0xE44D26)
        case "css": return Color(hex: 0x2965F1)
        case "json": return Color(hex: 0xCBCB41)
        case "py": return Color(hex: 0x3572A5)
        case "swift": return Color(hex: 0xF05138)
        default: return Color(hex: 0x9CDCFE)
        }
    }
}
