import Foundation
import SwiftUI

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
    var isGift: Bool = false                // built-in free provider, locked
    var modelDisplayNames: [String: String] = [:]   // real model id -> shown name

    var primaryModel: String { models.first ?? kind.defaultModel }

    func displayName(for model: String) -> String {
        modelDisplayNames[model] ?? model
    }

    static func makeOpenAI() -> AIProvider {
        AIProvider(name: "OpenAI", kind: .openAI, baseURL: ProviderKind.openAI.defaultBaseURL,
                   models: ["gpt-4o-mini", "gpt-4o"], apiKeyRef: UUID().uuidString,
                   isDefault: true, supportsImages: true, imageModel: "dall-e-3")
    }

    /// Built-in free provider, gifted with the app. Locked from viewing/editing.
    static let giftKeyRef = "gift_zyloo_key"
    static let giftKeyValue = "sk-zy-53cdaa462e1fb1f3426ebb5d3a9e17ecfb0c5db39dd162af"
    static func makeGift() -> AIProvider {
        AIProvider(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "OpenVolt Free",
            kind: .custom,
            baseURL: "https://api.zyloo.io/v1",
            models: ["zyloo/claude-sonnet-4-6", "zyloo/gpt-5.4"],
            apiKeyRef: giftKeyRef,
            isDefault: true,
            isGift: true,
            modelDisplayNames: [
                "zyloo/claude-sonnet-4-6": "Claude Sonnet 4.6",
                "zyloo/gpt-5.4": "GPT 5.4"
            ]
        )
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
    var skills: [Skill] = []                 // reusable abilities/instructions for the AI
    var instructions: String = ""            // project-wide instructions
    var board: Board = Board.makeDefault()   // task board (как в Obsidian)
    var terminalHistory: [TerminalEntry] = []
}

// MARK: - Board (холст задач, как Obsidian Canvas)

struct Board: Codable, Hashable {
    var nodes: [BoardNode] = []
    var edges: [BoardEdge] = []
    static func makeDefault() -> Board { Board() }
}

struct BoardNode: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var detail: String = ""
    var done: Bool = false
    var x: Double = 0          // canvas position
    var y: Double = 0
    var createdAt: Date = Date()
}

struct BoardEdge: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var from: UUID
    var to: UUID
}

// MARK: - Terminal entry (виртуальный терминал)

struct TerminalEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var command: String
    var output: String
    var isError: Bool = false
    var fromAI: Bool = false
    var createdAt: Date = Date()
}

// MARK: - Skill (навык/инструкция, которыми ИИ может пользоваться)

struct Skill: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var detail: String                       // what the skill does / how to use it
    var enabled: Bool = true
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
    var tasks: [AgentTask] = []         // AI-planned to-do tasks
    var createdAt: Date = Date()
}

// MARK: - Agent task (задача, которую ИИ придумывает и выполняет по очереди)

struct AgentTask: Identifiable, Codable, Hashable {
    enum Status: String, Codable { case pending, running, done, failed }
    var id: UUID = UUID()
    var title: String
    var status: Status = .pending
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
    var history: [FileVersion] = []          // change history (newest first)
    var isDirectory: Bool = false            // true = folder node
}

// MARK: - File version (история изменений)

struct FileVersion: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var content: String
    var savedAt: Date = Date()
    var note: String = ""                    // e.g. "ручная правка" / "ИИ обновил"
}

// MARK: - Poll (опрос от нейросети)

struct Poll: Codable, Hashable {
    var question: String
    var options: [String]
    var selected: String? = nil
    var confirmed: Bool = false              // user must confirm the choice
}

// MARK: - Code font (как в популярных IDE)

enum CodeFont: String, Codable, CaseIterable, Identifiable {
    case system        // SF Mono (системный моноширинный)
    case menlo         // Menlo (Xcode classic)
    case courier       // Courier — ретро
    case rounded       // SF Rounded — мягкий
    case serif         // New York — с засечками
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:  return "SF Mono"
        case .menlo:   return "Menlo"
        case .courier: return "Courier"
        case .rounded: return "Rounded"
        case .serif:   return "Serif"
        }
    }
    var subtitle: String {
        switch self {
        case .system:  return "Чистый моноширинный, как в современных IDE"
        case .menlo:   return "Классика Xcode и терминала"
        case .courier: return "Ретро печатная машинка"
        case .rounded: return "Мягкий скруглённый"
        case .serif:   return "С засечками, книжный"
        }
    }
    /// Returns a Font for a given size.
    func font(size: CGFloat) -> Font {
        switch self {
        case .system:  return .system(size: size, design: .monospaced)
        case .menlo:   return .custom("Menlo", size: size)
        case .courier: return .custom("Courier", size: size)
        case .rounded: return .system(size: size, design: .rounded)
        case .serif:   return .system(size: size, design: .serif)
        }
    }
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

// MARK: - Typing animation

enum TypingSpeed: String, Codable, CaseIterable, Identifiable {
    case slow, normal, fast, instant
    var id: String { rawValue }
    var title: String {
        switch self {
        case .slow: return "Медленно"
        case .normal: return "Обычно"
        case .fast: return "Быстро"
        case .instant: return "Мгновенно"
        }
    }
    /// Nanoseconds per character step.
    var charDelay: UInt64 {
        switch self {
        case .slow: return 28_000_000
        case .normal: return 9_000_000
        case .fast: return 3_000_000
        case .instant: return 0
        }
    }
    /// Nanoseconds per word step.
    var wordDelay: UInt64 {
        switch self {
        case .slow: return 90_000_000
        case .normal: return 35_000_000
        case .fast: return 14_000_000
        case .instant: return 0
        }
    }
}

enum TypingAnimation: String, Codable, CaseIterable, Identifiable {
    case instant, character, word, fade, wave
    var id: String { rawValue }
    var title: String {
        switch self {
        case .instant:   return "Мгновенно"
        case .character: return "По буквам"
        case .word:      return "По словам"
        case .fade:      return "Плавное появление"
        case .wave:      return "Волна"
        }
    }
    var subtitle: String {
        switch self {
        case .instant:   return "Текст появляется сразу"
        case .character: return "Печатает символ за символом"
        case .word:      return "Слово за словом"
        case .fade:      return "Текст мягко проявляется"
        case .wave:      return "Волнообразное появление слов"
        }
    }
    var icon: String {
        switch self {
        case .instant:   return "bolt.fill"
        case .character: return "character.cursor.ibeam"
        case .word:      return "text.word.spacing"
        case .fade:      return "sparkles"
        case .wave:      return "waveform"
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
