import SwiftUI

/// ChatGPT-style "creating image" animation: a shimmering placeholder that
/// cycles status phrases ("Полируем", "Наводим штрихи", "Почти готово"...).
struct ImageGeneratingView: View {
    let accent: LinearGradient
    @State private var phaseIndex = 0
    @State private var shimmer = false

    private let phrases = [
        "Задумываю композицию…",
        "Рисуем формы…",
        "Подбираем цвета…",
        "Наводим штрихи…",
        "Полируем детали…",
        "Почти готово…"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: 230, height: 230)
                // moving shimmer band
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(colors: [.clear, .white.opacity(0.25), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: 230, height: 230)
                    .mask(RoundedRectangle(cornerRadius: 14).frame(width: 230, height: 230))
                    .offset(x: shimmer ? 180 : -180)
                // pulsing icon
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(accent)
                    .scaleEffect(shimmer ? 1.12 : 0.9)
                    .opacity(0.9)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text(phrases[phaseIndex])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .id(phaseIndex)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) { shimmer = true }
            Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    phaseIndex = (phaseIndex + 1) % phrases.count
                }
            }
        }
    }
}

/// Full-screen image preview with save-to-photos and share.
struct ImagePreviewSheet: View {
    @Environment(\.dismiss) var dismiss
    let image: UIImage
    let fileName: String
    @State private var saved = false
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .padding()
            }
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            saved = true
                        } label: { Label(saved ? "Сохранено в Фото" : "Сохранить в Фото",
                                         systemImage: saved ? "checkmark" : "square.and.arrow.down") }
                        Button { showShare = true } label: { Label("Поделиться", systemImage: "square.and.arrow.up") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showShare) { ShareSheet(items: [image]) }
        }
    }
}
