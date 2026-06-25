import Foundation

// MARK: - Provider kind (тип API)

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case custom = "Custom"
    var id: String { rawValue }

    var defaultBaseURL: String {
        switch self {
        case .openAI:    return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .custom:    return "https://"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:    return "gpt-4o-mini"
        case .anthropic: return "claude-3-5-sonnet-latest"
        case .custom:    return "model-name"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .openAI:    return ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "o3-mini", "o1"]
        case .anthropic: return ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest", "claude-3-opus-latest"]
        case .custom:    return []
        }
    }

    var iconName: String {
        switch self {
        case .openAI:    return "sparkles"
        case .anthropic: return "a.circle"
        case .custom:    return "slider.horizontal.3"
        }
    }
}

// MARK: - AI Provider (нейросеть, добавленная по API)

struct AIProvider: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: ProviderKind
    var baseURL: String
    var models: [String]            // список моделей этого провайдера
    var apiKeyRef: String           // ключ в Keychain
    var isDefault: Bool = false

    var primaryModel: String { models.first ?? kind.defaultModel }

    static func makeOpenAI() -> AIProvider {
        AIProvider(name: "OpenAI",
                   kind: .openAI,
                   baseURL: ProviderKind.openAI.defaultBaseURL,
                   models: ["gpt-4o-mini", "gpt-4o"],
                   apiKeyRef: UUID().uuidString,
                   isDefault: true)
    }
}

// MARK: - Selectable model in chat (API model или Codex model)

struct ModelSelection: Codable, Hashable, Identifiable {
    enum Source: String, Codable { case api, codex }
    var id: String { source.rawValue + "|" + (providerID?.uuidString ?? "codex") + "|" + model }
    var source: Source
    var providerID: UUID?           // nil для codex
    var model: String
    var displayName: String

    static func codex(_ model: String) -> ModelSelection {
        ModelSelection(source: .codex, providerID: nil, model: model, displayName: "Codex · \(model)")
    }
}

// MARK: - Project

struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var chats: [Chat] = []
    var files: [GeneratedFile] = []
}

// MARK: - Chat

struct Chat: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var selection: ModelSelection?
    var messages: [Message] = []
}

// MARK: - Message

struct Message: Identifiable, Codable, Hashable {
    enum Role: String, Codable { case system, user, assistant }
    var id: UUID = UUID()
    var role: Role
    var content: String
    var attachments: [Attachment] = []
    var createdAt: Date = Date()
}

// MARK: - Attachment (вложения)

struct Attachment: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case image, file }
    var id: UUID = UUID()
    var kind: Kind
    var fileName: String
    var mimeType: String
    var base64: String              // содержимое в base64

    var sizeKB: Int { (base64.count * 3 / 4) / 1024 }
}

// MARK: - Generated File

struct GeneratedFile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var language: String
    var content: String
    var createdAt: Date = Date()
}

// MARK: - Theme

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, dark, light, midnight, volt
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:   return "Системная"
        case .dark:     return "Тёмная"
        case .light:    return "Светлая"
        case .midnight: return "Midnight"
        case .volt:     return "Volt"
        }
    }
}

enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case volt, cyan, magenta, green, orange
    var id: String { rawValue }
    var title: String {
        switch self {
        case .volt:    return "Электро"
        case .cyan:    return "Циан"
        case .magenta: return "Маджента"
        case .green:   return "Зелёный"
        case .orange:  return "Оранжевый"
        }
    }
}
