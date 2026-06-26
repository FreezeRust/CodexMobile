import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var step = 0
    var onFinish: () -> Void

    var body: some View {
        ZStack {
            // Themed animated background
            (settings.bgColor ?? Color(hex: 0x0D0A1F)).ignoresSafeArea()
            settings.accentGradient.opacity(0.12).ignoresSafeArea()

            Group {
                switch step {
                case 0: WelcomeStep { advance() }
                case 1: FontStep { advance() }
                case 2: ThemeStep { advance() }
                default: ModelsStep(onFinish: { finish() })
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .overlay(alignment: .top) { progressDots.padding(.top, 12) }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: step)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i == step ? AnyShapeStyle(settings.accentGradient) : AnyShapeStyle(Color.gray.opacity(0.4)))
                    .frame(width: i == step ? 22 : 8, height: 8)
            }
        }
    }

    private func advance() { withAnimation { step += 1 } }
    private func finish() {
        settings.hasOnboarded = true
        onFinish()
    }
}

// MARK: - Step 0: Welcome

private struct WelcomeStep: View {
    @EnvironmentObject var settings: SettingsStore
    var onNext: () -> Void
    @State private var appear = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(settings.accentGradient.opacity(0.25)).frame(width: 130, height: 130)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(settings.accentGradient)
                    .scaleEffect(appear ? 1 : 0.6)
            }
            VStack(spacing: 10) {
                Text("Добро пожаловать в OpenVolt")
                    .font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("Твой ИИ-агрегатор для кода: проекты, файлы, генерация и многое другое — прямо на iPhone.")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Spacer()
            PrimaryButton(title: "Начать", gradient: settings.accentGradient, action: onNext)
                .padding(.horizontal, 30).padding(.bottom, 30)
        }
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true } }
    }
}

// MARK: - Step 1: Font

private struct FontStep: View {
    @EnvironmentObject var settings: SettingsStore
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(icon: "textformat", title: "Выбери шрифт кода",
                       subtitle: "Как в любимой IDE")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(CodeFont.allCases) { f in
                        Button { withAnimation { settings.codeFont = f } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(f.title).font(.headline)
                                    Spacer()
                                    if settings.codeFont == f {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(settings.accentColor)
                                    }
                                }
                                Text("func openVolt() { print(\"Hello, \\(f.title)\") }")
                                    .font(f.font(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Text(f.subtitle).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(settings.cardColor ?? Color(.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(settings.codeFont == f ? settings.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            PrimaryButton(title: "Далее", gradient: settings.accentGradient, action: onNext)
                .padding(.horizontal, 30).padding(.bottom, 20)
        }
        .padding(.top, 50)
    }
}

// MARK: - Step 2: Theme

private struct ThemeStep: View {
    @EnvironmentObject var settings: SettingsStore
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(icon: "paintpalette.fill", title: "Выбери тему",
                       subtitle: "Оформление можно сменить позже в настройках")
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Тема", selection: $settings.theme) {
                        ForEach(AppTheme.allCases.filter { $0 != .custom }) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    Text("Акцент").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                    HStack(spacing: 14) {
                        ForEach(AccentTheme.allCases.filter { $0 != .custom }) { acc in
                            Button { withAnimation { settings.accent = acc } } label: {
                                Circle().fill(acc.gradient(custom: settings.customAccentColor))
                                    .frame(width: 38, height: 38)
                                    .overlay(Circle().stroke(.white, lineWidth: settings.accent == acc ? 3 : 0))
                            }.buttonStyle(.plain)
                        }
                    }

                    // live preview
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Spacer()
                            Text("Привет! Чем помочь?").padding(10)
                                .background(settings.accentGradient).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Text("Конечно! Вот пример кода 👇").padding(10)
                            .background(settings.cardColor ?? Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        Text("print(\"OpenVolt\")")
                            .font(settings.codeFont.font(size: 12))
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(16)
                    .background(settings.bgColor ?? Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 20)
                }
            }
            PrimaryButton(title: "Далее", gradient: settings.accentGradient, action: onNext)
                .padding(.horizontal, 30).padding(.bottom, 20)
        }
        .padding(.top, 50)
    }
}

// MARK: - Step 3: Models

private struct ModelsStep: View {
    @EnvironmentObject var settings: SettingsStore
    var onFinish: () -> Void
    @State private var showEditor = false
    @State private var preset: AIProvider?

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(icon: "brain.head.profile", title: "Добавь нейросеть",
                       subtitle: "Можно сейчас или позже в настройках")
            ScrollView {
                VStack(spacing: 12) {
                    if !settings.providers.isEmpty {
                        ForEach(settings.providers) { p in
                            HStack {
                                Image(systemName: p.kind.iconName).foregroundStyle(settings.accentGradient)
                                VStack(alignment: .leading) {
                                    Text(p.name).font(.headline)
                                    Text(p.models.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            .padding(14)
                            .background(settings.cardColor ?? Color(.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    presetButton("OpenAI", .openAI)
                    presetButton("Anthropic (Claude)", .anthropic)
                    presetButton("OpenRouter (сотни моделей)", .openRouter)
                    presetButton("Custom (свой endpoint)", .custom)
                }
                .padding(.horizontal, 20)
            }
            VStack(spacing: 10) {
                PrimaryButton(title: settings.providers.isEmpty ? "Пропустить" : "Готово",
                              gradient: settings.accentGradient, action: onFinish)
                if settings.providers.isEmpty {
                    Text("Без нейросети чат работать не будет — но добавить можно в любой момент.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 30).padding(.bottom, 20)
        }
        .padding(.top, 50)
        .sheet(item: $preset) { p in ProviderEditor(provider: nil, prefill: p) }
    }

    private func presetButton(_ title: String, _ kind: ProviderPreset) -> some View {
        Button { preset = kind.template } label: {
            HStack {
                Image(systemName: "plus.circle.fill").foregroundStyle(settings.accentColor)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(settings.cardColor ?? Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared bits

private struct StepHeader: View {
    @EnvironmentObject var settings: SettingsStore
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34))
                .foregroundStyle(settings.accentGradient)
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }
}

struct PrimaryButton: View {
    let title: String
    let gradient: LinearGradient
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(gradient, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
