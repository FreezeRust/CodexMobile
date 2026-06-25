import Foundation
import Combine

/// Persists projects/chats to disk as JSON in the app's Documents directory.
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

    // Projects
    func addProject(name: String) {
        projects.insert(Project(name: name), at: 0)
        save()
    }
    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    // Chats
    func addChat(to projectID: UUID, title: String, providerID: UUID?) -> Chat? {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let chat = Chat(title: title, providerID: providerID)
        projects[i].chats.insert(chat, at: 0)
        save()
        return chat
    }

    func appendMessage(_ message: Message, projectID: UUID, chatID: UUID) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let c = projects[p].chats.firstIndex(where: { $0.id == chatID }) else { return }
        projects[p].chats[c].messages.append(message)
        save()
    }

    func updateLastAssistantMessage(_ text: String, projectID: UUID, chatID: UUID) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let c = projects[p].chats.firstIndex(where: { $0.id == chatID }),
              let m = projects[p].chats[c].messages.lastIndex(where: { $0.role == .assistant })
        else { return }
        projects[p].chats[c].messages[m].content = text
    }

    func attachFiles(_ files: [GeneratedFile], projectID: UUID) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[p].files.insert(contentsOf: files, at: 0)
        save()
    }
}

/// Stores AI providers and which one is the default.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var providers: [AIProvider] = []

    private let key = "ai_providers"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AIProvider].self, from: data),
              !decoded.isEmpty else {
            providers = [AIProvider.makeOpenAI()]
            save()
            return
        }
        providers = decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(_ provider: AIProvider, apiKey: String) {
        var p = provider
        if providers.isEmpty { p.isDefault = true }
        KeychainService.set(apiKey, for: p.apiKeyRef)
        providers.append(p)
        save()
    }

    func update(_ provider: AIProvider, apiKey: String?) {
        guard let i = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[i] = provider
        if let apiKey { KeychainService.set(apiKey, for: provider.apiKeyRef) }
        save()
    }

    func delete(_ provider: AIProvider) {
        KeychainService.delete(provider.apiKeyRef)
        providers.removeAll { $0.id == provider.id }
        if !providers.contains(where: { $0.isDefault }), let first = providers.first {
            setDefault(first)
        }
        save()
    }

    func setDefault(_ provider: AIProvider) {
        for i in providers.indices { providers[i].isDefault = (providers[i].id == provider.id) }
        save()
    }

    var defaultProvider: AIProvider? {
        providers.first(where: { $0.isDefault }) ?? providers.first
    }
}

/// Tracks Codex web login state.
@MainActor
final class SessionStore: ObservableObject {
    @Published var isCodexLoggedIn: Bool {
        didSet { UserDefaults.standard.set(isCodexLoggedIn, forKey: "codex_logged_in") }
    }
    init() {
        isCodexLoggedIn = UserDefaults.standard.bool(forKey: "codex_logged_in")
    }
}
