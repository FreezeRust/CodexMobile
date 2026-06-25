import Foundation

/// Talks to OpenAI-compatible or Anthropic APIs with streaming.
struct AIClient {
    let provider: AIProvider
    let model: String

    enum AIError: LocalizedError {
        case missingKey, badURL
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .missingKey: return "Не задан API-ключ. Открой «Настройки → Нейросети» и впиши ключ."
            case .badURL:     return "Некорректный Base URL провайдера."
            case .http(let c, let b):
                let hint: String
                switch c {
                case 401: hint = "Неверный API-ключ (401). Проверь ключ и что он от нужного провайдера."
                case 403: hint = "Доступ запрещён (403). Ключ без прав или нет доступа к модели."
                case 404: hint = "Не найдено (404). Проверь Base URL и имя модели."
                case 429: hint = "Лимит/нет средств (429). Проверь биллинг провайдера."
                default:  hint = "Ошибка \(c)."
                }
                return b.isEmpty ? hint : "\(hint)\n\nОтвет сервера: \(b)"
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
                    guard let key = KeychainService.get(provider.apiKeyRef),
                          !key.trimmingCharacters(in: .whitespaces).isEmpty else { throw AIError.missingKey }
                    guard let url = URL(string: endpoint("/chat/completions")) else { throw AIError.badURL }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 120
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(key.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
                    // OpenRouter niceties (ignored by other providers)
                    req.setValue("https://openvolt.app", forHTTPHeaderField: "HTTP-Referer")
                    req.setValue("OpenVolt", forHTTPHeaderField: "X-Title")

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
                        let body = await collectBody(bytes)
                        throw AIError.http(h.statusCode, parseError(body))
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
                    guard let key = KeychainService.get(provider.apiKeyRef),
                          !key.trimmingCharacters(in: .whitespaces).isEmpty else { throw AIError.missingKey }
                    guard let url = URL(string: endpoint("/messages")) else { throw AIError.badURL }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 120
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue(key.trimmingCharacters(in: .whitespaces), forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    let system = messages.first(where: { $0.role == .system })?.content
                    let msgs: [[String: Any]] = messages.filter { $0.role != .system }.map { m in
                        var parts: [[String: Any]] = []
                        for a in m.attachments where a.kind == .image {
                            parts.append(["type": "image",
                                          "source": ["type": "base64", "media_type": a.mimeType, "data": a.base64]])
                        }
                        parts.append(["type": "text", "text": fullText(m)])
                        return ["role": m.role == .assistant ? "assistant" : "user", "content": parts]
                    }
                    var payload: [String: Any] = ["model": model, "max_tokens": 4096, "stream": true, "messages": msgs]
                    if let system, !system.isEmpty { payload["system"] = system }
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
                        let body = await collectBody(bytes)
                        throw AIError.http(h.statusCode, parseError(body))
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

    // MARK: - Helpers

    private func endpoint(_ path: String) -> String {
        var base = provider.baseURL.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix("/") { base.removeLast() }
        // If user already included the full endpoint, don't double it.
        if base.hasSuffix(path) { return base }
        return base + path
    }

    private func fullText(_ m: Message) -> String {
        var t = m.content
        for d in m.attachments where d.kind == .file {
            if let data = Data(base64Encoded: d.base64), let s = String(data: data, encoding: .utf8) {
                t += "\n\n--- Файл: \(d.fileName) ---\n\(s)"
            }
        }
        return t
    }

    private func collectBody(_ bytes: URLSession.AsyncBytes) async -> String {
        var data = Data()
        if let collected = try? await bytes.reduce(into: Data(), { $0.append($1) }) {
            data = collected
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Extract a human message from a JSON error body if possible.
    private func parseError(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(body.prefix(300))
        }
        if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
        if let msg = obj["error"] as? String { return msg }
        if let msg = obj["message"] as? String { return msg }
        return String(body.prefix(300))
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
