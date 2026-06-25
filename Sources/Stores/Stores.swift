import Foundation
import Combine

/// Persists projects/chats to disk as JSON.
@MainActor
final class AppStore: ObservableObject {
    @Published var projects: [Project] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("projects.json")
    }()

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Project].self, from: data) else { return }
        projects = decoded
    }
    func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func addProject(name: String) { projects.insert(Project(name: name), at: 0); save() }
    func deleteProject(_ p: Project) { projects.removeAll { $0.id == p.id }; save() }

    func addChat(to projectID: UUID, title: String, selection: ModelSelection?) -> Chat? {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let chat = Chat(title: title, selection: selection)
        projects[i].chats.insert(chat, at: 0)
        save()
        return chat
    }

    func setSelection(_ sel: ModelSelection, projectID: UUID, chatID: UUID) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let c = projects[p].chats.firstIndex(where: { $0.id == chatID }) else { return }
        projects[p].chats[c].selection = sel
        save()
    }

    func appendMessage(_ m: Message, projectID: UUID, chatID: UUID) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let c = projects[p].chats.firstIndex(where: { $0.id == chatID }) else { return }
        projects[p].chats[c].messages.append(m)
        save()
    }

    func updateLastAssistantMessage(_ text: String, projectID: UUID, chatID: UUID) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let c = projects[p].chats.firstIndex(where: { $0.id == chatID }),
              let m = projects[p].chats[c].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        projects[p].chats[c].messages[m].content = text
    }

    func attachFiles(_ files: [GeneratedFile], projectID: UUID) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[p].files.insert(contentsOf: files, at: 0)
        save()
    }
}

/// Stores AI providers, theme, and app settings.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var providers: [AIProvider] = []
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    @Published var accent: AccentTheme {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") }
    }
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "system_prompt") }
    }

    private let key = "ai_providers"

    init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .volt
        accent = AccentTheme(rawValue: UserDefaults.standard.string(forKey: "accent") ?? "") ?? .volt
        systemPrompt = UserDefaults.standard.string(forKey: "system_prompt")
            ?? "Ты — помощник-программист в приложении OpenVolt. Когда создаёшь файлы, оборачивай их в блоки ```язык и указывай имя файла комментарием // file: имя в первой строке."
        loadProviders()
    }

    func loadProviders() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AIProvider].self, from: data),
              !decoded.isEmpty else {
            providers = []
            return
        }
        providers = decoded
    }
    func save() {
        if let data = try? JSONEncoder().encode(providers) { UserDefaults.standard.set(data, forKey: key) }
    }

    func add(_ p: AIProvider, apiKey: String) {
        var p = p
        if providers.isEmpty { p.isDefault = true }
        KeychainService.set(apiKey, for: p.apiKeyRef)
        providers.append(p); save()
    }
    func update(_ p: AIProvider, apiKey: String?) {
        guard let i = providers.firstIndex(where: { $0.id == p.id }) else { return }
        providers[i] = p
        if let apiKey, !apiKey.isEmpty { KeychainService.set(apiKey, for: p.apiKeyRef) }
        save()
    }
    func delete(_ p: AIProvider) {
        KeychainService.delete(p.apiKeyRef)
        providers.removeAll { $0.id == p.id }
        if !providers.contains(where: { $0.isDefault }), let f = providers.first { setDefault(f) }
        save()
    }
    func setDefault(_ p: AIProvider) {
        for i in providers.indices { providers[i].isDefault = (providers[i].id == p.id) }
        save()
    }
    var defaultProvider: AIProvider? { providers.first(where: { $0.isDefault }) ?? providers.first }

    /// All selectable models for the chat picker.
    func availableSelections() -> [ModelSelection] {
        var out: [ModelSelection] = []
        for p in providers {
            for m in p.models {
                out.append(ModelSelection(providerID: p.id, model: m, displayName: "\(p.name) · \(m)"))
            }
        }
        return out
    }

    func provider(for id: UUID?) -> AIProvider? {
        providers.first(where: { $0.id == id })
    }
}
