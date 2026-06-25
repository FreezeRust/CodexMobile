import SwiftUI
import UniformTypeIdentifiers

/// Shows a generated file and lets the user export / "отдать" it via the share sheet.
struct FileDetailView: View {
    let file: GeneratedFile
    @State private var showShare = false
    @State private var exportedURL: URL?

    var body: some View {
        ScrollView {
            Text(file.content)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    export()
                } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .sheet(isPresented: $showShare) {
            if let exportedURL {
                ShareSheet(items: [exportedURL])
            }
        }
    }

    private func export() {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(file.name)
        do {
            try file.content.data(using: .utf8)?.write(to: url, options: .atomic)
            exportedURL = url
            showShare = true
        } catch {
            print("Export failed: \(error)")
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
