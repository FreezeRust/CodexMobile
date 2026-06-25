import Foundation

// MARK: - AI Provider (a "neural network" added by the user via API)

struct AIProvider: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String                 // e.g. "OpenAI Codex", "GPT-4o", "Local LLM"
    var baseURL: String              // e.g. "https://api.openai.com/v1"
    var model: String                // e.g. "gpt-4o-mini"
    var apiKeyRef: String            // key used to look up the secret in Keychain
    var isDefault: Bool = false

    static func makeOpenAI() -> AIProvider {
        AIProvider(name: "OpenAI",
                   baseURL: "https://api.openai.com/v1",
                   model: "gpt-4o-mini",
                   apiKeyRef: UUID().uuidString,
                   isDefault: true)
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
    var providerID: UUID?
    var messages: [Message] = []
}

// MARK: - Message

struct Message: Identifiable, Codable, Hashable {
    enum Role: String, Codable { case system, user, assistant }
    var id: UUID = UUID()
    var role: Role
    var content: String
    var createdAt: Date = Date()
}

// MARK: - Generated File (extracted from code blocks)

struct GeneratedFile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var language: String
    var content: String
    var createdAt: Date = Date()
}
