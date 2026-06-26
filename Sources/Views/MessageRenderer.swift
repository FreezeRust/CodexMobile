import SwiftUI

// MARK: - Parsed blocks

enum MessageBlock: Identifiable {
    case paragraph(String)
    case heading(String, Int)
    case bullet([String])
    case quote(String)
    case code(language: String, content: String, fileName: String?)

    var id: String {
        switch self {
        case .paragraph(let t): return "p" + t.prefix(24)
        case .heading(let t, let l): return "h\(l)" + t.prefix(24)
        case .bullet(let items): return "b" + (items.first?.prefix(24) ?? "")
        case .quote(let t): return "q" + t.prefix(24)
        case .code(_, let c, let f): return "c" + (f ?? "") + c.prefix(16)
        }
    }
}

enum MessageParser {
    static func parse(_ text: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []
        var bullets: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { blocks.append(.paragraph(joined)) }
                paragraph = []
            }
        }
        func flushBullets() {
            if !bullets.isEmpty { blocks.append(.bullet(bullets)); bullets = [] }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code fence
            if trimmed.hasPrefix("```") {
                flushParagraph(); flushBullets()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                let body = code.joined(separator: "\n")
                // Skip our control blocks (poll/image) entirely
                if lang.lowercased() == "poll" || lang.lowercased() == "image" {
                    i += 1; continue
                }
                let fileName = detectFileName(language: lang, firstLine: code.first ?? "")
                // Drop the "// file: name" marker line from the shown code.
                var shown = code
                if fileName != nil, let first = shown.first,
                   ["file:", "filename:", "File:", "FILE:"].contains(where: { first.contains($0) }) {
                    shown.removeFirst()
                }
                let cleaned = shown.joined(separator: "\n")
                blocks.append(.code(language: lang.isEmpty ? "text" : lang,
                                    content: cleaned.isEmpty ? body : cleaned, fileName: fileName))
                i += 1
                continue
            }
            // Heading
            if trimmed.hasPrefix("#") {
                flushParagraph(); flushBullets()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let t = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(t, min(level, 3)))
                i += 1; continue
            }
            // Quote
            if trimmed.hasPrefix(">") {
                flushParagraph(); flushBullets()
                var quote: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(lines[i].trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }
            // Bullet
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                flushParagraph()
                let item = trimmed
                    .replacingOccurrences(of: #"^[-*]\s"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                bullets.append(item)
                i += 1; continue
            }
            // Blank line
            if trimmed.isEmpty {
                flushParagraph(); flushBullets()
                i += 1; continue
            }
            // Normal text
            flushBullets()
            paragraph.append(line)
            i += 1
        }
        flushParagraph(); flushBullets()
        return blocks
    }

    private static func detectFileName(language: String, firstLine: String) -> String? {
        for marker in ["file:", "filename:", "File:", "FILE:"] where firstLine.contains(marker) {
            if let r = firstLine.range(of: marker) {
                let c = firstLine[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " *#/-`"))
                if !c.isEmpty { return c }
            }
        }
        return nil
    }
}

// MARK: - Inline markdown helper

func inlineMarkdown(_ s: String) -> AttributedString {
    if let attr = try? AttributedString(markdown: s,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
        return attr
    }
    return AttributedString(s)
}

// MARK: - Rendered message body

struct RenderedMessage: View {
    let text: String
    let isUser: Bool
    let onOpenCode: (_ name: String, _ language: String, _ content: String) -> Void

    var blocks: [MessageBlock] { MessageParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder private func blockView(_ block: MessageBlock) -> some View {
        switch block {
        case .paragraph(let t):
            Text(inlineMarkdown(t))
                .foregroundStyle(isUser ? .white : .primary)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let t, let level):
            Text(t)
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .foregroundStyle(isUser ? .white : .primary)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().frame(width: 5, height: 5)
                            .padding(.top, 7)
                            .foregroundStyle(isUser ? .white.opacity(0.8) : .secondary)
                        Text(inlineMarkdown(item))
                            .foregroundStyle(isUser ? .white : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .quote(let t):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).frame(width: 3)
                    .foregroundStyle(.secondary.opacity(0.6))
                Text(inlineMarkdown(t))
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .code(let language, let content, let fileName):
            if let fileName {
                FileCreationCard(fileName: fileName, language: language, lineCount: content.split(separator: "\n").count) {
                    onOpenCode(fileName, language, content)
                }
            } else {
                CodeCard(language: language, content: content) {
                    onOpenCode(language.isEmpty ? "snippet.txt" : "snippet.\(language)", language, content)
                }
            }
        }
    }
}

// MARK: - File creation card («Создание calculator.html»)

struct FileCreationCard: View {
    @EnvironmentObject var settings: SettingsStore
    let fileName: String
    let language: String
    let lineCount: Int
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(settings.accentGradient.opacity(0.25))
                        .frame(width: 38, height: 38)
                    Image(systemName: iconFor(language))
                        .foregroundStyle(settings.accentGradient)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Создание \(fileName)").font(.subheadline.bold())
                    Text("\(language.uppercased()) · \(lineCount) строк").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(settings.accentColor.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    private func iconFor(_ lang: String) -> String {
        switch lang.lowercased() {
        case "html": return "globe"
        case "swift": return "swift"
        case "python", "py": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        case "css": return "paintbrush"
        case "javascript", "js": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text.fill"
        }
    }
}

// MARK: - Generic code card

struct CodeCard: View {
    @EnvironmentObject var settings: SettingsStore
    let language: String
    let content: String
    var onOpen: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(language.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = content
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { copied = false } }
                } label: {
                    Label(copied ? "Скопировано" : "Копировать",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                Button(action: onOpen) {
                    Label("Открыть", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption2)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.black.opacity(0.25))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(settings.codeFont.font(size: 12))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    }
}
