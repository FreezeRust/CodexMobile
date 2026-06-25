import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var editing: AIProvider?
    @State private var newProvider: AIProvider?
    @State private var showSystemPrompt = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let bg = settings.theme.background { bg.ignoresSafeArea() }
                List {
                    appearanceSection
                    providersSection
                    behaviorSection
                    aboutSection
                }
                .scrollContentBackground(settings.theme.background == nil ? .visible : .hidden)
            }
            .navigationTitle("Настройки")
            .sheet(item: $newProvider) { p in ProviderEditor(provider: nil, prefill: p) }
            .sheet(item: $editing) { p in ProviderEditor(provider: p, prefill: nil) }
            .sheet(isPresented: $showSystemPrompt) { systemPromptEditor }
        }
    }

    // MARK: - Appearance (темы)

    private var appearanceSection: some View {
        Section("Оформление") {
            Picker("Тема", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Акцент").font(.subheadline)
                HStack(spacing: 14) {
                    ForEach(AccentTheme.allCases) { acc in
                        Button { settings.accent = acc } label: {
                            Circle()
                                .fill(acc.gradient)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.white, lineWidth: settings.accent == acc ? 3 : 0))
                                .shadow(color: acc.color.opacity(0.5), radius: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Providers (нейросети по API)

    private var providersSection: some View {
        Section {
            ForEach(settings.providers) { p in
                Button { editing = p } label: { providerRow(p) }
                    .swipeActions {
                        Button("По умолч.") { settings.setDefault(p) }.tint(settings.accent.color)
                        Button("Удалить", role: .destructive) { settings.delete(p) }
                    }
            }
            Menu {
                Button { newProvider = ProviderPreset.openAI.template } label: { Label("OpenAI", systemImage: "sparkles") }
                Button { newProvider = ProviderPreset.anthropic.template } label: { Label("Anthropic (Claude)", systemImage: "a.circle") }
                Button { newProvider = ProviderPreset.openRouter.template } label: { Label("OpenRouter (сотни моделей)", systemImage: "point.3.connected.trianglepath.dotted") }
                Button { newProvider = ProviderPreset.custom.template } label: { Label("Custom (свой endpoint)", systemImage: "slider.horizontal.3") }
            } label: {
                Label("Добавить нейросеть", systemImage: "plus")
            }
        } header: {
            Text("Нейросети по API")
        } footer: {
            Text("OpenAI, Anthropic, OpenRouter и любой OpenAI-совместимый endpoint (Custom). " +
                 "Совет: OpenRouter = один ключ на сотни моделей.")
        }
    }

    private func providerRow(_ p: AIProvider) -> some View {
        HStack(spacing: 12) {
            Image(systemName: p.kind.iconName)
                .foregroundStyle(settings.accent.gradient)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(p.name).font(.headline).foregroundStyle(.primary)
                    Text(p.kind.rawValue).font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(settings.accent.color.opacity(0.18), in: Capsule())
                }
                Text(p.models.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if p.isDefault { Image(systemName: "star.fill").foregroundStyle(settings.accent.color) }
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        Section("Поведение") {
            Button { showSystemPrompt = true } label: {
                HStack {
                    Label("Системный промпт", systemImage: "text.bubble")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var systemPromptEditor: some View {
        NavigationStack {
            Form {
                Section("Системный промпт") {
                    TextEditor(text: $settings.systemPrompt).frame(minHeight: 200)
                }
            }
            .navigationTitle("Системный промпт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showSystemPrompt = false }
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(settings.accent.gradient)
                VStack(alignment: .leading) {
                    Text("OpenVolt").font(.headline)
                    Text("v1.0 · ИИ-агрегатор на твоём iPhone").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Provider editor

enum ProviderPreset {
    case openAI, anthropic, openRouter, custom
    var template: AIProvider {
        switch self {
        case .openAI:
            return AIProvider(name: "OpenAI", kind: .openAI, baseURL: "https://api.openai.com/v1",
                              models: ["gpt-4o-mini", "gpt-4o"], apiKeyRef: UUID().uuidString)
        case .anthropic:
            return AIProvider(name: "Anthropic", kind: .anthropic, baseURL: "https://api.anthropic.com/v1",
                              models: ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest"], apiKeyRef: UUID().uuidString)
        case .openRouter:
            return AIProvider(name: "OpenRouter", kind: .custom, baseURL: "https://openrouter.ai/api/v1",
                              models: ["openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet", "google/gemini-flash-1.5"],
                              apiKeyRef: UUID().uuidString)
        case .custom:
            return AIProvider(name: "Custom", kind: .custom, baseURL: "https://",
                              models: ["model-name"], apiKeyRef: UUID().uuidString)
        }
    }
}

struct ProviderEditor: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) var dismiss
    let provider: AIProvider?
    let prefill: AIProvider?

    @State private var name = ""
    @State private var kind: ProviderKind = .openAI
    @State private var baseURL = ProviderKind.openAI.defaultBaseURL
    @State private var modelsText = ""
    @State private var apiKey = ""

    var isEdit: Bool { provider != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Тип API") {
                    Picker("Тип", selection: $kind) {
                        ForEach(ProviderKind.allCases) { k in
                            Label(k.rawValue, systemImage: k.iconName).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, k in
                        if !isEdit {
                            baseURL = k.defaultBaseURL
                            if modelsText.isEmpty { modelsText = k.defaultModel }
                        }
                    }
                }
                Section("Описание") {
                    TextField("Название", text: $name)
                }
                Section {
                    TextField("Base URL", text: $baseURL)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Модели через запятую", text: $modelsText, axis: .vertical)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField(isEdit ? "Новый API-ключ (опц.)" : "API-ключ", text: $apiKey)
                } header: {
                    Text("Подключение")
                } footer: {
                    if !kind.suggestedModels.isEmpty {
                        Text("Примеры: " + kind.suggestedModels.joined(separator: ", "))
                    }
                }
            }
            .navigationTitle(isEdit ? "Изменить" : "Новая нейросеть")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(name.isEmpty || baseURL.isEmpty || modelsText.isEmpty)
                }
            }
            .onAppear {
                if let p = provider { load(p) }
                else if let p = prefill { load(p) }
            }
        }
    }

    private func load(_ p: AIProvider) {
        name = p.name; kind = p.kind; baseURL = p.baseURL
        modelsText = p.models.joined(separator: ", ")
    }

    private func parsedModels() -> [String] {
        modelsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() {
        let models = parsedModels()
        if var p = provider {
            p.name = name; p.kind = kind; p.baseURL = baseURL; p.models = models
            settings.update(p, apiKey: apiKey.isEmpty ? nil : apiKey)
        } else {
            let p = AIProvider(name: name, kind: kind, baseURL: baseURL,
                               models: models, apiKeyRef: UUID().uuidString)
            settings.add(p, apiKey: apiKey)
        }
        dismiss()
    }
}
