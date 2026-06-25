import Foundation

/// Talks to OpenAI-compatible or Anthropic APIs with streaming.
struct AIClient {
    let provider: AIProvider
    let model: String

    enum AIError: LocalizedError {
        case missingKey, badURL, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .missingKey: return "Не задан API-ключ для провайдера."
            case .badURL:     return "Некорректный Base URL провайдера."
            case .http(let c, let b): return "Ошибка API (\(c)): \(b)"
            }
        }
    }

    func stream(messages: [Message]) -> AsyncThrowingStream<String, Error> {
        switch provider.kind {
        case .anthropic: return streamAnthropic(messages: messages)
        default:         return streamOpenAI(messages: messages)
        }
    }

    // MARK: - OpenAI-compatible (OpenAI / Custom)

    private func streamOpenAI(messages: [Message]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let key = KeychainService.get(provider.apiKeyRef), !key.isEmpty else { throw AIError.missingKey }
                    let base = provider.baseURL.hasSuffix("/") ? String(provider.baseURL.dropLast()) : provider.baseURL
                    guard let url = URL(string: base + "/chat/completions") else { throw AIError.badURL }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

                    let msgs: [[String: Any]] = messages.map { m in
                        if m.attachments.contains(where: { $0.kind == .image }) {
                            var parts: [[String: Any]] = [["type": "text", "text": m.content]]
                            for a in m.attachments where a.kind == .image {
                                parts.append(["type": "image_url",
                                              "image_url": ["url": "data:\(a.mimeType);base64,\(a.base64)"]])
                            }
                            return ["role": m.role.rawValue, "content": parts]
                        }
                        return ["role": m.role.rawValue, "content": fullText(m)]
                    }
                    let payload: [String: Any] = ["model": model, "stream": true, "messages": msgs]
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
                        throw AIError.http(h.statusCode, "запрос отклонён")
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
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    // MARK: - Anthropic

    private func streamAnthropic(messages: [Message]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let key = KeychainService.get(provider.apiKeyRef), !key.isEmpty else { throw AIError.missingKey }
                    let base = provider.baseURL.hasSuffix("/") ? String(provider.baseURL.dropLast()) : provider.baseURL
                    guard let url = URL(string: base + "/messages") else { throw AIError.badURL }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue(key, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    let msgs: [[String: Any]] = messages.filter { $0.role != .system }.map { m in
                        var parts: [[String: Any]] = []
                        for a in m.attachments where a.kind == .image {
                            parts.append(["type": "image",
                                          "source": ["type": "base64", "media_type": a.mimeType, "data": a.base64]])
                        }
                        parts.append(["type": "text", "text": fullText(m)])
                        return ["role": m.role == .assistant ? "assistant" : "user", "content": parts]
                    }
                    let payload: [String: Any] = ["model": model, "max_tokens": 4096, "stream": true, "messages": msgs]
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
                        throw AIError.http(h.statusCode, "запрос отклонён")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = json.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let delta = obj["delta"] as? [String: Any],
                              let token = delta["text"] as? String else { continue }
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    private func fullText(_ m: Message) -> String {
        var t = m.content
        let docs = m.attachments.filter { $0.kind == .file }
        for d in docs {
            if let data = Data(base64Encoded: d.base64), let s = String(data: data, encoding: .utf8) {
                t += "\n\n--- Файл: \(d.fileName) ---\n\(s)"
            }
        }
        return t
    }
}

/// Extracts ```lang\n...``` fenced blocks into GeneratedFile objects.
enum CodeExtractor {
    static func extract(from text: String) -> [GeneratedFile] {
        var files: [GeneratedFile] = []
        let pattern = "```([a-zA-Z0-9+#._-]*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var index = 1
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let lang = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2))
            let ext = fileExtension(for: lang)
            let firstLine = body.split(separator: "\n").first.map(String.init) ?? ""
            let name = detectName(in: firstLine) ?? "snippet_\(index).\(ext)"
            files.append(GeneratedFile(name: name, language: lang.isEmpty ? "text" : lang, content: body))
            index += 1
        }
        return files
    }

    private static func detectName(in line: String) -> String? {
        for marker in ["file:", "filename:", "File:", "FILE:"] where line.contains(marker) {
            if let r = line.range(of: marker) {
                let c = line[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " *#/-`"))
                if !c.isEmpty { return c }
            }
        }
        return nil
    }

    private static func fileExtension(for lang: String) -> String {
        switch lang.lowercased() {
        case "swift": return "swift"; case "python", "py": return "py"
        case "javascript", "js": return "js"; case "typescript", "ts": return "ts"
        case "json": return "json"; case "html": return "html"; case "css": return "css"
        case "bash", "sh", "shell": return "sh"; case "c": return "c"
        case "cpp", "c++": return "cpp"; case "java": return "java"
        case "kotlin", "kt": return "kt"; case "go": return "go"; case "rust", "rs": return "rs"
        case "ruby", "rb": return "rb"; case "yaml", "yml": return "yml"; case "markdown", "md": return "md"
        default: return "txt"
        }
    }
}
