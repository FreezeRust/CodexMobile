import SwiftUI

struct TerminalView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    let projectID: UUID

    @State private var command = ""
    @FocusState private var focused: Bool

    private var history: [TerminalEntry] { store.project(projectID)?.terminalHistory ?? [] }
    private var promptName: String { store.project(projectID)?.name ?? "project" }

    var body: some View {
        ZStack {
            Color(hex: 0x0A0A0C).ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OpenVolt Terminal · виртуальная среда\nВведите 'help' для списка команд.")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.green.opacity(0.7))
                            ForEach(history) { entry in
                                entryView(entry)
                            }
                            Color.clear.frame(height: 1).id("END")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .onChange(of: history.count) { _, _ in
                        withAnimation { proxy.scrollTo("END", anchor: .bottom) }
                    }
                }
                inputBar
            }
        }
        .navigationTitle("Терминал")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { store.clearTerminal(projectID: projectID) } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    private func entryView(_ entry: TerminalEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.fromAI ? "🤖" : "➜").foregroundStyle(entry.fromAI ? .purple : .green)
                Text(command(entry)).foregroundStyle(.white)
            }
            if !entry.output.isEmpty {
                Text(entry.output)
                    .foregroundStyle(entry.isError ? .red : .white.opacity(0.85))
            }
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }

    private func command(_ e: TerminalEntry) -> String { "\(promptName) $ \(e.command)" }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text("➜").foregroundStyle(.green)
            TextField("команда…", text: $command)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(.white)
                .onSubmit(runCommand)
            Button(action: runCommand) {
                Image(systemName: "return").foregroundStyle(settings.accentColor)
            }
        }
        .font(.system(.callout, design: .monospaced))
        .padding(12)
        .background(Color(hex: 0x141418))
    }

    private func runCommand() {
        let c = command.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        store.runTerminal(c, projectID: projectID)
        command = ""
        focused = true
    }
}
