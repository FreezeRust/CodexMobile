import Foundation
import Combine
import SwiftUI

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

    /// Mutate a specific message in place.
    func updateMessage(_ id: UUID, projectID: UUID, chatID: UUID, _ change: (inout Message) -> Void) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let c = projects[p].chats.firstIndex(where: { $0.id == chatID }),
              let m = projects[p].chats[c].messages.firstIndex(where: { $0.id == id }) else { return }
        change(&projects[p].chats[c].messages[m])
        save()
    }

    func setPollAnswer(_ option: String, messageID: UUID, projectID: UUID, chatID: UUID) {
        updateMessage(messageID, projectID: projectID, chatID: chatID) { $0.poll?.selected = option }
    }

    // MARK: - File editing

    func updateFile(_ id: UUID, projectID: UUID, content: String) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let f = projects[p].files.firstIndex(where: { $0.id == id }) else { return }
        projects[p].files[f].content = content
        save()
    }
    func renameFile(_ id: UUID, projectID: UUID, name: String) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let f = projects[p].files.firstIndex(where: { $0.id == id }) else { return }
        projects[p].files[f].name = name
        save()
    }
    func deleteFile(_ id: UUID, projectID: UUID) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[p].files.removeAll { $0.id == id }
        save()
    }
    func addEmptyFile(projectID: UUID, name: String) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[p].files.insert(GeneratedFile(name: name, language: "text", content: ""), at: 0)
        save()
    }

    func attachFiles(_ files: [GeneratedFile], projectID: UUID) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[p].files.insert(contentsOf: files, at: 0)
        save()
    }

    func project(_ id: UUID) -> Project? { projects.first(where: { $0.id == id }) }
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
    @Published var typingAnimation: TypingAnimation {
        didSet { UserDefaults.standard.set(typingAnimation.rawValue, forKey: "typing_anim") }
    }
    // Custom theme colors (hex strings)
    @Published var customAccentHex: String {
        didSet { UserDefaults.standard.set(customAccentHex, forKey: "custom_accent") }
    }
    @Published var customBackgroundHex: String {
        didSet { UserDefaults.standard.set(customBackgroundHex, forKey: "custom_bg") }
    }
    @Published var customCardHex: String {
        didSet { UserDefaults.standard.set(customCardHex, forKey: "custom_card") }
    }
    @Published var customIsDark: Bool {
        didSet { UserDefaults.standard.set(customIsDark, forKey: "custom_dark") }
    }

    private let key = "ai_providers"

    init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .volt
        accent = AccentTheme(rawValue: UserDefaults.standard.string(forKey: "accent") ?? "") ?? .volt
        systemPrompt = UserDefaults.standard.string(forKey: "system_prompt")
            ?? "Ты — помощник-программист в приложении OpenVolt. Когда создаёшь файл, ВСЕГДА оборачивай его в блок ```язык и первой строкой ставь комментарий с именем файла, например // file: calculator.html — тогда пользователь увидит карточку «Создание calculator.html». Используй markdown: заголовки #, списки -, **жирный**. Если уместно задать вопрос с вариантами, выведи блок ```poll с JSON {\"question\":\"...\",\"options\":[\"A\",\"B\"]}."
        customAccentHex = UserDefaults.standard.string(forKey: "custom_accent") ?? "#6B55F4"
        customBackgroundHex = UserDefaults.standard.string(forKey: "custom_bg") ?? "#0D0A1F"
        customCardHex = UserDefaults.standard.string(forKey: "custom_card") ?? "#1A1430"
        customIsDark = UserDefaults.standard.object(forKey: "custom_dark") as? Bool ?? true
        typingAnimation = TypingAnimation(rawValue: UserDefaults.standard.string(forKey: "typing_anim") ?? "") ?? .character
        loadProviders()
    }

    // MARK: - Resolved theme accessors (used by views)

    var customAccentColor: Color { Color(hexString: customAccentHex) ?? Color(hex: 0x6B55F4) }
    var customBackgroundColor: Color { Color(hexString: customBackgroundHex) ?? Color(hex: 0x0D0A1F) }
    var customCardColor: Color { Color(hexString: customCardHex) ?? Color(hex: 0x1A1430) }

    var accentColor: Color { accent.color(custom: customAccentColor) }
    var accentGradient: LinearGradient { accent.gradient(custom: customAccentColor) }
    var resolvedScheme: ColorScheme? { theme.colorScheme(custom: customIsDark ? .dark : .light) }
    var bgColor: Color? { theme.background(custom: customBackgroundColor) }
    var cardColor: Color? { theme.card(custom: customCardColor) }

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
