import Foundation

/// Talks to OpenAI-compatible or Anthropic APIs with streaming,
/// automatic retries for transient errors (5xx/429) and a non-streaming fallback.
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
                case 500...599: hint = "Сервер провайдера временно недоступен (\(c)). Мы пробовали несколько раз — попробуй позже или другую модель."
                default:  hint = "Ошибка \(c)."
                }
                return b.isEmpty ? hint : "\(hint)\n\nОтвет сервера: \(b)"
            }
        }
    }

    private static func isTransient(_ code: Int) -> Bool {
        code == 429 || (500...599).contains(code)
    }

    func stream(messages: [Message]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await run(messages: messages) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Tries streaming with retries; if streaming keeps failing on transient
    /// errors, falls back to a single non-streaming request.
    private func run(messages: [Message], onToken: @escaping (String) -> Void) async throws {
        let maxAttempts = 3
        var lastError: Error?

        // 1) streaming attempts with exponential backoff on transient errors
        for attempt in 0..<maxAttempts {
            do {
                try await performStreaming(messages: messages, onToken: onToken)
                return
            } catch let AIError.http(code, body) where Self.isTransient(code) {
                lastError = AIError.http(code, body)
                let delay = UInt64(pow(2.0, Double(attempt))) * 700_000_000  // 0.7s, 1.4s, 2.8s
                try? await Task.sleep(nanoseconds: delay)
            } catch let urlError as URLError where urlError.code == .networkConnectionLost
                                                || urlError.code == .timedOut {
                lastError = urlError
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }

        // 2) non-streaming fallback (some endpoints/proxies 503 only on stream)
        do {
            let text = try await performNonStreaming(messages: messages)
            if !text.isEmpty { onToken(text) }
            return
        } catch {
            throw lastError ?? error
        }
    }

    // MARK: - Streaming request

    private func performStreaming(messages: [Message], onToken: @escaping (String) -> Void) async throws {
        let (req, isAnthropic) = try buildRequest(messages: messages, stream: true)
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
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if isAnthropic {
                if let delta = obj["delta"] as? [String: Any], let t = delta["text"] as? String { onToken(t) }
            } else {
                if let choices = obj["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let t = delta["content"] as? String { onToken(t) }
            }
        }
    }

    // MARK: - Non-streaming request (fallback)

    private func performNonStreaming(messages: [Message]) async throws -> String {
        let (req, isAnthropic) = try buildRequest(messages: messages, stream: false)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
            throw AIError.http(h.statusCode, parseError(String(data: data, encoding: .utf8) ?? ""))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if isAnthropic {
            if let content = obj["content"] as? [[String: Any]] {
                return content.compactMap { $0["text"] as? String }.joined()
            }
        } else {
            if let choices = obj["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String { return content }
        }
        return ""
    }

    // MARK: - Request building

    private func buildRequest(messages: [Message], stream: Bool) throws -> (URLRequest, Bool) {
        guard let key = KeychainService.get(provider.apiKeyRef),
              !key.trimmingCharacters(in: .whitespaces).isEmpty else { throw AIError.missingKey }
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        let isAnthropic = provider.kind == .anthropic

        let path = isAnthropic ? "/messages" : "/chat/completions"
        guard let url = URL(string: endpoint(path)) else { throw AIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if isAnthropic {
            req.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
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
            var payload: [String: Any] = ["model": model, "max_tokens": 4096, "stream": stream, "messages": msgs]
            if let system, !system.isEmpty { payload["system"] = system }
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } else {
            req.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
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
            let payload: [String: Any] = ["model": model, "stream": stream, "messages": msgs]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        return (req, isAnthropic)
    }

    // MARK: - Image generation (OpenAI images API)

    /// Generates an image and returns base64 PNG/JPEG data (OpenAI-compatible).
    func generateImage(prompt: String) async throws -> String {
        guard let key = KeychainService.get(provider.apiKeyRef),
              !key.trimmingCharacters(in: .whitespaces).isEmpty else { throw AIError.missingKey }
        guard let url = URL(string: endpoint("/images/generations")) else { throw AIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        let imgModel = provider.imageModel.isEmpty ? "dall-e-3" : provider.imageModel
        let payload: [String: Any] = ["model": imgModel, "prompt": prompt,
                                      "n": 1, "size": "1024x1024", "response_format": "b64_json"]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
            throw AIError.http(h.statusCode, parseError(String(data: data, encoding: .utf8) ?? ""))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["data"] as? [[String: Any]] else { return "" }
        if let b64 = arr.first?["b64_json"] as? String { return b64 }
        // Some endpoints return a URL instead
        if let urlStr = arr.first?["url"] as? String, let u = URL(string: urlStr),
           let imgData = try? Data(contentsOf: u) {
            return imgData.base64EncodedString()
        }
        return ""
    }

    /// Generates an image via the CHAT endpoint (model returns a markdown image link).
    /// Returns base64 of the downloaded image, or "" on failure.
    func generateImageViaChat(prompt: String) async throws -> String {
        let msg = Message(role: .user, content: "Сгенерируй изображение: \(prompt)")
        var full = ""
        for try await token in stream(messages: [msg]) { full += token }
        if let urlStr = ResponseParser.firstImageURL(in: full),
           let b64 = await Self.downloadBase64(urlStr) {
            return b64
        }
        return ""
    }

    /// Download a remote image and return base64.
    static func downloadBase64(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        if let (data, _) = try? await URLSession.shared.data(from: url), !data.isEmpty {
            return data.base64EncodedString()
        }
        return nil
    }

    // MARK: - Helpers

    private func endpoint(_ path: String) -> String {
        var base = provider.baseURL.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix("/") { base.removeLast() }
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
        if let collected = try? await bytes.reduce(into: Data(), { $0.append($1) }) {
            return String(data: collected, encoding: .utf8) ?? ""
        }
        return ""
    }

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

/// Parses special structured blocks from an assistant response.
enum ResponseParser {
    /// Extract a ```poll ...``` JSON block, if present.
    static func extractPoll(from text: String) -> Poll? {
        let pattern = "```poll\\s*\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let json = ns.substring(with: m.range(at: 1))
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let q = obj["question"] as? String,
              let opts = obj["options"] as? [String], !opts.isEmpty else { return nil }
        return Poll(question: q, options: opts)
    }

    /// Detect an explicit image-generation request like ```image\n<prompt>``` or [[image: prompt]].
    static func extractImagePrompt(from text: String) -> String? {
        let fence = "```image\\s*\\n([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: fence, options: .caseInsensitive) {
            let ns = text as NSString
            if let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// Extract a ```tasks ...``` JSON array block (AI-planned tasks).
    static func extractTasks(from text: String) -> [AgentTask]? {
        let pattern = "```tasks\\s*\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let json = ns.substring(with: m.range(at: 1))
        guard let data = json.data(using: .utf8) else { return nil }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return arr.map { AgentTask(title: $0) }
        }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr.compactMap { ($0["title"] as? String).map { AgentTask(title: $0) } }
        }
        return nil
    }

    /// Extract folder-creation paths from ```mkdir blocks.
    static func extractFolders(from text: String) -> [String] {
        extractLines(from: text, fence: "mkdir")
    }
    /// Extract deletion paths from ```rm blocks.
    static func extractDeletions(from text: String) -> [String] {
        extractLines(from: text, fence: "rm")
    }
    /// Extract terminal commands from ```run blocks (one per line).
    static func extractTerminalCommands(from text: String) -> [String] {
        extractLines(from: text, fence: "run")
    }
    /// Extract board operations from ```board blocks (one op per line).
    static func extractBoardOps(from text: String) -> [String] {
        extractLines(from: text, fence: "board")
    }

    private static func extractLines(from text: String, fence: String) -> [String] {
        let pattern = "```\(fence)\\s*\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let ns = text as NSString
        var out: [String] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let body = ns.substring(with: m.range(at: 1))
            for line in body.components(separatedBy: "\n") {
                let p = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t-•\"'`"))
                if !p.isEmpty { out.append(p) }
            }
        }
        return out
    }

    /// Remove our special control blocks from displayed text.
    static func stripControlBlocks(_ text: String) -> String {
        var t = text
        for fence in ["poll", "image", "tasks", "mkdir", "rm", "run", "board"] {
            let pat = "```\(fence)\\s*\\n[\\s\\S]*?```"
            if let r = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let ns = t as NSString
                t = r.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: ns.length), withTemplate: "")
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First image URL from markdown ![alt](url) or a bare image URL.
    static func firstImageURL(in text: String) -> String? {
        // markdown image
        if let r = try? NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\((https?://[^)\\s]+)\\)") {
            let ns = text as NSString
            if let m = r.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: m.range(at: 1))
            }
        }
        // bare image url
        if let r = try? NSRegularExpression(pattern: "(https?://[^\\s)]+\\.(?:png|jpg|jpeg|webp|gif))",
                                            options: .caseInsensitive) {
            let ns = text as NSString
            if let m = r.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }

    /// True if the response looks like an in-progress / generated image answer.
    static func looksLikeImageAnswer(_ text: String) -> Bool {
        firstImageURL(in: text) != nil
            || text.contains("Processing image")
            || text.contains("生成中")
            || text.contains("🎨")
    }

    /// Removes image-generation noise + the markdown image, leaving clean text.
    static func stripImageNoise(_ text: String) -> String {
        var t = text
        for pat in ["!\\[[^\\]]*\\]\\([^)]*\\)",           // markdown image
                    "\\[[^\\]]*\\]\\(https?://[^)]*\\)",   // markdown link (download)
                    ">.*Processing image.*",
                    ">.*生成中.*",
                    ">.*notify you when your image.*"] {
            if let r = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                let ns = t as NSString
                t = r.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: ns.length), withTemplate: "")
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
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
            // Skip our control blocks — they must NOT become files.
            if ["poll", "image", "tasks", "mkdir", "rm", "run", "board"].contains(lang.lowercased()) { continue }
            var body = ns.substring(with: m.range(at: 2))
            var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let firstLine = lines.first ?? ""
            let name = detectName(in: firstLine)
            // Only treat a fenced block as a saved FILE if it has an explicit filename.
            // Plain code snippets (no // file:) stay inline and don't spam project files.
            guard let fileName = name else { continue }
            // drop the marker line from saved content
            if ["file:", "filename:", "File:", "FILE:"].contains(where: { firstLine.contains($0) }) {
                lines.removeFirst()
                body = lines.joined(separator: "\n")
            }
            files.append(GeneratedFile(name: fileName, language: lang.isEmpty ? "text" : lang, content: body))
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
