import SwiftUI

/// Manage AI providers ("добавлять по api нейросети").
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var editing: AIProvider?
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(settings.providers) { p in
                        Button {
                            editing = p
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.headline).foregroundStyle(.primary)
                                    Text(p.model).font(.caption).foregroundStyle(.secondary)
                                    Text(p.baseURL).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if p.isDefault {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .swipeActions {
                            Button("По умолч.") { settings.setDefault(p) }.tint(.green)
                            Button("Удалить", role: .destructive) { settings.delete(p) }
                        }
                    }
                } header: {
                    Text("Подключённые нейросети")
                } footer: {
                    Text("Поддерживается любой OpenAI-совместимый API: OpenAI, локальные модели, прокси и др.")
                }
            }
            .navigationTitle("Нейросети")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) {
                ProviderEditor(provider: nil)
            }
            .sheet(item: $editing) { p in
                ProviderEditor(provider: p)
            }
        }
    }
}

struct ProviderEditor: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) var dismiss

    let provider: AIProvider?

    @State private var name = ""
    @State private var baseURL = "https://api.openai.com/v1"
    @State private var model = "gpt-4o-mini"
    @State private var apiKey = ""

    var isEdit: Bool { provider != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Описание") {
                    TextField("Название (напр. OpenAI Codex)", text: $name)
                }
                Section("Подключение") {
                    TextField("Base URL", text: $baseURL)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Модель (напр. gpt-4o-mini)", text: $model)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField(isEdit ? "Новый API-ключ (опц.)" : "API-ключ", text: $apiKey)
                }
            }
            .navigationTitle(isEdit ? "Изменить" : "Новая нейросеть")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(name.isEmpty || baseURL.isEmpty || model.isEmpty)
                }
            }
            .onAppear {
                if let p = provider {
                    name = p.name; baseURL = p.baseURL; model = p.model
                }
            }
        }
    }

    private func save() {
        if var p = provider {
            p.name = name; p.baseURL = baseURL; p.model = model
            settings.update(p, apiKey: apiKey.isEmpty ? nil : apiKey)
        } else {
            let p = AIProvider(name: name, baseURL: baseURL, model: model,
                               apiKeyRef: UUID().uuidString)
            settings.add(p, apiKey: apiKey)
        }
        dismiss()
    }
}
