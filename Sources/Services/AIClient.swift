import Foundation

/// Talks to any OpenAI-compatible /chat/completions endpoint with SSE streaming.
struct AIClient {
    let provider: AIProvider

    enum AIError: LocalizedError {
        case missingKey
        case badURL
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .missingKey: return "Не задан API-ключ для провайдера."
            case .badURL: return "Некорректный Base URL провайдера."
            case .http(let code, let body): return "Ошибка API (\(code)): \(body)"
            }
        }
    }

    /// Streams assistant text token-by-token via an AsyncThrowingStream.
    func stream(messages: [Message]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let key = KeychainService.get(provider.apiKeyRef), !key.isEmpty else {
                        throw AIError.missingKey
                    }
                    let base = provider.baseURL.hasSuffix("/")
                        ? String(provider.baseURL.dropLast()) : provider.baseURL
                    guard let url = URL(string: base + "/chat/completions") else {
                        throw AIError.badURL
                    }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

                    let payload: [String: Any] = [
                        "model": provider.model,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw AIError.http(http.statusCode, "запрос отклонён")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if json == "[DONE]" { break }
                        guard let data = json.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let token = delta["content"] as? String else { continue }
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Extracts ```lang\n...code...``` fenced blocks into GeneratedFile objects.
enum CodeExtractor {
    static func extract(from text: String) -> [GeneratedFile] {
        var files: [GeneratedFile] = []
        let pattern = "```([a-zA-Z0-9+#._-]*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var index = 1
        for m in matches {
            let lang = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2))
            let ext = fileExtension(for: lang)
            // Try to detect a filename hint like "// file: app.swift" on the first line
            let firstLine = body.split(separator: "\n").first.map(String.init) ?? ""
            let name = detectName(in: firstLine) ?? "snippet_\(index).\(ext)"
            files.append(GeneratedFile(name: name,
                                       language: lang.isEmpty ? "text" : lang,
                                       content: body))
            index += 1
        }
        return files
    }

    private static func detectName(in line: String) -> String? {
        let markers = ["file:", "filename:", "File:", "FILE:"]
        for marker in markers where line.contains(marker) {
            if let range = line.range(of: marker) {
                let candidate = line[range.upperBound...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " *#/-`"))
                if !candidate.isEmpty { return candidate }
            }
        }
        return nil
    }

    private static func fileExtension(for lang: String) -> String {
        switch lang.lowercased() {
        case "swift": return "swift"
        case "python", "py": return "py"
        case "javascript", "js": return "js"
        case "typescript", "ts": return "ts"
        case "json": return "json"
        case "html": return "html"
        case "css": return "css"
        case "bash", "sh", "shell": return "sh"
        case "c": return "c"
        case "cpp", "c++": return "cpp"
        case "java": return "java"
        case "kotlin", "kt": return "kt"
        case "go": return "go"
        case "rust", "rs": return "rs"
        case "ruby", "rb": return "rb"
        case "yaml", "yml": return "yml"
        case "markdown", "md": return "md"
        default: return "txt"
        }
    }
}
