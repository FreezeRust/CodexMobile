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
        case .openAI:    return ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "o3-mini"]
        case .anthropic: return ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest"]
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

// MARK: - AI Provider

struct AIProvider: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: ProviderKind
    var baseURL: String
    var models: [String]
    var apiKeyRef: String
    var isDefault: Bool = false
    var supportsImages: Bool = false        // can generate images
    var imageModel: String = ""             // e.g. "dall-e-3" / "gpt-image-1"

    var primaryModel: String { models.first ?? kind.defaultModel }

    static func makeOpenAI() -> AIProvider {
        AIProvider(name: "OpenAI", kind: .openAI, baseURL: ProviderKind.openAI.defaultBaseURL,
                   models: ["gpt-4o-mini", "gpt-4o"], apiKeyRef: UUID().uuidString,
                   isDefault: true, supportsImages: true, imageModel: "dall-e-3")
    }
}

// MARK: - Selectable model

struct ModelSelection: Codable, Hashable, Identifiable {
    var id: String { (providerID?.uuidString ?? "none") + "|" + model }
    var providerID: UUID?
    var model: String
    var displayName: String
}

// MARK: - Project / Chat / Message

struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var chats: [Chat] = []
    var files: [GeneratedFile] = []
}

struct Chat: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var selection: ModelSelection?
    var messages: [Message] = []
}

struct Message: Identifiable, Codable, Hashable {
    enum Role: String, Codable { case system, user, assistant }
    var id: UUID = UUID()
    var role: Role
    var content: String
    var attachments: [Attachment] = []
    var quoted: String? = nil           // quoted/cited text
    var isMarked: Bool = false          // highlighted (underline)
    var poll: Poll? = nil               // AI-generated poll
    var createdAt: Date = Date()
}

struct Attachment: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case image, file }
    var id: UUID = UUID()
    var kind: Kind
    var fileName: String
    var mimeType: String
    var base64: String
    var sizeKB: Int { (base64.count * 3 / 4) / 1024 }
}

struct GeneratedFile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var language: String
    var content: String
    var createdAt: Date = Date()
}

// MARK: - Poll (опрос от нейросети)

struct Poll: Codable, Hashable {
    var question: String
    var options: [String]
    var selected: String? = nil
}

// MARK: - Themes

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, dark, light, midnight, volt, mono, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system:   return "Системная"
        case .dark:     return "Тёмная"
        case .light:    return "Светлая"
        case .midnight: return "Midnight"
        case .volt:     return "Volt"
        case .mono:     return "Чёрно-белая"
        case .custom:   return "Своя тема"
        }
    }
}

enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case volt, cyan, magenta, green, orange, mono, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .volt:    return "Электро"
        case .cyan:    return "Циан"
        case .magenta: return "Маджента"
        case .green:   return "Зелёный"
        case .orange:  return "Оранжевый"
        case .mono:    return "Моно"
        case .custom:  return "Свой"
        }
    }
}
