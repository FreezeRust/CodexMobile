import SwiftUI

struct FileDetailView: View {
    @EnvironmentObject var settings: SettingsStore
    let file: GeneratedFile
    @State private var showShare = false
    @State private var exportedURL: URL?

    var body: some View {
        ZStack {
            if let bg = settings.theme.background { bg.ignoresSafeArea() }
            ScrollView([.vertical, .horizontal]) {
                Text(file.content)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showShare) {
            if let exportedURL { ShareSheet(items: [exportedURL]) }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { export() } label: { Image(systemName: "square.and.arrow.up") }
        }
    }

    private func export() {
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
